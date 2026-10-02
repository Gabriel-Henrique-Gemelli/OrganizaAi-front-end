import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'srp.dart';

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

/// Tokens de uma conta recém-criada, ainda sem organização (que só existe depois do código do e-mail).
class PendingTokens {
  final String accessToken, refreshToken;
  PendingTokens(this.accessToken, this.refreshToken);
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
      // O Dio só serializa Map quando o content-type é application/json; o Cognito usa x-amz-json-1.1.
      final r = await http.post(
        url,
        data: jsonEncode(body),
        options: Options(
          headers: {
            'Content-Type': 'application/x-amz-json-1.1',
            'X-Amz-Target': 'AWSCognitoIdentityProviderService.$action',
          },
        ),
      );
      final decoded = r.data is String ? jsonDecode(r.data as String) : r.data;
      return Map<String, dynamic>.from(decoded as Map);
    } on DioException catch (e) {
      var j = e.response?.data;
      if (j is String) {
        try {
          j = jsonDecode(j);
        } catch (_) {}
      }
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
        'AliasExistsException' => 'Este e-mail já pertence a outra conta.',
        'InvalidParameterException' => 'Não foi possível entrar. Confira seus dados ou contate o responsável pelo sistema.',
        'TooManyRequestsException' || 'LimitExceededException' =>
          'Muitas tentativas. Aguarde antes de repetir.',
        _ => 'Não foi possível entrar. Confira sua conexão e tente novamente.',
      }, e.response?.statusCode);
    }
  }

  CognitoSrp? _prepared;

  /// Adianta o cálculo caro de A (g^a mod N) enquanto o usuário ainda digita. Não envia nada e
  /// não guarda segredo além do `a` efêmero, descartado no primeiro login.
  void prepare() {
    if (_prepared != null || clientId.trim().isEmpty) return;
    final srp = CognitoSrp(issuer.split('_').last);
    srp.publicA;
    _prepared = srp;
  }

  /// Entra por SRP: o Cognito nunca recebe a senha, só a prova calculada aqui.
  Future<Object> login(
    String username,
    String password, {
    bool pending = false,
  }) async {
    endpoint; // recusa emissor inválido antes de qualquer envio
    // `a` vale para uma única tentativa: o par (a, A) pré-calculado nunca é reaproveitado.
    final srp = _prepared ?? CognitoSrp(issuer.split('_').last);
    _prepared = null;
    final first = await call('InitiateAuth', {
      'ClientId': clientId,
      'AuthFlow': 'USER_SRP_AUTH',
      'AuthParameters': {'USERNAME': username, 'SRP_A': srp.publicAHex},
    });
    if (first['ChallengeName'] != 'PASSWORD_VERIFIER') {
      return _resolve(first, username, pending: pending);
    }
    final p = Map<String, dynamic>.from(first['ChallengeParameters'] ?? {});
    final userId = p['USER_ID_FOR_SRP'] ?? username;
    return _resolve(
      await call('RespondToAuthChallenge', {
        'ClientId': clientId,
        'ChallengeName': 'PASSWORD_VERIFIER',
        'ChallengeResponses': srp.respond(
          userId: userId,
          password: password,
          saltHex: p['SALT'],
          srpBHex: p['SRP_B'],
          secretBlock: p['SECRET_BLOCK'],
        ),
      }),
      userId,
      pending: pending,
    );
  }

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

  Future<Object> _resolve(
    Map<String, dynamic> j,
    String username, {
    bool pending = false,
  }) async {
    if (j['AuthenticationResult'] is Map) {
      final tokens = Map<String, dynamic>.from(j['AuthenticationResult']);
      // Conta sem organização (cadastro que parou no meio): o app completa o cadastro em vez de recusar.
      if (pending || !_hasOrganization(tokens['AccessToken'])) {
        return PendingTokens(
          tokens['AccessToken'],
          tokens['RefreshToken'] ?? '',
        );
      }
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

  /// Só lê a claim para decidir o caminho; quem autentica de verdade é o GetUser em [verify].
  static bool _hasOrganization(String accessToken) {
    try {
      final parts = accessToken.split('.');
      if (parts.length != 3)
        return true; // formato estranho: deixa o verify() recusar
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final org = claims is Map ? claims['custom:org_id'] : null;
      return org is String && org.isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  /// O e-mail da conta já foi confirmado? (Cadastro que parou depois do código.)
  Future<bool> emailVerified(String accessToken) async {
    final user = await call('GetUser', {'AccessToken': accessToken});
    for (final a in user['UserAttributes'] as List? ?? []) {
      if (a['Name'] == 'email_verified') return a['Value'] == 'true';
    }
    return false;
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

  /// Manda ao e-mail da conta o código que prova que a pessoa é dona do endereço.
  Future<void> sendEmailCode(String accessToken) async {
    await call('GetUserAttributeVerificationCode', {
      'AccessToken': accessToken,
      'AttributeName': 'email',
    });
  }

  Future<void> verifyEmail(String accessToken, String code) async {
    await call('VerifyUserAttribute', {
      'AccessToken': accessToken,
      'AttributeName': 'email',
      'Code': code,
    });
  }

  /// Renova a sessão de uma conta que acabou de ganhar organização: o token novo já traz o org_id.
  Future<AuthSession> refreshPending(PendingTokens t) async {
    final j = await call('InitiateAuth', {
      'ClientId': clientId,
      'AuthFlow': 'REFRESH_TOKEN_AUTH',
      'AuthParameters': {'REFRESH_TOKEN': t.refreshToken},
    });
    return verify(
      j['AuthenticationResult']['AccessToken'],
      refreshToken: t.refreshToken,
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
