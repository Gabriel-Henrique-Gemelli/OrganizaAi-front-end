import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/config.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

Future<void> selectDocuments(BuildContext context, AppStore store) async {
  await runAction(context, () async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: AppConfig.documentTypes.keys.toList(),
      withData: false,
      withReadStream: true,
    );
    if (picked == null) return;
    if (picked.files.length > 100 ||
        picked.files.fold<int>(0, (n, f) => n + f.size) > 200 * 1024 * 1024)
      throw Exception('Selecione até 100 arquivos e 200 MB por lote.');
    final files = <PickedAsset>[];
    for (final f in picked.files) {
      if (f.size > AppConfig.maxBytes(f.name))
        throw Exception('${f.name} ultrapassa o limite.');
      final builder = BytesBuilder(copy: false);
      if (f.bytes != null) {
        builder.add(f.bytes!);
      } else if (f.readStream != null) {
        await for (final chunk in f.readStream!) {
          builder.add(chunk);
        }
      } else if (f.path != null) {
        builder.add(await XFile(f.path!).readAsBytes());
      } else {
        throw Exception('Não foi possível ler ${f.name}. Selecione novamente.');
      }
      files.add(PickedAsset(f.name, builder.takeBytes()));
    }
    await store.addDocuments(files);
  });
}

class UploadPage extends StatefulWidget {
  final AppStore store;
  const UploadPage(this.store, {super.key});
  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  bool dragging = false;
  Future<void> receive(List<XFile> files) async => runAction(context, () async {
    if (files.length > 100) throw Exception('Selecione até 100 arquivos.');
    final picked = <PickedAsset>[];
    var total = 0;
    for (final f in files) {
      total += await f.length();
      if (total > 200 * 1024 * 1024)
        throw Exception('O lote deve ter até 200 MB.');
      if (await f.length() > AppConfig.maxBytes(f.name))
        throw Exception('${f.name} ultrapassa o limite.');
      picked.add(PickedAsset(f.name, await f.readAsBytes()));
    }
    await widget.store.addDocuments(picked);
  });
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          number: '02',
          title: 'Envie. A leitura começa aqui.',
          description: 'Documentos organizados por obra, com o original sempre preservado.',
        ),
        DropTarget(
          onDragEntered: (_) => setState(() => dragging = true),
          onDragExited: (_) => setState(() => dragging = false),
          onDragDone: (details) {
            setState(() => dragging = false);
            receive(details.files);
          },
          child: AnimatedContainer(
            duration: Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 44),
            decoration: BoxDecoration(
              color: dragging
                  ? Palette.accent.withValues(alpha: .1)
                  : Palette.surface,
              border: Border.all(
                color: dragging ? Palette.accent : Palette.border,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file_outlined,
                  size: 44,
                  color: Palette.accent,
                ),
                SizedBox(height: 18),
                Text(
                  dragging
                      ? 'SOLTE PARA ADICIONAR'
                      : 'ARQUIVOS DA OBRA.\nUM SÓ LUGAR.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Arraste arquivos ou selecione no dispositivo.',
                  style: TextStyle(color: Palette.muted),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: store.project == null
                          ? null
                          : () => selectDocuments(context, store),
                      child: Text('SELECIONAR ARQUIVOS'),
                    ),
                    if (!kIsWeb &&
                        {
                          TargetPlatform.android,
                          TargetPlatform.iOS,
                        }.contains(defaultTargetPlatform))
                      OutlinedButton.icon(
                        onPressed: () => runAction(context, () async {
                          final f = await ImagePicker().pickImage(
                            source: ImageSource.camera,
                            imageQuality: 90,
                          );
                          if (f != null) await receive([f]);
                        }),
                        icon: Icon(Icons.camera_alt_outlined, size: 18),
                        label: Text('FOTOGRAFAR'),
                      ),
                  ],
                ),
                SizedBox(height: 24),
                Text(
                  'PDF · JPG · PNG · TIFF · WORD · EXCEL · TXT',
                  style: mono(size: 10),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 6),
                Text(
                  '50 MB por documento · 20 MB para Office e TXT · até 100 arquivos',
                  style: TextStyle(color: Palette.muted, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 18),
        Notice(
          'Os arquivos serão enviados para a obra selecionada e ficarão disponíveis no acervo da organização.',
        ),
        SizedBox(height: 30),
        Row(
          children: [
            Expanded(child: Eyebrow('ENVIOS DESTA OBRA')),
            Text('${store.projectDocs.length} ARQUIVOS', style: mono(size: 10)),
          ],
        ),
        SizedBox(height: 14),
        for (final d in store.projectDocs)
          Container(
            padding: EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Palette.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: Palette.muted,
                      size: 22,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 5),
                          Text(
                            '${fileSize(d.size)} · ${d.statusLabel}',
                            style: TextStyle(
                              fontSize: 12,
                              color: documentColor(d),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (d.running)
                      IconButton(
                        tooltip: 'Cancelar consulta ou envio',
                        onPressed: () => store.cancel(d.id),
                        icon: Icon(Icons.close, size: 18),
                      )
                    else if (d.ready)
                      IconButton(
                        tooltip: 'Abrir documento',
                        onPressed: () =>
                            store.navigate(Section.review, document: d.id),
                        icon: Icon(Icons.arrow_forward, size: 20),
                      )
                    else if (d.status != 'DUPLICADO')
                      IconButton(
                        tooltip: 'Retomar',
                        onPressed: () =>
                            runAction(context, () => store.processDocument(d)),
                        icon: Icon(Icons.refresh, size: 20),
                      ),
                  ],
                ),
                if (d.running) ...[
                  SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: d.status == 'ENVIANDO' ? d.progress : null,
                    minHeight: 3,
                  ),
                ],
                if (d.message != null) ...[
                  SizedBox(height: 10),
                  Text(
                    d.message!,
                    style: TextStyle(fontSize: 12, color: Palette.warning),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
