import time
from collections import deque
from typing import Optional, Tuple

# 30 seconds × 30 fps = 900 frames
FRAMES_NEEDED = 900
FRAMES_FOR_HR = 300       # 10 sec — provisional HR
FRAMES_FOR_FINAL_HR = 600 # 20 sec — stable HR
TARGET_FPS = 30

# For poor-signal detection: last 5 seconds at 30fps
RECENT_WINDOW = 150


class MeasurementSession:
    """Accumulates camera ROI frames for rPPG analysis."""

    def __init__(self):
        # Each entry is (R, G, B) float tuple or None (rejected frame)
        self.frame_buffer: deque[Optional[Tuple[float, float, float]]] = deque(maxlen=FRAMES_NEEDED)
        # Timestamps of accepted frames only (Unix epoch seconds)
        self.timestamps: deque[float] = deque(maxlen=FRAMES_NEEDED)
        self.rejected_frames: int = 0
        self.start_time: Optional[float] = None
        self.is_active: bool = False

        # Rolling window for recent rejection-rate tracking
        self._recent_accepted: deque[bool] = deque(maxlen=RECENT_WINDOW)

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        self.frame_buffer.clear()
        self.timestamps.clear()
        self.rejected_frames = 0
        self.start_time = time.time()
        self.is_active = True
        self._recent_accepted.clear()

    # ------------------------------------------------------------------
    # Frame ingestion
    # ------------------------------------------------------------------

    def add_frame(self, rgb: Tuple[float, float, float], timestamp: float) -> None:
        self.frame_buffer.append(rgb)
        self.timestamps.append(timestamp)
        self._recent_accepted.append(True)

    def add_rejected(self) -> None:
        self.frame_buffer.append(None)
        self.rejected_frames += 1
        self._recent_accepted.append(False)

    # ------------------------------------------------------------------
    # Metrics
    # ------------------------------------------------------------------

    def get_valid_count(self) -> int:
        return sum(1 for f in self.frame_buffer if f is not None)

    def get_actual_fps(self) -> float:
        """Compute observed FPS from accepted-frame timestamps."""
        ts = list(self.timestamps)
        if len(ts) < 2:
            return float(TARGET_FPS)
        duration = ts[-1] - ts[0]
        if duration < 0.1:
            return float(TARGET_FPS)
        return (len(ts) - 1) / duration

    def get_progress(self) -> float:
        """Returns 0.0–1.0 based on valid frames vs FRAMES_NEEDED."""
        return min(1.0, self.get_valid_count() / FRAMES_NEEDED)

    def is_complete(self) -> bool:
        return self.get_valid_count() >= FRAMES_NEEDED

    def has_poor_signal(self) -> bool:
        """True if >30% of the recent frames were rejected."""
        if len(self._recent_accepted) < 30:
            return False
        rejection_rate = self._recent_accepted.count(False) / len(self._recent_accepted)
        return rejection_rate > 0.30

    def get_elapsed_seconds(self) -> float:
        if self.start_time is None:
            return 0.0
        return time.time() - self.start_time

    def get_remaining_seconds(self, total: float = 30.0) -> float:
        return max(0.0, total - self.get_elapsed_seconds())
