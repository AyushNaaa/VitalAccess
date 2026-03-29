from typing import Optional
from pydantic import BaseModel


class FrameRequest(BaseModel):
    frame: str       # base64-encoded JPEG
    timestamp: float # Unix epoch seconds


class FrameResponse(BaseModel):
    frame_accepted: bool
    frames_collected: int
    frames_needed: int = 900
    quality: str       # "good" | "poor" | "no_face"
    progress_percent: float


class VitalsResponse(BaseModel):
    hr: Optional[float] = None          # BPM
    hrv_sdnn: Optional[float] = None    # ms
    hrv_rmssd: Optional[float] = None   # ms
    rr: Optional[float] = None          # breaths/min
    confidence: str = "low"             # "high" | "medium" | "low"
    measurement_complete: bool = False
    frames_collected: int = 0
    actual_fps: float = 0.0


class StatusResponse(BaseModel):
    signal_quality_score: float  # 0.0–1.0
    motion_level: float          # 0.0–1.0
    face_detected: bool
    brightness_ok: bool
    seconds_elapsed: float
    seconds_remaining: float


class SessionResponse(BaseModel):
    session_id: str
    status: str
