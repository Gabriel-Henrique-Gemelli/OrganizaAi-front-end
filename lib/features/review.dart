import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/export.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const categories = [
  'Não classificado',
  'Contrato',
  'Alvará',
  'Memorial descritivo',
  'Projeto estrutural',
  'Projeto elétrico',
  'Projeto arquitetônico',
  'Orçamento',
  'Medição',
  'Relatório',
  'ART / RRT',
  'Outro',
];

class ReviewPage extends StatefulWidget {
  final AppStore store;
  const ReviewPage(this.store, {super.key});
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final reviewer = TextEditingController(), notes = TextEditingController();
  String category = 'Não classificado', loadedId = '';
  bool saving = false;
  @override
  void dispose() {
    reviewer.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final docs = store.projectDocs.where((d) => d.ready).toList();
    final d =
        docs.where((d) => d.id == store.selectedDocumentId).firstOrNull ??
        store.reviews.firstOrNull ??
        docs.firstOrNull;
    if (d == null)
      return EmptyState(
        title: 'Nenhuma leitura para conferir.',
        description: 'Os documentos aparecem aqui quando o OCR termina.',
        icon: Icons.fact_check_outlined,
        action: FilledButton(
          onPressed: () => store.navigate(Section.upload),
          child: Text('ENVIAR DOCUMENTO'),
        ),
      );
    if (loadedId != d.id) {
      loadedId = d.id;
      category = categories.contains(d.category) ? d.category : 'Outro';
      reviewer.text = store.userName;
      notes.text = d.fields['Observações'] ?? '';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          number: '03',
          title: 'A origem à vista. Você confere.',
          description:
              'Compare o original com o texto lido e organize o documento.',
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(d.id),
          initialValue: d.id,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Documento'),
          items: docs
              .map(
                (e) => DropdownMenuItem(
                  value: e.id,
                  child: Text(e.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          // Adiado para depois do frame: a chave do dropdown muda com o documento, e navegar na hora
          // desmonta o elemento enquanto a rota do menu ainda depende dele (assertion _dependents.isEmpty).
          onChanged: (id) => WidgetsBinding.instance.addPostFrameCallback(
            (_) => store.navigate(Section.review, document: id),
          ),
        ),
        SizedBox(height: 22),
        AdaptiveColumns(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Eyebrow('DOCUMENTO ORIGINAL')),
                  if (d.remoteId != null || store.bytes(d.id) != null)
                    TextButton.icon(
                      onPressed: () => runAction(
                        context,
                        () async => saveBytes(d.name, await store.original(d)),
                      ),
                      icon: Icon(Icons.download, size: 16),
                      label: Text('Baixar'),
                    ),
                ],
              ),
              SizedBox(height: 12),
              DocumentPreview(store, d),
              SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(d.statusLabel, color: documentColor(d)),
                  StatusPill('${d.pages} páginas'),
                  StatusPill(d.source.isEmpty ? 'Leitura' : d.source),
                ],
              ),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('TEXTO RECONHECIDO', accent: true),
                    SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 340),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          d.text.isEmpty
                              ? 'O servidor não retornou texto.'
                              : d.text,
                          style: TextStyle(height: 1.6, fontSize: 13),
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    if (d.fields['Confiança média OCR'] != null)
                      Text(
                        'Confiança média: ${d.fields['Confiança média OCR']}',
                        style: mono(size: 10),
                      ),
                    SizedBox(height: 12),
                    Text(
                      'O OCR atual devolve o texto integral, sem coordenadas de trechos. Confira a correspondência no original.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Palette.muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Eyebrow('CONFERÊNCIA MANUAL'),
                    SizedBox(height: 20),
                    FieldLabel(
                      'Categoria',
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('${d.id}-category'),
                        initialValue: category,
                        isExpanded: true,
                        items: categories
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => category = v!),
                      ),
                    ),
                    FieldLabel(
                      'Conferido por',
                      child: TextField(
                        controller: reviewer,
                        readOnly: true,
                        decoration: InputDecoration(hintText: 'Nome declarado'),
                      ),
                    ),
                    FieldLabel(
                      'Observações',
                      child: TextField(
                        controller: notes,
                        minLines: 2,
                        maxLines: 5,
                      ),
                    ),
                    Notice(
                      'Categoria, observações e conferência ficam salvas na organização.',
                    ),
                    SizedBox(height: 18),
                    FilledButton(
                      onPressed: saving || !store.canApprove || store.working
                          ? null
                          : () async {
                              setState(() => saving = true);
                              await runAction(
                                context,
                                () => store.review(d, category, reviewer.text, {
                                  'Observações': notes.text,
                                }),
                                success: 'Conferência salva.',
                              );
                              if (mounted) setState(() => saving = false);
                              // Conferido: segue para o próximo pendente ou, sem nenhum, para o acervo.
                              if (mounted && d.reviewed) {
                                final next = store.reviews.firstOrNull;
                                store.navigate(
                                  next == null
                                      ? Section.archive
                                      : Section.review,
                                  document: next?.id,
                                );
                              }
                            },
                      child: Text(saving ? 'SALVANDO…' : 'CONFIRMAR LEITURA'),
                    ),
                    SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () =>
                          store.navigate(Section.assistant, document: d.id),
                      child: Text('ABRIR ASSISTENTE DA OBRA'),
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
}

class DocumentPreview extends StatelessWidget {
  final AppStore store;
  final DocumentRecord doc;
  const DocumentPreview(this.store, this.doc, {super.key});
  @override
  Widget build(BuildContext context) {
    final b = store.bytes(doc.id);
    return Container(
      height: 560,
      decoration: BoxDecoration(
        color: Palette.surface,
        border: Border.all(color: Palette.border),
      ),
      child: b == null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 42,
                      color: Palette.muted,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Visualizar o original',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: store.working
                          ? null
                          : () => runAction(context, () => store.original(doc)),
                      icon: Icon(Icons.download_outlined),
                      label: Text('CARREGAR ORIGINAL'),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Carregue o arquivo para conferir o conteúdo ao lado do texto reconhecido.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Palette.muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : doc.contentType == 'application/pdf'
          ? PdfViewer.data(b, sourceName: doc.id, key: ValueKey(doc.id))
          : doc.contentType.startsWith('image/')
          ? InteractiveViewer(
              child: Image.memory(
                b,
                errorBuilder: (_, __, ___) => Center(
                  child: Text('Este formato de imagem pode ser baixado.'),
                ),
              ),
            )
          : Padding(
              padding: EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: SelectableText(
                  doc.contentType == 'text/plain'
                      ? utf8.decode(b, allowMalformed: true)
                      : 'A visualização deste formato não está disponível aqui. Baixe o original para abrir no seu aplicativo. O texto reconhecido está no painel de conferência.',
                  style: TextStyle(height: 1.7),
                ),
              ),
            ),
    );
  }
}
