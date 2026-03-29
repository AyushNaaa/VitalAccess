from typing import Optional, Tuple, Dict
import cv2
import mediapipe as mp
import numpy as np

# MediaPipe FaceMesh landmark indices for three skin ROI regions.
# These form quadrilaterals over forehead, left cheek, and right cheek.
FOREHEAD_LANDMARKS = [10, 338, 297, 332]
LEFT_CHEEK_LANDMARKS = [234, 93, 132, 58]
RIGHT_CHEEK_LANDMARKS = [454, 323, 361, 288]
ALL_ROI_INDICES = FOREHEAD_LANDMARKS + LEFT_CHEEK_LANDMARKS + RIGHT_CHEEK_LANDMARKS

# Minimum face bounding box area as fraction of total frame area
MIN_FACE_AREA_RATIO = 0.05

# Run full MediaPipe detection every N frames; use optical flow between
DETECTION_INTERVAL = 3


class FaceDetector:
    def __init__(self):
        mp_face_mesh = mp.solutions.face_mesh
        self._face_mesh = mp_face_mesh.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=False,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self._frame_count: int = 0
        # List of (x, y) pixel coords for all 468 landmarks, or None
        self._cached_landmarks: Optional[list] = None
        self._prev_gray: Optional[np.ndarray] = None
        self._last_motion: float = 0.0
        self._last_quality: Dict = {
            "face_detected": False,
            "brightness_ok": True,
            "motion_level": 0.0,
            "signal_quality_score": 0.0,
        }

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def extract_roi(self, frame: np.ndarray) -> Optional[Tuple[float, float, float]]:
        """
        Detect face, extract three skin ROIs, return weighted mean (R, G, B).
        Returns None if quality checks fail.
        """
        h, w = frame.shape[:2]
        curr_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        # Compute motion BEFORE updating prev_gray
        if self._prev_gray is not None:
            diff = cv2.absdiff(self._prev_gray, curr_gray)
            self._last_motion = float(np.mean(diff)) / 255.0
        else:
            self._last_motion = 0.0

        self._frame_count += 1
        run_detection = (self._frame_count % DETECTION_INTERVAL == 1) or (self._cached_landmarks is None)

        if run_detection:
            self._cached_landmarks = self._run_mediapipe(frame, h, w)
        else:
            self._track_with_optical_flow(curr_gray, h, w)

        self._prev_gray = curr_gray
        self._update_quality_cache(h, w)

        if self._cached_landmarks is None:
            return None

        return self._extract_mean_rgb(frame, h, w)

    def get_quality_info(self) -> Dict:
        """Return cached quality metrics from the last extract_roi() call."""
        return self._last_quality

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _run_mediapipe(self, frame: np.ndarray, h: int, w: int) -> Optional[list]:
        """Run MediaPipe FaceMesh and return list of (x, y) pixel coords."""
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        results = self._face_mesh.process(rgb)
        if not results.multi_face_landmarks:
            return None
        lm = results.multi_face_landmarks[0].landmark
        return [(int(l.x * w), int(l.y * h)) for l in lm]

    def _track_with_optical_flow(self, curr_gray: np.ndarray, h: int, w: int) -> None:
        """Shift all landmarks by the mean optical-flow displacement of ROI points."""
        if self._cached_landmarks is None or self._prev_gray is None:
            return

        # Sparse optical flow on ROI landmark points only
        prev_pts = np.array(
            [self._cached_landmarks[i] for i in ALL_ROI_INDICES],
            dtype=np.float32,
        ).reshape(-1, 1, 2)

        new_pts, status, _ = cv2.calcOpticalFlowPyrLK(
            self._prev_gray, curr_gray, prev_pts, None,
            winSize=(15, 15), maxLevel=2,
            criteria=(cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 10, 0.03),
        )

        if new_pts is None or status is None:
            return

        good_new = new_pts[status.flatten() == 1]
        good_old = prev_pts[status.flatten() == 1]

        if len(good_new) == 0:
            return

        displacement = np.mean(good_new.reshape(-1, 2) - good_old.reshape(-1, 2), axis=0)
        dx, dy = displacement[0], displacement[1]

        self._cached_landmarks = [
            (
                int(np.clip(x + dx, 0, w - 1)),
                int(np.clip(y + dy, 0, h - 1)),
            )
            for x, y in self._cached_landmarks
        ]

    def _extract_mean_rgb(
        self, frame: np.ndarray, h: int, w: int
    ) -> Optional[Tuple[float, float, float]]:
        """Extract per-ROI mean RGB and return area-weighted average."""
        roi_groups = [
            FOREHEAD_LANDMARKS,
            LEFT_CHEEK_LANDMARKS,
            RIGHT_CHEEK_LANDMARKS,
        ]

        roi_rgbs = []
        roi_areas = []

        for indices in roi_groups:
            pts = np.array(
                [self._cached_landmarks[i] for i in indices], dtype=np.int32
            )
            pts[:, 0] = np.clip(pts[:, 0], 0, w - 1)
            pts[:, 1] = np.clip(pts[:, 1], 0, h - 1)

            hull = cv2.convexHull(pts)
            mask = np.zeros((h, w), dtype=np.uint8)
            cv2.fillConvexPoly(mask, hull, 255)

            pixels = frame[mask == 255]  # shape: (N, 3) in BGR
            if len(pixels) < 10:
                continue

            mean_b = float(np.mean(pixels[:, 0]))
            mean_g = float(np.mean(pixels[:, 1]))
            mean_r = float(np.mean(pixels[:, 2]))

            # Brightness check using green channel (strongest rPPG signal)
            if mean_g < 30 or mean_g > 220:
                continue

            roi_rgbs.append((mean_r, mean_g, mean_b))
            roi_areas.append(len(pixels))

        if len(roi_rgbs) < 3:
            return None

        total_area = sum(roi_areas)
        r = sum(rgb[0] * a for rgb, a in zip(roi_rgbs, roi_areas)) / total_area
        g = sum(rgb[1] * a for rgb, a in zip(roi_rgbs, roi_areas)) / total_area
        b = sum(rgb[2] * a for rgb, a in zip(roi_rgbs, roi_areas)) / total_area

        return (r, g, b)

    def _update_quality_cache(self, h: int, w: int) -> None:
        """Recompute and cache quality metrics."""
        face_detected = self._cached_landmarks is not None

        # Estimate face bounding box area ratio
        if face_detected:
            pts = np.array(self._cached_landmarks)
            fmin, fmax = pts.min(axis=0), pts.max(axis=0)
            face_area = (fmax[0] - fmin[0]) * (fmax[1] - fmin[1])
            if face_area < MIN_FACE_AREA_RATIO * w * h:
                face_detected = False
                self._cached_landmarks = None

        # Use green channel proxy for brightness (derived from last ROI check)
        brightness_ok = True  # Checked per-ROI in _extract_mean_rgb

        motion_scaled = min(1.0, self._last_motion * 20.0)

        quality_score = 0.0
        if face_detected:
            quality_score += 0.5
        if brightness_ok:
            quality_score += 0.3
        if motion_scaled < 0.2:
            quality_score += 0.2
        elif motion_scaled < 0.5:
            quality_score += 0.1

        self._last_quality = {
            "face_detected": face_detected,
            "brightness_ok": brightness_ok,
            "motion_level": round(motion_scaled, 3),
            "signal_quality_score": round(quality_score, 3),
        }
