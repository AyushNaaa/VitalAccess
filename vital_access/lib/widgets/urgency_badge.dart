import 'package:flutter/material.dart';
import '../models/triage_result.dart';

class UrgencyBadge extends StatelessWidget {
  final UrgencyLevel urgency;

  /// [large] = hero version at the top of ResultScreen.
  /// [small] = compact version inside HealthSummaryCard.
  final bool large;

  const UrgencyBadge({super.key, required this.urgency, this.large = false});

  @override
  Widget build(BuildContext context) {
    return large ? _buildLarge(context) : _buildSmall(context);
  }

  Widget _buildLarge(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: urgency.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: urgency.color.withAlpha(80),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(urgency.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              urgency.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmall(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: urgency.lightColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: urgency.color.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(urgency.icon, color: urgency.color, size: 14),
          const SizedBox(width: 6),
          Text(
            urgency.label,
            style: TextStyle(
              color: urgency.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
