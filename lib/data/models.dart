import 'dart:typed_data';

enum Section { today, upload, review, archive, diary, assistant, account }

extension SectionText on Section {
  String get label => [
    'Hoje',
    'Enviar',
    'Revisar',
    'Acervo',
    'Diário',
    'Perguntar',
    'Conta',
  ][index];
  String get number => ['01', '02', '03', '05', '07', '09', '10'][index];
  String get path => [
    'hoje',
    'enviar',
    'revisar',
    'acervo',
    'diario',
    'perguntar',
    'conta',
  ][index];
}

class Project {
  String id,
      name,
      code,
      city,
      state,
      address,
      contractor,
      executor,
      plannedStartDate,
      plannedEndDate,
      responsible,
      registration,
      type,
      status;
  double? latitude, longitude;
  Project({
    required this.id,
    required this.name,
    this.code = '',
    this.city = '',
    this.state = '',
    this.address = '',
    this.contractor = '',
    this.executor = '',
    this.plannedStartDate = '',
    this.plannedEndDate = '',
    this.latitude,
    this.longitude,
    this.responsible = '',
    this.registration = '',
    this.type = 'RESIDENCIAL',
    this.status = 'EM_EXECUCAO',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'city': city,
    'state': state,
    'address': address,
    'contractor': contractor,
    'executor': executor,
    'plannedStartDate': plannedStartDate,
    'plannedEndDate': plannedEndDate,
    'latitude': latitude,
    'longitude': longitude,
    'responsible': responsible,
    'registration': registration,
    'type': type,
    'status': status,
  };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'],
    name: j['name'],
    code: j['code'] ?? '',
    city: j['city'] ?? '',
    state: j['state'] ?? '',
    address: j['address'] ?? '',
    contractor: j['contractor'] ?? '',
    executor: j['executor'] ?? '',
    plannedStartDate: j['plannedStartDate'] ?? '',
    plannedEndDate: j['plannedEndDate'] ?? '',
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    responsible: j['responsible'] ?? '',
    registration: j['registration'] ?? '',
    type: j['type'] ?? 'RESIDENCIAL',
    status: j['status'] ?? 'EM_EXECUCAO',
  );
}

class OcrLine {
  final int page;
  final String text;
  final double confidence;
  OcrLine(this.page, this.text, this.confidence);
  factory OcrLine.fromJson(Map<String, dynamic> j) => OcrLine(
    (j['pagina'] as num?)?.toInt() ?? 1,
    j['texto'] ?? '',
    (j['confianca'] as num?)?.toDouble() ?? 0,
  );
  Map<String, dynamic> toJson() => {
    'pagina': page,
    'texto': text,
    'confianca': confidence,
  };
}

class DocumentRecord {
  String id, projectId, name, contentType, hash, status, category, text, source, storage;
  String? remoteId, versionId, message, validity, reviewedBy;
  int size, pages;
  DateTime created, updated;
  bool reviewed, uploaded, confirmed;
  double progress;
  List<OcrLine> lines;
  Map<String, String> fields;
  DocumentRecord({
    required this.id,
    required this.projectId,
    required this.name,
    required this.contentType,
    required this.size,
    this.hash = '',
    this.status = 'NA_FILA',
    this.category = 'Não classificado',
    this.text = '',
    this.source = '',
    this.storage = '',
    this.remoteId,
    this.versionId,
    this.message,
    this.validity,
    this.reviewedBy,
    this.pages = 0,
    DateTime? created,
    DateTime? updated,
    this.reviewed = false,
    this.uploaded = false,
    this.confirmed = false,
    this.progress = 0,
    List<OcrLine>? lines,
    Map<String, String>? fields,
  }) : created = created ?? DateTime.now(),
       updated = updated ?? DateTime.now(),
       lines = lines ?? [],
       fields = fields ?? {};
  bool get ready =>
      {'SUCCEEDED', 'PARTIAL_SUCCESS', 'PROCESSADO'}.contains(status);
  bool get running =>
      {'NA_FILA', 'ENVIANDO', 'AGUARDANDO_OCR'}.contains(status);
  String get statusLabel => switch (status) {
    'NA_FILA' => 'Na fila',
    'ENVIANDO' => 'Enviando',
    'AGUARDANDO_OCR' => 'Lendo documento',
    'PROCESSADO' ||
    'SUCCEEDED' => reviewed ? 'Conferido' : 'Pronto para conferir',
    'PARTIAL_SUCCESS' => 'Leitura parcial',
    'PAUSADO' => 'Consulta pausada',
    'CANCELADO' => 'Cancelado',
    'FAILED' || 'FALHOU' => 'Falha',
    _ => status,
  };
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'name': name,
    'contentType': contentType,
    'size': size,
    'hash': hash,
    'status': status,
    'category': category,
    'text': text,
    'source': source,
    'storage': storage,
    'remoteId': remoteId,
    'versionId': versionId,
    'message': message,
    'validity': validity,
    'reviewedBy': reviewedBy,
    'pages': pages,
    'created': created.toIso8601String(),
    'updated': updated.toIso8601String(),
    'reviewed': reviewed,
    'uploaded': uploaded,
    'confirmed': confirmed,
    'lines': lines.map((e) => e.toJson()).toList(),
    'fields': fields,
  };
  factory DocumentRecord.fromJson(Map<String, dynamic> j) => DocumentRecord(
    id: j['id'],
    projectId: j['projectId'],
    name: j['name'],
    contentType: j['contentType'],
    size: j['size'],
    hash: j['hash'] ?? '',
    status: j['status'],
    category: j['category'] ?? 'Não classificado',
    text: j['text'] ?? '',
    source: j['source'] ?? '',
    storage: j['storage'] ?? '',
    remoteId: j['remoteId'],
    versionId: j['versionId'],
    message: j['message'],
    validity: j['validity'],
    reviewedBy: j['reviewedBy'],
    pages: j['pages'] ?? 0,
    created: DateTime.parse(j['created']),
    updated: DateTime.parse(j['updated']),
    reviewed: j['reviewed'] ?? false,
    uploaded: j['uploaded'] ?? false,
    confirmed: j['confirmed'] ?? false,
    lines: (j['lines'] as List? ?? [])
        .map((e) => OcrLine.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    fields: Map<String, String>.from(j['fields'] ?? {}),
  );
}

class DiaryEntry {
  String id, projectId, author, role, reviewer, raw, corrected, edited, status;
  String? remoteId, message;
  DateTime date;
  double? confidence, seconds;
  List<Map<String, dynamic>> lowConfidence;
  Map<String, String> details;
  Map<String, dynamic> weather;
  bool closed;
  DiaryEntry({
    required this.id,
    required this.projectId,
    required this.author,
    required this.role,
    required this.date,
    this.reviewer = '',
    this.raw = '',
    this.corrected = '',
    this.edited = '',
    this.status = 'GRAVADO',
    this.remoteId,
    this.message,
    this.confidence,
    this.seconds,
    this.closed = false,
    List<Map<String, dynamic>>? lowConfidence,
    Map<String, String>? details,
    Map<String, dynamic>? weather,
  }) : lowConfidence = lowConfidence ?? [],
       details = details ?? {},
       weather = weather ?? {};
  String get displayText => edited.isNotEmpty
      ? edited
      : corrected.isNotEmpty
      ? corrected
      : raw;
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'author': author,
    'role': role,
    'date': date.toIso8601String(),
    'reviewer': reviewer,
    'raw': raw,
    'corrected': corrected,
    'edited': edited,
    'status': status,
    'remoteId': remoteId,
    'message': message,
    'confidence': confidence,
    'seconds': seconds,
    'closed': closed,
    'lowConfidence': lowConfidence,
    'details': details,
    'weather': weather,
  };
  factory DiaryEntry.fromJson(Map<String, dynamic> j) => DiaryEntry(
    id: j['id'],
    projectId: j['projectId'],
    author: j['author'],
    role: j['role'],
    date: DateTime.parse(j['date']),
    reviewer: j['reviewer'] ?? '',
    raw: j['raw'] ?? '',
    corrected: j['corrected'] ?? '',
    edited: j['edited'] ?? '',
    status: j['status'],
    remoteId: j['remoteId'],
    message: j['message'],
    confidence: (j['confidence'] as num?)?.toDouble(),
    seconds: (j['seconds'] as num?)?.toDouble(),
    closed: j['closed'] ?? false,
    lowConfidence: (j['lowConfidence'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
    details: Map<String, String>.from(j['details'] ?? {}),
    weather: Map<String, dynamic>.from(j['weather'] ?? {}),
  );
}

class Citation {
  final String chunkId, title, snippet;
  final int? page;
  Citation(this.chunkId, this.title, this.snippet, {this.page});
  factory Citation.fromJson(Map<String, dynamic> j) => Citation(
    j['chunkId'],
    j['documentTitle'] ?? 'Fonte',
    j['snippet'] ?? '',
    page: (j['page'] as num?)?.toInt(),
  );
  Map<String, dynamic> toJson() => {
    'chunkId': chunkId,
    'documentTitle': title,
    'snippet': snippet,
    'page': page,
  };
}

class ChatMessage {
  final String text;
  final bool user, noSource;
  final String projectId;
  final String? sessionId;
  final DateTime date;
  final List<Citation> citations;
  ChatMessage(
    this.text,
    this.user,
    this.projectId, {
    DateTime? date,
    this.sessionId,
    this.noSource = false,
    List<Citation>? citations,
  }) : date = date ?? DateTime.now(),
       citations = citations ?? [];
  Map<String, dynamic> toJson() => {
    'text': text,
    'user': user,
    'projectId': projectId,
    'sessionId': sessionId,
    'date': date.toIso8601String(),
    'noSource': noSource,
    'citations': citations.map((e) => e.toJson()).toList(),
  };
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    j['text'],
    j['user'],
    j['projectId'] ?? '',
    sessionId: j['sessionId'],
    date: DateTime.parse(j['date']),
    noSource: j['noSource'] ?? false,
    citations: (j['citations'] as List? ?? [])
        .map((e) => Citation.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
}

class PickedAsset {
  final String name;
  final Uint8List bytes;
  const PickedAsset(this.name, this.bytes);
}
