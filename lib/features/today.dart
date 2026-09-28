import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'projects.dart';

class TodayPage extends StatelessWidget {
  final AppStore store;
  const TodayPage(this.store, {super.key});
  @override
  Widget build(BuildContext context) {
    final docs = store.projectDocs, pending = store.reviews.length;
    if (store.project == null)
      return EmptyState(
        title: 'Sua primeira obra começa aqui.',
        description:
            'Adicione uma obra para organizar documentos e registrar o diário.',
        action: store.canManageProjects
            ? FilledButton(
                onPressed: () => projectDialog(context, store),
                child: Text('ADICIONAR OBRA'),
              )
            : null,
      );
    final categories = <String, int>{};
    for (final d in docs) {
      categories.update(d.category, (n) => n + 1, ifAbsent: () => 1);
    }
    final diaryPending = store.projectDiaries.where((d) => !d.closed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Eyebrow('01 / HOJE NA OBRA', accent: true),
        SizedBox(height: 18),
        Container(
          padding: EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Palette.accent, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (c, constraints) => Text(
                  pending > 0
                      ? '$pending LEITURAS.\nSEU OLHAR FAZ A DIFERENÇA.'
                      : 'SUA OBRA.\nDOCUMENTADA.',
                  style: TextStyle(
                    fontSize: constraints.maxWidth > 750 ? 54 : 34,
                    fontWeight: FontWeight.w800,
                    height: 1.01,
                    letterSpacing: -1.6,
                  ),
                ),
              ),
              SizedBox(height: 18),
              Text(
                pending > 0
                    ? 'Os documentos foram lidos. Confira o conteúdo, organize as categorias e mantenha a origem à vista.'
                    : 'Envie documentos, registre o dia e encontre a informação de que precisa.',
                style: TextStyle(
                  fontSize: 16,
                  color: Palette.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 26),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (store.canManageProjects)
              OutlinedButton.icon(
                onPressed: store.working
                    ? null
                    : () => projectDialog(
                        context,
                        store,
                        existing: store.project,
                      ),
                icon: Icon(Icons.business_outlined, size: 18),
                label: Text('DADOS DA OBRA'),
              ),
            FilledButton.icon(
              onPressed: () =>
                  store.navigate(pending > 0 ? Section.review : Section.upload),
              icon: Icon(
                pending > 0 ? Icons.fact_check_outlined : Icons.add,
                size: 18,
              ),
              label: Text(
                pending > 0 ? 'CONFERIR LEITURAS' : 'ENVIAR DOCUMENTO',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => store.navigate(Section.diary),
              icon: Icon(Icons.mic_none, size: 18),
              label: Text('REGISTRAR O DIA'),
            ),
          ],
        ),
        SizedBox(height: 32),
        LayoutBuilder(
          builder: (c, constraints) {
            final width =
                (constraints.maxWidth -
                    (constraints.maxWidth < 650 ? 12 : 36)) /
                (constraints.maxWidth < 650 ? 2 : 4);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: Metric(
                    '${docs.length}'.padLeft(2, '0'),
                    'NO ACERVO',
                    'Documentos desta obra',
                    onTap: () => store.navigate(Section.archive),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: Metric(
                    '${docs.where((d) => d.reviewed).length}'.padLeft(2, '0'),
                    'CONFERIDOS',
                    'Leitura revisada',
                    onTap: () => store.navigate(Section.archive),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: Metric(
                    '$pending'.padLeft(2, '0'),
                    'PARA CONFERIR',
                    'Aguardam seu olhar',
                    accent: true,
                    onTap: () => store.navigate(Section.review),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: Metric(
                    '$diaryPending'.padLeft(2, '0'),
                    'DIÁRIOS ABERTOS',
                    'Registros em elaboração',
                    onTap: () => store.navigate(Section.diary),
                  ),
                ),
              ],
            );
          },
        ),
        SizedBox(height: 32),
        AdaptiveColumns(
          left: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Eyebrow('MOVIMENTAÇÕES DA OBRA')),
                    TextButton(
                      onPressed: () => store.navigate(Section.archive),
                      child: Text('Ver acervo →'),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                if (docs.isEmpty)
                  Text(
                    'Nenhum envio ainda.',
                    style: TextStyle(color: Palette.muted),
                  ),
                ...docs
                    .take(6)
                    .map(
                      (d) => InkWell(
                        onTap: () => store.navigate(
                          d.ready ? Section.review : Section.upload,
                          document: d.id,
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 15),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                color: documentColor(d),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 5),
                                    Text(
                                      '${d.statusLabel} · ${d.category}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Palette.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(timeLabel(d.created), style: mono(size: 10)),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('ACERVO POR CATEGORIA'),
                    SizedBox(height: 20),
                    if (categories.isEmpty)
                      Text(
                        'As categorias aparecem após sua conferência.',
                        style: TextStyle(color: Palette.muted),
                      ),
                    ...categories.entries
                        .take(5)
                        .map(
                          (e) => Padding(
                            padding: EdgeInsets.only(bottom: 18),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.key,
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    Text(
                                      '${e.value}',
                                      style: mono(color: Palette.text),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 9),
                                LinearProgressIndicator(
                                  value: e.value / docs.length,
                                  minHeight: 3,
                                  color: Palette.accent,
                                  backgroundColor: Palette.border,
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('DA OBRA PARA O ACERVO', accent: true),
                    SizedBox(height: 12),
                    Text(
                      'Fale. Revise.\nRegistre o dia.',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      'O diário por voz preserva a transcrição original e a revisão.',
                      style: TextStyle(color: Palette.muted, height: 1.5),
                    ),
                    SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => store.navigate(Section.diary),
                      child: Text('ABRIR DIÁRIO →'),
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
