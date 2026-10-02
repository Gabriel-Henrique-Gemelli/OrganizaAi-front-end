import 'package:flutter/material.dart';

import '../core/error_handling.dart';
import '../data/app_store.dart';
import '../data/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class AssistantPage extends StatefulWidget {
  final AppStore store;
  const AssistantPage(this.store, {super.key});
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final question = TextEditingController();
  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  Future<void> send() async {
    final q = question.text.trim();
    if (q.isEmpty || widget.store.busyChat) return;
    try {
      await widget.store.ask(q);
      if (mounted && question.text.trim() == q) question.clear();
    } catch (e, st) {
      if (mounted) toast(context, friendlyMessage(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    if (store.project == null)
      return EmptyState(
        title: 'Selecione uma obra para começar.',
        description: 'O assistente pesquisa os documentos e diários da obra selecionada.',
        icon: Icons.forum_outlined,
      );
    final conversation = store.messages
        .where((m) => m.projectId == store.selectedProjectId)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeading(
          number: '09',
          title: 'Pergunte. Volte à fonte.',
          description: 'Encontre respostas nos documentos e diários da sua obra, com trechos para conferir.',
        ),
        AdaptiveColumns(
          leftFlex: 1,
          rightFlex: 3,
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Eyebrow('CONTEXTO DA CONVERSA'),
              SizedBox(height: 16),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.domain_outlined, color: Palette.accent),
                    SizedBox(height: 14),
                    Text(
                      store.project!.name,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Documentos e diários indexados desta obra',
                      style: TextStyle(color: Palette.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 22),
              Eyebrow('COMECE POR AQUI'),
              SizedBox(height: 12),
              for (final q in [
                'Quais serviços foram registrados nos últimos diários?',
                'Quais são os valores e condições dos contratos?',
                'Quem são os responsáveis citados nos documentos?',
                'Resuma as ocorrências registradas na obra.',
              ])
                Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: OutlinedButton(
                    onPressed: store.busyChat ? null : () => question.text = q,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        q,
                        style: TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  ),
                ),
              SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: store.busyChat || conversation.isEmpty
                    ? null
                    : () async {
                        if (await confirm(
                          context,
                          'Iniciar nova conversa?',
                          'O histórico desta conversa será removido deste dispositivo. Os documentos serão preservados.',
                          button: 'Nova conversa',
                        )) {
                          if (!context.mounted) return;
                          await runAction(context, store.newConversation);
                        }
                      },
                icon: Icon(Icons.add_comment_outlined, size: 17),
                label: Text('NOVA CONVERSA'),
              ),
              SizedBox(height: 16),
              Notice(
                'Confira os trechos citados antes de utilizar uma resposta. Documentos recém-enviados podem levar um tempo para aparecer na pesquisa.',
              ),
            ],
          ),
          right: Panel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_outlined,
                        color: Palette.accent,
                        size: 18,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ASSISTENTE DA OBRA',
                          style: mono(color: Palette.text),
                        ),
                      ),
                      StatusPill('IA'),
                    ],
                  ),
                ),
                Divider(),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: 350, maxHeight: 650),
                  child: SingleChildScrollView(
                    reverse: true,
                    padding: EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (conversation.isEmpty)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 65),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.forum_outlined,
                                  size: 34,
                                  color: Palette.muted,
                                ),
                                SizedBox(height: 18),
                                Text(
                                  'A informação já está na obra.\nVamos encontrá-la.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Escolha uma pergunta ou escreva a sua.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Palette.muted),
                                ),
                              ],
                            ),
                          ),
                        for (final m in conversation)
                          Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Eyebrow(
                                  m.user ? 'VOCÊ' : 'ORGANIZAI',
                                  accent: !m.user,
                                ),
                                SizedBox(height: 9),
                                SelectableText(
                                  m.text,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.6,
                                    color: m.user
                                        ? Palette.text
                                        : Palette.muted,
                                  ),
                                ),
                                if (m.noSource) ...[
                                  SizedBox(height: 12),
                                  StatusPill(
                                    'SEM FONTE ENCONTRADA',
                                    color: Palette.warning,
                                  ),
                                ],
                                if (m.citations.isNotEmpty) ...[
                                  SizedBox(height: 16),
                                  Eyebrow('FONTES DA RESPOSTA'),
                                  SizedBox(height: 8),
                                  for (final citation in m.citations)
                                    Padding(
                                      padding: EdgeInsets.only(bottom: 8),
                                      child: CitationCard(citation),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        if (store.busyChat)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Consultando o acervo da obra…',
                                style: mono(size: 11),
                              ),
                              SizedBox(height: 12),
                              LinearProgressIndicator(minHeight: 2),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                Divider(),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: question,
                          enabled: !store.busyChat,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                          decoration: InputDecoration(
                            hintText: 'O que você precisa saber?',
                            counterText: '',
                          ),
                          onSubmitted: (_) => send(),
                        ),
                      ),
                      SizedBox(width: 10),
                      IconButton.filled(
                        tooltip: 'Enviar pergunta',
                        onPressed: store.busyChat ? null : send,
                        style: IconButton.styleFrom(
                          backgroundColor: Palette.accent,
                          foregroundColor: Palette.bg,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(2),
                          ),
                          padding: EdgeInsets.all(17),
                        ),
                        icon: Icon(Icons.arrow_upward, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CitationCard extends StatelessWidget {
  final Citation citation;
  const CitationCard(this.citation, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Palette.bg,
      border: Border(left: BorderSide(color: Palette.accent, width: 2)),
    ),
    padding: EdgeInsets.all(14),
    width: double.infinity,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          citation.title,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        if (citation.page != null) ...[
          SizedBox(height: 6),
          Text('Página ${citation.page}', style: mono(size: 10)),
        ],
        SizedBox(height: 8),
        SelectableText(
          citation.snippet,
          style: TextStyle(color: Palette.muted, height: 1.5, fontSize: 12),
        ),
        // A API retorna chunkId, título, página opcional e snippet. Não há ID/URL do original.
      ],
    ),
  );
}
