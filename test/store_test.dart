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
Object? base(RequestOptions r, {String organization = org}) {
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
  return null;
}

/// Adaptador que já responde conta e obras, para o teste cuidar só do que importa.
FakeAdapter fake(Future<ResponseBody> Function(RequestOptions) handler) =>
    FakeAdapter((r) async {
      final b = base(r);
      return b != null ? jsonResponse(b) : handler(r);
    });

/// Conecta; as obras vêm da sincronização com o servidor.
Future<AppStore> ready(FakeAdapter adapter, {List<String> roles = const ['GESTOR']}) async {
  final s = harness(adapter);
  await s.connect(session(roles: roles));
  return s;
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
  test('Entrada confirma a conta no servidor e traz as obras do banco', () async {
    final adapter = fake((r) async => jsonResponse({}, 500));
    final s = harness(adapter);
    await s.connect(session());
    expect(s.started, true);
    expect(s.company, 'Empresa');
    expect(s.projects.single.name, 'Obra de teste');
    expect(s.selectedProjectId, projectId);
    // conta e obras saem juntas (a sessão só existe depois do GetUser); a ordem de chegada não importa.
    expect(adapter.requests.map((r) => r.path), unorderedEquals(['/api/conta', '/api/obras?page=0']));
    s.dispose();
  });
  test('Conta de outra organização não abre o catálogo', () async {
    final s = harness(
      FakeAdapter(
        (r) async => jsonResponse(base(r, organization: 'outra') ?? {}),
      ),
    );
    await expectLater(s.connect(session()), throwsA(isA<ApiFailure>()));
    expect(s.started, false);
    s.dispose();
  });
  test('Falha da API impede a entrada', () async {
    final s = harness(FakeAdapter((r) async => jsonResponse({}, 503)));
    await expectLater(s.connect(session()), throwsA(isA<ApiFailure>()));
    expect(s.started, false);
    expect(s.session, isNull);
    s.dispose();
  });
  test('Obra nova vai ao servidor sem ID e usa o ID gerado pelo banco', () async {
    final adapter = fake((r) async {
      if (r.method == 'POST' && r.path == '/api/obras')
        return jsonResponse({
          ...project(),
          'id': '00000000-0000-4000-8000-0000000000aa',
          'name': 'Nova obra',
        }, 201);
      return jsonResponse({}, 500);
    });
    final s = await ready(adapter);
    await s.saveProject(Project(id: '', name: 'Nova obra'));
    final post = adapter.requests.singleWhere((r) => r.method == 'POST');
    expect((post.data as Map).containsKey('id'), false);
    expect((post.data as Map)['name'], 'Nova obra');
    expect(s.selectedProjectId, '00000000-0000-4000-8000-0000000000aa');
    expect(s.projects.length, 2);
    s.dispose();
  });
  test('Auditor não salva obra', () async {
    final adapter = fake((r) async => jsonResponse({}));
    final s = await ready(adapter, roles: ['AUDITOR']);
    await expectLater(
      s.saveProject(Project(id: '', name: 'Obra')),
      throwsA(isA<ApiFailure>()),
    );
    expect(adapter.requests.any((r) => r.method == 'POST'), false);
    s.dispose();
  });
  test('Conferência vale no aparelho e usa o revisor autenticado', () async {
    final adapter = fake((r) async => jsonResponse({}));
    final s = await ready(adapter);
    s.documents = [DocumentRecord.fromJson(doc())];
    final d = s.documents.single;
    await s.review(d, 'Contrato', 'Nome arbitrário', {'Observações': 'Revisto'});
    expect(d.reviewed, true);
    expect(d.reviewedBy, 'Pessoa autenticada');
    expect(d.category, 'Contrato');
    expect(d.fields, {'Observações': 'Revisto'});
    expect(adapter.requests.any((r) => r.path.contains('/revisao')), false);
    s.dispose();
  });
  test('Atualizar retoma só o que está em processamento no servidor', () async {
    final adapter = fake((r) async {
      if (r.path == '/api/documentos/pendente/ocr')
        return jsonResponse({'status': 'PROCESSADO', 'texto': 'ABC', 'paginas': 1});
      if (r.path == '/api/diario/e1/transcricao')
        return jsonResponse({
          'status': 'AGUARDANDO_REVISAO',
          'transcriptRaw': 'cru',
          'transcriptClean': 'limpo',
        });
      return jsonResponse({}, 500);
    });
    final s = await ready(adapter);
    s.documents = [
      DocumentRecord.fromJson({
        ...doc(),
        'id': 'pendente',
        'remoteId': 'pendente',
        'status': 'AGUARDANDO_OCR',
        'text': '',
      }),
      DocumentRecord.fromJson({...doc(), 'id': 'pronto', 'remoteId': 'pronto'}),
    ];
    s.diaries = [
      DiaryEntry(
        id: 'e1',
        remoteId: 'e1',
        projectId: projectId,
        author: 'Pessoa',
        role: 'Engenheiro',
        date: DateTime(2026, 1, 1),
        status: 'EM_TRANSCRICAO',
      ),
    ];
    await s.synchronize();
    expect(s.documents.first.text, 'ABC');
    expect(s.documents.first.status, 'PROCESSADO');
    expect(s.diaries.single.status, 'AGUARDANDO_REVISAO');
    expect(s.diaries.single.corrected, 'limpo');
    expect(
      adapter.requests
          .map((r) => r.path)
          .where((p) => p.startsWith('/api/documentos') || p.startsWith('/api/diario'))
          .toSet(),
      {'/api/documentos/pendente/ocr', '/api/diario/e1/transcricao'},
    );
    s.dispose();
  });
  test('Mesmo arquivo no lote gera um upload com tamanho e hash reais', () async {
    final adapter = fake((r) async {
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
      return jsonResponse({});
    });
    final s = await ready(adapter);
    final file = PickedAsset('memorial.txt', Uint8List.fromList([65, 66, 67]));
    await s.addDocuments([file, file]);
    expect(s.documents.length, 1);
    expect(s.documents.single.text, 'ABC');
    final upload = adapter.requests.singleWhere(
      (r) => r.path == '/api/documentos/upload-url',
    );
    expect((upload.data as Map)['tamanhoBytes'], 3);
    final confirm = adapter.requests.singleWhere(
      (r) => r.path.endsWith('/confirmar-upload'),
    );
    expect(
      (confirm.data as Map)['sha256'],
      'b5d4045c3f466fa91fe2cc6abe79232a1a57cdf104f7a26e716e0a1e2789df78',
    );
    s.dispose();
  });
  test('Áudio do diário é enviado, confirmado e transcrito', () async {
    final adapter = fake((r) async {
      if (r.uri.host == 'storage.example')
        return ResponseBody.fromString('', 200);
      if (r.path == '/api/diario/upload-url')
        return jsonResponse({
          'diarioId': 'dia',
          'urlUpload': 'https://storage.example/audio',
          'metodo': 'PUT',
          'headers': {},
          'expiraEm': DateTime.now()
              .add(Duration(minutes: 5))
              .toIso8601String(),
        }, 201);
      if (r.path == '/api/diario/dia/confirmar-upload')
        return jsonResponse({
          'status': 'AGUARDANDO_REVISAO',
          'transcriptRaw': 'cru',
          'transcriptClean': 'limpo',
        });
      return jsonResponse({}, 500);
    });
    final s = await ready(adapter);
    final e = await s.addDiary(
      PickedAsset('nota.ogg', Uint8List.fromList([1, 2, 3, 4])),
      'x',
      'Engenheiro',
      DateTime(2026, 9, 29),
    );
    expect(e.status, 'AGUARDANDO_REVISAO');
    expect(e.corrected, 'limpo');
    final upload = adapter.requests.singleWhere(
      (r) => r.path == '/api/diario/upload-url',
    );
    expect((upload.data as Map)['tamanhoBytes'], 4);
    expect(
      adapter.requests.map((r) => r.path).toList().indexOf('/api/diario/dia/confirmar-upload'),
      greaterThan(adapter.requests.indexWhere((r) => r.uri.host == 'storage.example')),
    );
    s.dispose();
  });
  test('Texto do diário vai sem campos extras e diário fechado é protegido', () async {
    final adapter = fake(
      (r) async => jsonResponse(
        r.path.endsWith('/texto')
            ? {'status': 'AGUARDANDO_REVISAO', 'transcriptEdited': 'Texto final'}
            : {},
      ),
    );
    final s = await ready(adapter);
    final e = DiaryEntry(
      id: 'e',
      remoteId: 'e',
      projectId: projectId,
      author: 'Pessoa',
      role: 'Engenheiro',
      date: DateTime(2026, 1, 1),
      status: 'AGUARDANDO_REVISAO',
    );
    await s.saveDiary(e, 'Texto final', 'Pessoa', details: {'Equipe': '5 pessoas'});
    expect(adapter.requests.last.data, {'texto': 'Texto final'});
    expect(e.details['Equipe'], '5 pessoas');
    e.closed = true;
    await expectLater(
      s.saveDiary(e, 'Outro texto', 'Pessoa'),
      throwsA(isA<ApiFailure>()),
    );
    expect(e.edited, 'Texto final');
    s.dispose();
  });
  test('Clima automático só é consultado; gravar é passo separado', () async {
    final adapter = fake(
      (r) async => jsonResponse({
        'temperaturaC': 21.5,
        'condicao': 'Nublado',
        'tokenConsulta': 'tok',
      }),
    );
    final s = await ready(adapter);
    final e = DiaryEntry(
      id: 'e',
      remoteId: 'e',
      projectId: projectId,
      author: 'Pessoa',
      role: 'Engenheiro',
      date: DateTime(2026, 1, 1),
    );
    final suggestion = await s.fetchWeather(e);
    expect(suggestion['tokenConsulta'], 'tok');
    final clima = adapter.requests.last;
    expect(clima.method, 'GET');
    expect(clima.uri.queryParameters['projectId'], projectId);
    expect(e.weather, isEmpty);
    s.dispose();
  });
}
