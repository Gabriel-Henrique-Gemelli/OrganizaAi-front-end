// ignore_for_file: avoid_relative_lib_imports
// ignore_for_file: avoid_print
// Testes executáveis sem pub get: dart tool/core_check.dart
import 'dart:convert';

import '../lib/core/config.dart';
import '../lib/core/csv.dart';
import '../lib/data/models.dart';

void check(bool condition, String description) {
  if (!condition) throw StateError(description);
  print('OK $description');
}

void main() {
  check(
    AppConfig.validateUrl('http://192.168.1.20:8080') == null,
    'URL de desenvolvimento em LAN',
  );
  check(
    AppConfig.validateUrl('http://api.example.com') != null,
    'HTTP público recusado',
  );
  check(
    AppConfig.validateUrl('https://user:password@example.com') != null,
    'Credenciais na URL recusadas',
  );
  check(
    AppConfig.validateUrl('https://example.com/api?token=secret') != null,
    'Token em query recusado',
  );
  check(
    AppConfig.documentTypes['xlsx'] ==
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'MIME de Excel do contrato Java',
  );
  check(
    AppConfig.maxBytes('ORCAMENTO.XLSX') == 20 * 1024 * 1024,
    'Limite de Office distinto do PDF',
  );
  check(
    AppConfig.audioTypes['opus'] == 'audio/ogg',
    'Opus identificado como container Ogg',
  );
  final d = DocumentRecord(
    id: 'doc-local',
    projectId: 'proj',
    name: 'Memorial.pdf',
    contentType: 'application/pdf',
    size: 42,
    remoteId: 'doc-remoto',
    versionId: 'versao',
    uploaded: true,
    confirmed: true,
    status: 'PROCESSADO',
    reviewed: true,
    reviewedBy: 'José',
    fields: {'Observações': 'ação “revisada”'},
  );
  final restored = DocumentRecord.fromJson(
    Map<String, dynamic>.from(jsonDecode(jsonEncode(d.toJson()))),
  );
  check(
    restored.uploaded &&
        restored.confirmed &&
        restored.remoteId == 'doc-remoto' &&
        restored.versionId == 'versao',
    'Serialização preserva confirmação e IDs para não reenviar arquivo',
  );
  check(
    restored.ready &&
        restored.reviewed &&
        restored.fields['Observações'] == 'ação “revisada”',
    'Serialização preserva revisão e Unicode',
  );
  final diary = DiaryEntry(
    id: '1',
    projectId: 'p',
    author: 'Maria',
    role: 'Engenharia',
    date: DateTime(2026, 9, 18),
    raw: 'original',
    corrected: 'corrigido',
    edited: 'editado',
    closed: true,
    status: 'FECHADO',
  );
  final restoredDiary = DiaryEntry.fromJson(
    Map<String, dynamic>.from(jsonDecode(jsonEncode(diary.toJson()))),
  );
  check(
    restoredDiary.displayText == 'editado' &&
        restoredDiary.raw == 'original' &&
        restoredDiary.closed,
    'Diário preserva original, edição e fechamento',
  );
  check(
    csvCell('=HYPERLINK("x")').startsWith('"\''),
    'Exportação neutraliza fórmula em CSV',
  );
  check(csvCell('a;"b"') == '"a;""b"""', 'CSV protege separadores e aspas');
  final exported = csvBytes([
    ['ação', 12],
  ]);
  check(
    exported.take(3).join(',') == '239,187,191' &&
        utf8.decode(exported).contains('ação'),
    'CSV em UTF-8 com BOM',
  );
  check(
    AppConfig.validateUrl('http://127.example.com:8080') != null &&
        AppConfig.validateUrl('http://10.example.com') != null,
    'Domínio parecido com IP local exige HTTPS',
  );
  check(
    Section.values.length == 7 && !Section.values.any((s) => s.label == 'BIM'),
    'Escopo final com sete módulos',
  );
}
