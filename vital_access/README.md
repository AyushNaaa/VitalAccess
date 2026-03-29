# VitalAccess — Flutter App

Mobile frontend for the VitalAccess health triage system. See the [root README](../README.md) for the full project overview.

---

## Requirements

- Flutter SDK ≥ 3.x
- Dart ≥ 3.x
- Android SDK (API 21+) or Xcode (iOS 13+)
- CV Pipeline server running (see [`../CV_Pipeline/`](../CV_Pipeline/))

---

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Configure environment

Create a `.env` file in this directory (`vital_access/.env`):

```env
ANTHROPIC_API_KEY=sk-ant-api03-...

# Android emulator (host machine is reachable at 10.0.2.2)
CV_PIPELINE_URL=http://10.0.2.2:8000

# Physical Android device (use your machine's WiFi IP)
# CV_PIPELINE_URL=http://192.168.x.x:8000
```

### 3. Run

```bash
# List available devices
flutter devices

# Run on a specific device
flutter run -d <device-id>
```

---

## Project Structure

```
lib/
├── main.dart                      # App entry point, dotenv + runApp
├── app.dart                       # MaterialApp, routes, theme
│
├── config/
│   ├── constants.dart             # AppRoutes, translation function t()
│   └── theme.dart                 # AppColors, AppTheme
│
├── models/
│   ├── vital_scan_result.dart     # HR, HRV, RR from scan
│   ├── symptom_intake.dart        # Structured symptom summary from Claude
│   ├── triage_result.dart         # UrgencyLevel enum + extension
│   └── health_summary.dart        # Full combined output
│
├── providers/
│   └── session_provider.dart      # ChangeNotifier — holds all session state
│
├── screens/
│   ├── language_select_screen.dart  # Entry screen, language + demo mode
│   ├── scan_screen.dart             # Camera + rPPG measurement
│   ├── symptom_chat_screen.dart     # Claude-powered symptom intake chat
│   ├── processing_screen.dart       # 4-step triage pipeline runner
│   └── result_screen.dart           # Final health summary display
│
├── services/
│   ├── vitals_service.dart          # CV Pipeline HTTP client + MockVitalsService
│   ├── claude_service.dart          # Claude API — intake + triage
│   └── share_service.dart           # Share/export health summary
│
└── widgets/
    ├── vitals_display.dart          # 2×2 vitals grid with staggered animation
    ├── chat_bubble.dart             # ChatBubble + TypingIndicator
    ├── urgency_badge.dart           # Color-coded urgency level badge
    └── health_summary_card.dart     # Health summary display card
```

---

## Screen Flow

```
LanguageSelectScreen
    ↓  (language tap)
ScanScreen
    ↓  (measurement complete)
SymptomChatScreen
    ↓  ([INTAKE_COMPLETE] detected)
ProcessingScreen
    ↓  (triage done)
ResultScreen
```

---

## Key Concepts

### SessionProvider

All app state lives in `SessionProvider` (Provider pattern). Screens read/write through `context.read<SessionProvider>()` and `context.watch<SessionProvider>()`. Fields:

- `language` — selected language code (`en`, `fr`, `es`, `ar`)
- `demoMode` — bypasses CV server, uses mock vitals
- `vitalScanResult` — HR/HRV/RR from scan
- `symptomIntake` — structured output from Claude intake
- `triageResult` — urgency level + explanation
- `healthSummary` — full combined output

### VitalsService

`CvPipelineVitalsService` sends camera frames (YUV420 → JPEG, 320×240, quality 70) to the CV Pipeline server via Dio. Falls back to `MockVitalsService` after 10 consecutive failures.

`MockVitalsService` simulates a 30-second measurement with realistic random vitals — used in demo mode.

### ClaudeService

Stateless API calls — full conversation history sent on every request. The intake prompt uses `[INTAKE_COMPLETE]` as a termination token with a JSON payload. The triage prompt chains 4 analysis steps in a single call.

---

## Demo Mode

Tap the heart logo on the language screen **3 times** to toggle demo mode. When active:
- A `DEMO` badge appears on the logo
- Scan screen skips the CV server and uses `MockVitalsService`
- Full UI flow (chat → processing → result) is still exercisable

Claude API calls still require a valid `ANTHROPIC_API_KEY` in `.env`.

---

## Running on a Physical Android Device

1. Enable **Developer Options** and **USB Debugging** on the device
2. Connect via USB
3. Verify the device is detected: `adb devices`
4. Find your machine's WiFi IP address (`ipconfig` on Windows)
5. Update `.env`: `CV_PIPELINE_URL=http://<your-wifi-ip>:8000`
6. Ensure port 8000 is open in your firewall
7. Start the CV Pipeline server: `uvicorn main:app --host 0.0.0.0 --port 8000`
8. Run: `flutter run -d <device-id>`
