"""
VitalsPipeline — orchestrates the rPPG processing steps on a MeasurementSession.
"""
from typing import Optional
import numpy as np
from scipy.signal import detrend

from session import MeasurementSession, FRAMES_NEEDED, FRAMES_FOR_HR, FRAMES_FOR_FINAL_HR
from signal_processing import (
    compute_bvp,
    bandpass_filter,
    compute_heart_rate,
    compute_hrv,
    compute_respiratory_rate,
    compute_snr,
)


class VitalsPipeline:
    def __init__(self, session: MeasurementSession):
        self.session = session

    def process(self) -> dict:
        """
        Run the full pipeline on the current session buffer.
        Returns a dict matching the VitalsResponse schema.
        """
        buffer = list(self.session.frame_buffer)
        valid_count = sum(1 for f in buffer if f is not None)
        fps = self.session.get_actual_fps()

        base = {
            "hr": None,
            "hrv_sdnn": None,
            "hrv_rmssd": None,
            "rr": None,
            "confidence": "low",
            "measurement_complete": False,
            "frames_collected": valid_count,
            "actual_fps": round(fps, 1),
        }

        # Need at least 10 seconds of data for a provisional HR
        if valid_count < FRAMES_FOR_HR:
            return base

        # Extract and interpolate RGB time series
        r_series, g_series, b_series = self._extract_rgb(buffer)

        # CHROM → detrend → bandpass
        bvp_raw = compute_bvp(r_series, g_series, b_series)
        bvp_detrended = detrend(bvp_raw, type="linear")
        bvp_filtered = bandpass_filter(bvp_detrended, 0.75, 4.0, fps, order=4)

        # Heart rate (available from 10 sec onward)
        hr, hr_conf = compute_heart_rate(bvp_filtered, fps)

        # HRV and RR only after the full 30 sec window
        hrv_sdnn: Optional[float] = None
        hrv_rmssd: Optional[float] = None
        rr: Optional[float] = None

        if valid_count >= FRAMES_NEEDED:
            hrv_sdnn, hrv_rmssd = compute_hrv(bvp_filtered, fps)
            rr = compute_respiratory_rate(bvp_filtered, fps)

        # --- Composite confidence (4 factors, each up to 0.25) ---
        snr = compute_snr(bvp_raw, fps)
        snr_score = min(0.25, snr * 0.625)          # SNR 0.4 → full 0.25

        hr_conf_score = min(0.25, hr_conf * 0.25)   # Rescale 0-1 → 0-0.25

        total_frames = max(1, len(buffer))
        frame_quality = valid_count / total_frames
        frame_score = min(0.25, frame_quality * 0.25)

        if 40.0 <= hr <= 130.0:
            hr_plausibility = 0.25
        elif 130.0 < hr <= 180.0:
            hr_plausibility = 0.15
        else:
            hr_plausibility = 0.0

        composite = snr_score + hr_conf_score + frame_score + hr_plausibility

        if composite >= 0.75:
            confidence = "high"
        elif composite >= 0.45:
            confidence = "medium"
        else:
            confidence = "low"

        is_complete = valid_count >= FRAMES_NEEDED

        return {
            "hr": round(hr, 1),
            "hrv_sdnn": round(hrv_sdnn, 1) if hrv_sdnn is not None else None,
            "hrv_rmssd": round(hrv_rmssd, 1) if hrv_rmssd is not None else None,
            "rr": round(rr, 1) if rr is not None else None,
            "confidence": confidence,
            "measurement_complete": is_complete,
            "frames_collected": valid_count,
            "actual_fps": round(fps, 1),
        }

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _extract_rgb(self, buffer):
        """Extract R, G, B series from the buffer, interpolating over None entries."""
        r_raw = [f[0] if f is not None else np.nan for f in buffer]
        g_raw = [f[1] if f is not None else np.nan for f in buffer]
        b_raw = [f[2] if f is not None else np.nan for f in buffer]

        r = self._interpolate_nans(np.array(r_raw, dtype=np.float64))
        g = self._interpolate_nans(np.array(g_raw, dtype=np.float64))
        b = self._interpolate_nans(np.array(b_raw, dtype=np.float64))

        return r, g, b

    @staticmethod
    def _interpolate_nans(arr: np.ndarray) -> np.ndarray:
        """Linear interpolation over NaN values in a 1D array."""
        nans = np.isnan(arr)
        if not np.any(nans):
            return arr
        not_nans = ~nans
        if not np.any(not_nans):
            return np.zeros_like(arr)
        x = np.arange(len(arr))
        arr[nans] = np.interp(x[nans], x[not_nans], arr[not_nans])
        return arr
