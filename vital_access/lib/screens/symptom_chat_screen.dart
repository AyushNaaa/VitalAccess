import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/chat_message.dart';
import '../models/symptom_intake.dart';
import '../models/vital_scan_result.dart';
import '../providers/session_provider.dart';
import '../services/claude_service.dart';
import '../widgets/chat_bubble.dart';

class SymptomChatScreen extends StatefulWidget {
  const SymptomChatScreen({super.key});

  @override
  State<SymptomChatScreen> createState() => _SymptomChatScreenState();
}

class _SymptomChatScreenState extends State<SymptomChatScreen> {
  final _scrollController = ScrollController();
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  late final ClaudeService _claude;
  late final VitalScanResult _vitals;
  late final String _language;

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _inputEnabled = false;
  bool _intakeComplete = false;
  String? _errorMessage;

  /// Number of full user→assistant exchanges completed.
  int _exchangeCount = 0;

  /// Show "Finish intake" button after 10 exchanges.
  bool get _showForceFinish => _exchangeCount >= 10 && !_intakeComplete;

  @override
  void initState() {
    super.initState();

    final session = context.read<SessionProvider>();
    _language = session.language;
    _vitals = session.vitalScanResult!;

    final apiKey = dotenv.env['ANTHROPIC_API_KEY'] ?? '';
    _claude = ClaudeService(apiKey: apiKey);

    // Claude sends the first message — no user input needed to start.
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendOpeningMessage());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Messaging logic
  // ---------------------------------------------------------------------------

  /// Called once on load — kicks off the conversation with Claude's first question.
  Future<void> _sendOpeningMessage() async {
    setState(() {
      _isTyping = true;
      _errorMessage = null;
    });

    try {
      // Pass an empty history and a silent "start" user message.
      // The system prompt instructs Claude to open with the first question.
      final reply = await _claude.sendSymptomMessage(
        conversationHistory: const [],
        userMessage: 'start',
        language: _language,
        vitals: _vitals,
      );

      final cleaned = _stripIntakeToken(reply);
      _appendAssistant(cleaned);
      setState(() => _inputEnabled = true);
    } on ClaudeApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isTyping || !_inputEnabled) return;

    _textController.clear();
    _focusNode.unfocus();

    _appendUser(text);
    setState(() {
      _isTyping = true;
      _inputEnabled = false;
      _errorMessage = null;
    });
    _scrollToBottom();

    try {
      final reply = await _claude.sendSymptomMessage(
        conversationHistory: _messages.sublist(0, _messages.length - 1),
        userMessage: text,
        language: _language,
        vitals: _vitals,
      );

      _exchangeCount++;
      _handleReply(reply);
    } on ClaudeApiException catch (e) {
      setState(() => _errorMessage = e.message);
      // Re-enable input so the user can retry.
      setState(() => _inputEnabled = true);
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  Future<void> _onForceFinish() async {
    setState(() {
      _isTyping = true;
      _inputEnabled = false;
      _errorMessage = null;
    });
    _scrollToBottom();

    try {
      final reply = await _claude.forceIntakeComplete(
        conversationHistory: _messages,
        language: _language,
        vitals: _vitals,
      );
      _handleReply(reply);
    } on ClaudeApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _inputEnabled = true;
      });
    } finally {
      if (mounted) setState(() => _isTyping = false);
    }
  }

  void _handleReply(String reply) {
    if (reply.contains(kIntakeCompleteToken)) {
      final displayText = _stripIntakeToken(reply).trim();
      if (displayText.isNotEmpty) _appendAssistant(displayText);
      _completeIntake(reply);
    } else {
      _appendAssistant(reply);
      setState(() => _inputEnabled = true);
    }
    _scrollToBottom();
  }

  void _completeIntake(String fullReply) {
    setState(() => _intakeComplete = true);

    final summary = _extractSymptomSummary(fullReply);
    final intake = SymptomIntake(
      conversation: List.unmodifiable(_messages),
      structuredSummary: summary,
    );

    context.read<SessionProvider>().setSymptomIntake(intake);

    // Brief pause so the user sees Claude's closing message before we navigate.
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.processing);
    });
  }

  // ---------------------------------------------------------------------------
  // Skip
  // ---------------------------------------------------------------------------

  void _onSkip() {
    final intake = SymptomIntake(
      conversation: List.unmodifiable(_messages),
      structuredSummary: 'No symptoms reported — vitals-only triage.',
    );
    context.read<SessionProvider>().setSymptomIntake(intake);
    Navigator.of(context).pushReplacementNamed(AppRoutes.processing);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _appendUser(String text) {
    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ));
    });
  }

  void _appendAssistant(String text) {
    if (text.isEmpty) return;
    setState(() {
      _messages.add(ChatMessage(
        role: 'assistant',
        content: text,
        timestamp: DateTime.now(),
      ));
    });
  }

  /// Removes everything from [INTAKE_COMPLETE] onward, returning just the
  /// human-readable portion of Claude's message.
  String _stripIntakeToken(String reply) {
    final idx = reply.indexOf(kIntakeCompleteToken);
    return idx == -1 ? reply : reply.substring(0, idx).trim();
  }

  /// Extracts the JSON symptom summary that follows [INTAKE_COMPLETE] and
  /// converts it to a readable multi-line string.
  String _extractSymptomSummary(String reply) {
    final idx = reply.indexOf(kIntakeCompleteToken);
    if (idx == -1) return reply;

    final after = reply.substring(idx + kIntakeCompleteToken.length).trim();
    final jsonStart = after.indexOf('{');
    final jsonEnd = after.lastIndexOf('}');

    if (jsonStart == -1 || jsonEnd == -1) return after;

    try {
      final map =
          jsonDecode(after.substring(jsonStart, jsonEnd + 1)) as Map<String, dynamic>;

      final buffer = StringBuffer();
      final symptoms = map['symptoms'];
      final duration = map['duration'];
      final severity = map['severity'];
      final context = map['additional_context'];

      if (symptoms != null && symptoms.toString().isNotEmpty) {
        buffer.writeln('Symptoms: $symptoms');
      }
      if (duration != null && duration.toString().isNotEmpty) {
        buffer.writeln('Duration: $duration');
      }
      if (severity != null && severity.toString().isNotEmpty) {
        buffer.writeln('Severity: $severity');
      }
      if (context != null && context.toString().isNotEmpty) {
        buffer.writeln('Additional context: $context');
      }

      return buffer.toString().trim();
    } catch (_) {
      return after;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          if (_errorMessage != null) _buildErrorBanner(),
          if (_showForceFinish) _buildForceFinishBanner(),
          _buildInputRow(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Text(t(_language, 'chat_title')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _intakeComplete ? null : _onSkip,
          child: Text(
            t(_language, 'chat_skip'),
            style: TextStyle(
              color: _intakeComplete ? AppColors.subtle : AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _isTyping) {
          return const TypingIndicator();
        }
        return ChatBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.emergencyLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.emergency.withAlpha(80)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              size: 16, color: AppColors.emergency),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                  color: AppColors.emergency,
                  fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _errorMessage = null),
            child: Icon(Icons.close_rounded,
                size: 16, color: AppColors.emergency),
          ),
        ],
      ),
    );
  }

  Widget _buildForceFinishBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: OutlinedButton.icon(
        onPressed: _isTyping ? null : _onForceFinish,
        icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
        label: Text(t(_language, 'finish_intake')),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    );
  }

  Widget _buildInputRow() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                enabled: _inputEnabled && !_intakeComplete,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: t(_language, 'chat_hint'),
                  hintStyle: TextStyle(color: AppColors.subtle),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide:
                        BorderSide(color: AppColors.primary, width: 2),
                  ),
                  filled: true,
                  fillColor: _inputEnabled && !_intakeComplete
                      ? AppColors.surface
                      : AppColors.background,
                ),
                onSubmitted: (_) => _onSend(),
              ),
            ),
            const SizedBox(width: 10),
            _SendButton(
              enabled: _inputEnabled && !_intakeComplete,
              onTap: _onSend,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Send button with press animation
// ---------------------------------------------------------------------------

class _SendButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _SendButton({required this.enabled, required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => _ctrl.reverse() : null,
      onTapUp: widget.enabled
          ? (_) {
              _ctrl.forward();
              widget.onTap();
            }
          : null,
      onTapCancel: () => _ctrl.forward(),
      child: ScaleTransition(
        scale: _ctrl,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.enabled ? AppColors.primary : AppColors.border,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.send_rounded,
            color: widget.enabled ? Colors.white : AppColors.subtle,
            size: 20,
          ),
        ),
      ),
    );
  }
}
