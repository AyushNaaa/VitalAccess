import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/chat_message.dart';
import '../models/triage_result.dart';
import '../models/vital_scan_result.dart';

/// Token Claude emits to signal the symptom intake is finished.
const String kIntakeCompleteToken = '[INTAKE_COMPLETE]';

/// Wraps all Claude API interactions: symptom intake chat and triage pipeline.
class ClaudeService {
  final Dio _dio;
  final String _model = 'claude-sonnet-4-20250514';

  ClaudeService({required String apiKey})
      : _dio = Dio(
          BaseOptions(
            baseUrl: 'https://api.anthropic.com/v1',
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
          ),
        );

  // ---------------------------------------------------------------------------
  // 5.2 — Symptom intake
  // ---------------------------------------------------------------------------

  /// Sends the next user message and returns Claude's reply.
  ///
  /// When the reply contains [INTAKE_COMPLETE], the caller should parse
  /// the structured JSON that follows it and end the intake flow.
  ///
  /// Pass [conversationHistory] as the full prior conversation (excluding the
  /// new [userMessage] — this method appends it internally).
  Future<String> sendSymptomMessage({
    required List<ChatMessage> conversationHistory,
    required String userMessage,
    required String language,
    required VitalScanResult vitals,
  }) async {
    final messages = [
      ...conversationHistory.map((m) => m.toApiMessage()),
      {'role': 'user', 'content': userMessage},
    ];

    final systemPrompt = _buildIntakeSystemPrompt(language, vitals);

    final response = await _post('/messages', {
      'model': _model,
      'max_tokens': 1024,
      'system': systemPrompt,
      'messages': messages,
    });

    return _extractText(response);
  }

  /// Sends a forced-summary request when the chat has gone on too long.
  /// Returns a reply that must contain [INTAKE_COMPLETE].
  Future<String> forceIntakeComplete({
    required List<ChatMessage> conversationHistory,
    required String language,
    required VitalScanResult vitals,
  }) async {
    return sendSymptomMessage(
      conversationHistory: conversationHistory,
      userMessage:
          'Please summarize all the symptoms I have described so far, '
          'then end your response with $kIntakeCompleteToken followed by '
          'a JSON object summarising the symptoms.',
      language: language,
      vitals: vitals,
    );
  }

  // ---------------------------------------------------------------------------
  // 5.3 — Triage pipeline
  // ---------------------------------------------------------------------------

  /// Runs the 4-step triage pipeline and returns a [TriageResult].
  ///
  /// Steps performed inside a single Claude call:
  ///   1. Vitals Interpretation
  ///   2. Symptom Assessment
  ///   3. Triage Classification → urgency level
  ///   4. Plain-language Explanation (6th-grade, in [language])
  Future<TriageResult> runTriagePipeline({
    required VitalScanResult vitals,
    required String symptomSummary,
    required String language,
    int? age,
    String? sex,
  }) async {
    final systemPrompt = _buildTriageSystemPrompt(language);
    final userPrompt =
        _buildTriageUserPrompt(vitals, symptomSummary, age, sex, language);

    try {
      final response = await _post('/messages', {
        'model': _model,
        'max_tokens': 1024,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
      });

      final text = _extractText(response);
      return _parseTriageJson(text);
    } on ClaudeApiException {
      rethrow;
    } catch (_) {
      return TriageResult.fallback();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      return res.data!;
    } on DioException catch (e) {
      throw ClaudeApiException._fromDio(e);
    }
  }

  String _extractText(Map<String, dynamic> response) {
    final content = response['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw const ClaudeApiException('Empty response from Claude API');
    }
    final block = content.first as Map<String, dynamic>;
    return block['text'] as String? ?? '';
  }

  TriageResult _parseTriageJson(String text) {
    // Claude may wrap the JSON in a markdown code block — strip it.
    final cleaned = text
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    // Find the first { ... } block.
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1) return TriageResult.fallback();

    try {
      final json = jsonDecode(cleaned.substring(start, end + 1))
          as Map<String, dynamic>;
      return TriageResult.fromJson(json);
    } catch (_) {
      return TriageResult.fallback();
    }
  }

  // ---------------------------------------------------------------------------
  // System prompts
  // ---------------------------------------------------------------------------

  String _buildIntakeSystemPrompt(String language, VitalScanResult vitals) {
    final vitalsJson = jsonEncode(vitals.toJson());
    final langName = _languageName(language);

    return '''
You are a structured symptom collector for VitalAccess, a health triage app.
You are NOT a doctor and you do NOT diagnose. Your only job is to collect symptoms clearly and efficiently.

RULES — follow these exactly:
1. Ask ONE clear, plain-language question at a time.
2. Branch your next question based on the user's answer (e.g. if they say "chest pain", ask about nature, duration, triggers).
3. Respond in $langName. Keep all messages in $langName.
4. Never name a disease, condition, or diagnosis. Never say "you have X" or "this sounds like X".
5. Ask between 5 and 8 questions total, then end the intake.
6. When you have collected enough information (after 5–8 exchanges), output your final message in this exact format:

[INTAKE_COMPLETE]
{"symptoms": "<plain English bullet list of symptoms reported>", "duration": "<how long symptoms have been present>", "severity": "<mild/moderate/severe>", "additional_context": "<any other relevant details>"}

Start your very first message with: "Do you have any symptoms or concerns right now?"

PATIENT VITALS CONTEXT (use this to guide relevant follow-up questions):
$vitalsJson
''';
  }

  String _buildTriageSystemPrompt(String language) {
    final langName = _languageName(language);

    return '''
You are a clinical triage classifier for VitalAccess, a health triage app used in low-resource settings.

You perform TRIAGE ONLY — not diagnosis. You classify urgency. You never name specific diseases or conditions.
Never say "you have X". Always say "this suggests you should see a doctor because..." or "your vitals indicate...".

You will reason through 4 steps and output structured JSON:

STEP 1 — VITALS INTERPRETATION
Analyse the provided HR, HRV (SDNN & RMSSD), and respiratory rate against standard clinical baselines for the patient's age/sex. Note deviations. Do not diagnose.

STEP 2 — SYMPTOM ASSESSMENT
Map the reported symptom cluster to clinical patterns (e.g. "elevated HR + chest tightness + shortness of breath = possible cardiac or respiratory concern"). Do not name conditions.

STEP 3 — TRIAGE CLASSIFICATION
Fuse steps 1 and 2 into exactly one urgency level:
  - "emergency"  → potential life-threatening concern, seek care immediately
  - "urgent"     → significant concern, see a doctor within 48 hours
  - "routine"    → non-urgent concern, schedule a visit when convenient
  - "selfCare"   → low concern, monitor at home

STEP 4 — PLAIN-LANGUAGE EXPLANATION
Rewrite the reasoning at a 6th-grade reading level in $langName. Avoid medical jargon.
Include what symptoms to watch for that would escalate urgency.

OUTPUT FORMAT — respond with ONLY this JSON object, no other text:
{
  "urgency": "emergency|urgent|routine|selfCare",
  "clinicalReasoning": "<step 1+2 reasoning, 2-3 sentences, plain language>",
  "plainExplanation": "<step 4 explanation in $langName, 3-5 sentences>",
  "watchFor": "<comma-separated list of escalation warning signs in $langName>"
}
''';
  }

  String _buildTriageUserPrompt(
    VitalScanResult vitals,
    String symptomSummary,
    int? age,
    String? sex,
    String language,
  ) {
    final vitalsJson = jsonEncode(vitals.toJson());
    final ageStr = age != null ? '$age years old' : 'unknown age';
    final sexStr = sex ?? 'unknown sex';

    return '''
PATIENT: $ageStr, $sexStr

VITALS (measured via rPPG face scan):
$vitalsJson

SYMPTOMS REPORTED:
$symptomSummary

Please classify the urgency and provide a plain-language explanation.
''';
  }

  String _languageName(String code) {
    switch (code) {
      case 'fr':
        return 'French';
      case 'es':
        return 'Spanish';
      case 'ar':
        return 'Arabic';
      default:
        return 'English';
    }
  }
}

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

class ClaudeApiException implements Exception {
  final String message;
  final int? statusCode;

  const ClaudeApiException(this.message, {this.statusCode});

  factory ClaudeApiException._fromDio(DioException e) {
    final code = e.response?.statusCode;
    final data = e.response?.data;
    String msg;

    switch (code) {
      case 401:
        msg = 'Invalid API key. Check your ANTHROPIC_API_KEY in .env.';
      case 429:
        msg = 'Rate limited. Please wait a moment and try again.';
      case 500:
      case 529:
        msg = 'Claude API is temporarily unavailable. Try again shortly.';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          msg = 'Request timed out. Check your connection and try again.';
        } else if (e.type == DioExceptionType.connectionError) {
          msg = 'No internet connection. Check your network and try again.';
        } else {
          final error = data is Map ? data['error'] : null;
          final detail = error is Map ? error['message'] : null;
          msg = detail as String? ?? 'Unexpected error (${e.message})';
        }
    }
    return ClaudeApiException(msg, statusCode: code);
  }

  @override
  String toString() => 'ClaudeApiException($statusCode): $message';
}
