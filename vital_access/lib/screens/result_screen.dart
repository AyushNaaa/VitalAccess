import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/health_summary.dart';
import '../providers/session_provider.dart';
import '../services/share_service.dart';
import '../widgets/health_summary_card.dart';
import '../widgets/urgency_badge.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  bool _sharingText = false;
  bool _sharingPdf = false;

  final _shareService = ShareService();

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _fadeAnim =
        CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _onShareText(HealthSummary summary) async {
    setState(() => _sharingText = true);
    final lang = context.read<SessionProvider>().language;
    try {
      await _shareService.shareAsText(summary);
    } catch (_) {
      if (mounted) _showError(t(lang, 'share_error'));
    } finally {
      if (mounted) setState(() => _sharingText = false);
    }
  }

  Future<void> _onSharePdf(HealthSummary summary) async {
    setState(() => _sharingPdf = true);
    final lang = context.read<SessionProvider>().language;
    try {
      await _shareService.shareAsPdf(summary);
    } catch (_) {
      if (mounted) _showError(t(lang, 'pdf_error'));
    } finally {
      if (mounted) setState(() => _sharingPdf = false);
    }
  }

  void _onStartOver() {
    context.read<SessionProvider>().reset();
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.language,
      (route) => false,
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.emergency,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final summary = session.healthSummary;
    final lang = session.language;

    if (summary == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(t(lang, 'no_results')),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _onStartOver,
                child: Text(t(lang, 'start_over')),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              _buildTopSection(context, summary, lang),
              Expanded(child: _buildScrollableBody(summary, lang)),
              _buildBottomActions(context, summary, lang),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top section: safe area + urgency badge + explanation + disclaimer
  // ---------------------------------------------------------------------------

  Widget _buildTopSection(
      BuildContext context, HealthSummary summary, String lang) {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // App bar row
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.onSurface,
                    onPressed: () => Navigator.of(context).maybePop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    t(lang, 'your_results'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Large urgency badge
              UrgencyBadge(urgency: summary.triage.urgency, large: true),
              const SizedBox(height: 14),

              // Plain explanation
              Text(
                summary.triage.plainExplanation,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.onSurface,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 14),

              // Disclaimer — always visible, never scrolled away
              _buildDisclaimerStrip(context, lang),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDisclaimerStrip(BuildContext context, String lang) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.urgentLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.urgent.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: AppColors.urgent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t(lang, 'disclaimer_full'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    color: AppColors.urgent,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Scrollable body: full health summary card
  // ---------------------------------------------------------------------------

  Widget _buildScrollableBody(HealthSummary summary, String lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: HealthSummaryCard(summary: summary, lang: lang),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom action buttons
  // ---------------------------------------------------------------------------

  Widget _buildBottomActions(
      BuildContext context, HealthSummary summary, String lang) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Share row
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: t(lang, 'share_summary'),
                  icon: Icons.share_rounded,
                  loading: _sharingText,
                  onTap: () => _onShareText(summary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  label: t(lang, 'save_pdf'),
                  icon: Icons.picture_as_pdf_rounded,
                  loading: _sharingPdf,
                  outlined: true,
                  onTap: () => _onSharePdf(summary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Start over
          TextButton.icon(
            onPressed: _onStartOver,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(t(lang, 'start_over')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.subtle,
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action button with loading state
// ---------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final bool outlined;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          );

    if (outlined) {
      return OutlinedButton(
        onPressed: loading ? null : onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: child,
      );
    }

    return ElevatedButton(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: child,
    );
  }
}
