import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/config.dart';

class ApiFailure implements Exception {
  final String message;
  final int? status;
  const ApiFailure(this.message, [this.status]);
  @override
  String toString() => message;
}

class ApiClient {
  final Dio http;
  final Dio storage;

  /// Chamado quando o servidor responde 401 (sessão vencida ou revogada), para quem usa o cliente encerrar
  /// a sessão em vez de deixar o app "logado" com um token que não vale mais.
  void Function()? onUnauthorized;
  ApiClient(String baseUrl, {String token = '', Dio? client, Dio? uploadClient})
    : http =
          client ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''),
              connectTimeout: Duration(seconds: 15),
              receiveTimeout: Duration(seconds: 90),
              headers: {
                'Accept': 'application/json',
                if (token.isNotEmpty) 'Authorization': 'Bearer $token',
              },
            ),
          ),
      storage =
          uploadClient ??
          Dio(
            BaseOptions(
              connectTimeout: Duration(seconds: 20),
              sendTimeout: Duration(minutes: 5),
              receiveTimeout: Duration(seconds: 60),
            ),
          );

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Object? data,
    CancelToken? cancel,
    bool allowEmpty = false,
    bool ocrResult = false,
  }) async {
    try {
      final result = await http.request(
        path,
        data: data,
        cancelToken: cancel,
        options: Options(method: method),
      );
      if (allowEmpty && (result.data == null || result.data == '')) return {};
      if (result.data is! Map)
        throw ApiFailure('O servidor retornou uma resposta inesperada.');
      return Map<String, dynamic>.from(result.data as Map);
    } on TypeError {
      throw ApiFailure('O servidor retornou uma resposta inesperada.');
    } on FormatException {
      throw ApiFailure('O servidor retornou uma resposta inesperada.');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw ApiFailure('Operação cancelada.');
      final body = e.response?.data;
      if (e.response == null) {
        // Sem resposta: distinguir demora de falta de conexão ajuda o usuário a saber o que fazer.
        throw ApiFailure(switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout =>
            'O servidor demorou para responder. Tente novamente em instantes.',
          DioExceptionType.connectionError =>
            'Sem conexão com o servidor. Confira sua internet.',
          _ => 'Não foi possível acessar o serviço. Tente novamente.',
        });
      }
      if (e.response?.statusCode == 401) {
        try {
          onUnauthorized?.call();
        } catch (_) {
          // Encerrar a sessão não pode esconder a resposta original para quem chamou.
        }
      }
      if (ocrResult &&
          e.response?.statusCode == 422 &&
          body is Map &&
          body['status'] == 'FALHOU') {
        return Map<String, dynamic>.from(body);
      }
      throw ApiFailure(switch (e.response?.statusCode) {
        400 => 'Confira os campos preenchidos e tente novamente.',
        401 => 'Sua sessão expirou. Entre novamente.',
        403 => 'Acesso recusado pelo servidor.',
        404 => 'Este registro não está disponível para sua conta.',
        409 => 'Este registro já existe ou foi alterado. Atualize os dados antes de repetir.',
        413 => 'O arquivo é maior do que o servidor aceita.',
        415 => 'O servidor não aceita este formato de arquivo.',
        429 => 'Muitas solicitações. Aguarde antes de tentar novamente.',
        502 || 503 || 504 => 'O serviço está indisponível no momento. Tente novamente em instantes.',
        _ => 'Não foi possível acessar o serviço. Confira sua conexão e tente novamente.',
      }, e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> prepareDocument(
    String name,
    String project,
    int size, {
    CancelToken? cancel,
  }) => request(
    'POST',
    '/api/documentos/upload-url',
    data: {
      'nomeArquivo': name,
      'contentType': AppConfig.documentTypes[AppConfig.extension(name)],
      'projectId': project,
      'tamanhoBytes': size,
    },
    cancel: cancel,
  );
  Future<Map<String, dynamic>> prepareDiary(
    String type,
    String project,
    String date,
    String role,
    int size, {
    CancelToken? cancel,
  }) => request(
    'POST',
    '/api/diario/upload-url',
    data: {
      'contentType': type,
      'projectId': project,
      'entryDate': date,
      'authorRole': role,
      'tamanhoBytes': size,
    },
    cancel: cancel,
  );
  Future<void> putSigned(
    Map<String, dynamic> signed,
    Uint8List bytes, {
    CancelToken? cancel,
    void Function(double)? progress,
  }) async {
    final url = Uri.tryParse(signed['urlUpload'] ?? '');
    if (url == null || url.scheme != 'https')
      throw ApiFailure(
        'O servidor não forneceu uma URL de envio HTTPS válida.',
      );
    final expires = DateTime.tryParse(signed['expiraEm'] ?? '');
    if (expires != null && expires.isBefore(DateTime.now()))
      throw ApiFailure('O link de envio expirou. Solicite um novo envio.');
    try {
      // Cliente separado: nunca envia Authorization da API ao endereço pré-assinado.
      await storage.request(
        url.toString(),
        data: bytes,
        cancelToken: cancel,
        options: Options(
          method: signed['metodo'] ?? 'PUT',
          headers: Map<String, dynamic>.from(signed['headers'] ?? {}),
          responseType: ResponseType.plain,
        ),
        onSendProgress: (sent, total) =>
            progress?.call(total > 0 ? sent / total : 0),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw ApiFailure('Envio cancelado.');
      throw ApiFailure(
        'Falha no envio ao armazenamento (${e.response?.statusCode ?? 'conexão'}). Tente novamente.',
      );
    }
  }

  Future<Map<String, dynamic>> confirm(
    String id,
    String version,
    String hash, {
    CancelToken? cancel,
  }) => request(
    'POST',
    '/api/documentos/$id/versoes/$version/confirmar-upload',
    data: {'sha256': hash},
    cancel: cancel,
  );

  /// Avisa o servidor que o áudio já está no armazenamento; ele confere o arquivo e inicia a transcrição.
  Future<Map<String, dynamic>> confirmDiary(String id, {CancelToken? cancel}) =>
      request('POST', '/api/diario/$id/confirmar-upload', cancel: cancel);
  Future<Map<String, dynamic>> result(
    String id, {
    bool audio = false,
    CancelToken? cancel,
  }) => request(
    'GET',
    audio ? '/api/diario/$id/transcricao' : '/api/documentos/$id/ocr',
    cancel: cancel,
    ocrResult: !audio,
  );

  /// Espera [interval] ou o cancelamento, o que vier primeiro. Sem `Future` de erro solto: o antigo
  /// `cancel.whenCancel.then((_) => throw ...)` virava erro não tratado quando o tempo vencia a corrida.
  Future<void> _pause(Duration interval, CancelToken? cancel) async {
    final done = Completer<void>();
    final timer = Timer(interval, () {
      if (!done.isCompleted) done.complete();
    });
    cancel?.whenCancel.then((_) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    timer.cancel();
    if (cancel?.isCancelled == true) throw ApiFailure('Consulta cancelada.');
  }

  Future<Map<String, dynamic>> poll(
    String id, {
    bool audio = false,
    CancelToken? cancel,
    Duration interval = const Duration(seconds: 4),
    int attempts = 90,
    void Function(Map<String, dynamic>)? onUpdate,
  }) async {
    for (var i = 0; i < attempts; i++) {
      if (cancel?.isCancelled == true) throw ApiFailure('Consulta cancelada.');
      final body = await result(id, audio: audio, cancel: cancel);
      onUpdate?.call(body);
      if (!{
        'AGUARDANDO_OCR',
        'GRAVADO',
        'EM_TRANSCRICAO',
      }.contains(body['status']))
        return body;
      if (i < attempts - 1) await _pause(interval, cancel);
    }
    throw ApiFailure(
      'O processamento continua no servidor. Retome a consulta quando quiser.',
      202,
    );
  }

  /// Cadastro, etapa 1 (público, sem token): cria o usuário com o e-mail ainda não verificado e devolve
  /// o nome interno dele no Cognito, que vale para entrar até o e-mail ser verificado.
  Future<String> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final r = await http.post(
        '/api/conta/cadastro',
        data: {'nome': name, 'email': email, 'senha': password},
      );
      final data = r.data;
      if (data is Map && data['usuario'] is String) return data['usuario'];
      throw ApiFailure('O servidor retornou uma resposta inesperada.');
    } on DioException catch (e) {
      final body = e.response?.data;
      final detail = body is Map && body['detail'] is String
          ? body['detail'] as String
          : null;
      throw ApiFailure(switch (e.response?.statusCode) {
        400 => detail ?? 'Confira os campos preenchidos e tente novamente.',
        409 => 'Já existe uma conta com este e-mail. Use “Entrar”.',
        429 => 'Muitos cadastros agora. Tente novamente em alguns minutos.',
        _ => 'Não foi possível criar a conta. Confira sua conexão e tente novamente.',
      }, e.response?.statusCode);
    }
  }

  /// Cadastro, etapa 2 (com o token de quem já verificou o e-mail): cria a organização da pessoa.
  Future<void> activate(String company) async {
    try {
      await request(
        'POST',
        '/api/conta/ativar',
        data: {'organizacao': company},
      );
    } on ApiFailure catch (e) {
      if (e.status == 403) {
        throw ApiFailure(
          'Confirme o código do e-mail antes de continuar.',
          403,
        );
      }
      if (e.status == 409) {
        throw ApiFailure(
          'Já existe uma conta com este e-mail. Use “Entrar”.',
          409,
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> editDiary(String id, String text) =>
      request('PATCH', '/api/diario/$id/texto', data: {'texto': text});
  Future<Map<String, dynamic>> approveDiary(String id) =>
      request('POST', '/api/diario/$id/aprovar');
  Future<Map<String, dynamic>> ask(
    String projectId,
    String question, {
    String? sessionId,
    CancelToken? cancel,
  }) => request(
    'POST',
    '/api/assistente/perguntas',
    data: {
      'projectId': projectId,
      'pergunta': question,
      if (sessionId != null) 'sessionId': sessionId,
    },
    cancel: cancel,
  );
  Future<Map<String, dynamic>> weather(
    String id,
    Map<String, dynamic> values,
  ) => request('PATCH', '/api/diario/$id/clima', data: values);

  /// Consulta o clima atual da obra sem gravar; o usuário confirma ou corrige antes de salvar.
  Future<Map<String, dynamic>> consultWeather(String projectId) =>
      request('GET', '/api/diario/clima?projectId=$projectId');

  /// Consome todas as páginas de uma listagem `{items, hasNext}`.
  Future<List<Map<String, dynamic>>> listAll(String path) async {
    final items = <Map<String, dynamic>>[];
    for (var page = 0; page < 10000; page++) {
      final result = await request('GET', '$path?page=$page');
      if (result['items'] is! List || result['hasNext'] is! bool)
        throw ApiFailure('O serviço retornou uma lista inválida.');
      items.addAll(
        (result['items'] as List).map((j) => Map<String, dynamic>.from(j)),
      );
      if (result['hasNext'] == false) return items;
    }
    throw ApiFailure('Há muitos registros para uma única atualização.');
  }

  void close() {
    http.close(force: true);
    storage.close(force: true);
  }
}
