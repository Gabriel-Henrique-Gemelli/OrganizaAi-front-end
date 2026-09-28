import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_client.dart';

/// Tokens vivem apenas na memória; nenhuma senha, chave AWS ou client secret é salva.
class AuthSession {
  final String accessToken, refreshToken, subject, organizationId, name;
  final List<String> roles;
  final DateTime expires;
  AuthSession({
    required this.accessToken,
    this.refreshToken = '',
    required this.subject,
    required this.organizationId,
    required this.name,
    required this.roles,
    required this.expires,
  });
}

class AuthChallenge {
  final String name, session, username;
  final List<String> attributes;
  AuthChallenge(this.name, this.session, this.username, this.attributes);
}

class CognitoAuth {
  final String issuer, clientId;
  final Dio http;
  CognitoAuth(this.issuer, this.clientId, {Dio? client})
    : http =
          client ??
          Dio(
            BaseOptions(
              followRedirects: false,
              connectTimeout: Duration(seconds: 15),
              receiveTimeout: Duration(seconds: 30),
            ),
          );

  Uri get endpoint {
    final uri = Uri.tryParse(issuer);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.hasPort ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        !RegExp(r'^cognito-idp\.[a-z0-9-]+\.amazonaws\.com$')
            .hasMatch(uri.host) ||
        !RegExp(r'^/[a-z0-9-]+_[a-zA-Z0-9]+$').hasMatch(uri.path) ||
        clientId.trim().isEmpty) {
      throw ApiFailure(
        'O acesso da organização precisa ser configurado pelo responsável pelo sistema.',
      );
    }
    return Uri(scheme: 'https', host: uri.host, path: '/');
  }

  Future<Map<String, dynamic>> call(
    String action,
    Map<String, dynamic> body,
  ) async {
    final url = endpoint.toString();
    try {
      final r = await http.post(
        url,
        data: body,
        options: Options(
          headers: {
            'Content-Type': 'application/x-amz-json-1.1',
            'X-Amz-Target': 'AWSCognitoIdentityProviderService.$action',
          },
        ),
      );
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      final j = e.response?.data;
      final code = j is Map ? '${j['__type']}'.split('#').last : '';
      throw ApiFailure(switch (code) {
        'NotAuthorizedException' || 'UserNotFoundException' =>
          'Acesso não autorizado. Confira seus dados ou entre novamente.',
        'UserNotConfirmedException' =>
          'Confirme seu cadastro com o administrador da organização.',
        'PasswordResetRequiredException' =>
          'Use “Esqueci minha senha” para definir uma nova senha.',
        'CodeMismatchException' =>
          'Código incorreto. Confira e tente novamente.',
        'ExpiredCodeException' => 'O código expirou. Solicite outro.',
        'InvalidPasswordException' =>
          'A senha não atende à política da organização.',
        'InvalidParameterException' => 'Não foi possível entrar. Confira seus dados ou contate o responsável pelo sistema.',
        'TooManyRequestsException' || 'LimitExceededException' =>
          'Muitas tentativas. Aguarde antes de repetir.',
        _ => 'Não foi possível entrar. Confira sua conexão e tente novamente.',
      }, e.response?.statusCode);
    }
  }

  Future<Object> login(String username, String password) async => _resolve(
    await call('InitiateAuth', {
      'ClientId': clientId,
      'AuthFlow': 'USER_PASSWORD_AUTH',
      'AuthParameters': {'USERNAME': username, 'PASSWORD': password},
    }),
    username,
  );

  Future<Object> respond(
    AuthChallenge c,
    String value,
    Map<String, String> attributes,
  ) async {
    final key = switch (c.name) {
      'NEW_PASSWORD_REQUIRED' => 'NEW_PASSWORD',
      'SMS_MFA' => 'SMS_MFA_CODE',
      'SOFTWARE_TOKEN_MFA' => 'SOFTWARE_TOKEN_MFA_CODE',
      'EMAIL_OTP' => 'EMAIL_OTP_CODE',
      _ => throw ApiFailure(
        'Este desafio de autenticação requer configuração pelo administrador.',
      ),
    };
    return _resolve(
      await call('RespondToAuthChallenge', {
        'ClientId': clientId,
        'ChallengeName': c.name,
        'Session': c.session,
        'ChallengeResponses': {
          'USERNAME': c.username,
          key: value,
          for (final a in attributes.entries)
            'userAttributes.${a.key}': a.value,
        },
      }),
      c.username,
    );
  }

  Future<Object> _resolve(Map<String, dynamic> j, String username) async {
    if (j['AuthenticationResult'] is Map) {
      final tokens = Map<String, dynamic>.from(j['AuthenticationResult']);
      return verify(
        tokens['AccessToken'],
        refreshToken: tokens['RefreshToken'] ?? '',
      );
    }
    final name = j['ChallengeName'];
    if (!{
      'NEW_PASSWORD_REQUIRED',
      'SMS_MFA',
      'SOFTWARE_TOKEN_MFA',
      'EMAIL_OTP',
    }.contains(name)) {
      throw ApiFailure(
        'Esta forma de confirmação precisa ser configurada pelo administrador.',
      );
    }
    final p = Map<String, dynamic>.from(j['ChallengeParameters'] ?? {});
    final attributes = (jsonDecode(p['requiredAttributes'] ?? '[]') as List)
        .map((a) => '$a'.replaceFirst('userAttributes.', ''))
        .toList();
    // A organização é provisionada pelo administrador, nunca atribuída no cadastro do cliente.
    if (attributes.any((a) => a.startsWith('custom:'))) {
      throw ApiFailure(
        'O administrador precisa completar os atributos de organização do usuário.',
      );
    }
    return AuthChallenge(
      name,
      j['Session'],
      p['USER_ID_FOR_SRP'] ?? username,
      attributes,
    );
  }

  Future<AuthSession> verify(
    String accessToken, {
    String refreshToken = '',
  }) async {
    Map<String, dynamic> claims;
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3) throw FormatException();
      claims = Map<String, dynamic>.from(
        jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ),
      );
    } catch (_) {
      throw ApiFailure('Sua sessão é inválida. Entre novamente.');
    }
    final exp = claims['exp'];
    final org = claims['custom:org_id'];
    if (claims['iss'] != issuer ||
        claims['client_id'] != clientId ||
        claims['token_use'] != 'access' ||
        exp is! num ||
        exp * 1000 <= DateTime.now().millisecondsSinceEpoch ||
        org is! String ||
        !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
            .hasMatch(org) ||
        claims['sub'] is! String) {
      throw ApiFailure(
        'Não foi possível confirmar o acesso à organização. Contate o responsável pelo sistema.',
      );
    }
    // Decodificar JWT não autentica: só liberamos o cache após validação real pelo Cognito.
    final user = await call('GetUser', {'AccessToken': accessToken});
    final attrs = {
      for (final a in user['UserAttributes'] as List? ?? [])
        a['Name'] as String: a['Value'] as String,
    };
    if (attrs['sub'] != claims['sub'])
      throw ApiFailure('Identidade retornada pelo Cognito não confere.');
    final groups = claims['cognito:groups'];
    final roles = groups is List
        ? groups.map((g) => '$g'.toUpperCase()).toList()
        : <String>[];
    if (!roles.any(
      {'ADMIN', 'GESTOR', 'REVISOR', 'COLABORADOR', 'AUDITOR'}.contains,
    )) {
      throw ApiFailure(
        'O usuário ainda não pertence a um perfil OrganizAI. Solicite acesso ao administrador.',
      );
    }
    final displayName = [
      claims['name'],
      claims['username'],
      attrs['name'],
      user['Username'],
      claims['sub'],
    ].whereType<String>().firstWhere((v) => v.trim().isNotEmpty);
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      subject: claims['sub'],
      organizationId: org,
      name: displayName,
      roles: roles,
      expires: DateTime.fromMillisecondsSinceEpoch(
        (exp * 1000).toInt(),
        isUtc: true,
      ),
    );
  }

  Future<AuthSession> refresh(AuthSession s) async {
    final j = await call('InitiateAuth', {
      'ClientId': clientId,
      'AuthFlow': 'REFRESH_TOKEN_AUTH',
      'AuthParameters': {'REFRESH_TOKEN': s.refreshToken},
    });
    return verify(
      j['AuthenticationResult']['AccessToken'],
      refreshToken: s.refreshToken,
    );
  }

  Future<void> forgot(String username) async {
    await call('ForgotPassword', {'ClientId': clientId, 'Username': username});
  }

  Future<void> reset(String username, String code, String password) async {
    await call('ConfirmForgotPassword', {
      'ClientId': clientId,
      'Username': username,
      'ConfirmationCode': code,
      'Password': password,
    });
  }

  void close() => http.close(force: true);
}
