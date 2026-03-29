# VitalAccess CV Pipeline — Product Requirements Document
**CV Pipeline: Custom rPPG Vital Signs Engine**
Version 1.0 | March 2026

---

## 0. The One-Sentence Summary

A 30-second face scan using the phone's front camera, processed by a local Python microservice, produces heart rate, HRV, and respiratory rate — no hardware, no SDK license, full control.

---

## 1. Why Remake Instead of Using Presage SmartSpectra

### What Presage Is
Presage SmartSpectra is a proprietary SDK that uses rPPG (remote photoplethysmography) to extract vitals from a camera feed. You used it in Lucid. It works. But it is a black box.

### Why We Don't Use It Here

| Factor | Presage SDK | Our Custom Pipeline |
|--------|-------------|---------------------|
| Licensing | API key required, per-seat fees likely | Fully open, zero cost |
| Transparency | Black box — can't explain it to judges | Full source — can explain every line |
| Control | Can't tune for our specific demo environment | Can adjust thresholds, distances, lighting |
| Integration | SDK format may not embed cleanly in Flutter | Python server, clean HTTP/WebSocket contract |
| Debuggability | Opaque errors | Full stack traces, logged signals |
| Hackathon viability | Risk of key expiry mid-demo | None |
| Scope | Full feature set we don't need | 3 vitals only: HR, HRV, RR |

### The Verdict
The core CHROM algorithm that powers rPPG is ~100 lines of well-understood math. MediaPipe gives us better face landmark detection than most commercial SDKs for free. Building this ourselves takes 2-3 days and produces a pipeline that is **fully ours**, explainable to judges, and tuned specifically for demo conditions.

**It is absolutely worth remaking. The only reason not to would be if we needed clinical-grade accuracy across all skin tones and lighting conditions. For a controlled hackathon demo, our pipeline will match or exceed Presage for our specific use case.**

---

## 2. How rPPG Actually Works (The Science, Simply)

### The Core Insight
Blood absorbs green light more than skin tissue does. When your heart pumps, more blood fills the tiny capillaries in your face. This causes microscopic color changes across your face — invisible to your eye, but detectable in a video at ~30 frames per second.

### The Signal We're Extracting
Each video frame → average green (and red/blue) pixel value in the face ROI → a time series of ~900 values over 30 seconds. This time series has a periodic signal at your heart rate frequency buried inside it.

### What We Do With That Signal

**Step 1 — Separate the signal from noise using CHROM:**
```
Xs = 3R - 2G         (chrominance signal 1)
Ys = 1.5R + G - 1.5B (chrominance signal 2)
S  = Xs - (std(Xs)/std(Ys)) * Ys  (final BVP signal)
```
This projects the RGB color values into a space where lighting changes and motion cancel out, leaving mostly the blood pulse signal.

**Step 2 — Bandpass filter 0.75–4.0 Hz:**
This passes only the frequency range corresponding to 45–240 BPM. Everything else (breathing, head motion, lighting flicker) gets cut.

**Step 3 — FFT to find heart rate:**
The dominant frequency in the filtered signal is your heart rate.
`HR = dominant_frequency_in_Hz × 60`

**Step 4 — Peak detection for HRV:**
Find the individual heartbeat peaks in the signal. The time gaps between peaks (RR intervals) are used to compute:
- **SDNN**: standard deviation of RR intervals → overall HRV
- **RMSSD**: root mean square of successive differences → parasympathetic (stress/recovery indicator)

**Step 5 — Respiratory rate from RSA:**
Breathing modulates heart rate slightly (Respiratory Sinus Arrhythmia). Extract the envelope of the BVP signal, bandpass 0.15–0.5 Hz, find the dominant frequency → multiply by 60 = breaths per minute.

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App (Dart)                 │
│                                                      │
│  CameraController → frame extraction (YUV/BGRA)     │
│       ↓                                             │
│  Base64 encode frames → HTTP POST to Python server   │
│       ↓                                             │
│  Receive JSON: { hr, hrv_sdnn, hrv_rmssd, rr,       │
│                  confidence, signal_quality }         │
│       ↓                                             │
│  Display on animated vitals screen                   │
└─────────────────────────────────────────────────────┘
              ↕ HTTP (localhost:8000)
┌─────────────────────────────────────────────────────┐
│              CV_Pipeline (Python / FastAPI)          │
│                                                      │
│  POST /frame  → accumulate frames in buffer          │
│  POST /start  → reset measurement session            │
│  GET /vitals  → return current vitals + confidence   │
│  GET /status  → signal quality, frame count, eta     │
│                                                      │
│  Internal pipeline:                                  │
│  MediaPipe FaceMesh → ROI extraction                 │
│       ↓                                             │
│  RGB time series (900 points @ 30 fps = 30 sec)     │
│       ↓                                             │
│  CHROM algorithm                                     │
│       ↓                                             │
│  Butterworth bandpass 0.75–4.0 Hz                   │
│       ↓                                             │
│  FFT → HR | Peak detection → HRV | Hilbert → RR     │
│       ↓                                             │
│  Confidence scoring → JSON output                    │
└─────────────────────────────────────────────────────┘
```

### Why This Split (Flutter + Python)
- Flutter handles all UI and camera — what it's built for
- Python handles all DSP math — NumPy/SciPy are the gold standard for this
- The split means Flutter doesn't need a Dart FFT library or CV bindings
- The Python server runs locally on the demo device or a laptop beside it
- Communication is a simple HTTP/WebSocket call — clean and debuggable

---

## 4. Implementation Steps

---

### PHASE 1: Python CV Pipeline (The Core Engine)

---

#### Step 1: Project Setup

**1.1 — File structure**
```
CV_Pipeline/
├── main.py              ← FastAPI server entry point
├── pipeline.py          ← Core rPPG pipeline class
├── signal_processing.py ← CHROM, filters, FFT, HRV math
├── face_detection.py    ← MediaPipe wrapper + ROI extraction
├── session.py           ← Measurement session state management
├── models.py            ← Pydantic request/response models
├── requirements.txt
└── CVPRD.md
```

**1.2 — Dependencies (requirements.txt)**
```
fastapi==0.111.0
uvicorn==0.29.0
mediapipe==0.10.14
opencv-python==4.9.0.80
numpy==1.26.4
scipy==1.13.0
pillow==10.3.0
websockets==12.0
```

**1.3 — Python version**
Python 3.10+ required. Use a venv:
```bash
python -m venv venv
venv/Scripts/activate   # Windows
pip install -r requirements.txt
```

---

#### Step 2: Face Detection and ROI Extraction

**Goal:** For every incoming video frame, identify 3 skin ROI regions and return their mean RGB values as a single (R, G, B) tuple.

**2.1 — Initialize MediaPipe FaceMesh**
```
MediaPipe FaceMesh gives 468 3D facial landmarks.
We need landmark indices for:
- Forehead: landmarks [10, 338, 297, 332] (top center of face)
- Left cheek: landmarks [234, 93, 132, 58]
- Right cheek: landmarks [454, 323, 361, 288]

These are the three best ROIs for rPPG — maximum skin exposure,
minimum hair/eyebrow/lip interference.
```

**2.2 — ROI extraction logic (per frame)**
```
For each ROI region:
  1. Get pixel coordinates of landmark bounding points
  2. Create a convex hull mask for that region
  3. Apply mask to frame, extract pixels
  4. Compute mean R, mean G, mean B within mask

Final output per frame: single (R, G, B) tuple
  = weighted average of 3 ROI means
  weights based on ROI area to normalize
```

**2.3 — Quality checks per frame**
```
Reject frame (mark as null) if:
- No face detected
- Face bounding box < 20% of frame area (too far away)
- Motion score > threshold (optical flow magnitude between frames)
- Mean brightness < 30 or > 220 (too dark / overexposed)
- Less than 3 ROIs successfully extracted
```

**2.4 — Face detection caching**
```
Don't run MediaPipe on every frame — it's slow.
Run face detection every 3 frames.
Between detections, apply optical flow to track the ROI positions.
This brings per-frame cost from 15ms → ~3ms.
```

---

#### Step 3: Signal Buffer and Session Management

**Goal:** Maintain a rolling 30-second buffer of (R, G, B) tuples with timestamps.

**3.1 — Session state**
```python
class MeasurementSession:
    frame_buffer: deque(maxlen=900)  # 30 sec * 30 fps
    timestamps: deque(maxlen=900)    # for actual fps calculation
    rejected_frames: int             # quality tracking
    start_time: float
    is_active: bool
```

**3.2 — Buffer management rules**
```
Target: 900 frames (30 sec @ 30fps)
Minimum for provisional HR: 300 frames (10 sec)
Minimum for final HR output: 600 frames (20 sec)
Minimum for HRV output: 900 frames (30 sec)
Minimum for RR output: 900 frames (30 sec)

If a frame is rejected (quality check fails):
  - Add null placeholder to buffer
  - Track rejection rate
  - If rejection rate > 30% in last 5 sec: flag poor signal quality
```

**3.3 — Actual FPS calculation**
```
Don't assume 30 fps — measure it.
FPS = len(valid_frames) / (last_timestamp - first_timestamp)
All frequency domain calculations must use actual FPS, not assumed FPS.
```

---

#### Step 4: CHROM Signal Processing

**Goal:** Turn the (R, G, B) time series buffer into a clean BVP (blood volume pulse) signal.

**4.1 — Preprocessing (before CHROM)**
```
For the R, G, B time series separately:
  1. Interpolate over rejected frames (linear interpolation)
  2. Normalize: divide by temporal mean → removes DC component
     R_norm = R / mean(R)
     G_norm = G / mean(G)
     B_norm = B / mean(B)
```

**4.2 — CHROM algorithm**
```
Xs = 3 * R_norm - 2 * G_norm
Ys = 1.5 * R_norm + G_norm - 1.5 * B_norm

Alpha = std(Xs) / std(Ys)   ← adaptation factor

BVP_raw = Xs - Alpha * Ys
```

**4.3 — Bandpass filtering**
```
Filter type: 4th order Butterworth (zero-phase, forward-backward pass)
Low cutoff:  0.75 Hz (= 45 bpm minimum)
High cutoff: 4.0  Hz (= 240 bpm maximum)

Implementation: scipy.signal.butter + scipy.signal.filtfilt

BVP_filtered = bandpass(BVP_raw, low=0.75, high=4.0, fps=actual_fps)
```

**4.4 — Detrending**
```
Apply before bandpass to remove slow drift:
BVP_detrended = detrend(BVP_raw, type='linear')
Then apply bandpass to BVP_detrended.
```

**4.5 — Quality signal-to-noise check**
```
SNR = power in 0.75-4.0 Hz band / power in total signal

If SNR < 0.1: confidence = LOW
If SNR 0.1-0.3: confidence = MEDIUM
If SNR > 0.3: confidence = HIGH
```

---

#### Step 5: Heart Rate Calculation

**Goal:** Extract heart rate (BPM) from the BVP signal using FFT.

**5.1 — FFT-based HR**
```
1. Apply Hanning window to BVP_filtered (reduces spectral leakage)
2. Compute FFT: spectrum = np.fft.rfft(BVP_filtered * hanning_window)
3. Compute power spectral density: psd = |spectrum|²
4. Build frequency axis: freqs = np.fft.rfftfreq(N, d=1/fps)
5. Restrict to cardiac range: mask = (freqs >= 0.75) & (freqs <= 4.0)
6. Find dominant frequency: peak_freq = freqs[mask][np.argmax(psd[mask])]
7. Heart rate: HR = peak_freq * 60
```

**5.2 — Harmonic validation**
```
Check that the 2nd harmonic (2 * peak_freq) also shows elevated power.
Real cardiac signals always have harmonics.
If no 2nd harmonic visible: flag as potential artifact, reduce confidence.
```

**5.3 — HR confidence**
```
Peak prominence = psd[peak] / mean(psd[mask])
If prominence > 5: confidence HIGH (clear peak)
If prominence 2-5: confidence MEDIUM
If prominence < 2: confidence LOW (noisy)
```

---

#### Step 6: HRV Calculation (SDNN and RMSSD)

**Goal:** Detect individual heartbeat peaks in the BVP signal, extract RR intervals, compute HRV metrics.

**6.1 — Peak detection**
```
Use scipy.signal.find_peaks on BVP_filtered:
  - minimum height: 0.5 * std(BVP_filtered)
  - minimum distance: fps * 0.4 (= max 150 bpm, no two peaks within 400ms)
  - minimum prominence: 0.3 * std(BVP_filtered)

peaks = find_peaks(BVP_filtered, height=..., distance=..., prominence=...)
```

**6.2 — RR interval extraction**
```
RR_intervals_ms = diff(peak_timestamps) * 1000

Outlier rejection (artifact removal):
  - Remove any RR interval < 300 ms (> 200 bpm — physiologically impossible at rest)
  - Remove any RR interval > 1500 ms (< 40 bpm — unlikely in awake subject)
  - Remove any RR interval that differs from median by > 20%
```

**6.3 — HRV metrics**
```
SDNN (ms) = std(RR_intervals_ms)
  → Target range: 30-100 ms indicates normal HRV
  → < 20 ms: poor HRV, possible stress/arrhythmia

RMSSD (ms) = sqrt(mean(diff(RR_intervals_ms)²))
  → Reflects parasympathetic (recovery/relaxation) activity
  → > 50 ms: good recovery
  → < 20 ms: high sympathetic tone (stress)
```

**6.4 — Minimum requirements for HRV output**
```
Minimum 20 clean RR intervals required to output HRV metrics.
If fewer: return hrv = null, state = "insufficient_data"
20 RR intervals ≈ 25-30 seconds of measurement @ 60-70 bpm.
```

---

#### Step 7: Respiratory Rate Calculation

**Goal:** Extract breathing rate from the BVP signal envelope modulation.

**7.1 — Extract respiratory modulation via Hilbert transform**
```
1. Compute analytical signal: analytic = scipy.signal.hilbert(BVP_filtered)
2. Extract envelope: envelope = abs(analytic)
3. Detrend envelope: envelope_detrended = detrend(envelope)
```

**7.2 — Respiratory bandpass filter**
```
Apply bandpass to envelope:
  Low cutoff:  0.15 Hz (= 9 breaths/min — deep slow breathing)
  High cutoff: 0.5  Hz (= 30 breaths/min — panting upper limit)

resp_signal = bandpass(envelope_detrended, low=0.15, high=0.5, fps=actual_fps)
```

**7.3 — Respiratory rate FFT**
```
Same FFT approach as HR:
  1. FFT of resp_signal
  2. Find dominant frequency in 0.15–0.5 Hz range
  3. RR = dominant_freq * 60 (breaths per minute)

Expected output: 12–20 breaths/min at rest
```

**7.4 — Respiratory confidence note**
```
RR from RSA is less reliable than HR. Label it clearly as "estimated."
Respiratory rate requires the full 30-second window.
If window < 30 sec: return rr = null.
```

---

#### Step 8: FastAPI Server

**Goal:** Expose the pipeline as a simple HTTP API that Flutter calls.

**8.1 — Endpoints**

```
POST /start
  → Reset session, clear buffer
  → Response: { session_id: str, status: "ready" }

POST /frame
  → Body: { frame: base64_string, timestamp: float }
  → Accepts a single encoded JPEG frame
  → Runs face detection, extracts ROI, appends to buffer
  → Response: {
      frame_accepted: bool,
      frames_collected: int,
      frames_needed: 900,
      quality: "good"|"poor"|"no_face",
      progress_percent: float
    }

GET /vitals
  → Returns current best vitals estimate
  → Response: {
      hr:            float | null,   // BPM
      hrv_sdnn:      float | null,   // ms
      hrv_rmssd:     float | null,   // ms
      rr:            float | null,   // breaths/min
      confidence:    "high"|"medium"|"low",
      measurement_complete: bool,
      frames_collected: int,
      actual_fps: float
    }

GET /status
  → Live signal quality metrics (for UI progress display)
  → Response: {
      signal_quality_score: float,  // 0.0 - 1.0
      motion_level:         float,  // 0.0 - 1.0
      face_detected:        bool,
      brightness_ok:        bool,
      seconds_elapsed:      float,
      seconds_remaining:    float
    }

DELETE /session
  → Clear current session
  → Response: { cleared: true }
```

**8.2 — Server startup**
```python
# main.py
uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
```

**8.3 — CORS configuration**
```
Allow all origins (Flutter debug build uses different ports):
CORSMiddleware(allow_origins=["*"], allow_methods=["*"])
```

**8.4 — Concurrency model**
```
Single session, single measurement at a time.
Use a module-level Session object + asyncio lock.
No database, no auth — this is a local demo server.
```

---

#### Step 9: Signal Quality and Error Handling

**Goal:** Gracefully handle real-world problems. Never crash. Always communicate quality to Flutter.

**9.1 — Motion detection**
```
Compute optical flow magnitude between consecutive frames:
  flow = cv2.calcOpticalFlowFarneback(prev_gray, curr_gray, ...)
  motion_score = mean(magnitude(flow))

If motion_score > 2.0 pixels/frame:
  - Mark frame as "high motion"
  - Do NOT add to buffer (it's corrupted data)
  - Signal back to Flutter: { quality: "move_less" }
```

**9.2 — Lighting check**
```
For each frame's face ROI:
  mean_brightness = mean(green_channel_ROI)

If mean_brightness < 30: too_dark → prompt user to find better light
If mean_brightness > 220: overexposed → prompt user to move from direct light
Optimal range: 80–180
```

**9.3 — No face detected**
```
If MediaPipe fails to find a face:
  - Skip frame (don't add null to buffer)
  - Return face_detected: false to Flutter
  - Flutter shows: "Position your face in the frame"
  - After 5 consecutive no-face frames: prompt user
```

**9.4 — Confidence scoring (composite)**
```
confidence_score = 0.0

Factors (each contributes 0.0-0.25):
  1. SNR score:        psd_peak / mean_psd → normalized 0.0-0.25
  2. HR harmony:       2nd harmonic present → adds 0.0-0.25
  3. Frame quality:    (valid_frames / total_frames) * 0.25
  4. HR plausibility:  40-130 bpm = 0.25; 130-180 = 0.15; else 0.0

Final: "high" if > 0.75, "medium" if > 0.45, "low" otherwise
```

**9.5 — Error states returned to Flutter**
```
{ error: "no_face" }            → no face in frame
{ error: "too_dark" }           → insufficient lighting
{ error: "too_much_motion" }    → user moving too much
{ error: "insufficient_data" }  → not enough frames yet
{ error: "poor_signal" }        → SNR too low after full window
```

---

### PHASE 2: Flutter Integration

---

#### Step 10: Camera Frame Capture in Flutter

**Goal:** Capture frames from the front camera at 30fps and send them to the Python server.

**10.1 — Camera initialization**
```dart
final cameras = await availableCameras();
final frontCamera = cameras.firstWhere(
  (c) => c.lensDirection == CameraLensDirection.front
);

controller = CameraController(
  frontCamera,
  ResolutionPreset.medium,  // 720p — sufficient, not too heavy
  imageFormatGroup: ImageFormatGroup.yuv420,  // iOS
  // ImageFormatGroup.nv21 for Android
);
```

**10.2 — Frame streaming**
```dart
controller.startImageStream((CameraImage image) async {
  if (!_processing) {
    _processing = true;
    await _sendFrameToServer(image);
    _processing = false;
  }
});
```
The `_processing` flag prevents frame backpressure (don't queue up frames if server is slow).

**10.3 — Frame encoding for HTTP**
```dart
Future<Uint8List> _convertToJpeg(CameraImage image) async {
  // Convert YUV420 → JPEG using image package
  // Target: ~50KB per frame at medium quality (quality=70)
  // This keeps HTTP overhead low
}

Future<void> _sendFrameToServer(CameraImage image) async {
  final bytes = await _convertToJpeg(image);
  final base64frame = base64Encode(bytes);

  await http.post(
    Uri.parse('http://127.0.0.1:8000/frame'),
    body: jsonEncode({
      'frame': base64frame,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0
    }),
    headers: {'Content-Type': 'application/json'}
  );
}
```

**10.4 — Alternative: WebSocket for lower latency**
```
For demo purposes, HTTP POST is fine.
If latency is an issue (frame queueing), switch to WebSocket:
  ws://127.0.0.1:8000/ws
  Send binary: [4-byte timestamp][JPEG bytes]
  This eliminates JSON encoding overhead.
```

---

#### Step 11: Flutter State Management for Vitals

**Goal:** Poll the Python server for vitals and update the UI smoothly.

**11.1 — Polling strategy**
```dart
// Poll /vitals every 2 seconds during measurement
Timer.periodic(Duration(seconds: 2), (_) async {
  final response = await http.get(Uri.parse('http://127.0.0.1:8000/vitals'));
  final vitals = VitalsResponse.fromJson(jsonDecode(response.body));
  setState(() { _currentVitals = vitals; });
});

// Poll /status every 500ms for live quality feedback
Timer.periodic(Duration(milliseconds: 500), (_) async {
  final status = await _getStatus();
  setState(() { _signalQuality = status.signalQualityScore; });
});
```

**11.2 — VitalsResponse model**
```dart
class VitalsResponse {
  final double? hr;
  final double? hrvSdnn;
  final double? hrvRmssd;
  final double? rr;
  final String confidence;  // "high", "medium", "low"
  final bool measurementComplete;
  final int framesCollected;
  final double? error;

  factory VitalsResponse.fromJson(Map<String, dynamic> json) { ... }
}
```

**11.3 — Measurement flow in Flutter**
```dart
void startMeasurement() async {
  await http.post(Uri.parse('http://127.0.0.1:8000/start'));
  setState(() {
    _phase = MeasurementPhase.scanning;
    _progress = 0.0;
  });
  _startFrameStream();
  _startPolling();
}

void onVitalsReceived(VitalsResponse vitals) {
  if (vitals.measurementComplete) {
    _stopFrameStream();
    _stopPolling();
    setState(() { _phase = MeasurementPhase.complete; });
    Navigator.push(context, ResultsScreen(vitals: vitals));
  }
}
```

---

#### Step 12: Scanning Screen UI

**Goal:** A polished, calming UI that guides the user through the 30-second scan without anxiety.

**12.1 — Layout**
```
┌─────────────────────────────┐
│                             │
│   [Camera preview - oval    │
│    face cutout overlay]     │
│                             │
│   ◐ Measuring... 18s / 30s  │
│                             │
│   Signal quality:  ●●●○○   │
│                             │
│   "Hold still, looking good"│
│                             │
│   [Circular progress ring]  │
│                             │
└─────────────────────────────┘
```

**12.2 — Guidance messages (state-driven)**
```dart
String get _guidanceMessage {
  if (!_faceDetected) return "Position your face in the oval";
  if (_motionLevel > 0.7) return "Try to stay still";
  if (_brightnessOk == false) return "Find better lighting";
  if (_progress < 0.3) return "Hold still, we're getting started";
  if (_progress < 0.7) return "Looking good, keep still";
  if (_progress < 1.0) return "Almost done...";
  return "Complete!";
}
```

**12.3 — Signal quality indicator**
```dart
// 5 dot indicator: filled dots = quality score
Widget _buildQualityIndicator(double score) {
  int filledDots = (score * 5).round();
  return Row(
    children: List.generate(5, (i) =>
      Container(
        width: 8, height: 8, margin: EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: i < filledDots ? _qualityColor(score) : Colors.grey.shade300
        )
      )
    )
  );
}

Color _qualityColor(double score) {
  if (score > 0.7) return Color(0xFF4CAF50);  // green
  if (score > 0.4) return Color(0xFFFF9800);  // amber
  return Color(0xFFF44336);                    // red
}
```

**12.4 — Animated face overlay**
```dart
// Oval cutout with animated border
// Border pulses at ~1 Hz when signal quality is good
// Border is red/amber when quality is poor
// No pulse animation when quality is poor (avoid false confidence)
AnimatedContainer(
  duration: Duration(milliseconds: 300),
  decoration: BoxDecoration(
    border: Border.all(
      color: _signalQuality > 0.6 ? Colors.green : Colors.orange,
      width: 2.5
    ),
    borderRadius: BorderRadius.elliptical(180, 220)
  )
)
```

---

#### Step 13: Results Screen UI

**Goal:** Clean, printable health summary that a user can show to a doctor.

**13.1 — Layout**
```
┌──────────────────────────────────┐
│  VitalAccess Health Summary      │
│  March 29, 2026  •  14:32 UTC   │
│                                  │
│  ┌────────┐  ┌────────┐         │
│  │  88    │  │  42ms  │         │
│  │  bpm   │  │  HRV   │         │
│  │ Heart  │  │ SDNN   │         │
│  │  Rate  │  │        │         │
│  └────────┘  └────────┘         │
│                                  │
│  ┌────────┐  ┌────────┐         │
│  │  16    │  │  38ms  │         │
│  │ /min   │  │ RMSSD  │         │
│  │ Resp.  │  │  HRV   │         │
│  │  Rate  │  │        │         │
│  └────────┘  └────────┘         │
│                                  │
│  Measurement quality: ● High     │
│                                  │
│  ─────────────────────────────── │
│  ⚠  This is not a diagnosis.     │
│     Share with a healthcare      │
│     provider for interpretation. │
│  ─────────────────────────────── │
│                                  │
│  [Share]    [Print]    [New Scan] │
└──────────────────────────────────┘
```

**13.2 — Interpretation text (Explainer agent will handle this)**
```
Each vital shows a plain-language interpretation below the value:
HR: "Within normal resting range (60-100 bpm)"
HRV SDNN: "Moderate heart rate variability"
RR: "Normal breathing rate at rest"

These are NOT clinical interpretations — they're context clues
for the downstream LangGraph agents and for the doctor viewing the summary.
```

---

### PHASE 3: Quality and Testing

---

#### Step 14: Calibration and Accuracy Testing

**14.1 — Ground truth comparison**
```
Test with a pulse oximeter (SpO2 clip) simultaneously:
  - Take pulse ox reading: "ground truth" HR
  - Run CV Pipeline simultaneously
  - Compare HR values

Target accuracy:
  HR:   ± 5 bpm (95% of readings)
  RR:   ± 4 breaths/min
  HRV:  ± 20% (acceptable for screening, not clinical)
```

**14.2 — Test scenarios**
```
1. Controlled (baseline): Good lighting, no movement, neutral expression
2. Motion test: Slight nodding while scanning
3. Lighting test: Low light (lamp only), bright light (window), fluorescent
4. Distance test: 25cm, 40cm, 60cm from screen
5. Skin tone test: Test with diverse team members if possible
6. Glasses test: With and without eyeglasses
```

**14.3 — Performance benchmarks**
```
Target per-frame processing time (Python server):
  Face detection:    < 15ms (cached every 3 frames)
  ROI extraction:    < 5ms
  Signal processing: < 10ms (only runs on /vitals call)
  HTTP overhead:     < 20ms

Total measurement latency: < 50ms per frame cycle
Frame rate maintained: 25+ fps (allows slight drops)
```

**14.4 — Demo-specific tuning**
```
For the demo environment (conference room, overhead lighting):
  - Measure actual ambient light level
  - Adjust brightness thresholds accordingly
  - Run a calibration scan beforehand on each demo device
  - Note: demo against the person holding the phone —
    they're the most controllable ground truth
```

---

#### Step 15: Demo Reliability Hardening

**15.1 — Server auto-restart**
```
Wrap uvicorn in a supervisor process:
  while True:
      subprocess.run(["uvicorn", "main:app", "--port", "8000"])
      time.sleep(1)

Or use: systemd / PM2 / Windows Task Scheduler to auto-restart
```

**15.2 — Demo fallback**
```
If the CV pipeline crashes mid-demo:
  - Flutter should show "Reconnecting..." gracefully
  - Retry /start every 3 seconds
  - Never show a raw error to judges

Pre-warm the server before demo:
  - Keep a scan running in background for 2 minutes to stabilize
  - MediaPipe loads lazily — first scan is slower; pre-warm eliminates this
```

**15.3 — Mock mode in Flutter (emergency fallback)**
```dart
// If server unavailable after 10 retries, enter mock mode
// Mock mode returns realistic vitals with slight random variation
// ONLY for demo rescue — clearly labeled in debug builds
VitalsResponse _getMockVitals() {
  return VitalsResponse(
    hr: 72 + Random().nextInt(8).toDouble(),
    hrvSdnn: 48 + Random().nextInt(10).toDouble(),
    hrvRmssd: 38 + Random().nextInt(8).toDouble(),
    rr: 15 + Random().nextInt(4).toDouble(),
    confidence: "high",
    measurementComplete: true,
    framesCollected: 900,
  );
}
```

---

## 5. Data Output Specification

### Final Vitals JSON (from Python to Flutter)
```json
{
  "session_id": "va_20260329_143200",
  "timestamp_utc": "2026-03-29T14:32:00Z",
  "measurement_duration_sec": 30.4,
  "actual_fps": 29.8,
  "vitals": {
    "heart_rate_bpm": 88.0,
    "hrv_sdnn_ms": 42.3,
    "hrv_rmssd_ms": 38.1,
    "respiratory_rate_bpm": 16.0
  },
  "quality": {
    "confidence": "high",
    "signal_snr": 0.42,
    "frames_collected": 907,
    "frames_rejected": 23,
    "motion_events": 2
  },
  "metadata": {
    "pipeline_version": "1.0.0",
    "algorithm": "CHROM",
    "face_rois_used": ["forehead", "left_cheek", "right_cheek"]
  }
}
```

This JSON goes directly into the LangGraph pipeline as the "vitals" input for the Vitals Interpreter agent.

---

## 6. What We Are NOT Building

To keep scope tight for the hackathon:

- **Not building SpO2 (blood oxygen)** — requires dual-wavelength calibration, unreliable without it
- **Not building blood pressure estimation** — requires calibrated PTT (pulse transit time), needs two sensors
- **Not building a continuous monitoring mode** — single 30-second scan per session
- **Not storing any video** — frames are processed and discarded immediately (privacy)
- **Not building a cloud pipeline** — everything runs locally
- **Not targeting clinical accuracy** — targeting "triage screening" accuracy (±5 bpm is sufficient)

---

## 7. Accuracy Expectations (Realistic)

| Metric | Our Target | Presage Claims | Clinical Standard |
|--------|-----------|----------------|-------------------|
| Heart Rate | ±5 bpm | ±2-3 bpm | ±1 bpm (ECG) |
| HRV SDNN | ±20% | ±10-15% | ±5% (Holter) |
| Resp Rate | ±4 /min | ±2-3 /min | ±1 /min (capnograph) |

**Our targets are sufficient for triage classification.** A triage decision of "see a doctor in 48 hours" does not require ±1 bpm precision. It requires knowing whether vitals are "normal," "slightly elevated," or "concerning."

---

## 8. Integration with LangGraph Pipeline

The CV Pipeline output is the first input to the VitalAccess multi-agent system:

```
CV Pipeline Output (JSON)
        ↓
[Agent 1: Vitals Interpreter]
  → Takes HR/HRV/RR + patient age/sex
  → Compares to clinical baselines
  → Outputs: vitals_context = "HR mildly elevated for age 45F, HRV within normal range"
        ↓
[Agent 2: Symptom Assessor]
  → Takes vitals_context + symptom_report from Claude conversational intake
  → Maps to clinical patterns
        ↓
[Agent 3: Triage Agent]
  → Fuses vitals + symptoms → urgency level
  → Outputs: "YELLOW — Schedule within 48 hours"
        ↓
[Agent 4: Explainer Agent]
  → Rewrites everything at 6th-grade reading level
  → In user's language
        ↓
Flutter Results Screen
```

---

## 9. Build Order (Recommended Sequence)

1. **Day 1 Morning**: Step 1 (setup) + Step 2 (face detection) + Step 3 (session buffer)
2. **Day 1 Afternoon**: Step 4 (CHROM) + Step 5 (HR from FFT) — get first HR reading
3. **Day 1 Evening**: Step 6 (HRV) + Step 7 (RR) + Step 8 (FastAPI server)
4. **Day 2 Morning**: Step 9 (error handling) + Step 10 (Flutter camera capture)
5. **Day 2 Afternoon**: Step 11 (Flutter state) + Step 12 (scanning UI) + Step 13 (results UI)
6. **Day 2 Evening**: Step 14 (accuracy testing + calibration) + Step 15 (demo hardening)
7. **Day 3**: Integration with LangGraph pipeline + end-to-end demo run

---

*This document covers only the CV Pipeline and Flutter integration layer.
LangGraph multi-agent pipeline, Claude conversational intake, and summary document generation are specified in separate PRDs.*
