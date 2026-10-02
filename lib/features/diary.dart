import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../core/export.dart';
import '../core/recording_path.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'weather.dart';

class DiaryPage extends StatefulWidget {
  final AppStore store;
  const DiaryPage(this.store, {super.key});
  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  AudioRecorder? recorder;
  Timer? timer;
  final author = TextEditingController(),
      role = TextEditingController(text: 'Engenheiro de campo'),
      text = TextEditingController(),
      reviewer = TextEditingController(),
      weather = TextEditingController(),
      services = TextEditingController(),
      people = TextEditingController();
  DateTime date = DateTime.now();
  int elapsed = 0;
  bool recording = false, busy = false;
  String loaded = '';
  @override
  void initState() {
    super.initState();
    author.text = widget.store.userName;
    reviewer.text = widget.store.userName;
  }

  @override
  void dispose() {
    timer?.cancel();
    recorder?.dispose();
    for (final c in [author, role, text, reviewer, weather, services, people]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> start() async {
    if (author.text.trim().isEmpty ||
        role.text.trim().isEmpty ||
        widget.store.project == null) {
      toast(context, 'Informe a obra, o nome e a função de quem vai falar.');
      return;
    }
    await runAction(context, () async {
      recorder ??= AudioRecorder();
      if (!await recorder!.hasPermission())
        throw Exception(
          'Permita o acesso ao microfone nas configurações do dispositivo.',
        );
      await recorder!.start(
        RecordConfig(
          encoder: AudioEncoder.opus,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: await recordingPath(),
      );
      if (!mounted) return;
      setState(() {
        recording = true;
        elapsed = 0;
      });
      widget.store.setRecording(true);
      timer = Timer.periodic(Duration(seconds: 1), (_) {
        if (mounted) setState(() => elapsed++);
        if (elapsed >= 3600) stop();
      });
    });
  }

  Future<void> stop() async {
    if (!recording) return;
    timer?.cancel();
    setState(() => recording = false);
    await runAction(context, () async {
      final path = await recorder!.stop();
      if (path == null)
        throw Exception('A gravação não gerou áudio. Tente novamente.');
      final data = await XFile(path).readAsBytes();
      await removeRecording(path);
      if (!mounted) return;
      await submit(
        PickedAsset(
          'diario-${DateTime.now().millisecondsSinceEpoch}.${kIsWeb ? 'webm' : 'ogg'}',
          data,
        ),
      );
    });
    widget.store.setRecording(false);
  }

  Future<void> submit(PickedAsset file) async {
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final pending = widget.store.addDiary(file, author.text, role.text, date);
      widget.store.setRecording(false);
      await pending;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importAudio() async => runAction(context, () async {
    final extensions = ['ogg', 'opus', 'webm'];
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    if (selected == null) return;
    final f = selected.files.single;
    if (f.bytes != null) await submit(PickedAsset(f.name, f.bytes!));
  });
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final entries = store.projectDiaries;
    final entry =
        entries.where((e) => e.id == store.selectedDiaryId).firstOrNull ??
        entries.firstOrNull;
    if (entry != null && loaded != entry.id) {
      loaded = entry.id;
      text.text = entry.displayText;
      reviewer.text = entry.reviewer.isNotEmpty
          ? entry.reviewer
          : store.userName;
      weather.text = entry.details['Clima observado'] ?? '';
      services.text = entry.details['Serviços executados'] ?? '';
      people.text = entry.details['Efetivo informado'] ?? '';
    }
    // Uma transcrição termina depois que a entrada foi criada; preencher só quando ainda não há edição.
    if (entry != null && text.text.isEmpty && entry.displayText.isNotEmpty)
      text.text = entry.displayText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          number: '07',
          title: 'O dia acontece. Você registra.',
          description: 'Grave em campo, confira a transcrição e aprove o diário com sua conta.',
        ),
        AdaptiveColumns(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Eyebrow('NOVO REGISTRO DE CAMPO', accent: true),
                    SizedBox(height: 20),
                    FieldLabel(
                      'Quem está falando?',
                      child: TextField(
                        controller: author,
                        enabled: false,
                        decoration: InputDecoration(
                          hintText: 'Autor autenticado',
                        ),
                      ),
                    ),
                    FieldLabel(
                      'Função',
                      child: TextField(
                        controller: role,
                        enabled: !recording && !busy,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Data do registro\n${dateLabel(date)}',
                            style: TextStyle(height: 1.7),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: recording || busy
                              ? null
                              : () async {
                                  final d = await showDatePicker(
                                    context: context,
                                    initialDate: date,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (d != null && mounted) setState(() => date = d);
                                },
                          icon: Icon(Icons.calendar_today_outlined, size: 17),
                          label: Text('Alterar'),
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Container(
                      padding: EdgeInsets.all(24),
                      color: Palette.bg,
                      child: Column(
                        children: [
                          Icon(
                            recording ? Icons.graphic_eq : Icons.mic_none,
                            size: 40,
                            color: Palette.accent,
                          ),
                          SizedBox(height: 15),
                          Text(
                            '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
                            style: mono(size: 34, color: Palette.text),
                          ),
                          SizedBox(height: 12),
                          Text(
                            recording
                                ? 'Gravando · máximo de 60 minutos'
                                : 'Conte os serviços, materiais e ocorrências.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Palette.muted,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : recording
                                ? stop
                                : start,
                            icon: Icon(
                              recording ? Icons.stop : Icons.mic,
                              size: 18,
                            ),
                            label: Text(
                              recording
                                  ? 'ENCERRAR E ENVIAR'
                                  : 'INICIAR GRAVAÇÃO',
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: recording || busy ? null : importAudio,
                      icon: Icon(Icons.audio_file_outlined, size: 17),
                      label: Text(
                        busy ? 'PROCESSANDO ÁUDIO…' : 'IMPORTAR ÁUDIO',
                      ),
                    ),
                    if (busy) ...[
                      SizedBox(height: 14),
                      LinearProgressIndicator(minHeight: 3),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 20),
              if (entry != null)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Eyebrow('TRANSCRIÇÃO E REVISÃO')),
                          StatusPill(
                            entry.status.replaceAll('_', ' '),
                            color: entry.closed
                                ? Palette.success
                                : Palette.warning,
                          ),
                        ],
                      ),
                      SizedBox(height: 18),
                      if (store.bytes(entry.id) != null) ...[
                        OutlinedButton.icon(
                          onPressed: () => runAction(
                            context,
                            () => saveBytes(
                              entry.details['Arquivo de áudio'] ?? 'diario.ogg',
                              store.bytes(entry.id)!,
                            ),
                          ),
                          icon: Icon(Icons.download_outlined, size: 16),
                          label: Text('BAIXAR ÁUDIO ORIGINAL'),
                        ),
                        SizedBox(height: 14),
                      ],
                      if (entry.message != null) ...[
                        Notice(entry.message!, color: Palette.warning),
                        SizedBox(height: 16),
                      ],
                      if (entry.status == 'EM_TRANSCRICAO' ||
                          entry.status == 'GRAVADO')
                        LinearProgressIndicator(minHeight: 3),
                      if (entry.displayText.isNotEmpty) ...[
                        TextField(
                          controller: text,
                          maxLength: 50000,
                          readOnly: entry.closed,
                          minLines: 8,
                          maxLines: 20,
                          decoration: InputDecoration(
                            labelText: 'Texto revisado',
                          ),
                        ),
                        SizedBox(height: 16),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            'Ver transcrição original',
                            style: TextStyle(fontSize: 13),
                          ),
                          children: [
                            Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: SelectableText(
                                entry.raw,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Palette.muted,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (entry.lowConfidence.isNotEmpty)
                          Notice(
                            'Confira estas palavras: ${entry.lowConfidence.map((e) => e['palavra']).join(', ')}',
                            color: Palette.warning,
                          ),
                        SizedBox(height: 16),
                        FieldLabel(
                          'Nome do revisor',
                          child: TextField(
                            controller: reviewer,
                            readOnly: true,
                          ),
                        ),
                        if (!entry.closed)
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => save(entry, false),
                                child: Text('SALVAR REVISÃO'),
                              ),
                              FilledButton(
                                onPressed: busy || !store.canApprove
                                    ? null
                                    : () => save(entry, true),
                                child: Text('APROVAR DIÁRIO'),
                              ),
                            ],
                          ),
                        SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => runAction(context, () async {
                            await saveBytes(
                              'diario-${dateLabel(entry.date).replaceAll('/', '-')}.pdf',
                              await diaryPdf(entry, store.project?.name ?? ''),
                            );
                          }),
                          icon: Icon(Icons.picture_as_pdf_outlined, size: 18),
                          label: Text('EXPORTAR PDF'),
                        ),
                      ] else
                        OutlinedButton(
                          onPressed: store.tasks.containsKey(entry.id)
                              ? null
                              : () => runAction(
                                  context,
                                  () => store.refreshDiary(entry),
                                ),
                          child: Text('CONSULTAR TRANSCRIÇÃO'),
                        ),
                      if (store.tasks.containsKey(entry.id))
                        TextButton(
                          onPressed: () => store.cancel(entry.id),
                          child: Text('Parar consulta'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (entry != null) ...[
                DiaryWeather(store, entry, key: ValueKey(entry.id)),
                SizedBox(height: 20),
              ],
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Eyebrow('REGISTROS DA OBRA'),
                    SizedBox(height: 16),
                    if (entries.isEmpty)
                      Text(
                        'Os registros aparecerão aqui.',
                        style: TextStyle(color: Palette.muted),
                      ),
                    for (final e in entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        selected: entry?.id == e.id,
                        onTap: recording
                            ? null
                            : () => store.navigate(Section.diary, diary: e.id),
                        leading: Icon(
                          e.closed ? Icons.task_alt : Icons.mic_none,
                          color: e.closed ? Palette.success : Palette.accent,
                        ),
                        title: Text(
                          dateLabel(e.date),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          e.author,
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Icon(Icons.chevron_right, size: 18),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              if (entry != null)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Eyebrow('COMPLEMENTOS DO REGISTRO'),
                      SizedBox(height: 18),
                      FieldLabel(
                        'Serviços executados',
                        child: TextField(
                          controller: services,
                          readOnly: entry.closed,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Informação declarada',
                          ),
                        ),
                      ),
                      FieldLabel(
                        'Efetivo informado',
                        child: TextField(
                          controller: people,
                          readOnly: entry.closed,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      FieldLabel(
                        'Clima observado',
                        child: TextField(
                          controller: weather,
                          readOnly: entry.closed,
                          decoration: InputDecoration(
                            hintText: 'Ex.: chuva à tarde',
                          ),
                          maxLines: 2,
                        ),
                      ),
                      Notice(
                        'Estes complementos são preenchidos manualmente, salvos na organização e incluídos no PDF.',
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> save(DiaryEntry entry, bool close) async {
    if (close &&
        !await confirm(
          context,
          'Aprovar e fechar o diário?',
          'Confira a transcrição antes de aprovar. O registro ficará fechado para edição no aplicativo.',
          button: 'Aprovar',
        ))
      return;
    if (!mounted) return;
    setState(() => busy = true);
    await runAction(
      context,
      () => widget.store.saveDiary(
        entry,
        text.text,
        reviewer.text,
        close: close,
        details: {
          'Clima observado': weather.text,
          'Serviços executados': services.text,
          'Efetivo informado': people.text,
        },
      ),
      success: close ? 'Diário aprovado.' : 'Revisão salva.',
    );
    if (mounted) setState(() => busy = false);
  }
}
