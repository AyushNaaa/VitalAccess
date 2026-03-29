# VitalAccess — Product Requirements Document

## Overview

VitalAccess is a mobile health triage app that uses a phone's front camera to capture vitals (heart rate, HRV, respiratory rate) via rPPG, then runs a conversational symptom intake powered by Claude, and produces a shareable health summary with an urgency classification. No hardware required — just a phone camera.

**Platform:** Flutter/Dart (Android-first, iOS stretch)
**Build scope:** 4-hour hackathon sprint
**Core thesis:** Triage, not diagnosis. Urgency classification, never a medical condition label.

---

## User Flow

1. **Language Selection** — User opens the app, picks their language
2. **Vitals Scan** — 30-second face scan via front camera → displays HR, HRV, respiratory rate
3. **Symptom Intake** — Claude-powered conversational Q&A (5-8 branching questions)
4. **Triage Pipeline** — Backend processes vitals + symptoms → urgency classification
5. **Results & Summary** — Triage result displayed with plain-language explanation + shareable health summary

---

## Architecture

### Frontend (Flutter)

| Screen | Purpose |
|---|---|
| `LanguageSelectScreen` | Language picker (English, French, Spanish, Arabic — minimum 4) |
| `ScanScreen` | Camera preview + 30s countdown + real-time vitals display |
| `SymptomChatScreen` | Chat UI for Claude-driven symptom intake |
| `ProcessingScreen` | Loading animation while triage pipeline runs |
| `ResultScreen` | Triage result (color-coded urgency) + plain explanation + shareable summary |

### Biometric Capture — Presage SmartSpectra SDK

- Integrate via platform channel (native Android/iOS SDK → Flutter bridge)
- Input: 30 seconds of front camera feed on user's face
- Output: HR (bpm), HRV (ms), Respiratory Rate (breaths/min)
- Fallback: If SDK integration is blocked during build, use mock vitals with a realistic camera-scanning UX so the demo still works end-to-end

### Symptom Intake — Claude API

- Direct Claude API call from the app (or via a thin backend proxy)
- System prompt defines Claude as a structured symptom collector — asks branching clinical questions, never diagnoses
- Conversation limited to 5-8 turns, then auto-summarizes collected symptoms
- Multi-language: system prompt instructs Claude to respond in the user's selected language

### Triage Pipeline — Claude API (Multi-step)

Rather than a full LangGraph deployment (heavy for 4 hours), implement the 4-agent logic as **sequential Claude API calls with distinct system prompts**:

| Agent | Input | Output |
|---|---|---|
| **Vitals Interpreter** | HR, HRV, RR + user age/sex | Clinical interpretation of vitals (e.g., "mildly elevated HR") |
| **Symptom Assessor** | Structured symptom summary | Differential patterns identified (e.g., "cardiac or respiratory flag") |
| **Triage Agent** | Vitals interpretation + symptom assessment | Urgency level: Emergency (red), Urgent/48hr (yellow), Routine (green), Self-care (blue) |
| **Explainer Agent** | Triage output + all context | 6th-grade reading level explanation in user's language |

**Implementation shortcut:** These can be collapsed into 1-2 Claude calls with a well-structured prompt that performs all four reasoning steps in sequence, outputting structured JSON. Expand to separate calls only if time permits.

---

## Data Model

```dart
class VitalScanResult {
  final double heartRate;       // bpm
  final double heartRateVariability; // ms
  final double respiratoryRate; // breaths/min
  final DateTime timestamp;
}

class SymptomIntake {
  final List<ChatMessage> conversation;
  final String structuredSummary; // Claude-generated summary of symptoms
}

class TriageResult {
  final UrgencyLevel urgency;   // emergency, urgent, routine, selfCare
  final String clinicalReasoning;
  final String plainExplanation;
  final String watchFor;        // escalation warnings
}

class HealthSummary {
  final String sessionId;
  final DateTime timestamp;
  final String language;
  final VitalScanResult vitals;
  final SymptomIntake symptoms;
  final TriageResult triage;
}
```

---

## Urgency Levels

| Level | Color | Label | Meaning |
|---|---|---|---|
| Emergency | Red | "Seek emergency care now" | Life-threatening indicators |
| Urgent | Yellow | "See a doctor within 48 hours" | Needs medical attention soon |
| Routine | Green | "Schedule a visit when convenient" | Non-urgent but worth a checkup |
| Self-care | Blue | "Monitor at home" | Low concern, with watch-for guidance |

---

## Shareable Health Summary

The `ResultScreen` generates a summary card containing:
- Vitals snapshot (HR, HRV, RR)
- Symptoms reported (bullet list)
- Triage classification (color + label)
- Plain-language explanation
- "This is not a diagnosis" disclaimer
- Timestamp + session ID

**Share options:** Screenshot, system share sheet (WhatsApp, email, etc.), or export as PDF if time allows.

---

## Safety & Ethics (Non-negotiable)

1. **Never output a diagnosis.** Every agent prompt and every UI string says "triage" / "urgency classification"
2. **Explicit disclaimer** on every result: "This is not a medical diagnosis. Please consult a healthcare professional."
3. **Triage Agent cannot name diseases.** It outputs urgency levels and descriptive reasoning only
4. **No data persistence beyond the session** (for hackathon scope — no backend DB, no user accounts)
5. **Explainer Agent** always includes what symptoms to watch for that would escalate urgency

---

## 4-Hour Build Plan

| Time | Milestone |
|---|---|
| 0:00–0:30 | Project setup: Flutter scaffold, dependencies, navigation, theming |
| 0:30–1:15 | Scan screen: camera integration + Presage SDK bridge (or mock fallback) |
| 1:15–2:15 | Symptom chat: Claude API integration, chat UI, structured intake flow |
| 2:15–3:00 | Triage pipeline: sequential Claude calls, parse structured output, result screen |
| 3:00–3:30 | Health summary: generate shareable card, share sheet, disclaimer |
| 3:30–4:00 | Polish: animations, error states, language selection, demo rehearsal |

---

## Dependencies

| Dependency | Purpose |
|---|---|
| `camera` (Flutter plugin) | Front camera access |
| Presage SmartSpectra SDK | rPPG vitals extraction (native bridge) |
| `http` / `dio` | Claude API calls |
| `flutter_chat_ui` or custom | Chat interface for symptom intake |
| `share_plus` | System share sheet |
| `pdf` (optional) | PDF export of health summary |

---

## MVP Cut Line

**Must have (demo-critical):**
- Camera scan screen with vitals display (real or mocked)
- Conversational symptom intake via Claude
- Triage result with urgency classification
- Shareable health summary
- At least 2 languages working

**Nice to have (if time permits):**
- Real Presage SDK integration (vs. mock)
- PDF export
- Smooth animations/transitions
- 4+ languages
- Separate Claude calls for each pipeline agent (vs. combined prompt)

---

## Key Demo Moment

Scan a judge's face live. Vitals appear in 30 seconds. Walk through 6 symptom questions. Triage result comes out. They *feel* what a community health worker would feel using this. The demo is the pitch.
