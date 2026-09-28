import 'package:flutter/material.dart';

import '../core/export.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'review.dart';

class ArchivePage extends StatefulWidget {
  final AppStore store;
  const ArchivePage(this.store, {super.key});
  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  String query = '', category = 'Todas', status = 'Todos', sort = 'recent';
  DateTimeRange? range;
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final docs =
        store.projectDocs.where((d) {
          final hay = '${d.name} ${d.text} ${d.category}'.toLowerCase();
          return hay.contains(query.toLowerCase()) &&
              (category == 'Todas' || d.category == category) &&
              (status == 'Todos' ||
                  status == 'Conferidos' && d.reviewed ||
                  status == 'Para conferir' && d.ready && !d.reviewed ||
                  status == 'Em processamento' && d.running ||
                  status == 'Com falha' &&
                      {'FAILED', 'FALHOU'}.contains(d.status)) &&
              (range == null ||
                  !d.created.isBefore(range!.start) &&
                      d.created.isBefore(range!.end.add(Duration(days: 1))));
        }).toList()..sort(
          (a, b) => sort == 'name'
              ? a.name.compareTo(b.name)
              : b.created.compareTo(a.created),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          number: '05',
          title: 'Encontre o que importa.',
          description: 'Busque pelo nome ou pelo texto lido. Cada documento continua ligado à sua obra.',
          actions: [
            FilledButton.icon(
              onPressed: () => store.navigate(Section.upload),
              icon: Icon(Icons.add, size: 18),
              label: Text('ENVIAR DOCUMENTO'),
            ),
            OutlinedButton.icon(
              onPressed: docs.isEmpty
                  ? null
                  : () => runAction(
                      context,
                      () => saveBytes(
                        'acervo-organizai.csv',
                        csvBytes([
                          [
                            'Arquivo',
                            'Categoria',
                            'Situação',
                            'Páginas',
                            'Bytes',
                          ],
                          ...docs.map(
                            (d) => [
                              d.name,
                              d.category,
                              d.statusLabel,
                              d.pages,
                              d.size,
                            ],
                          ),
                        ]),
                      ),
                    ),
              icon: Icon(Icons.download_outlined, size: 17),
              label: Text('EXPORTAR CSV'),
            ),
            OutlinedButton.icon(
              onPressed: store.working
                  ? null
                  : () => runAction(context, store.synchronize),
              icon: Icon(Icons.sync, size: 17),
              label: Text('ATUALIZAR'),
            ),
          ],
        ),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: Palette.muted),
            hintText: 'Nome do arquivo, termo do documento, categoria…',
          ),
        ),
        SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 210,
              child: DropdownButtonFormField<String>(
                initialValue: category,
                decoration: InputDecoration(labelText: 'Categoria'),
                isExpanded: true,
                items: ['Todas', ...categories]
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => category = v!),
              ),
            ),
            SizedBox(
              width: 195,
              child: DropdownButtonFormField<String>(
                initialValue: status,
                decoration: InputDecoration(labelText: 'Situação'),
                isExpanded: true,
                items:
                    [
                          'Todos',
                          'Conferidos',
                          'Para conferir',
                          'Em processamento',
                          'Com falha',
                        ]
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: (v) => setState(() => status = v!),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final r = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(Duration(days: 1)),
                  initialDateRange: range,
                );
                if (r != null) setState(() => range = r);
              },
              icon: Icon(Icons.date_range_outlined, size: 16),
              label: Text(
                range == null
                    ? 'Período'
                    : '${dateLabel(range!.start)} — ${dateLabel(range!.end)}',
              ),
            ),
            if (range != null)
              IconButton(
                tooltip: 'Limpar período',
                onPressed: () => setState(() => range = null),
                icon: Icon(Icons.close, size: 18),
              ),
            TextButton.icon(
              onPressed: () =>
                  setState(() => sort = sort == 'recent' ? 'name' : 'recent'),
              icon: Icon(Icons.sort, size: 17),
              label: Text(sort == 'recent' ? 'Mais recentes' : 'Nome A–Z'),
            ),
          ],
        ),
        SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Eyebrow('${docs.length} DOCUMENTOS ENCONTRADOS')),
            Text('ACERVO DA OBRA', style: mono(size: 9)),
          ],
        ),
        SizedBox(height: 14),
        if (docs.isEmpty)
          EmptyState(
            title: 'Nenhum documento encontrado.',
            description:
                'Ajuste os filtros ou envie o primeiro documento desta obra.',
            action: FilledButton(
              onPressed: () => store.navigate(Section.upload),
              child: Text('ENVIAR DOCUMENTO'),
            ),
          )
        else
          LayoutBuilder(
            builder: (c, constraints) => Column(
              children: [
                if (constraints.maxWidth >= 850)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Palette.raised,
                    child: Row(
                      children: [
                        Expanded(flex: 5, child: Eyebrow('ARQUIVO')),
                        Expanded(flex: 3, child: Eyebrow('CATEGORIA')),
                        Expanded(flex: 3, child: Eyebrow('SITUAÇÃO')),
                        Expanded(flex: 2, child: Eyebrow('ENVIO')),
                        SizedBox(width: 44),
                      ],
                    ),
                  ),
                for (final d in docs)
                  InkWell(
                    onTap: () => store.navigate(
                      d.ready ? Section.review : Section.upload,
                      document: d.id,
                    ),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Palette.border),
                        ),
                      ),
                      child: constraints.maxWidth >= 850
                          ? Row(
                              children: [
                                Expanded(flex: 5, child: _name(d)),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    d.category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Palette.muted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    d.statusLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: documentColor(d),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    dateLabel(d.created),
                                    style: mono(size: 10),
                                  ),
                                ),
                                _menu(d),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _name(d),
                                      SizedBox(height: 9),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 8,
                                        children: [
                                          StatusPill(
                                            d.statusLabel,
                                            color: documentColor(d),
                                          ),
                                          Text(
                                            d.category,
                                            style: TextStyle(
                                              color: Palette.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                _menu(d),
                              ],
                            ),
                    ),
                  ),
              ],
            ),
          ),
        SizedBox(height: 20),
        Notice(
          'A lista reúne os documentos da obra consultados no servidor. Use Atualizar para buscar novos registros.',
        ),
      ],
    );
  }

  Widget _name(DocumentRecord d) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        d.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      SizedBox(height: 5),
      Text('${fileSize(d.size)} · ${d.pages} pág.', style: mono(size: 9)),
    ],
  );
  Widget _menu(DocumentRecord d) => PopupMenuButton<String>(
    tooltip: 'Ações do documento',
    onSelected: (v) async {
      if (v == 'open')
        widget.store.navigate(
          d.ready ? Section.review : Section.upload,
          document: d.id,
        );
      if (v == 'download')
        await runAction(
          context,
          () async => saveBytes(d.name, await widget.store.original(d)),
        );
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'open', child: Text('Abrir')),
      PopupMenuItem(value: 'download', child: Text('Baixar original')),
    ],
  );
}
