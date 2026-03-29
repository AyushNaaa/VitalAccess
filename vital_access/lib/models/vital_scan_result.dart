// Stub — full implementation in Task 2
class VitalScanResult {
  final double heartRate;
  final double hrvSdnn;
  final double hrvRmssd;
  final double respiratoryRate;
  final String confidence;
  final double actualFps;
  final DateTime timestamp;

  const VitalScanResult({
    required this.heartRate,
    required this.hrvSdnn,
    required this.hrvRmssd,
    required this.respiratoryRate,
    required this.confidence,
    required this.actualFps,
    required this.timestamp,
  });
}
