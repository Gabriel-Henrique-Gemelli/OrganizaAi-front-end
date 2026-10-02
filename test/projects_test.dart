import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/data/app_store.dart';
import 'package:organizai_flutter/features/projects.dart';

import 'widget_test.dart' show authenticated;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Datas no formato brasileiro', () {
    test('ISO da API vira dd/mm/aaaa na tela e volta igual', () {
      expect(isoToBrDate('2026-10-02'), '02/10/2026');
      expect(brDateToIso('02/10/2026'), '2026-10-02');
      expect(brDateToIso(isoToBrDate('2026-01-09')), '2026-01-09');
    });

    test('vazio ou inválido vira vazio', () {
      expect(isoToBrDate(''), '');
      expect(isoToBrDate('lixo'), '');
      expect(brDateToIso(''), '');
      expect(brDateToIso('2026-10-02'), '');
    });

    test('recusa dia ou mês que não existem', () {
      expect(parseBrDate('31/02/2026'), isNull);
      expect(parseBrDate('00/10/2026'), isNull);
      expect(parseBrDate('10/13/2026'), isNull);
      expect(parseBrDate('29/02/2024'), DateTime(2024, 2, 29));
    });
  });

  group('Diálogo de obra', () {
    Future<AppStore> abrir(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannel('desktop_drop'),
            (_) async => null,
          );
      final store = AppStore();
      await store.initialize();
      authenticated(store);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('pt', 'BR'),
          supportedLocales: const [Locale('pt', 'BR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => projectDialog(context, store),
                child: const Text('ABRIR'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ABRIR'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets(
      'fecha sem erro: os controllers só são descartados depois da saída',
      (tester) async {
        final store = await abrir(tester);
        await tester.enterText(find.byType(TextFormField).first, 'Obra Centro');
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Adicionar obra'), findsNothing);
        store.dispose();
      },
    );

    testWidgets('data escolhida aparece como dd/mm/aaaa', (tester) async {
      final store = await abrir(tester);
      await tester.tap(find.text('Mais detalhes (opcional)'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('INÍCIO PREVISTO'));
      await tester.tap(find.byIcon(Icons.calendar_month).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final hoje = DateTime.now();
      expect(find.text(formatBrDate(hoje)), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d{4}-\d{2}-\d{2}$')), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      store.dispose();
    });
  });
}
