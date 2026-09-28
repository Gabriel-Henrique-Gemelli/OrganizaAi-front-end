import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/data/api_client.dart';
import 'package:organizai_flutter/data/app_store.dart';
import 'package:organizai_flutter/data/models.dart';
import 'package:organizai_flutter/data/auth.dart';

import 'api_client_test.dart' show FakeAdapter, jsonResponse;

const org = '00000000-0000-4000-8000-000000000001';
const projectId = '00000000-0000-4000-8000-000000000002';
AuthSession session({
  String organization = org,
  List<String> roles = const ['GESTOR'],
}) => AuthSession(
  accessToken: 'test-only',
  subject: 'user',
  organizationId: organization,
  name: 'Pessoa autenticada',
  roles: roles,
  expires: DateTime.now().add(Duration(hours: 1)),
);
Map<String, dynamic> project() => Project(
  id: projectId,
  name: 'Obra de teste',
  executor: 'Empresa',
  responsible: 'Pessoa',
  city: 'Cidade',
  state: 'RS',
  address: 'Rua',
  plannedStartDate: '2026-01-01',
  plannedEndDate: '2027-01-01',
).toJson();
Map<String, dynamic> doc() => DocumentRecord(
  id: 'doc',
  remoteId: 'doc',
  versionId: 'v1',
  projectId: projectId,
  name: 'arquivo.txt',
  contentType: 'text/plain',
  size: 3,
  status: 'PROCESSADO',
  text: 'ABC',
  uploaded: true,
  confirmed: true,
).toJson();
AppStore harness(FakeAdapter adapter) => AppStore(
  apiFactory: (url, token) => ApiClient(
    url,
    client: Dio(BaseOptions(baseUrl: url))..httpClientAdapter = adapter,
    uploadClient: Dio()..httpClientAdapter = adapter,
  ),
)..baseUrl = 'https://api.example';
Object baseResponse(RequestOptions r, {String organization = org}) {
  if (r.path == '/api/conta')
    return {
      'subject': 'user',
      'organizationId': organization,
      'company': 'Empresa',
    };
  if (r.path.startsWith('/api/obras?'))
    return {
      'items': [project()],
      'hasNext': false,
    };
  return {'items': [], 'hasNext': false};
}

void main() {
  test('Inicialização não cria obras ou documentos de demonstração', () async {
    final s = AppStore();
    await s.initialize();
    expect(s.started, false);
    expect(s.projects, isEmpty);
    expect(s.documents, isEmpty);
    expect(s.diaries, isEmpty);
    s.dispose();
  });
  test(
    'Entrada carrega catálogo remoto e exige confirmar a organização',
    () async {
      final adapter = FakeAdapter(
        (r) async => jsonResponse(
          r.path.contains('/documentos?')
              ? {
                  'items': [doc()],
                  'hasNext': false,
                }
              : baseResponse(r),
        ),
      );
      final s = harness(adapter);
      await s.connect(session());
      expect(s.started, true);
      expect(s.project!.name, 'Obra de teste');
      expect(s.documents.single.text, 'ABC');
      expect(s.company, 'Empresa');
      expect(adapter.requests.any((r) => r.path.contains('/diarios?')), true);
      s.dispose();
    },
  );
  test('Falha da API impede entrada e não oferece dados fictícios', () async {
    final s = harness(FakeAdapter((r) async => jsonResponse({}, 503)));
    await expectLater(s.connect(session()), throwsA(isA<ApiFailure>()));
    expect(s.started, false);
    expect(s.session, isNull);
    expect(s.documents, isEmpty);
    s.dispose();
  });
  test('Conta de outra organização não abre o catálogo', () async {
    final s = harness(
      FakeAdapter(
        (r) async => jsonResponse(baseResponse(r, organization: 'outra')),
      ),
    );
    await expectLater(s.connect(session()), throwsA(isA<ApiFailure>()));
    expect(s.started, false);
    s.dispose();
  });
  test(
    'Auditor consulta documentos, mas não busca diários nem salva obra',
    () async {
      final adapter = FakeAdapter((r) async => jsonResponse(baseResponse(r)));
      final s = harness(adapter);
      await s.connect(session(roles: ['AUDITOR']));
      expect(adapter.requests.any((r) => r.path.contains('/diarios?')), false);
      await expectLater(
        s.saveProject(Project(id: '', name: 'Obra')),
        throwsA(isA<ApiFailure>()),
      );
      expect(adapter.requests.any((r) => r.method == 'POST'), false);
      s.dispose();
    },
  );
  test(
    'Conferência só muda após confirmação da API e usa revisor autenticado',
    () async {
      final adapter = FakeAdapter(
        (r) async => jsonResponse(
          r.path.endsWith('/revisao')
              ? {
                  ...doc(),
                  'reviewed': true,
                  'reviewedBy': 'Pessoa autenticada',
                  'category': 'Contrato',
                  'fields': {'Observações': 'Revisto'},
                }
              : r.path.contains('/documentos?')
              ? {
                  'items': [doc()],
                  'hasNext': false,
                }
              : baseResponse(r),
        ),
      );
      final s = harness(adapter);
      await s.connect(session());
      final d = s.documents.single;
      await s.review(d, 'Contrato', 'Nome arbitrário', {
        'Observações': 'Revisto',
      });
      expect(d.reviewed, true);
      expect(d.reviewedBy, 'Pessoa autenticada');
      expect(adapter.requests.last.data, {
        'versionId': 'v1',
        'category': 'Contrato',
        'fields': {'Observações': 'Revisto'},
      });
      s.dispose();
    },
  );
  test('Mesmo arquivo no lote gera um upload e envia hash real', () async {
    final adapter = FakeAdapter((r) async {
      if (r.uri.host == 'storage.example')
        return ResponseBody.fromString('', 200);
      if (r.path == '/api/documentos/upload-url')
        return jsonResponse({
          'documentoId': 'd',
          'versionId': 'v',
          'urlUpload': 'https://storage.example/file',
          'metodo': 'PUT',
          'headers': {},
          'expiraEm': DateTime.now()
              .add(Duration(minutes: 5))
              .toIso8601String(),
        }, 201);
      if (r.path.endsWith('/confirmar-upload')) return jsonResponse({});
      if (r.path.endsWith('/ocr'))
        return jsonResponse({
          'status': 'PROCESSADO',
          'texto': 'ABC',
          'paginas': 1,
        });
      return jsonResponse(baseResponse(r));
    });
    final s = harness(adapter);
    await s.connect(session());
    final file = PickedAsset('memorial.txt', Uint8List.fromList([65, 66, 67]));
    await s.addDocuments([file, file]);
    expect(s.documents.length, 1);
    expect(s.documents.single.text, 'ABC');
    expect(
      adapter.requests
          .where((r) => r.path == '/api/documentos/upload-url')
          .length,
      1,
    );
    final confirm = adapter.requests.singleWhere(
      (r) => r.path.endsWith('/confirmar-upload'),
    );
    expect(
      (confirm.data as Map)['sha256'],
      'b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78',
    );
    s.dispose();
  });
  test(
    'Campos do diário são enviados ao servidor e diário fechado é protegido',
    () async {
      final adapter = FakeAdapter(
        (r) async => jsonResponse(
          r.path.endsWith('/texto')
              ? {
                  'status': 'AGUARDANDO_REVISAO',
                  'transcriptEdited': 'Texto final',
                }
              : baseResponse(r),
        ),
      );
      final s = harness(adapter);
      await s.connect(session());
      final e = DiaryEntry(
        id: 'e',
        remoteId: 'e',
        projectId: projectId,
        author: 'Pessoa',
        role: 'Engenheiro',
        date: DateTime(2026, 1, 1),
        status: 'AGUARDANDO_REVISAO',
      );
      await s.saveDiary(
        e,
        'Texto final',
        'Pessoa',
        details: {'Equipe': '5 pessoas'},
      );
      expect(adapter.requests.last.data, {
        'texto': 'Texto final',
        'campos': {'Equipe': '5 pessoas'},
      });
      e.closed = true;
      await expectLater(
        s.saveDiary(e, 'Outro texto', 'Pessoa'),
        throwsA(isA<ApiFailure>()),
      );
      expect(e.edited, 'Texto final');
      s.dispose();
    },
  );
}
