# Vytal

**Vytal** is a mobile health triage app that uses a phone's front camera to estimate vitals, collects symptoms through an AI-guided conversation, and produces a plain-language health summary the user can share with a clinician.

> **Triage support, not medical diagnosis.**

---

## How It Works

### 1. Face Scan — Vitals Estimation

The user faces their phone camera for ~30 seconds. The app uses **remote photoplethysmography (rPPG)** to detect tiny color changes in facial skin caused by blood flow.

A custom **CV Pipeline** (Python/FastAPI + MediaPipe) runs on the host machine and processes frames in real time using the **CHROM algorithm** to extract:

| Vital | Description |
|---|---|
| **Heart Rate (HR)** | Beats per minute from BVP signal FFT |
| **HRV SDNN** | Standard deviation of RR intervals |
| **HRV RMSSD** | Root mean square of successive RR differences |
| **Respiratory Rate (RR)** | Breaths per minute via Hilbert envelope |

No wearable. No oximeter. Just a phone.

### 2. Symptom Intake — Claude AI Conversation

After the scan, **Claude API** conducts a guided symptom intake (5–8 branching questions):

- What are you experiencing?
- Where exactly is the discomfort?
- How long has this been going on?
- Does anything make it better or worse?

The conversation adapts based on answers. A `[INTAKE_COMPLETE]` token signals the end and emits a structured JSON summary.

### 3. Triage Pipeline — 4-Step Analysis

The vitals and symptom summary are passed through a 4-step Claude pipeline:

| Step | Purpose |
|---|---|
| **Vitals Interpreter** | Reviews HR, HRV, and RR against clinical baselines |
| **Symptom Assessor** | Identifies symptom patterns and clinical concerns |
| **Triage Agent** | Combines vitals + symptoms → assigns urgency level |
| **Explainer Agent** | Rewrites result in plain language |

### 4. Output — Health Summary

The app generates a shareable health summary:

- Vitals snapshot
- Reported symptoms
- **Urgency classification**: `emergency` / `urgent` / `routine` / `selfCare`
- Plain-language explanation
- Timestamp and session ID

---

## User Flow

```
Language Select → Face Scan (30s) → Vitals Display → Symptom Chat → Processing → Result
```

1. Select language (English, French, Spanish, Arabic)
2. Face the camera — real-time quality feedback
3. View estimated vitals
4. Answer 5–8 guided symptom questions
5. Triage pipeline runs (15–30s)
6. Receive urgency classification and plain-language summary
7. Share or save the result

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Flutter App (Android/iOS)                          │
│                                                     │
│  LanguageSelectScreen                               │
│       ↓                                             │
│  ScanScreen ──────── frames (JPEG) ──────────────┐  │
│       ↓                                          │  │
│  SymptomChatScreen ── Claude API (intake) ──┐    │  │
│       ↓                                     │    │  │
│  ProcessingScreen ─── Claude API (triage) ─-┘    │  │
│       ↓                                          │  │
│  ResultScreen                                    │  │
└──────────────────────────────────────────────────┼──┘
                                                   │
                              ┌────────────────────▼───┐
                              │  CV Pipeline (Python)  │
                              │  FastAPI on :8000       │
                              │                         │
                              │  MediaPipe FaceMesh     │
                              │  CHROM rPPG algorithm   │
                              │  Butterworth bandpass   │
                              │  FFT heart rate         │
                              │  HRV peak detection     │
                              └────────────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart) — Android + iOS |
| State management | Provider (`SessionProvider`) |
| CV Pipeline server | Python, FastAPI, uvicorn |
| Face detection | MediaPipe FaceMesh (468 landmarks) |
| rPPG algorithm | CHROM (Xs/Ys chrominance decomposition) |
| Signal processing | SciPy Butterworth filter, NumPy FFT |
| AI — symptom intake | Claude API (`claude-sonnet-4-20250514`) |
| AI — triage pipeline | Claude API (4-step chain) |
| HTTP client (Flutter) | Dio |
| Camera (Flutter) | `camera` plugin, YUV420 frame stream |

---

## Project Structure

```
Vytal/
├── CV_Pipeline/            # Python vitals estimation server
│   ├── main.py             # FastAPI app + endpoints
│   ├── face_detection.py   # MediaPipe + optical flow + ROI extraction
│   ├── signal_processing.py# CHROM, bandpass, FFT, HRV, RR
│   ├── pipeline.py         # Composite confidence + NaN interpolation
│   ├── session.py          # Frame buffer + measurement session
│   ├── models.py           # Pydantic request/response models
│   └── requirements.txt
│
└── vytal_access/           # Flutter app
    └── lib/
        ├── main.dart
        ├── app.dart
        ├── config/         # Theme, constants, translations
        ├── models/         # VitalScanResult, SymptomIntake, TriageResult, HealthSummary
        ├── providers/      # SessionProvider (app state)
        ├── screens/        # One file per screen
        │   ├── language_select_screen.dart
        │   ├── scan_screen.dart
        │   ├── symptom_chat_screen.dart
        │   ├── processing_screen.dart
        │   └── result_screen.dart
        ├── services/
        │   ├── vitals_service.dart   # CV Pipeline client + MockVitalsService
        │   └── claude_service.dart   # Intake + triage Claude API calls
        └── widgets/
            ├── vitals_display.dart
            ├── chat_bubble.dart
            ├── urgency_badge.dart
            └── health_summary_card.dart
```

---

## Setup

### Prerequisites

- Flutter SDK (≥ 3.x)
- Python 3.10+
- Android device or emulator

### 1. CV Pipeline

```bash
cd CV_Pipeline
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 2. Flutter App

```bash
cd vital_access
```

Create `.env` in `vital_access/`:

```env
ANTHROPIC_API_KEY=sk-ant-api03-...
CV_PIPELINE_URL=http://10.0.2.2:8000   # emulator
# CV_PIPELINE_URL=http://<your-wifi-ip>:8000  # physical phone
```

```bash
flutter pub get
flutter run
```

### Physical Phone

1. Enable USB debugging on the device
2. Find your machine's WiFi IP (`ipconfig` on Windows)
3. Set `CV_PIPELINE_URL=http://<wifi-ip>:8000` in `.env`
4. Open Windows Firewall for port 8000 (inbound TCP)
5. `flutter run -d <device-id>`

### Demo Mode

Tap the Vytal logo **3 times** on the language screen to enable demo mode. This bypasses the CV Pipeline server and uses a mock vitals service — useful for testing the UI flow without running the backend.

---

## API Reference — CV Pipeline

| Endpoint | Method | Description |
|---|---|---|
| `/health` | GET | Server health check |
| `/start` | POST | Begin a new measurement session |
| `/frame` | POST | Submit a base64-encoded JPEG frame |
| `/vitals` | GET | Get current vitals estimate |
| `/status` | GET | Signal quality, motion, face detection |
| `/session` | DELETE | Reset the current session |

---

## Supported Languages

| Language | Code |
|---|---|
| English | `en` |
| French | `fr` |
| Spanish | `es` |
| Arabic | `ar` (RTL supported) |

---

## Disclaimer

Vytal is designed for **triage support and health communication**, not as a replacement for professional medical care. All output should be reviewed by a qualified clinician.
