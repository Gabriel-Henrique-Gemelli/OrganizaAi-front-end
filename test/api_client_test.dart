import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/data/api_client.dart';

class FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];
  FakeAdapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object body, [int status = 200]) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
void main() {
  test(
    'Contrato Gemas-Dev: criação, confirmação SHA-256 e consulta de OCR',
    () async {
      final adapter = FakeAdapter(
        (o) async => jsonResponse({
          'documentoId': 'd',
          'versionId': 'v',
          'status': 'PROCESSADO',
          'texto': 'memorial',
          'paginas': 1,
        }),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'));
      dio.httpClientAdapter = adapter;
      final api = ApiClient('https://api.example', client: dio);
      await api.prepareDocument('obra.pdf', 'proj', 2048);
      await api.confirm('d', 'v', 'a' * 64);
      await api.result('d');
      expect(adapter.requests.map((r) => r.path), [
        '/api/documentos/upload-url',
        '/api/documentos/d/versoes/v/confirmar-upload',
        '/api/documentos/d/ocr',
      ]);
      expect(adapter.requests[0].data, {
        'projectId': 'proj',
        'tamanhoBytes': 2048,
        'nomeArquivo': 'obra.pdf',
        'contentType': 'application/pdf',
      });
      expect(adapter.requests[1].data, {'sha256': 'a' * 64});
      api.close();
    },
  );
  test(
    'Upload usa método e headers assinados sem enviar token da API',
    () async {
      final uploaded = FakeAdapter(
        (o) async => ResponseBody.fromString('', 200),
      );
      final storage = Dio()..httpClientAdapter = uploaded;
      final api = ApiClient(
        'https://api.example',
        token: 'secret',
        uploadClient: storage,
      );
      await api.putSigned({
        'urlUpload': 'https://storage.example/signed',
        'metodo': 'PUT',
        'headers': {'Content-Type': 'application/pdf', 'x-amz-tagging': 'a=b'},
        'expiraEm': DateTime.now()
            .add(Duration(minutes: 2))
            .toUtc()
            .toIso8601String(),
      }, Uint8List.fromList([1, 2, 3]));
      final request = uploaded.requests.single;
      expect(request.method, 'PUT');
      expect(request.headers['x-amz-tagging'], 'a=b');
      expect(
        request.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
      api.close();
    },
  );
  test(
    'Polling entende estados do diário e não considera GRAVADO concluído',
    () async {
      var attempts = 0;
      final adapter = FakeAdapter(
        (_) async => jsonResponse({
          'status': ++attempts < 3 ? 'GRAVADO' : 'AGUARDANDO_REVISAO',
          'transcriptRaw': 'feito',
        }, attempts < 3 ? 202 : 200),
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
        ..httpClientAdapter = adapter;
      final api = ApiClient('https://api.example', client: dio);
      final result = await api.poll(
        'entry',
        audio: true,
        interval: Duration.zero,
        attempts: 4,
      );
      expect(attempts, 3);
      expect(result['transcriptRaw'], 'feito');
      expect(adapter.requests.first.path, '/api/diario/entry/transcricao');
      api.close();
    },
  );
  test('Timeout de polling mantém processamento remoto recuperável', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = FakeAdapter(
        (_) async => jsonResponse({'status': 'AGUARDANDO_OCR'}, 202),
      );
    final api = ApiClient('https://api.example', client: dio);
    await expectLater(
      api.poll('doc', attempts: 2, interval: Duration.zero),
      throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 202)),
    );
    api.close();
  });
  test(
    'Conflito preserva status e mostra orientação sem detalhes internos',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
        ..httpClientAdapter = FakeAdapter(
          (_) async => jsonResponse({
            'title': 'Duplicado',
            'detail': 'Documento já existente.',
          }, 409),
        );
      final api = ApiClient('https://api.example', client: dio);
      await expectLater(
        api.confirm('d', 'v', 'a' * 64),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.status, 'status', 409)
              .having(
                (e) => e.message,
                'detail',
                'Este registro já existe ou foi alterado. Atualize os dados antes de repetir.',
              ),
        ),
      );
      api.close();
    },
  );
  test('Identidade vem do JWT, nunca do corpo de edição e aprovação', () async {
    final adapter = FakeAdapter(
      (_) async => jsonResponse({'status': 'FECHADO'}),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = adapter;
    final api = ApiClient('https://api.example', client: dio);
    await api.editDiary('e', 'texto revisado');
    await api.approveDiary('e');
    expect(adapter.requests[0].method, 'PATCH');
    expect(adapter.requests[0].data, {'texto': 'texto revisado'});
    expect(adapter.requests[1].path, '/api/diario/e/aprovar');
    expect(adapter.requests[1].data, isNull);
    api.close();
  });
  test('Assistente usa sessão por obra e clima aceita 202 sem corpo', () async {
    final adapter = FakeAdapter(
      (o) async => o.path.endsWith('tentar-novamente')
          ? ResponseBody.fromString('', 202)
          : jsonResponse({
              'resposta': 'Texto',
              'sessionId': 's',
              'citacoes': [],
              'semFonte': true,
            }),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = adapter;
    final api = ApiClient('https://api.example', client: dio);
    await api.ask('obra', 'Pergunta', sessionId: 's');
    expect(adapter.requests.single.path, '/api/assistente/perguntas');
    expect(adapter.requests.single.data, {
      'projectId': 'obra',
      'pergunta': 'Pergunta',
      'sessionId': 's',
    });
    api.close();
  });
  test('OCR 422 FALHOU é um resultado terminal do processamento', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = FakeAdapter(
        (_) async => jsonResponse({
          'documentoId': 'd',
          'status': 'FALHOU',
          'texto': null,
        }, 422),
      );
    final api = ApiClient('https://api.example', client: dio);
    expect((await api.poll('d'))['status'], 'FALHOU');
    api.close();
  });
  test('Upload do diário não envia organizationId nem authorName', () async {
    final adapter = FakeAdapter((_) async => jsonResponse({'diarioId': 'd'}));
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = adapter;
    final api = ApiClient('https://api.example', client: dio);
    await api.prepareDiary(
      'audio/ogg',
      'obra',
      '2026-09-21',
      'Engenheiro',
      4096,
    );
    expect(adapter.requests.single.data, {
      'contentType': 'audio/ogg',
      'projectId': 'obra',
      'entryDate': '2026-09-21',
      'authorRole': 'Engenheiro',
      'tamanhoBytes': 4096,
    });
    api.close();
  });
  test('Áudio enviado é confirmado e o clima é consultado sem gravar', () async {
    final adapter = FakeAdapter(
      (r) async => jsonResponse({'status': 'EM_TRANSCRICAO'}),
    );
    final api = ApiClient(
      'https://api.example',
      client: Dio(BaseOptions(baseUrl: 'https://api.example'))
        ..httpClientAdapter = adapter,
    );
    await api.confirmDiary('d');
    await api.consultWeather('obra');
    await api.editDiary('d', 'texto');
    expect(
      adapter.requests.map(
        (r) =>
            '${r.method} ${r.uri.path}${r.uri.hasQuery ? '?${r.uri.query}' : ''}',
      ),
      [
        'POST /api/diario/d/confirmar-upload',
        'GET /api/diario/clima?projectId=obra',
        'PATCH /api/diario/d/texto',
      ],
    );
    expect(adapter.requests.last.data, {'texto': 'texto'});
    api.close();
  });

  group('Cadastro público', () {
    ApiClient clientWith(FakeAdapter adapter) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example'));
      dio.httpClientAdapter = adapter;
      return ApiClient('https://api.example', client: dio);
    }

    test('envia nome, e-mail, senha e empresa sem token', () async {
      final adapter = FakeAdapter(
        (o) async =>
            jsonResponse({'organizationId': 'o', 'email': 'a@b.co'}, 201),
      );
      await clientWith(adapter).signup(
        name: 'Maria',
        email: 'a@b.co',
        password: 'Senha#Forte1',
        company: 'Construtora',
      );
      expect(adapter.requests.single.path, '/api/conta/cadastro');
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        false,
      );
      expect(adapter.requests.single.data, {
        'nome': 'Maria',
        'email': 'a@b.co',
        'senha': 'Senha#Forte1',
        'organizacao': 'Construtora',
      });
    });

    for (final c in {
      409: 'Já existe uma conta com este e-mail',
      429: 'Muitos cadastros',
      500: 'Não foi possível criar a conta',
    }.entries) {
      test('status ${c.key} vira mensagem em português', () async {
        final api = clientWith(
          FakeAdapter((o) async => jsonResponse({}, c.key)),
        );
        await expectLater(
          api.signup(name: 'M', email: 'a@b.co', password: 'x', company: 'C'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.message,
              'message',
              contains(c.value),
            ),
          ),
        );
      });
    }

    test('400 mostra o motivo que o servidor explicou', () async {
      final api = clientWith(
        FakeAdapter(
          (o) async =>
              jsonResponse({'detail': 'a senha precisa ser mais forte'}, 400),
        ),
      );
      await expectLater(
        api.signup(name: 'M', email: 'a@b.co', password: 'x', company: 'C'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            'a senha precisa ser mais forte',
          ),
        ),
      );
    });
  });
}
