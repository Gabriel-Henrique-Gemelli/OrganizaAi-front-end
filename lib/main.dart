import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import 'core/config.dart';
import 'core/error_handling.dart';
import 'data/app_store.dart';
import 'data/models.dart';
import 'features/account.dart';
import 'features/archive.dart';
import 'features/assistant.dart';
import 'features/diary.dart';
import 'features/projects.dart';
import 'features/review.dart';
import 'features/today.dart';
import 'features/upload.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrors.install();
  try {
    await Hive.initFlutter('organizai');
    final box = await Hive.openBox('workspace_v1');
    final store = AppStore(box: box);
    await store.initialize();
    AppErrors.recover = () => store.navigate(Section.today);
    runApp(OrganizAiApp(store: store));
  } catch (e, s) {
    AppErrors.report(e, s, 'inicializacao');
    runApp(
      MaterialApp(
        theme: appTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Não foi possível abrir os dados deste dispositivo. Verifique o espaço disponível e reinicie o aplicativo. Nenhum dado foi apagado.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OrganizAiApp extends StatelessWidget {
  final AppStore store;
  const OrganizAiApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => MaterialApp(
      title: AppConfig.brand,
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      locale: Locale('pt', 'BR'),
      supportedLocales: [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: store.started && store.session != null
          ? Workspace(store)
          : WelcomePage(store),
    ),
  );
}

class Brand extends StatelessWidget {
  final double size;
  const Brand({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: 'ORGANIZ'),
        TextSpan(
          text: 'AI',
          style: TextStyle(color: Palette.accent),
        ),
      ],
    ),
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -.8,
    ),
    semanticsLabel: AppConfig.brand,
  );
}

class WelcomePage extends StatelessWidget {
  final AppStore store;
  const WelcomePage(this.store, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(26),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 1120),
            child: AdaptiveColumns(
              breakpoint: 850,
              left: Padding(
                padding: EdgeInsets.only(right: 28, top: 30, bottom: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Brand(size: 30),
                    SizedBox(height: 65),
                    Eyebrow('INTELIGÊNCIA DOCUMENTAL PARA OBRAS', accent: true),
                    SizedBox(height: 20),
                    Text(
                      'MENOS PROCURA.\nMAIS OBRA.',
                      style: TextStyle(
                        fontSize: 58,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                    SizedBox(height: 26),
                    Text(
                      'Documentos, leitura inteligente e diário de campo.\nDo celular ao escritório, a informação acompanha você.',
                      style: TextStyle(
                        fontSize: 17,
                        color: Palette.muted,
                        height: 1.6,
                      ),
                    ),
                    SizedBox(height: 40),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        StatusPill('DOCUMENTOS'),
                        StatusPill('DIÁRIO POR VOZ'),
                        StatusPill('ASSISTENTE IA'),
                      ],
                    ),
                  ],
                ),
              ),
              right: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Eyebrow('SEU ESPAÇO DE TRABALHO'),
                    SizedBox(height: 18),
                    Text(
                      'Vamos começar.',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 24),
                    ConnectionForm(store),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class Workspace extends StatefulWidget {
  final AppStore store;
  const Workspace(this.store, {super.key});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  final scaffold = GlobalKey<ScaffoldState>();
  void go(Section section) {
    if (widget.store.recordingActive) {
      toast(context, 'Encerre a gravação antes de mudar de tela.');
      return;
    }
    widget.store.navigate(section);
    if (scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1050;
        return PopScope(
          canPop: !s.recordingActive,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) toast(context, 'Encerre a gravação antes de sair.');
          },
          child: Scaffold(
            key: scaffold,
            drawer: wide
                ? null
                : Drawer(
                    width: 260,
                    backgroundColor: Palette.bg,
                    child: _sidebar(),
                  ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    height: 68,
                    selectedIndex: switch (s.section) {
                      Section.today => 0,
                      Section.archive => 1,
                      Section.upload => 2,
                      Section.diary => 3,
                      _ => 4,
                    },
                    onDestinationSelected: (i) {
                      if (i == 4) {
                        scaffold.currentState?.openDrawer();
                      } else {
                        go(
                          [
                            Section.today,
                            Section.archive,
                            Section.upload,
                            Section.diary,
                          ][i],
                        );
                      }
                    },
                    destinations: [
                      NavigationDestination(
                        icon: Icon(Icons.grid_view_outlined, size: 20),
                        label: 'Hoje',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.folder_open_outlined, size: 20),
                        label: 'Acervo',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.add_box_outlined, size: 21),
                        label: 'Enviar',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.mic_none, size: 21),
                        label: 'Diário',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.menu, size: 21),
                        label: 'Mais',
                      ),
                    ],
                  ),
            body: SafeArea(
              child: Row(
                children: [
                  if (wide) SizedBox(width: 228, child: _sidebar()),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 62,
                          padding: EdgeInsets.symmetric(
                            horizontal: wide ? 32 : 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Palette.border),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (!wide)
                                IconButton(
                                  tooltip: 'Abrir menu',
                                  onPressed: () =>
                                      scaffold.currentState?.openDrawer(),
                                  icon: Icon(Icons.menu, size: 20),
                                ),
                              Expanded(
                                child: Text(
                                  s.project == null
                                      ? 'SELECIONE UMA OBRA'
                                      : '${s.project!.name.toUpperCase()}${wide ? ' · ${s.project!.code}' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                  style: mono(size: wide ? 11 : 10),
                                ),
                              ),
                              if (wide) ...[
                                Text(
                                  DateFormat(
                                    'EEE dd MMM',
                                    'pt_BR',
                                  ).format(DateTime.now()).toUpperCase(),
                                  style: mono(size: 10),
                                ),
                                SizedBox(width: 20),
                              ],
                              IconButton(
                                tooltip: 'Atualizar dados',
                                onPressed: s.working
                                    ? null
                                    : () => runAction(context, s.synchronize),
                                icon: Icon(
                                  Icons.sync,
                                  color: s.syncError == null
                                      ? Palette.muted
                                      : Palette.warning,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            key: PageStorageKey(
                              '${s.scope}-${s.section.name}-${s.selectedProjectId}',
                            ),
                            padding: EdgeInsets.fromLTRB(
                              wide ? 32 : 18,
                              wide ? 34 : 24,
                              wide ? 32 : 18,
                              40,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 1440),
                                child: _page(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _page() => switch (widget.store.section) {
    Section.today => TodayPage(widget.store),
    Section.upload =>
      widget.store.canUpload ? UploadPage(widget.store) : accessDenied(),
    Section.review => ReviewPage(widget.store),
    Section.archive => ArchivePage(widget.store),
    Section.diary =>
      widget.store.canDiary ? DiaryPage(widget.store) : accessDenied(),
    Section.assistant => AssistantPage(widget.store),
    Section.account => AccountPage(widget.store),
  };
  Widget _sidebar() {
    final s = widget.store;
    return Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: Palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 24), child: Brand()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Panel(
              padding: EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow('OBRA ATIVA'),
                  SizedBox(height: 6),
                  DropdownButton<String>(
                    value: s.projects.any((p) => p.id == s.selectedProjectId)
                        ? s.selectedProjectId
                        : null,
                    isExpanded: true,
                    underline: SizedBox.shrink(),
                    hint: Text('Selecione', style: TextStyle(fontSize: 14)),
                    items: s.projects
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              p.name.toUpperCase(),
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: s.recordingActive
                        ? null
                        : (id) {
                            if (id != null)
                              runAction(context, () => s.selectProject(id));
                          },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.project?.code ?? 'SEM OBRA',
                          style: mono(size: 9),
                        ),
                      ),
                      if (s.canManageProjects)
                        InkWell(
                          onTap: s.working
                              ? null
                              : () => projectDialog(context, s),
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: Text(
                              '+ nova',
                              style: mono(size: 10, color: Palette.accent),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final section in Section.values)
                  Material(
                    color: s.section == section
                        ? Palette.raised
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => go(section),
                      child: Container(
                        height: 49,
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: s.section == section
                                  ? Palette.accent
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 17),
                        child: Row(
                          children: [
                            _navIcon(section, s.section == section),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                section.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: s.section == section
                                      ? Palette.text
                                      : Palette.muted,
                                ),
                              ),
                            ),
                            if (section == Section.review &&
                                s.reviews.isNotEmpty)
                              StatusPill(
                                '${s.reviews.length}',
                                color: Palette.accent,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(),
                SizedBox(height: 16),
                Eyebrow('ACERVO DA ORGANIZAÇÃO'),
                SizedBox(height: 10),
                Text(
                  '${s.projectDocs.length} documentos · ${s.projectDiaries.length} diários',
                  style: mono(size: 9),
                ),
                SizedBox(height: 10),
                Text(
                  'Da obra ao escritório.',
                  style: TextStyle(color: Palette.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navIcon(Section s, bool selected) {
    if (s == Section.diary)
      return Icon(
        Icons.mic_none,
        size: 19,
        color: selected ? Palette.text : Palette.muted,
      );
    final name = {
      Section.today: 'hoje',
      Section.upload: 'enviar',
      Section.review: 'revisar',
      Section.archive: 'acervo',
      Section.assistant: 'perguntar',
      Section.account: 'conta',
    }[s]!;
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      width: 18,
      height: 18,
      colorFilter: ColorFilter.mode(
        selected ? Palette.text : Palette.muted,
        BlendMode.srcIn,
      ),
    );
  }
}

Widget accessDenied() => EmptyState(
  title: 'Acesso restrito ao seu perfil.',
  description: 'Consulte o administrador para solicitar acesso a este módulo.',
  icon: Icons.lock_outline,
);
