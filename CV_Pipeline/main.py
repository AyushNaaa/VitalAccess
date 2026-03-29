"""
VitalAccess CV Pipeline — FastAPI server
Run with: uvicorn main:app --host 127.0.0.1 --port 8000 --reload
"""
import asyncio
import base64
import uuid

import cv2
import numpy as np
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from models import FrameRequest, FrameResponse, VitalsResponse, StatusResponse, SessionResponse
from session import MeasurementSession
from face_detection import FaceDetector
from pipeline import VitalsPipeline

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

app = FastAPI(title="VitalAccess CV Pipeline", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Module-level singleton state
# Single session, single measurement — no DB, no auth, local demo server.
# ---------------------------------------------------------------------------

_session = MeasurementSession()
_detector = FaceDetector()
_lock = asyncio.Lock()
_session_id: str = ""

# Cached quality info from the last processed frame
_last_quality: dict = {
    "face_detected": False,
    "brightness_ok": True,
    "motion_level": 0.0,
    "signal_quality_score": 0.0,
}


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.post("/start", response_model=SessionResponse)
async def start_session():
    """Reset and start a new measurement session."""
    global _session_id
    async with _lock:
        _session.start()
        _session_id = str(uuid.uuid4())[:8].upper()
    return SessionResponse(session_id=_session_id, status="ready")


@app.post("/frame", response_model=FrameResponse)
async def receive_frame(req: FrameRequest):
    """
    Accept a single base64-encoded JPEG frame from Flutter.
    Decodes, runs face detection, extracts ROI RGB, appends to session buffer.
    """
    global _last_quality

    # Decode base64 → OpenCV frame
    try:
        img_bytes = base64.b64decode(req.frame)
        arr = np.frombuffer(img_bytes, dtype=np.uint8)
        frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if frame is None:
            raise ValueError("cv2.imdecode returned None")
    except Exception:
        async with _lock:
            _session.add_rejected()
        return FrameResponse(
            frame_accepted=False,
            frames_collected=_session.get_valid_count(),
            quality="poor",
            progress_percent=round(_session.get_progress() * 100, 1),
        )

    # Face detection + ROI extraction (CPU-bound but fast enough at 30fps)
    roi_rgb = _detector.extract_roi(frame)
    quality_info = _detector.get_quality_info()

    async with _lock:
        _last_quality = quality_info

        if roi_rgb is not None:
            _session.add_frame(roi_rgb, req.timestamp)
            quality_str = "good"
            accepted = True
        else:
            _session.add_rejected()
            quality_str = "no_face" if not quality_info["face_detected"] else "poor"
            accepted = False

    return FrameResponse(
        frame_accepted=accepted,
        frames_collected=_session.get_valid_count(),
        quality=quality_str,
        progress_percent=round(_session.get_progress() * 100, 1),
    )


@app.get("/vitals", response_model=VitalsResponse)
async def get_vitals():
    """Run the pipeline on the current buffer and return best vitals estimate."""
    async with _lock:
        result = VitalsPipeline(_session).process()
    return VitalsResponse(**result)


@app.get("/status", response_model=StatusResponse)
async def get_status():
    """Return live signal quality and progress metrics."""
    elapsed = _session.get_elapsed_seconds()
    remaining = _session.get_remaining_seconds()

    return StatusResponse(
        signal_quality_score=_last_quality.get("signal_quality_score", 0.0),
        motion_level=_last_quality.get("motion_level", 0.0),
        face_detected=_last_quality.get("face_detected", False),
        brightness_ok=_last_quality.get("brightness_ok", True),
        seconds_elapsed=round(elapsed, 1),
        seconds_remaining=round(remaining, 1),
    )


@app.delete("/session")
async def delete_session():
    """Clear the current session (equivalent to a reset)."""
    async with _lock:
        _session.start()
    return {"cleared": True}


@app.get("/health")
async def health_check():
    """Simple liveness check for Flutter connection test."""
    return {"status": "ok", "version": "1.0.0"}


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
