import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/data/api_client.dart';
import 'package:organizai_flutter/data/app_store.dart';
import 'package:organizai_flutter/data/auth.dart';
import 'package:organizai_flutter/features/account.dart';

import 'api_client_test.dart' show FakeAdapter, jsonResponse;
import 'store_test.dart' as fixture;

const issuer = 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_POOL';

String accessToken({bool comOrganizacao = false}) {
  final payload = {
    'iss': issuer,
    'client_id': 'client',
    'token_use': 'access',
    'sub': 'user',
    'username': 'u-1',
    if (comOrganizacao) 'custom:org_id': fixture.org,
    if (comOrganizacao) 'cognito:groups': ['gestor'],
    'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  };
  return 'header.${base64Url.encode(utf8.encode(jsonEncode(payload)))}.assinatura';
}

/// Cognito de mentira: entra por SRP com um token SEM organização e responde ao resto do fluxo de cadastro.
class FakeCognito {
  final bool emailVerificado;
  final List<String> chamadas = [];
  FakeCognito({required this.emailVerificado});

  Future<ResponseBody> call(RequestOptions r) async {
    final alvo = (r.headers['X-Amz-Target'] as String).split('.').last;
    final corpo = jsonDecode(r.data as String) as Map;
    chamadas.add(alvo);
    switch (alvo) {
      case 'InitiateAuth':
        if (corpo['AuthFlow'] == 'REFRESH_TOKEN_AUTH') {
          return jsonResponse({
            'AuthenticationResult': {'AccessToken': accessToken(comOrganizacao: true)},
          });
        }
        return jsonResponse({
          'ChallengeName': 'PASSWORD_VERIFIER',
          'ChallengeParameters': {
            'USER_ID_FOR_SRP': 'u-1',
            'SALT': 'abcdef0123456789abcdef0123456789',
            'SRP_B': '1234567890abcdef1234567890abcdef1234567890abcdef',
            'SECRET_BLOCK': base64.encode(utf8.encode('bloco')),
          },
        });
      case 'RespondToAuthChallenge':
        return jsonResponse({
          'AuthenticationResult': {'AccessToken': accessToken(), 'RefreshToken': 'refresh'},
        });
      case 'GetUser':
        return jsonResponse({
          'Username': 'u-1',
          'UserAttributes': [
            {'Name': 'sub', 'Value': 'user'},
            {'Name': 'email_verified', 'Value': emailVerificado ? 'true' : 'false'},
          ],
        });
      default: // GetUserAttributeVerificationCode, VerifyUserAttribute
        return jsonResponse({});
    }
  }

  int quantas(String alvo) => chamadas.where((c) => c == alvo).length;
}

void main() {
  late AppStore store;

  setUp(() {
    store = fixture.harness(fixture.fake((r) async => jsonResponse({}, 500)));
  });
  tearDown(() => store.dispose());

  Future<void> abrir(WidgetTester tester, FakeCognito cognito, {ApiClient Function(String, {String token})? api}) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = CognitoAuth(issuer, 'client', client: Dio()..httpClientAdapter = FakeAdapter(cognito.call));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConnectionForm(store, cognitoClient: auth, apiBuilder: api),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> entrar(WidgetTester tester) async {
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), 'maria@exemplo.com');
    await tester.enterText(campos.at(1), 'Senha#Forte1');
    await tester.tap(find.text('ENTRAR'));
    await tester.pumpAndSettle();
  }

  testWidgets('login de conta sem organização e com e-mail já verificado pede só a empresa', (tester) async {
    final cognito = FakeCognito(emailVerificado: true);
    await abrir(tester, cognito);

    await entrar(tester);

    expect(find.text('Conclua seu cadastro'), findsOneWidget);
    expect(find.text('EMPRESA'), findsOneWidget);
    expect(find.text('CÓDIGO DE VERIFICAÇÃO'), findsNothing);
    expect(find.text('Reenviar código'), findsNothing);
    expect(cognito.quantas('GetUserAttributeVerificationCode'), 0);
  });

  testWidgets('login de conta sem organização e com e-mail não verificado envia o código', (tester) async {
    final cognito = FakeCognito(emailVerificado: false);
    await abrir(tester, cognito);

    await entrar(tester);

    expect(find.text('Confirme seu e-mail'), findsOneWidget);
    expect(find.text('CÓDIGO DE VERIFICAÇÃO'), findsOneWidget);
    expect(find.text('Reenviar código'), findsOneWidget);
    expect(cognito.quantas('GetUserAttributeVerificationCode'), 1);
  });

  testWidgets('falha ao criar a organização e nova tentativa não confirmam o código de novo', (tester) async {
    final cognito = FakeCognito(emailVerificado: false);
    var tentativasDeAtivar = 0;
    final apiAdapter = FakeAdapter((r) async {
      if (r.path == '/api/conta/ativar') {
        tentativasDeAtivar++;
        return tentativasDeAtivar == 1
            ? jsonResponse({}, 503)
            : jsonResponse({'organizationId': fixture.org});
      }
      return jsonResponse({}, 500);
    });
    await abrir(
      tester,
      cognito,
      api: (url, {String token = ''}) => ApiClient(
        url,
        token: token,
        client: Dio(BaseOptions(baseUrl: url))..httpClientAdapter = apiAdapter,
      ),
    );
    await entrar(tester);
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), 'Construtora Teste');
    await tester.enterText(campos.at(1), '123456');

    await tester.tap(find.text('CONFIRMAR E ENTRAR'));
    await tester.pumpAndSettle();
    expect(find.textContaining('indisponível'), findsOneWidget);
    expect(cognito.quantas('VerifyUserAttribute'), 1);

    await tester.tap(find.text('CONFIRMAR E ENTRAR'));
    await tester.pumpAndSettle();

    expect(tentativasDeAtivar, 2);
    // O código já tinha sido confirmado: a segunda tentativa não o reenvia ao Cognito (que o recusaria).
    expect(cognito.quantas('VerifyUserAttribute'), 1);
    // A segunda tentativa conectou de verdade: encerra a sessão para cancelar o timer de sincronização.
    expect(store.started, true);
    store.signOut();
  });

  testWidgets('Cancelar volta ao login e zera o estado do cadastro', (tester) async {
    final cognito = FakeCognito(emailVerificado: true);
    await abrir(tester, cognito);
    await entrar(tester);
    expect(find.text('Conclua seu cadastro'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Conclua seu cadastro'), findsNothing);
    expect(find.text('ENTRAR'), findsOneWidget);
  });
}
