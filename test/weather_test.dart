import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/data/app_store.dart';
import 'package:organizai_flutter/data/models.dart';
import 'package:organizai_flutter/features/weather.dart';

import 'store_test.dart' as fixture;
import 'widget_test.dart' show authenticated;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppStore, DiaryEntry)> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel('desktop_drop'), (_) async => null);
    final store = AppStore();
    await store.initialize();
    authenticated(store);
    final entry = DiaryEntry(
      id: 'd1',
      remoteId: 'd1',
      projectId: fixture.projectId,
      author: 'Pessoa',
      role: 'Engenheiro',
      date: DateTime(2026, 1, 1),
      status: 'AGUARDANDO_REVISAO',
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DiaryWeather(store, entry)))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('INFORMAR CLIMA'));
    await tester.pumpAndSettle();
    return (store, entry);
  }

  testWidgets('abrir e cancelar o diálogo de clima não gera exceção', (tester) async {
    final (store, _) = await abrir(tester);
    expect(find.text('Clima observado'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'ensolarado');

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Clima observado'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('valor fora da faixa mostra o motivo e mantém o diálogo aberto', (tester) async {
    final (store, _) = await abrir(tester);
    await tester.enterText(find.byType(TextField).at(2), '150'); // umidade acima de 100

    await tester.tap(find.text('Salvar clima'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Umidade (%): informe um valor entre 0 e 100'), findsOneWidget);
    expect(find.text('Clima observado'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('diálogo sem nenhum campo preenchido pede ao menos um', (tester) async {
    final (store, _) = await abrir(tester);

    await tester.tap(find.text('Salvar clima'));
    await tester.pumpAndSettle();

    expect(find.text('Preencha ao menos um campo.'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
