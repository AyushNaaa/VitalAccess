// Stub — full implementation in Task 2
enum UrgencyLevel { emergency, urgent, routine, selfCare }

class TriageResult {
  final UrgencyLevel urgency;
  final String clinicalReasoning;
  final String plainExplanation;
  final String watchFor;

  const TriageResult({
    required this.urgency,
    required this.clinicalReasoning,
    required this.plainExplanation,
    required this.watchFor,
  });
}
