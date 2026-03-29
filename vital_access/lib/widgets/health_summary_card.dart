import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/health_summary.dart';
import 'urgency_badge.dart';

class HealthSummaryCard extends StatelessWidget {
  final HealthSummary summary;
  final String lang;

  const HealthSummaryCard({super.key, required this.summary, this.lang = 'en'});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const Divider(height: 1, color: AppColors.border),
          _buildVitalsSection(context),
          const Divider(height: 1, color: AppColors.border),
          if (summary.symptoms.structuredSummary.isNotEmpty) ...[
            _buildSymptomsSection(context),
            const Divider(height: 1, color: AppColors.border),
          ],
          _buildTriageSection(context),
          if (summary.triage.watchFor.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.border),
            _buildWatchForSection(context),
          ],
          const Divider(height: 1, color: AppColors.border),
          _buildFooter(context),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(BuildContext context) {
    final ts = summary.timestamp;
    final dateStr =
        '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year}  '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(lang, 'vitals_summary'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                ),
                Text(
                  dateStr,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
          _SessionIdChip(sessionId: summary.sessionId),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Vitals
  // ---------------------------------------------------------------------------

  Widget _buildVitalsSection(BuildContext context) {
    final v = summary.vitals;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, '📊', t(lang, 'vitals_section')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _VitalChip(
                  icon: Icons.favorite_rounded,
                  iconColor: AppColors.emergency,
                  label: t(lang, 'heart_rate'),
                  value: v.heartRate.toStringAsFixed(0),
                  unit: t(lang, 'bpm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VitalChip(
                  icon: Icons.show_chart_rounded,
                  iconColor: AppColors.primary,
                  label: t(lang, 'hrv_sdnn'),
                  value: v.hrvSdnn.toStringAsFixed(0),
                  unit: t(lang, 'ms'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _VitalChip(
                  icon: Icons.air_rounded,
                  iconColor: AppColors.selfCare,
                  label: t(lang, 'resp_rate'),
                  value: v.respiratoryRate.toStringAsFixed(0),
                  unit: t(lang, 'per_min'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _VitalChip(
                  icon: Icons.verified_rounded,
                  iconColor: _confidenceColor(v.confidence),
                  label: t(lang, 'confidence'),
                  value: v.confidence[0].toUpperCase() +
                      v.confidence.substring(1),
                  unit: '',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Symptoms
  // ---------------------------------------------------------------------------

  Widget _buildSymptomsSection(BuildContext context) {
    final lines = summary.symptoms.structuredSummary
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, '🗣', t(lang, 'symptoms_reported')),
          const SizedBox(height: 10),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.subtle,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontSize: 13,
                            color: AppColors.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Triage
  // ---------------------------------------------------------------------------

  Widget _buildTriageSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, '🔔', t(lang, 'triage_result')),
          const SizedBox(height: 10),
          UrgencyBadge(urgency: summary.triage.urgency),
          const SizedBox(height: 12),
          Text(
            summary.triage.plainExplanation,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 13,
                  color: AppColors.onSurface,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Watch-for
  // ---------------------------------------------------------------------------

  Widget _buildWatchForSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.emergencyLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.emergency.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppColors.emergency),
              const SizedBox(width: 6),
              Text(
                t(lang, 'watch_for'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.emergency,
                      fontSize: 12,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            summary.triage.watchFor,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 12,
                  color: AppColors.emergency,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Footer disclaimer
  // ---------------------------------------------------------------------------

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: AppColors.subtle),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t(lang, 'disclaimer_full'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _sectionLabel(BuildContext context, String emoji, String label) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.subtle,
                fontSize: 11,
                letterSpacing: 0.5,
              ),
        ),
      ],
    );
  }

  Color _confidenceColor(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return AppColors.qualityHigh;
      case 'medium':
        return AppColors.qualityMedium;
      default:
        return AppColors.qualityLow;
    }
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _VitalChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;

  const _VitalChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.subtle,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.subtle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionIdChip extends StatelessWidget {
  final String sessionId;

  const _SessionIdChip({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '#$sessionId',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.subtle,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
