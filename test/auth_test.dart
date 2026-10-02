import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:organizai_flutter/data/auth.dart';

import 'api_client_test.dart' show FakeAdapter, jsonResponse;

String token({String use = 'access', String client = 'client', int? expiry}) {
  final payload = {
    'iss': 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_POOL',
    'client_id': client,
    'token_use': use,
    'sub': 'usuario',
    'custom:org_id': '00000000-0000-0000-0000-000000000001',
    'username': 'Marina',
    'cognito:groups': ['revisor'],
    'exp':
        expiry ??
        DateTime.now().add(Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  };
  return 'header.${base64Url.encode(utf8.encode(jsonEncode(payload)))}.test-signature';
}

void main() {
  const issuer = 'https://cognito-idp.us-east-1.amazonaws.com/us-east-1_POOL';
  test('Token somente abre sessão após GetUser validar no Cognito', () async {
    final adapter = FakeAdapter(
      (_) async => jsonResponse({
        'Username': 'Marina',
        'UserAttributes': [
          {'Name': 'sub', 'Value': 'usuario'},
        ],
      }),
    );
    final auth = CognitoAuth(
      issuer,
      'client',
      client: Dio()..httpClientAdapter = adapter,
    );
    final access = token();
    final s = await auth.verify(access);
    expect(s.roles, ['REVISOR']);
    expect(s.name, 'Marina');
    expect(
      adapter.requests.single.headers['X-Amz-Target'],
      'AWSCognitoIdentityProviderService.GetUser',
    );
    expect(jsonDecode(adapter.requests.single.data as String), {
      'AccessToken': access,
    });
    auth.close();
  });
  test('ID token, cliente diferente e token expirado são recusados', () async {
    final adapter = FakeAdapter((_) async => jsonResponse({}));
    final auth = CognitoAuth(
      issuer,
      'client',
      client: Dio()..httpClientAdapter = adapter,
    );
    for (final t in [
      token(use: 'id'),
      token(client: 'outro'),
      token(expiry: 1),
    ]) {
      await expectLater(auth.verify(t), throwsException);
    }
    expect(adapter.requests, isEmpty);
    auth.close();
  });
  test('JWT decodificável com GetUser recusado não autentica', () async {
    final adapter = FakeAdapter(
      (_) async => jsonResponse({'__type': 'NotAuthorizedException'}, 400),
    );
    final auth = CognitoAuth(
      issuer,
      'client',
      client: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(auth.verify(token()), throwsException);
    auth.close();
  });
  test('Senha não é enviada para domínio Cognito arbitrário', () async {
    final adapter = FakeAdapter((_) async => jsonResponse({}));
    final auth = CognitoAuth(
      'https://example.com/pool',
      'client',
      client: Dio()..httpClientAdapter = adapter,
    );
    await expectLater(auth.login('user', 'test-password'), throwsException);
    expect(adapter.requests, isEmpty);
    auth.close();
  });
  test('Login usa SRP: a senha nunca é enviada ao Cognito', () async {
    const password = 'senha-que-nao-pode-vazar';
    final access = token();
    final adapter = FakeAdapter((r) async {
      final target = r.headers['X-Amz-Target'] as String;
      if (target.endsWith('.InitiateAuth')) {
        return jsonResponse({
          'ChallengeName': 'PASSWORD_VERIFIER',
          'ChallengeParameters': {
            'USER_ID_FOR_SRP': 'usuario-teste',
            'SALT': 'abcdef0123456789abcdef0123456789',
            'SRP_B': '1234567890abcdef1234567890abcdef1234567890abcdef',
            'SECRET_BLOCK': base64.encode(utf8.encode('bloco-secreto')),
          },
        });
      }
      if (target.endsWith('.RespondToAuthChallenge')) {
        return jsonResponse({
          'AuthenticationResult': {'AccessToken': access, 'RefreshToken': 'r'},
        });
      }
      return jsonResponse({
        'Username': 'Marina',
        'UserAttributes': [
          {'Name': 'sub', 'Value': 'usuario'},
        ],
      });
    });
    final auth = CognitoAuth(
      issuer,
      'client',
      client: Dio()..httpClientAdapter = adapter,
    );
    final result = await auth.login('teste@organizai.dev', password);
    expect(result, isA<AuthSession>());
    expect(adapter.requests.map((r) => r.headers['X-Amz-Target']), [
      'AWSCognitoIdentityProviderService.InitiateAuth',
      'AWSCognitoIdentityProviderService.RespondToAuthChallenge',
      'AWSCognitoIdentityProviderService.GetUser',
    ]);
    final first = jsonDecode(adapter.requests[0].data as String) as Map;
    expect(first['AuthFlow'], 'USER_SRP_AUTH');
    expect((first['AuthParameters'] as Map).containsKey('SRP_A'), true);
    final second = jsonDecode(adapter.requests[1].data as String) as Map;
    expect(second['ChallengeName'], 'PASSWORD_VERIFIER');
    expect((second['ChallengeResponses'] as Map)['USERNAME'], 'usuario-teste');
    for (final r in adapter.requests) {
      expect('${r.data}'.contains(password), false);
    }
    auth.close();
  });
  test('SRP pré-calculado vale para um único login e o expoente é novo a cada tentativa', () async {
    final access = token();
    final adapter = FakeAdapter((r) async {
      final target = r.headers['X-Amz-Target'] as String;
      if (target.endsWith('.InitiateAuth')) {
        return jsonResponse({
          'ChallengeName': 'PASSWORD_VERIFIER',
          'ChallengeParameters': {
            'USER_ID_FOR_SRP': 'usuario-teste',
            'SALT': 'abcdef0123456789abcdef0123456789',
            'SRP_B': '1234567890abcdef1234567890abcdef1234567890abcdef',
            'SECRET_BLOCK': base64.encode(utf8.encode('bloco-secreto')),
          },
        });
      }
      if (target.endsWith('.RespondToAuthChallenge')) {
        return jsonResponse({
          'AuthenticationResult': {'AccessToken': access},
        });
      }
      return jsonResponse({
        'Username': 'Marina',
        'UserAttributes': [
          {'Name': 'sub', 'Value': 'usuario'},
        ],
      });
    });
    final auth = CognitoAuth(
      issuer,
      'client',
      client: Dio()..httpClientAdapter = adapter,
    );
    auth.prepare();
    await auth.login('teste@organizai.dev', 'x');
    await auth.login('teste@organizai.dev', 'x');
    final a = [
      for (final r in adapter.requests)
        if ('${r.headers['X-Amz-Target']}'.endsWith('.InitiateAuth'))
          ((jsonDecode(r.data as String) as Map)['AuthParameters']
              as Map)['SRP_A'],
    ];
    expect(a.length, 2);
    expect(a[0], isNot(a[1]));
    auth.close();
  });
  test(
    'Erro do Cognito em texto é interpretado, não vira falha de conexão',
    () async {
      final adapter = FakeAdapter(
        (_) async => jsonResponse('{"__type":"NotAuthorizedException"}', 400),
      );
      final auth = CognitoAuth(
        issuer,
        'client',
        client: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        auth.login('a@b.c', 'x'),
        throwsA(predicate((e) => '$e'.contains('Acesso não autorizado'))),
      );
      auth.close();
    },
  );
  test(
    'Verificação de e-mail pede e confirma o código com o access token',
    () async {
      final adapter = FakeAdapter((_) async => jsonResponse({}));
      final auth = CognitoAuth(
        issuer,
        'client',
        client: Dio()..httpClientAdapter = adapter,
      );
      await auth.sendEmailCode('tok');
      await auth.verifyEmail('tok', '123456');
      expect(adapter.requests.map((r) => r.headers['X-Amz-Target']), [
        'AWSCognitoIdentityProviderService.GetUserAttributeVerificationCode',
        'AWSCognitoIdentityProviderService.VerifyUserAttribute',
      ]);
      expect(jsonDecode(adapter.requests[0].data as String), {
        'AccessToken': 'tok',
        'AttributeName': 'email',
      });
      expect(jsonDecode(adapter.requests[1].data as String), {
        'AccessToken': 'tok',
        'AttributeName': 'email',
        'Code': '123456',
      });
      auth.close();
    },
  );
}
