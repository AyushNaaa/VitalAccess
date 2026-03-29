// Stub — full implementation in Task 2
import 'vital_scan_result.dart';
import 'symptom_intake.dart';
import 'triage_result.dart';

class HealthSummary {
  final String sessionId;
  final DateTime timestamp;
  final String language;
  final VitalScanResult vitals;
  final SymptomIntake symptoms;
  final TriageResult triage;

  const HealthSummary({
    required this.sessionId,
    required this.timestamp,
    required this.language,
    required this.vitals,
    required this.symptoms,
    required this.triage,
  });
}
