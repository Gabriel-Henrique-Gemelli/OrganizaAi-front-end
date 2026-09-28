import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';

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
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) throw ApiFailure('Operação cancelada.');
      final body = e.response?.data;
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
        429 => 'Muitas solicitações. Aguarde antes de tentar novamente.',
        _ => 'Não foi possível acessar o serviço. Confira sua conexão e tente novamente.',
      }, e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> prepareDocument(
    String name,
    String project, {
    CancelToken? cancel,
  }) => request(
    'POST',
    '/api/documentos/upload-url',
    data: {
      'nomeArquivo': name,
      'contentType': AppConfig.documentTypes[AppConfig.extension(name)],
      'projectId': project,
    },
    cancel: cancel,
  );
  Future<Map<String, dynamic>> prepareDiary(
    String type,
    String project,
    String date,
    String role, {
    CancelToken? cancel,
  }) => request(
    'POST',
    '/api/diario/upload-url',
    data: {
      'contentType': type,
      'projectId': project,
      'entryDate': date,
      'authorRole': role,
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
      if (i < attempts - 1)
        await Future.any([
          Future.delayed(interval),
          if (cancel != null)
            cancel.whenCancel.then(
              (_) => throw ApiFailure('Consulta cancelada.'),
            ),
        ]);
    }
    throw ApiFailure(
      'O processamento continua no servidor. Retome a consulta quando quiser.',
      202,
    );
  }

  Future<Map<String, dynamic>> editDiary(
    String id,
    String text, {
    Map<String, String>? fields,
  }) => request(
    'PATCH',
    '/api/diario/$id/texto',
    data: {'texto': text, if (fields != null) 'campos': fields},
  );
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
  Future<void> retryWeather(String id) async {
    await request(
      'POST',
      '/api/diario/$id/clima/tentar-novamente',
      allowEmpty: true,
    );
  }

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

  Future<Uint8List> downloadOriginal(String id) async {
    final info = await request('GET', '/api/documentos/$id/download');
    final uri = Uri.tryParse(info['url'] ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty)
      throw ApiFailure('O arquivo não está disponível para download.');
    try {
      final r = await storage.get<List<int>>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
        ),
      );
      final bytes = Uint8List.fromList(r.data ?? []);
      if (bytes.isEmpty || sha256.convert(bytes).toString() != info['sha256'])
        throw ApiFailure(
          'O arquivo recebido está incompleto. Tente novamente.',
        );
      return bytes;
    } on DioException {
      throw ApiFailure('Não foi possível baixar o arquivo. Tente novamente.');
    }
  }

  void close() {
    http.close(force: true);
    storage.close(force: true);
  }
}
