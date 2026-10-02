import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../core/error_handling.dart';
import '../core/export.dart';
import 'api_client.dart';
import 'auth.dart';
import 'models.dart';

class AppStore extends ChangeNotifier {
  final Box? box;
  final ApiClient Function(String, String)? apiFactory;
  final _memory = <String, dynamic>{};
  AppStore({this.box, this.apiFactory});
  static const uuid = Uuid();
  bool recordingActive = false, started = false, busyChat = false;
  String baseUrl = AppConfig.defaultUrl,
      organizationId = '',
      company = '',
      userName = '';
  String token = '', selectedProjectId = '', subject = '';
  final String cognitoIssuer = AppConfig.cognitoIssuer,
      cognitoClientId = AppConfig.cognitoClientId;
  List<String> roles = [];
  AuthSession? session;
  CognitoAuth? _auth;
  Timer? _sessionTimer, _syncTimer;
  bool syncing = false;
  String? syncError;
  DateTime? lastSync;
  final Map<String, String> chatSessions = {};
  bool get canUpload => roles.any({'ADMIN', 'GESTOR', 'COLABORADOR'}.contains);
  bool get canDiary =>
      roles.any({'ADMIN', 'GESTOR', 'COLABORADOR', 'REVISOR'}.contains);
  bool get canApprove => roles.any({'ADMIN', 'GESTOR', 'REVISOR'}.contains);
  bool get canManageProjects => roles.any({'ADMIN', 'GESTOR'}.contains);
  void require(bool allowed) {
    if (session == null || session!.expires.isBefore(DateTime.now()))
      throw ApiFailure('Entre novamente para continuar.');
    if (!allowed) throw ApiFailure('Seu perfil não permite esta operação.');
  }

  Section section = Section.today;
  String? selectedDocumentId, selectedDiaryId;
  List<Project> projects = [];
  List<DocumentRecord> documents = [];
  List<DiaryEntry> diaries = [];
  List<ChatMessage> messages = [];
  List<Map<String, dynamic>> audit = [];
  final Map<String, CancelToken> tasks = {};
  final Map<String, Map<String, dynamic>> _receipts = {};
  ApiClient? _api;
  ApiClient get api => _api ??=
      (apiFactory?.call(baseUrl, token) ?? ApiClient(baseUrl, token: token))
        ..onUnauthorized = _sessionRejected;

  /// O servidor recusou o token (401): encerra a sessão uma vez, em vez de deixar o app logado com um
  /// token que não vale mais e mostrar o mesmo erro em cada ação.
  void _sessionRejected() {
    if (session == null || _disposed) return;
    AppErrors.report('401 do servidor: sessão encerrada', null, 'sessao');
    signOut();
  }

  String get scope => sha256
      .convert(utf8.encode('$baseUrl|$cognitoIssuer|$organizationId|$subject'))
      .toString();
  Project? get project =>
      projects.where((p) => p.id == selectedProjectId).firstOrNull;
  List<DocumentRecord> get projectDocs =>
      documents.where((d) => d.projectId == selectedProjectId).toList();
  List<DiaryEntry> get projectDiaries =>
      diaries.where((d) => d.projectId == selectedProjectId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
  List<DocumentRecord> get reviews =>
      projectDocs.where((d) => d.ready && !d.reviewed).toList();
  int _operations = 0;
  Future<T> _during<T>(Future<T> Function() action) async {
    _operations++;
    notifyListeners();
    try {
      return await action();
    } finally {
      _operations--;
      notifyListeners();
    }
  }

  bool get working =>
      _operations > 0 ||
      tasks.isNotEmpty ||
      busyChat ||
      recordingActive ||
      syncing;
  void setRecording(bool value) {
    recordingActive = value;
    notifyListeners();
  }

  dynamic _get(String key) => box?.get(key) ?? _memory[key];
  Future<void> _put(String key, dynamic value) async {
    if (box != null) {
      await box!.put(key, value);
    } else {
      _memory[key] = value;
    }
  }

  // Configuração vem da compilação. Não carrega configurações ou exemplos das versões antigas.
  Future<void> initialize() async {
    started = false;
  }

  Future<void> _load() async {
    _receipts.clear();
    chatSessions.clear();
    documents = [];
    diaries = [];
    messages = [];
    projects = [];
    audit = [];
    selectedDocumentId = null;
    selectedDiaryId = null;
    final raw = _get('$scope:workspace_v3');
    if (raw is String) {
      // Cache local corrompido ou de versão antiga não pode impedir o login: descarta e segue com listas
      // vazias, que a sincronização preenche a partir do servidor.
      try {
        final j = Map<String, dynamic>.from(jsonDecode(raw));
        projects = _parseItems(j['projects'], Project.fromJson, 'obras');
        documents = _parseItems(
          j['documents'],
          DocumentRecord.fromJson,
          'documentos',
        );
        diaries = _parseItems(j['diaries'], DiaryEntry.fromJson, 'diarios');
        messages = _parseItems(
          j['messages'],
          ChatMessage.fromJson,
          'mensagens',
        );
        audit = _parseItems(j['audit'], (m) => m, 'auditoria');
        chatSessions.addAll(Map<String, String>.from(j['chatSessions'] ?? {}));
        selectedProjectId = (j['selectedProjectId'] ?? '').toString();
      } catch (e, st) {
        AppErrors.report(e, st, 'cache_local_corrompido');
        projects = [];
        documents = [];
        diaries = [];
        messages = [];
        audit = [];
        chatSessions.clear();
        selectedProjectId = '';
      }
    }
  }

  /// Converte uma lista vinda de JSON item a item: um item inválido é registrado e ignorado, em vez de
  /// derrubar a lista inteira (e, com ela, o login ou a sincronização).
  List<T> _parseItems<T>(
    Object? raw,
    T Function(Map<String, dynamic>) parse,
    String what,
  ) {
    final out = <T>[];
    if (raw is! List) return out;
    for (final item in raw) {
      try {
        if (item is! Map)
          throw FormatException('item de $what não é um objeto');
        out.add(parse(Map<String, dynamic>.from(item)));
      } catch (e, st) {
        AppErrors.report(e, st, 'dados_invalidos:$what');
      }
    }
    return out;
  }

  Future<void> connect(AuthSession authenticated) async {
    if (working)
      throw ApiFailure('Aguarde o fim das operações para entrar novamente.');
    if (AppConfig.validateUrl(baseUrl) != null)
      throw ApiFailure(
        'O acesso da organização ainda não foi configurado. Contate o responsável pelo sistema.',
      );
    if (authenticated.expires.isBefore(DateTime.now()))
      throw ApiFailure('Entre novamente para continuar.');
    _sessionTimer?.cancel();
    _syncTimer?.cancel();
    _api?.close();
    _api = null;
    _auth?.close();
    _auth = null;
    session = authenticated;
    organizationId = authenticated.organizationId;
    subject = authenticated.subject;
    userName = authenticated.name;
    roles = authenticated.roles;
    token = authenticated.accessToken;
    baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      // O token já foi validado pelo Cognito (GetUser); as duas leituras são independentes e
      // seguem juntas. Se a conta não confere, a lista de obras é descartada.
      final projectsRequest = api.listAll('/api/obras');
      unawaited(projectsRequest.then((_) {}, onError: (_) {}));
      final account = await api.request('GET', '/api/conta');
      if (account['organizationId'] != organizationId ||
          account['subject'] != subject)
        throw ApiFailure('Não foi possível confirmar o acesso à organização.');
      company = (account['company'] ?? '').toString();
      await _load();
      await synchronize(prefetched: projectsRequest);
      started = true;
      section = Section.today;
      _scheduleSession();
      _syncTimer = Timer.periodic(Duration(seconds: 30), (_) {
        if (started &&
            !working &&
            {Section.today, Section.archive}.contains(section)) {
          unawaited(
            synchronize().catchError((Object e, StackTrace s) {
              AppErrors.report(e, s, 'sincronizacao');
            }),
          );
        }
      });
      notifyListeners();
    } catch (_) {
      signOut();
      rethrow;
    }
  }

  /// As obras vêm do servidor. Documentos e diários ficam no cache local: aqui só se retoma a consulta
  /// do que ainda está em processamento (leitura de documento e transcrição).
  Future<void> synchronize({
    Future<List<Map<String, dynamic>>>? prefetched,
  }) async {
    require(true);
    if (working) throw ApiFailure('Aguarde o fim da operação para atualizar.');
    final current = session;
    syncing = true;
    syncError = null;
    notifyListeners();
    try {
      final freshProjects = _parseItems(
        await (prefetched ?? api.listAll('/api/obras')),
        Project.fromJson,
        'obras',
      );
      if (session != current) return;
      projects = freshProjects;
      if (!projects.any((p) => p.id == selectedProjectId))
        selectedProjectId = projects.firstOrNull?.id ?? '';
      for (final d in documents.where(
        (d) =>
            d.remoteId != null && d.confirmed && d.status == 'AGUARDANDO_OCR',
      )) {
        try {
          final j = await api.result(d.remoteId!);
          if (session != current) return;
          _applyOcr(d, j);
          d.updated = DateTime.now();
        } catch (e, st) {
          d.message = friendlyMessage(e, st);
        }
      }
      for (final e in diaries.where(
        (e) =>
            e.remoteId != null &&
            {'GRAVADO', 'EM_TRANSCRICAO'}.contains(e.status),
      )) {
        try {
          final j = await api.result(e.remoteId!, audio: true);
          if (session != current) return;
          _applyDiary(e, j);
        } catch (err, st) {
          e.message = friendlyMessage(err, st);
        }
      }
      lastSync = DateTime.now();
      await persist();
    } catch (e, st) {
      if (session == current) syncError = friendlyMessage(e, st);
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void _scheduleSession() {
    _sessionTimer?.cancel();
    final current = session;
    if (current == null) return;
    final remaining = current.expires.difference(DateTime.now());
    final refreshIn = remaining - const Duration(minutes: 1);
    if (current.refreshToken.isNotEmpty && refreshIn > Duration.zero) {
      _sessionTimer = Timer(refreshIn, () async {
        try {
          _auth ??= CognitoAuth(cognitoIssuer, cognitoClientId);
          final updated = await _auth!.refresh(current);
          if (session != current) return;
          if (updated.subject != subject ||
              updated.organizationId != organizationId) {
            signOut();
            return;
          }
          session = updated;
          token = updated.accessToken;
          roles = updated.roles;
          _api?.http.options.headers['Authorization'] = 'Bearer $token';
          _scheduleSession();
          notifyListeners();
        } catch (e, st) {
          AppErrors.report(e, st, 'renovacao_sessao');
          if (session == current)
            _sessionTimer = Timer(
              current.expires.difference(DateTime.now()),
              signOut,
            );
        }
      });
    } else {
      _sessionTimer = Timer(remaining, signOut);
    }
  }

  void signOut() {
    _sessionTimer?.cancel();
    _syncTimer?.cancel();
    for (final t in tasks.values) {
      t.cancel();
    }
    // Mantém o escopo até os callbacks cancelados terminarem, sem exibir seu conteúdo.
    for (final d in documents) {
      if (d.running) d.status = 'PAUSADO';
    }
    token = '';
    session = null;
    started = false;
    recordingActive = false;
    _api?.close();
    _api = null;
    _auth?.close();
    _auth = null;
    notifyListeners();
  }

  static bool isUuid(String s) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(s.trim());

  /// Grava o espaço de trabalho no aparelho. Falha de disco é registrada e não propaga: os dados seguem
  /// na memória, e um erro aqui não pode mascarar o erro original de quem chamou dentro de um `finally`.
  Future<void> persist() async {
    try {
      await _put('$scope:workspace_v3', jsonEncode(snapshot()));
    } catch (e, st) {
      AppErrors.report(e, st, 'persistencia');
    }
    notifyListeners();
  }

  bool _disposed = false;

  /// Timers e `finally` podem notificar depois do `dispose`: isso viraria 'used after dispose'.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  Map<String, dynamic> snapshot() => {
    'schemaVersion': 3,
    'chatSessions': chatSessions,
    'projects': projects.map((e) => e.toJson()).toList(),
    'documents': documents.map((e) => e.toJson()).toList(),
    'diaries': diaries.map((e) => e.toJson()).toList(),
    'messages': messages.map((e) => e.toJson()).toList(),
    'audit': audit,
    'selectedProjectId': selectedProjectId,
  };
  void navigate(Section s, {String? document, String? diary}) {
    section = s;
    if (document != null) selectedDocumentId = document;
    if (diary != null) selectedDiaryId = diary;
    notifyListeners();
  }

  Future<void> selectProject(String id) async {
    selectedProjectId = id;
    selectedDocumentId = null;
    selectedDiaryId = null;
    await persist();
  }

  /// Cria ou edita a obra no servidor: o ID é gerado pelo banco, e executora e responsável, quando
  /// vazios, vêm da organização e do usuário logado.
  Future<void> saveProject(Project p) => _during(() async {
    require(canManageProjects);
    final saved = Project.fromJson(
      await api.request(
        p.id.isEmpty ? 'POST' : 'PATCH',
        p.id.isEmpty ? '/api/obras' : '/api/obras/${p.id}',
        data: p.toJson()..remove('id'),
      ),
    );
    projects.removeWhere((e) => e.id == saved.id);
    projects.add(saved);
    selectedProjectId = saved.id;
    log('Obra salva', saved.name);
    await persist();
  });

  void log(String action, String name) {
    audit.insert(0, {
      'action': action,
      'name': name,
      'date': DateTime.now().toIso8601String(),
      'projectId': selectedProjectId,
    });
    if (audit.length > 2000) audit.removeLast();
  }

  Future<void> cache(String id, Uint8List bytes) =>
      _put('$scope:bytes:$id', bytes);
  Uint8List? bytes(String id) {
    final value = _get('$scope:bytes:$id');
    return value is Uint8List
        ? value
        : value is List
        ? Uint8List.fromList(value.cast<int>())
        : null;
  }

  Future<void> addDocuments(List<PickedAsset> files) =>
      _during(() => _addDocuments(files));
  Future<void> _addDocuments(List<PickedAsset> files) async {
    require(canUpload);
    final projectId = selectedProjectId;
    if (files.fold<int>(0, (n, f) => n + f.bytes.length) > 200 * 1024 * 1024)
      throw ApiFailure('O lote deve ter até 200 MB.');
    if (projectId.isEmpty)
      throw ApiFailure('Selecione uma obra antes de enviar.');
    if (files.length > 100)
      throw ApiFailure('Selecione até 100 arquivos por lote.');
    final queue = <DocumentRecord>[];
    for (final file in files) {
      if (file.name.length > 255)
        throw ApiFailure('O nome do arquivo deve ter até 255 caracteres.');
      final ext = AppConfig.extension(file.name),
          type = AppConfig.documentTypes[AppConfig.extension(file.name)];
      if (type == null) throw ApiFailure('O formato .$ext não é aceito.');
      if (file.bytes.isEmpty ||
          file.bytes.length > AppConfig.maxBytes(file.name))
        throw ApiFailure(
          '${file.name}: arquivo vazio ou acima do limite (${AppConfig.maxBytes(file.name) ~/ 1024 ~/ 1024} MB).',
        );
    }
    for (final file in files) {
      final hash = sha256.convert(file.bytes).toString();
      if (documents.any((d) => d.projectId == projectId && d.hash == hash)) {
        log('Duplicata não enviada', file.name);
        continue;
      }
      final d = DocumentRecord(
        id: uuid.v4(),
        projectId: projectId,
        name: file.name,
        contentType: AppConfig.documentTypes[AppConfig.extension(file.name)]!,
        size: file.bytes.length,
        hash: hash,
      );
      await cache(d.id, file.bytes);
      documents.insert(0, d);
      queue.add(d);
    }
    await persist();
    navigate(Section.upload);
    // Sequencial: limita o uso de memória e não dispara lotes ilimitados na AWS.
    for (final d in queue) {
      if (d.status == 'CANCELADO') continue;
      await processDocument(d);
    }
  }

  Future<void> processDocument(DocumentRecord d) async {
    require(d.uploaded ? true : canUpload);
    if (tasks.containsKey(d.id)) return;
    final cancel = CancelToken();
    tasks[d.id] = cancel;
    notifyListeners();
    try {
      Map<String, dynamic>? receipt =
          _receipts[d.id] ??
          (_get('$scope:receipt:${d.id}') is String
              ? Map<String, dynamic>.from(
                  jsonDecode(_get('$scope:receipt:${d.id}')),
                )
              : null);
      d.uploaded = d.uploaded || receipt?['uploaded'] == true;
      d.confirmed = d.confirmed || receipt?['confirmed'] == true;
      final expires = DateTime.tryParse(receipt?['expiraEm'] ?? '');
      if (!d.uploaded &&
          (d.remoteId == null ||
              receipt == null ||
              expires != null && expires.isBefore(DateTime.now()))) {
        if (bytes(d.id) == null)
          throw ApiFailure(
            'Este envio foi iniciado em outro dispositivo. Conclua o envio no dispositivo de origem.',
          );
        d.status = 'ENVIANDO';
        notifyListeners();
        receipt = await api.prepareDocument(
          d.name,
          d.projectId,
          d.size,
          cancel: cancel,
        );
        d.remoteId = receipt['documentoId'];
        d.versionId = receipt['versionId'];
        // Onde o arquivo ficou no armazenamento (bucket/chave): <nome>_orig.<ext> na versão 1.
        if (receipt['chave'] is String)
          d.storage = '${receipt['bucket'] ?? ''}/${receipt['chave']}';
        if (d.remoteId == null || d.versionId == null)
          throw ApiFailure('Resposta de upload sem documentoId ou versionId.');
        _receipts[d.id] = receipt;
        await _put('$scope:receipt:${d.id}', jsonEncode(receipt));
        await persist();
      }
      if (!d.uploaded) {
        final payload = bytes(d.id);
        if (payload == null || receipt == null)
          throw ApiFailure(
            'O original não está neste dispositivo. Conclua o envio no dispositivo de origem.',
          );
        d.status = 'ENVIANDO';
        await api.putSigned(
          receipt,
          payload,
          cancel: cancel,
          progress: (p) {
            d.progress = p;
            notifyListeners();
          },
        );
        d.uploaded = true;
        receipt['uploaded'] = true;
        await _put('$scope:receipt:${d.id}', jsonEncode(receipt));
        await persist();
      }
      if (!d.confirmed) {
        await api.confirm(d.remoteId!, d.versionId!, d.hash, cancel: cancel);
        d.confirmed = true;
        if (receipt != null) {
          receipt['confirmed'] = true;
          await _put('$scope:receipt:${d.id}', jsonEncode(receipt));
        }
        await persist();
      }
      d.status = 'AGUARDANDO_OCR';
      d.progress = 1;
      await persist();
      final result = await api.poll(d.remoteId!, cancel: cancel);
      _applyOcr(d, result);
      log(d.ready ? 'Leitura concluída' : 'Leitura falhou', d.name);
      d.message = d.ready ? null : 'O processamento falhou no servidor. Confira o arquivo antes de reenviar.';
    } catch (e, st) {
      d.status = cancel.isCancelled
          ? 'CANCELADO'
          : e is ApiFailure && e.status == 202
          ? 'PAUSADO'
          : e is ApiFailure && e.status == 409
          ? 'DUPLICADO'
          : 'FAILED';
      d.message = friendlyMessage(e, st);
    } finally {
      tasks.remove(d.id);
      d.updated = DateTime.now();
      await persist();
    }
  }

  void _applyOcr(DocumentRecord d, Map<String, dynamic> j) {
    d.status = j['status'] ?? 'FAILED';
    d.versionId = j['versionId'] ?? d.versionId;
    d.text = j['texto'] ?? '';
    d.pages = (j['paginas'] as num?)?.toInt() ?? 0;
    d.source = j['engine'] ?? '';
    if (j['confiancaMedia'] is num)
      d.fields['Confiança média OCR'] =
          '${((j['confiancaMedia'] as num) * 100).toStringAsFixed(1)}%';
    // O contrato atual não fornece geometria, linhas ou páginas dos trechos.
    d.lines = [];
  }

  void cancel(String id) {
    tasks[id]?.cancel();
    final d = documents.where((d) => d.id == id).firstOrNull;
    if (d != null && !tasks.containsKey(id)) {
      d.status = 'CANCELADO';
      unawaited(persist());
    }
  }

  Future<void> review(
    DocumentRecord d,
    String category,
    String reviewer,
    Map<String, String> fields,
  ) => _during(() async {
    require(canApprove);
    if (d.remoteId == null || d.versionId == null)
      throw ApiFailure('Aguarde a leitura do documento.');
    // O servidor ainda não guarda a conferência: ela vale neste aparelho.
    d.category = category;
    d.fields = fields;
    d.reviewed = true;
    d.reviewedBy = userName;
    d.updated = DateTime.now();
    log('Conferência salva', d.name);
    await persist();
  });

  Future<Uint8List> original(DocumentRecord d) => _during(() async {
    require(true);
    final cached = bytes(d.id);
    if (cached != null) return cached;
    throw ApiFailure(
      'O original só está disponível no aparelho que fez o envio.',
    );
  });

  Future<DiaryEntry> addDiary(
    PickedAsset audio,
    String author,
    String role,
    DateTime date,
  ) async {
    require(canDiary);
    author = userName;
    if (project == null || author.trim().isEmpty || role.trim().isEmpty)
      throw ApiFailure('Informe obra, nome e função do autor.');
    if (role.trim().length > 100)
      throw ApiFailure('A função deve ter até 100 caracteres.');
    final type = AppConfig.audioTypes[AppConfig.extension(audio.name)];
    if (type == null ||
        audio.bytes.isEmpty ||
        audio.bytes.length > 120 * 1024 * 1024)
      throw ApiFailure('Envie um áudio OGG ou WEBM de até 120 MB.');
    final e = DiaryEntry(
      id: uuid.v4(),
      projectId: selectedProjectId,
      author: author.trim(),
      role: role.trim(),
      date: date,
    );
    diaries.insert(0, e);
    selectedDiaryId = e.id;
    final cancel = CancelToken();
    tasks[e.id] = cancel;
    notifyListeners();
    try {
      await cache(e.id, audio.bytes);
      e.details['Arquivo de áudio'] = audio.name;
      await persist();
      final signed = await api.prepareDiary(
        type,
        e.projectId,
        date.toIso8601String().substring(0, 10),
        e.role,
        audio.bytes.length,
        cancel: cancel,
      );
      e.remoteId = signed['diarioId'];
      e.weather = Map<String, dynamic>.from(signed['clima'] ?? {});
      await persist();
      await api.putSigned(signed, audio.bytes, cancel: cancel);
      e.status = 'EM_TRANSCRICAO';
      await persist();
      var j = await api.confirmDiary(e.remoteId!, cancel: cancel);
      if ({'GRAVADO', 'EM_TRANSCRICAO'}.contains(j['status']))
        j = await api.poll(e.remoteId!, audio: true, cancel: cancel);
      _applyDiary(e, j);
      log('Áudio registrado', e.author);
    } catch (err, st) {
      e.status = cancel.isCancelled ? 'CANCELADO' : 'FALHA_TRANSCRICAO';
      e.message = friendlyMessage(err, st);
    } finally {
      tasks.remove(e.id);
      await persist();
    }
    return e;
  }

  void _applyDiary(DiaryEntry e, Map<String, dynamic> j) {
    e.status = j['status'] ?? 'FALHA_TRANSCRICAO';
    e.raw = j['transcriptRaw'] ?? '';
    e.corrected = j['transcriptClean'] ?? '';
    e.message = j['mensagem'];
    e.weather = Map<String, dynamic>.from(j['clima'] ?? {});
    if (j['transcriptEdited'] != null) e.edited = j['transcriptEdited'];
    e.closed = {'FECHADO', 'RETIFICADO'}.contains(e.status);
    if ((j['palavrasBaixaConfianca'] as List? ?? []).isNotEmpty)
      e.lowConfidence = (j['palavrasBaixaConfianca'] as List)
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
  }

  Future<void> refreshDiary(DiaryEntry e) async {
    if (e.remoteId == null)
      throw ApiFailure('O envio não foi concluído. Importe o áudio novamente.');
    if (tasks.containsKey(e.id)) return;
    final cancel = CancelToken();
    tasks[e.id] = cancel;
    notifyListeners();
    try {
      _applyDiary(e, await api.poll(e.remoteId!, audio: true, cancel: cancel));
    } catch (err, st) {
      e.message = friendlyMessage(err, st);
    } finally {
      tasks.remove(e.id);
      await persist();
    }
  }

  Future<void> saveDiary(
    DiaryEntry e,
    String text,
    String reviewer, {
    bool close = false,
    Map<String, String>? details,
  }) => _during(
    () => _saveDiary(e, text, reviewer, close: close, details: details),
  );
  Future<void> _saveDiary(
    DiaryEntry e,
    String text,
    String reviewer, {
    bool close = false,
    Map<String, String>? details,
  }) async {
    require(close ? canApprove : canDiary);
    reviewer = userName;
    if (text.length > 50000)
      throw ApiFailure('A transcrição deve ter até 50.000 caracteres.');
    if (text.trim().isEmpty || reviewer.trim().isEmpty)
      throw ApiFailure('Preencha a transcrição e o nome do revisor.');
    if (e.closed)
      throw ApiFailure(
        'Diário fechado. A retificação ainda não está disponível no aplicativo.',
      );
    {
      if (e.remoteId == null)
        throw ApiFailure('O diário ainda não foi enviado.');
      final edited = await api.editDiary(e.remoteId!, text.trim());
      e.edited = edited['transcriptEdited'] ?? text.trim();
      e.status = edited['status'] ?? e.status;
      e.weather = Map<String, dynamic>.from(edited['clima'] ?? {});
      await persist();
      if (close) {
        final approved = await api.approveDiary(e.remoteId!);
        e.status = approved['status'];
        e.closed = {'FECHADO', 'RETIFICADO'}.contains(e.status);
        e.reviewer = approved['approvedBy'] ?? reviewer;
        e.weather = Map<String, dynamic>.from(approved['clima'] ?? {});
        e.details['Número sequencial'] = '${approved['sequenceNumber']}';
        e.details['Aprovado em'] = '${approved['approvedAt']}';
      }
    }
    e.reviewer = reviewer.trim();
    if (details != null) e.details.addAll(details);
    log(close ? 'Diário fechado' : 'Diário revisado', e.author);
    await persist();
  }

  Future<void> updateWeather(DiaryEntry e, Map<String, dynamic> values) =>
      _during(() => _updateWeather(e, values));
  Future<void> _updateWeather(DiaryEntry e, Map<String, dynamic> values) async {
    require(canDiary);
    if (e.remoteId == null)
      throw ApiFailure('Envie o diário antes de atualizar o clima.');
    e.weather = await api.weather(e.remoteId!, values);
    await persist();
  }

  /// Consulta o clima automático da obra. Não grava: a tela mostra os valores para o usuário confirmar
  /// ou corrigir, e só então [updateWeather] envia (com o `tokenConsulta` se nada mudou).
  Future<Map<String, dynamic>> fetchWeather(DiaryEntry e) => _during(() async {
    require(canDiary);
    return api.consultWeather(e.projectId);
  });

  Future<void> newConversation() async {
    if (busyChat) return;
    chatSessions.remove(selectedProjectId);
    messages.removeWhere((m) => m.projectId == selectedProjectId);
    await persist();
  }

  Future<void> ask(String question) async {
    require(true);
    if (busyChat || question.trim().isEmpty) return;
    if (project == null)
      throw ApiFailure('Selecione uma obra antes de perguntar.');
    if (question.trim().length > 2000)
      throw ApiFailure('Escreva até 2.000 caracteres por pergunta.');
    final p = selectedProjectId;
    final sessionId = chatSessions[p];
    final userMessage = ChatMessage(
      question.trim(),
      true,
      p,
      sessionId: sessionId,
    );
    final expected = session;
    busyChat = true;
    messages.add(userMessage);
    notifyListeners();
    try {
      final j = await api.ask(p, question.trim(), sessionId: sessionId);
      if (session != expected) return;
      if (j['resposta'] is! String || j['sessionId'] is! String)
        throw ApiFailure('Resposta do assistente incompleta.');
      chatSessions[p] = j['sessionId'];
      messages.add(
        ChatMessage(
          j['resposta'],
          false,
          p,
          sessionId: j['sessionId'],
          noSource: j['semFonte'] == true,
          citations: (j['citacoes'] as List? ?? [])
              .map((c) => Citation.fromJson(Map<String, dynamic>.from(c)))
              .toList(),
        ),
      );
      log(
        'Pergunta respondida',
        projects.where((e) => e.id == p).firstOrNull?.name ?? p,
      );
    } catch (_) {
      messages.remove(userMessage);
      rethrow;
    } finally {
      busyChat = false;
      await persist();
    }
  }

  Uint8List inventory() => csvBytes([
    [
      'Arquivo',
      'Categoria',
      'Obra',
      'Situação',
      'Páginas',
      'Bytes',
      'Conferido por',
    ],
    ...projectDocs.map(
      (d) => [
        d.name,
        d.category,
        project?.name,
        d.statusLabel,
        d.pages,
        d.size,
        d.reviewedBy ?? '',
      ],
    ),
  ]);

  @override
  void dispose() {
    _disposed = true;
    _sessionTimer?.cancel();
    _syncTimer?.cancel();
    _auth?.close();
    for (final c in tasks.values) {
      c.cancel();
    }
    _api?.close();
    super.dispose();
  }
}
