import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../models/vital_scan_result.dart';

/// A 2×2 grid of vitals cards shown after the scan completes.
/// Each card fades in and slides up with a staggered entrance animation.
class VitalsDisplay extends StatefulWidget {
  final VitalScanResult vitals;
  final String lang;

  const VitalsDisplay({super.key, required this.vitals, this.lang = 'en'});

  @override
  State<VitalsDisplay> createState() => _VitalsDisplayState();
}

class _VitalsDisplayState extends State<VitalsDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _fadeAnims;
  late final List<Animation<Offset>> _slideAnims;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Stagger: each card starts 80ms after the previous one
    _fadeAnims = List.generate(4, (i) {
      final start = i * 0.15;
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
              curve: Curves.easeOut),
        ),
      );
    });

    _slideAnims = List.generate(4, (i) {
      final start = i * 0.15;
      return Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
              curve: Curves.easeOut),
        ),
      );
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.vitals;
    final l = widget.lang;
    final cards = [
      _VitalCard(
        label: t(l, 'heart_rate'),
        value: v.heartRate.toStringAsFixed(0),
        unit: t(l, 'bpm'),
        icon: Icons.favorite_rounded,
        iconColor: AppColors.emergency,
      ),
      _VitalCard(
        label: t(l, 'hrv_sdnn'),
        value: v.hrvSdnn.toStringAsFixed(0),
        unit: t(l, 'ms'),
        icon: Icons.show_chart_rounded,
        iconColor: AppColors.primary,
      ),
      _VitalCard(
        label: t(l, 'resp_rate'),
        value: v.respiratoryRate.toStringAsFixed(0),
        unit: t(l, 'per_min'),
        icon: Icons.air_rounded,
        iconColor: AppColors.selfCare,
      ),
      _VitalCard(
        label: t(l, 'confidence'),
        value: _capitalise(v.confidence),
        unit: '',
        icon: _confidenceIcon(v.confidence),
        iconColor: _confidenceColor(v.confidence),
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: List.generate(4, (i) {
        return FadeTransition(
          opacity: _fadeAnims[i],
          child: SlideTransition(
            position: _slideAnims[i],
            child: cards[i],
          ),
        );
      }),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  IconData _confidenceIcon(String c) {
    switch (c) {
      case 'high':
        return Icons.check_circle_rounded;
      case 'medium':
        return Icons.info_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  Color _confidenceColor(String c) {
    switch (c) {
      case 'high':
        return AppColors.routine;
      case 'medium':
        return AppColors.urgent;
      default:
        return AppColors.qualityLow;
    }
  }
}

// ---------------------------------------------------------------------------
// Single vitals card
// ---------------------------------------------------------------------------

class _VitalCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color iconColor;

  const _VitalCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: iconColor, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: tt.displayMedium?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      height: 1.0,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        unit,
                        style: tt.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: AppColors.subtle,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: tt.bodyMedium?.copyWith(
                  fontSize: 12,
                  color: AppColors.subtle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
