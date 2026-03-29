VitalAccess — Simple Breakdown
The Core Insight (One Sentence)
Your phone camera can measure your heartbeat. The Presage SmartSpectra SDK (which you already used in Lucid) detects tiny color changes in your face caused by blood flow — no hardware needed. That's the whole unlock.

How It Actually Works, Layer by Layer
Layer 1 — Biometric Capture (Presage SDK)
User holds their phone up, faces the camera for 30 seconds. The SDK analyzes rPPG (remote photoplethysmography) — it reads micro-fluctuations in skin color from blood pumping through facial capillaries. Output:

Heart Rate (HR)
Heart Rate Variability (HRV)
Respiratory Rate

No wearable. No oximeter. Just a $50 Android phone.
Layer 2 — Symptom Collection (Claude API, Conversational)
After the scan, Claude runs a guided symptom intake — NOT a free-text dump. It asks structured, branching questions like a nurse would:

"Where is the pain?"
"Does it get worse when you breathe deeply?"
"How long has this been happening?"

Multi-language, plain language, works for someone who's never seen a doctor form before.
Layer 3 — The LangGraph Pipeline (4 Agents)
Vitals Interpreter → Symptom Assessor → Triage Agent → Explainer Agent
AgentWhat It DoesVitals InterpreterTakes HR/HRV/RR, compares against clinical baselines for age/sex. "HR of 102 in a 45-year-old woman = mildly elevated, possible fever/stress/cardiac"Symptom AssessorStructured differential reasoning. Maps symptom clusters to clinical patterns. "Chest tightness + elevated HR + shortness of breath = flag for cardiac or respiratory"Triage AgentFuses vitals context + symptom assessment → one of 4 urgency levelsExplainer AgentRewrites everything at a 6th-grade reading level in the user's language
Layer 4 — Output
A printable/shareable health summary the user shows a doctor:

Vitals snapshot
Symptoms reported
Triage classification
Plain-language explanation
Timestamp + session ID


The Full User Flow
[1] Open app → select language
        ↓
[2] "Hold phone at arm's length, look at camera"
    → 30-second face scan
    → Vitals appear on screen (HR: 88bpm, HRV: 42ms, RR: 16/min)
        ↓
[3] Conversational symptom intake
    Claude: "Do you have any pain right now?"
    User: "Yes, chest"
    Claude: "Is it sharp or more like pressure?"
    → ~5-8 questions, branching based on answers
        ↓
[4] LangGraph pipeline runs (takes ~10-15 seconds)
    → 4 agents fire in sequence
        ↓
[5] Triage result displayed:
    🟡 "Schedule a visit within 48 hours"
    Plain explanation of why
    What to watch for that would escalate it
        ↓
[6] Health summary generated
    → Can screenshot, print, or share via WhatsApp
    → User walks into clinic and SHOWS it to the doctor
