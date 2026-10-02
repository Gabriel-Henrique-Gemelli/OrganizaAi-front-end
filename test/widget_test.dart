import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/data/app_store.dart';
import 'package:organizai_flutter/data/models.dart';
import 'package:organizai_flutter/main.dart';

import 'store_test.dart' as fixture;

void authenticated(AppStore store) {
  store.session = fixture.session();
  store.roles = ['GESTOR'];
  store.userName = 'Pessoa';
  store.company = 'Empresa';
  store.started = true;
  store.projects = [Project.fromJson(fixture.project())];
  store.selectedProjectId = fixture.projectId;
  store.documents = [DocumentRecord.fromJson(fixture.doc())];
  store.diaries = [
    DiaryEntry(
      id: 'entry',
      remoteId: 'entry',
      projectId: fixture.projectId,
      author: 'Pessoa',
      role: 'Engenheiro',
      date: DateTime(2026, 1, 1),
      status: 'AGUARDANDO_REVISAO',
      raw: 'Texto para revisão',
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannel('desktop_drop'),
          (_) async => null,
        );
  });
  testWidgets('Login não pede configuração técnica nem oferece demonstração', (
    tester,
  ) async {
    final store = AppStore();
    await store.initialize();
    await tester.pumpWidget(OrganizAiApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('USUÁRIO OU E-MAIL'), findsOneWidget);
    expect(find.text('SENHA'), findsOneWidget);
    for (final text in [
      'Demonstração',
      'Endereço da API',
      'App Client ID público',
      'Access token Cognito',
    ]) {
      expect(find.text(text), findsNothing);
    }
    await tester.pumpWidget(SizedBox.shrink());
    store.dispose();
  });
  testWidgets('Login oferece criar conta e voltar para entrar', (tester) async {
    tester.view.physicalSize = Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore();
    await store.initialize();
    await tester.pumpWidget(OrganizAiApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Não tenho conta. Criar conta'));
    await tester.pumpAndSettle();
    for (final label in [
      'SEU NOME',
      'EMPRESA',
      'E-MAIL',
      'SENHA',
      'CONFIRMAR SENHA',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('CRIAR CONTA'));
    await tester.pumpAndSettle();
    expect(find.text('Informe seu nome.'), findsOneWidget);
    await tester.tap(find.text('Já tenho conta. Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('USUÁRIO OU E-MAIL'), findsOneWidget);
    await tester.pumpWidget(SizedBox.shrink());
    store.dispose();
  });
  for (final size in [Size(390, 844), Size(800, 1100), Size(1440, 1000)]) {
    testWidgets('Sete telas adaptadas a ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore();
      await store.initialize();
      authenticated(store);
      await tester.pumpWidget(OrganizAiApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('DEMONSTRAÇÃO'), findsNothing);
      for (final section in Section.values) {
        store.navigate(section);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow ou erro em ${section.name} / ${size.width}',
        );
      }
      await tester.pumpWidget(SizedBox.shrink());
      store.dispose();
    });
  }
  testWidgets('Mobile tem menu inferior e desktop navegação lateral', (
    tester,
  ) async {
    final store = AppStore();
    await store.initialize();
    authenticated(store);
    tester.view.physicalSize = Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OrganizAiApp(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    tester.view.physicalSize = Size(1440, 1000);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpWidget(SizedBox.shrink());
    store.dispose();
  });
}
