"""
rPPG Signal Processing — CHROM algorithm + bandpass + FFT + HRV + Respiratory Rate.
All functions are pure (no side effects), operating on numpy arrays.
"""
from typing import Optional, Tuple
import numpy as np
from scipy import signal
from scipy.signal import find_peaks, hilbert


# ---------------------------------------------------------------------------
# CHROM (Chrominance-based) Blood Volume Pulse extraction
# ---------------------------------------------------------------------------

def compute_bvp(
    r_series: np.ndarray,
    g_series: np.ndarray,
    b_series: np.ndarray,
) -> np.ndarray:
    """
    CHROM algorithm: projects RGB into chrominance space orthogonal to
    skin-tone direction, cancelling illumination and motion artifacts.

    Returns the raw BVP (blood volume pulse) signal.
    """
    r = np.array(r_series, dtype=np.float64)
    g = np.array(g_series, dtype=np.float64)
    b = np.array(b_series, dtype=np.float64)

    # Normalize each channel by its temporal mean
    r_norm = r / (np.mean(r) + 1e-10)
    g_norm = g / (np.mean(g) + 1e-10)
    b_norm = b / (np.mean(b) + 1e-10)

    # Chrominance signals (De Haan & Jeanne 2013)
    xs = 3.0 * r_norm - 2.0 * g_norm
    ys = 1.5 * r_norm + g_norm - 1.5 * b_norm

    # Adaptation factor balances the two chrominance components
    alpha = np.std(xs) / (np.std(ys) + 1e-10)

    bvp = xs - alpha * ys
    return bvp


# ---------------------------------------------------------------------------
# Butterworth Bandpass Filter
# ---------------------------------------------------------------------------

def bandpass_filter(
    sig: np.ndarray,
    low_hz: float,
    high_hz: float,
    fps: float,
    order: int = 4,
) -> np.ndarray:
    """
    Zero-phase 4th-order Butterworth bandpass filter (scipy filtfilt).
    For cardiac BVP: low=0.75 Hz (45 bpm), high=4.0 Hz (240 bpm).
    """
    nyq = fps / 2.0
    low = low_hz / nyq
    high = high_hz / nyq

    # Guard against edge cases
    low = float(np.clip(low, 0.01, 0.99))
    high = float(np.clip(high, 0.01, 0.99))

    if low >= high or len(sig) < (order * 3 + 1):
        return sig

    b, a = signal.butter(order, [low, high], btype="band")
    return signal.filtfilt(b, a, sig)


# ---------------------------------------------------------------------------
# Heart Rate (FFT-based)
# ---------------------------------------------------------------------------

def compute_heart_rate(
    bvp_filtered: np.ndarray,
    fps: float,
) -> Tuple[float, float]:
    """
    Finds dominant cardiac frequency via FFT with Hanning window.
    Validates by checking 2nd harmonic presence.

    Returns (hr_bpm, confidence_0_to_1).
    """
    n = len(bvp_filtered)
    if n < 10:
        return 60.0, 0.0

    window = np.hanning(n)
    windowed = bvp_filtered * window

    fft_vals = np.fft.rfft(windowed)
    psd = np.abs(fft_vals) ** 2
    freqs = np.fft.rfftfreq(n, d=1.0 / fps)

    # Restrict to physiological cardiac band
    cardiac_mask = (freqs >= 0.75) & (freqs <= 4.0)
    if not np.any(cardiac_mask):
        return 60.0, 0.0

    psd_cardiac = psd[cardiac_mask]
    freqs_cardiac = freqs[cardiac_mask]

    peak_idx = int(np.argmax(psd_cardiac))
    peak_freq = float(freqs_cardiac[peak_idx])
    hr = peak_freq * 60.0

    # 2nd harmonic validation
    harmonic_freq = 2.0 * peak_freq
    harmonic_mask = (freqs >= harmonic_freq * 0.85) & (freqs <= harmonic_freq * 1.15)
    harmonic_present = (
        np.any(harmonic_mask)
        and np.max(psd[harmonic_mask]) > np.mean(psd_cardiac) * 0.5
    )

    # Confidence: peak prominence + harmonic bonus
    mean_psd = float(np.mean(psd_cardiac)) + 1e-10
    peak_prom = float(psd_cardiac[peak_idx]) / mean_psd
    harmonic_bonus = 0.25 if harmonic_present else 0.0
    confidence = float(np.clip(peak_prom / 10.0 + harmonic_bonus, 0.0, 1.0))

    return hr, confidence


# ---------------------------------------------------------------------------
# HRV — Peak Detection on BVP
# ---------------------------------------------------------------------------

def compute_hrv(
    bvp_filtered: np.ndarray,
    fps: float,
) -> Tuple[Optional[float], Optional[float]]:
    """
    Detect cardiac peaks, extract RR intervals, compute SDNN and RMSSD.

    Returns (sdnn_ms, rmssd_ms) or (None, None) if insufficient peaks.
    """
    std_val = float(np.std(bvp_filtered))
    if std_val < 1e-10:
        return None, None

    peaks, _ = find_peaks(
        bvp_filtered,
        height=0.5 * std_val,
        distance=fps * 0.4,    # min 400ms between peaks → max 150 bpm
        prominence=0.3 * std_val,
    )

    if len(peaks) < 3:
        return None, None

    # Convert peak indices to milliseconds
    peak_times_ms = peaks / fps * 1000.0
    rr_intervals = np.diff(peak_times_ms)

    # Outlier rejection: physiologically implausible and >20% from median
    median_rr = float(np.median(rr_intervals))
    valid = (
        (rr_intervals >= 300.0) &
        (rr_intervals <= 1500.0) &
        (np.abs(rr_intervals - median_rr) / (median_rr + 1e-10) <= 0.20)
    )
    rr_clean = rr_intervals[valid]

    if len(rr_clean) < 20:
        return None, None

    sdnn = float(np.std(rr_clean))
    rmssd = float(np.sqrt(np.mean(np.diff(rr_clean) ** 2))) if len(rr_clean) > 1 else 0.0

    return sdnn, rmssd


# ---------------------------------------------------------------------------
# Respiratory Rate — Hilbert Envelope Modulation
# ---------------------------------------------------------------------------

def compute_respiratory_rate(
    bvp_filtered: np.ndarray,
    fps: float,
    min_duration_sec: float = 30.0,
) -> Optional[float]:
    """
    Extracts respiratory rate from RSA (Respiratory Sinus Arrhythmia) —
    the amplitude modulation of the BVP signal caused by breathing.

    Returns breaths/min or None if the window is too short.
    """
    duration = len(bvp_filtered) / fps
    if duration < min_duration_sec:
        return None

    # Hilbert transform → instantaneous envelope
    analytic = hilbert(bvp_filtered)
    envelope = np.abs(analytic)

    # Remove trend + bandpass for respiratory range (9–30 breaths/min)
    envelope_detrended = signal.detrend(envelope)
    resp_signal = bandpass_filter(envelope_detrended, 0.15, 0.50, fps, order=3)

    n = len(resp_signal)
    window = np.hanning(n)
    fft_vals = np.fft.rfft(resp_signal * window)
    psd = np.abs(fft_vals) ** 2
    freqs = np.fft.rfftfreq(n, d=1.0 / fps)

    resp_mask = (freqs >= 0.15) & (freqs <= 0.50)
    if not np.any(resp_mask):
        return None

    peak_freq = float(freqs[resp_mask][np.argmax(psd[resp_mask])])
    rr = peak_freq * 60.0

    # Sanity bounds: 6–35 breaths/min
    if rr < 6.0 or rr > 35.0:
        return None

    return rr


# ---------------------------------------------------------------------------
# SNR — Signal Quality Metric
# ---------------------------------------------------------------------------

def compute_snr(bvp_raw: np.ndarray, fps: float) -> float:
    """
    Ratio of power in the cardiac band (0.75–4.0 Hz) to total power.
    Used as a component of composite confidence scoring.
    """
    n = len(bvp_raw)
    if n < 4:
        return 0.0

    fft_vals = np.fft.rfft(bvp_raw)
    psd = np.abs(fft_vals) ** 2
    freqs = np.fft.rfftfreq(n, d=1.0 / fps)

    cardiac_mask = (freqs >= 0.75) & (freqs <= 4.0)
    total_power = float(np.sum(psd)) + 1e-10
    cardiac_power = float(np.sum(psd[cardiac_mask]))

    return cardiac_power / total_power
