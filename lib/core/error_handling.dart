import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/api_client.dart';

/// Um erro que o app capturou, para diagnóstico (nunca vai para a tela do usuário).
class AppErrorRecord {
  final DateTime when;
  final String origin;
  final Object error;
  final StackTrace? stack;
  AppErrorRecord(this.origin, this.error, this.stack) : when = DateTime.now();
  @override
  String toString() => '[$origin] $error';
}

/// Registro central de erros e instalação dos handlers globais.
///
/// Sem isto, uma exceção dentro de um `build()` vira a tela vermelha do modo debug, que ocupa a janela
/// inteira, e uma exceção em código assíncrono some sem rastro. Aqui os erros são registrados e a parte
/// quebrada da tela é trocada por um aviso compacto, para o resto do app continuar funcionando.
class AppErrors {
  static const _limit = 50;
  static final List<AppErrorRecord> recent = [];

  /// Volta o app a um estado seguro (ex.: tela inicial). Definido por quem monta o app.
  static VoidCallback? recover;

  /// Chamado a cada erro registrado (ponto para plugar um serviço de monitoramento).
  static void Function(AppErrorRecord record)? listener;

  static void report(Object error, [StackTrace? stack, String origin = 'app']) {
    final record = AppErrorRecord(origin, error, stack);
    recent.add(record);
    if (recent.length > _limit) recent.removeAt(0);
    debugPrint('erro_capturado $record');
    if (kDebugMode && stack != null) debugPrint('$stack');
    try {
      listener?.call(record);
    } catch (e) {
      debugPrint('erro_no_listener $e');
    }
  }

  /// Instala os handlers globais. Chamar uma vez, no `main`, antes do `runApp`.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      report(details.exception, details.stack, 'flutter');
      // Mantém o comportamento padrão (log no console em debug) sem derrubar o app.
      if (previous != null) previous(details);
    };
    // Erros assíncronos que ninguém tratou: registra e segue, em vez de matar o app.
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, 'async');
      return true;
    };
    ErrorWidget.builder = (details) => CompactErrorWidget(details);
  }
}

/// Aviso que substitui só o widget que quebrou, no lugar da tela vermelha cheia.
class CompactErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const CompactErrorWidget(this.details, {super.key});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 160),
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF2A1A1A),
            border: Border.all(color: const Color(0xFF8A3B3B)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Não foi possível exibir esta parte da tela.',
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                kDebugMode
                    ? details.exceptionAsString().split('\n').first
                    : 'O restante do aplicativo continua funcionando.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFC9C9C9),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  decoration: TextDecoration.none,
                ),
              ),
              if (AppErrors.recover != null) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () {
                    try {
                      AppErrors.recover?.call();
                    } catch (e, s) {
                      AppErrors.report(e, s, 'recover');
                    }
                  },
                  child: const Text(
                    'VOLTAR AO INÍCIO',
                    style: TextStyle(
                      color: Color(0xFFFF5A1F),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Mensagem para o usuário a partir de qualquer erro. Erro de programação (bug) nunca vaza o texto técnico:
/// vira uma frase genérica e fica registrado em [AppErrors].
String friendlyMessage(Object error, [StackTrace? stack]) {
  if (error is ApiFailure) return error.message;
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'O servidor demorou para responder. Tente novamente em instantes.',
      DioExceptionType.connectionError =>
        'Sem conexão com o servidor. Confira sua internet.',
      DioExceptionType.cancel => 'Operação cancelada.',
      _ => 'Não foi possível acessar o serviço. Tente novamente.',
    };
  }
  if (error is TimeoutException) {
    return 'A operação demorou demais. Tente novamente.';
  }
  AppErrors.report(error, stack, 'inesperado');
  return 'Algo deu errado. Tente novamente; se continuar, avise o suporte.';
}
