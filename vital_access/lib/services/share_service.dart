import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../models/health_summary.dart';
import '../models/triage_result.dart';

class ShareService {
  /// Opens the system share sheet with the summary as plain text.
  Future<void> shareAsText(HealthSummary summary) async {
    await Share.share(
      summary.toShareableText(),
      subject: 'VitalAccess Health Summary — ${_dateStr(summary.timestamp)}',
    );
  }

  /// Generates a PDF and shares it via the system share sheet.
  Future<void> shareAsPdf(HealthSummary summary) async {
    final file = await _buildPdf(summary);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'VitalAccess Health Summary — ${_dateStr(summary.timestamp)}',
    );
  }

  // ---------------------------------------------------------------------------
  // PDF generation
  // ---------------------------------------------------------------------------

  Future<File> _buildPdf(HealthSummary summary) async {
    final doc = pw.Document();

    final urgencyColor = _pdfColor(summary.triage.urgency);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) => [
          _pdfHeader(summary),
          pw.SizedBox(height: 20),
          _pdfUrgencyBanner(summary.triage, urgencyColor),
          pw.SizedBox(height: 20),
          _pdfVitalsSection(summary),
          pw.SizedBox(height: 16),
          if (summary.symptoms.structuredSummary.isNotEmpty) ...[
            _pdfSymptomsSection(summary),
            pw.SizedBox(height: 16),
          ],
          _pdfExplanationSection(summary),
          if (summary.triage.watchFor.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _pdfWatchForSection(summary, urgencyColor),
          ],
          pw.SizedBox(height: 24),
          _pdfDisclaimer(),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final fileName =
        'VitalAccess_${summary.sessionId}_${_fileDateStr(summary.timestamp)}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  pw.Widget _pdfHeader(HealthSummary summary) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'VitalAccess',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#0D9488'),
              ),
            ),
            pw.Text(
              'Health Summary',
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColor.fromHex('#64748B'),
              ),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              _dateStr(summary.timestamp),
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColor.fromHex('#64748B'),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              'Session #${summary.sessionId}',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColor.fromHex('#94A3B8'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _pdfUrgencyBanner(TriageResult triage, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(
        triage.urgency.label.toUpperCase(),
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 15,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  pw.Widget _pdfVitalsSection(HealthSummary summary) {
    final v = summary.vitals;
    final items = [
      ('Heart Rate', '${v.heartRate.toStringAsFixed(0)} bpm'),
      ('HRV (SDNN)', '${v.hrvSdnn.toStringAsFixed(0)} ms'),
      ('HRV (RMSSD)', '${v.hrvRmssd.toStringAsFixed(0)} ms'),
      ('Respiratory Rate', '${v.respiratoryRate.toStringAsFixed(0)} /min'),
      (
        'Confidence',
        v.confidence[0].toUpperCase() + v.confidence.substring(1)
      ),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pdfSectionTitle('VITALS'),
        pw.SizedBox(height: 8),
        pw.Wrap(
          spacing: 10,
          runSpacing: 8,
          children: items
              .map(
                (item) => pw.Container(
                  width: 155,
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8FAFC'),
                    border: pw.Border.all(
                        color: PdfColor.fromHex('#E2E8F0')),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        item.$1,
                        style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromHex('#64748B'),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        item.$2,
                        style: pw.TextStyle(
                          fontSize: 15,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#1E293B'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  pw.Widget _pdfSymptomsSection(HealthSummary summary) {
    final lines = summary.symptoms.structuredSummary
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pdfSectionTitle('SYMPTOMS REPORTED'),
        pw.SizedBox(height: 8),
        ...lines.map(
          (line) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('• ',
                    style: pw.TextStyle(
                        color: PdfColor.fromHex('#64748B'))),
                pw.Expanded(
                  child: pw.Text(
                    line,
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfExplanationSection(HealthSummary summary) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _pdfSectionTitle('TRIAGE EXPLANATION'),
        pw.SizedBox(height: 8),
        pw.Text(
          summary.triage.plainExplanation,
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
        ),
      ],
    );
  }

  pw.Widget _pdfWatchForSection(HealthSummary summary, PdfColor color) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FEE2E2'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#DC2626')),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'SEEK IMMEDIATE CARE IF:',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#DC2626'),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            summary.triage.watchFor,
            style: pw.TextStyle(
              fontSize: 11,
              color: PdfColor.fromHex('#DC2626'),
              lineSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfDisclaimer() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F1F5F9'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
      ),
      child: pw.Text(
        '⚠ This is NOT a medical diagnosis. This summary is intended to '
        'assist communication with a healthcare provider. Always consult '
        'a qualified healthcare professional for medical advice.',
        style: pw.TextStyle(
          fontSize: 9,
          color: PdfColor.fromHex('#64748B'),
          fontStyle: pw.FontStyle.italic,
          lineSpacing: 2,
        ),
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('#64748B'),
        letterSpacing: 0.5,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _dateStr(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _fileDateStr(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

  PdfColor _pdfColor(UrgencyLevel level) {
    switch (level) {
      case UrgencyLevel.emergency:
        return PdfColor.fromHex('#DC2626');
      case UrgencyLevel.urgent:
        return PdfColor.fromHex('#D97706');
      case UrgencyLevel.routine:
        return PdfColor.fromHex('#16A34A');
      case UrgencyLevel.selfCare:
        return PdfColor.fromHex('#2563EB');
    }
  }
}
