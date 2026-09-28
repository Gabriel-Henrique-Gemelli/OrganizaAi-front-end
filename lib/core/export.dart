import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import 'save_web.dart' if (dart.library.io) 'save_native.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';
export 'csv.dart';

Future<void> saveBytes(String name, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Salvar arquivo',
    fileName: name,
    bytes: bytes,
  );
  await ensureDesktopSave(path, bytes);
}

Future<Uint8List> diaryPdf(DiaryEntry entry, String project) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/IBMPlexMono-Regular.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 200,
      margin: pw.EdgeInsets.all(40),
      build: (_) => [
        pw.Text(
          'OrganizAI | DIARIO DE OBRA',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text(project),
        pw.Text('Data: ${entry.date.toIso8601String().substring(0, 10)}'),
        pw.Text('Autor: ${entry.author} | ${entry.role}'),
        pw.Text('Situacao: ${entry.status}'),
        if (entry.reviewer.isNotEmpty) pw.Text('Revisor: ${entry.reviewer}'),
        pw.Divider(),
        for (var start = 0; start < entry.displayText.length; start += 1200)
          pw.Paragraph(
            text: entry.displayText.substring(
              start,
              (start + 1200).clamp(0, entry.displayText.length).toInt(),
            ),
          ),
        pw.SizedBox(height: 20),
        for (final e in entry.details.entries)
          pw.Paragraph(text: '${e.key}: ${e.value}'),
        if (entry.weather.isNotEmpty) ...[
          pw.Text('Clima'),
          for (final e in entry.weather.entries)
            if (e.value != null)
              pw.Paragraph(
                text:
                    '${const {'temperaturaC': 'Temperatura (°C)', 'condicao': 'Condição', 'umidadePercent': 'Umidade (%)', 'ventoKmh': 'Vento (km/h)', 'precipitacaoMm': 'Chuva (mm)', 'fonte': 'Fonte'}[e.key] ?? e.key}: ${e.value}',
              ),
        ],
        pw.Divider(),
        pw.Text(
          'Registro exportado pelo aplicativo; sem assinatura digital.',
          style: pw.TextStyle(fontSize: 9),
        ),
      ],
    ),
  );
  return doc.save();
}
