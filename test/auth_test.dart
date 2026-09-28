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
    expect(adapter.requests.single.data, {'AccessToken': access});
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
}
