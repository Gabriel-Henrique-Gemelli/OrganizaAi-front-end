import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/core/error_handling.dart';
import 'package:organizai_flutter/data/api_client.dart';

class _Boom extends StatelessWidget {
  const _Boom();
  @override
  Widget build(BuildContext context) => throw StateError('quebrou no build');
}

void main() {
  late FlutterExceptionHandler? originalOnError;
  late ErrorWidgetBuilder originalBuilder;
  late bool Function(Object, StackTrace)? originalAsync;

  setUp(() {
    originalOnError = FlutterError.onError;
    originalBuilder = ErrorWidget.builder;
    originalAsync = PlatformDispatcher.instance.onError;
    AppErrors.recent.clear();
    AppErrors.recover = null;
    AppErrors.listener = null;
  });
  tearDown(() {
    FlutterError.onError = originalOnError;
    ErrorWidget.builder = originalBuilder;
    PlatformDispatcher.instance.onError = originalAsync;
  });

  group('friendlyMessage', () {
    test('ApiFailure mostra a mensagem que o app escreveu', () {
      expect(
        friendlyMessage(const ApiFailure('Sua sessão expirou.')),
        'Sua sessão expirou.',
      );
    });

    test(
      'Dio: timeout, sem conexão e cancelamento viram frases em português',
      () {
        DioException de(DioExceptionType t) => DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: t,
        );
        expect(
          friendlyMessage(de(DioExceptionType.receiveTimeout)),
          contains('demorou'),
        );
        expect(
          friendlyMessage(de(DioExceptionType.connectionError)),
          contains('Sem conexão'),
        );
        expect(
          friendlyMessage(de(DioExceptionType.cancel)),
          'Operação cancelada.',
        );
      },
    );

    test('TimeoutException vira frase em português', () {
      expect(friendlyMessage(TimeoutException('x')), contains('demorou'));
    });

    test(
      'bug (TypeError, StateError) não vaza texto técnico e fica registrado',
      () {
        final msg = friendlyMessage(
          StateError('segredo interno 123'),
          StackTrace.current,
        );
        expect(msg, isNot(contains('segredo')));
        expect(msg, contains('Algo deu errado'));
        expect(AppErrors.recent.single.origin, 'inesperado');
      },
    );
  });

  group('AppErrors', () {
    test('guarda no máximo 50 erros e avisa o listener', () {
      var avisos = 0;
      AppErrors.listener = (_) => avisos++;
      for (var i = 0; i < 60; i++) {
        AppErrors.report('erro $i');
      }
      expect(AppErrors.recent, hasLength(50));
      expect(AppErrors.recent.first.error, 'erro 10');
      expect(avisos, 60);
    });

    test('listener que lança não derruba o registro', () {
      AppErrors.listener = (_) => throw StateError('listener quebrado');
      expect(() => AppErrors.report('x'), returnsNormally);
    });

    test('erro assíncrono sem dono é registrado e engolido', () {
      AppErrors.install();
      final handled = PlatformDispatcher.instance.onError!(
        StateError('async'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(AppErrors.recent.last.origin, 'async');
    });
  });

  testWidgets(
    'widget que quebra no build vira aviso compacto e o resto da tela segue',
    (tester) async {
      // O handler anterior do framework de teste falharia o teste a cada erro reportado.
      FlutterError.onError = (_) {};
      AppErrors.install();
      var recuperou = false;
      AppErrors.recover = () => recuperou = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('parte saudável'),
                const SizedBox(height: 300, width: 600, child: _Boom()),
                TextButton(
                  onPressed: () {},
                  child: const Text('botão que continua vivo'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('Não foi possível exibir esta parte da tela.'),
        findsOneWidget,
      );
      expect(find.text('parte saudável'), findsOneWidget);
      expect(find.text('botão que continua vivo'), findsOneWidget);
      expect(AppErrors.recent.any((r) => r.origin == 'flutter'), isTrue);
      await tester.tap(find.text('VOLTAR AO INÍCIO'));
      expect(recuperou, isTrue);
      tester.takeException();
    },
  );
}
