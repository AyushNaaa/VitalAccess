import 'package:flutter/foundation.dart';
import '../models/vital_scan_result.dart';
import '../models/symptom_intake.dart';
import '../models/triage_result.dart';
import '../models/health_summary.dart';

class SessionProvider extends ChangeNotifier {
  String _language = 'en';
  VitalScanResult? _vitalScanResult;
  SymptomIntake? _symptomIntake;
  TriageResult? _triageResult;
  HealthSummary? _healthSummary;

  // Demo mode: skip the 30-second scan wait
  bool _demoMode = false;

  // Getters
  String get language => _language;
  VitalScanResult? get vitalScanResult => _vitalScanResult;
  SymptomIntake? get symptomIntake => _symptomIntake;
  TriageResult? get triageResult => _triageResult;
  HealthSummary? get healthSummary => _healthSummary;
  bool get demoMode => _demoMode;

  void setLanguage(String code) {
    _language = code;
    notifyListeners();
  }

  void setVitalScanResult(VitalScanResult result) {
    _vitalScanResult = result;
    notifyListeners();
  }

  void setSymptomIntake(SymptomIntake intake) {
    _symptomIntake = intake;
    notifyListeners();
  }

  void setTriageResult(TriageResult result) {
    _triageResult = result;
    notifyListeners();
  }

  void setHealthSummary(HealthSummary summary) {
    _healthSummary = summary;
    notifyListeners();
  }

  void toggleDemoMode() {
    _demoMode = !_demoMode;
    notifyListeners();
  }

  /// Reset all session data to start a new scan.
  void reset() {
    _vitalScanResult = null;
    _symptomIntake = null;
    _triageResult = null;
    _healthSummary = null;
    notifyListeners();
  }
}
