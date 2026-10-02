import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../core/config.dart';
import '../core/error_handling.dart';
import '../data/api_client.dart';
import '../data/auth.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class ConnectionForm extends StatefulWidget {
  final AppStore store;
  final VoidCallback? onSaved;
  const ConnectionForm(this.store, {super.key, this.onSaved});
  @override
  State<ConnectionForm> createState() => _ConnectionFormState();
}

class _ConnectionFormState extends State<ConnectionForm> {
  final username = TextEditingController(),
      password = TextEditingController(),
      code = TextEditingController(),
      name = TextEditingController(),
      company = TextEditingController(),
      confirm = TextEditingController();
  final attributes = <String, TextEditingController>{};
  bool saving = false,
      resetting = false,
      showPassword = false,
      registering = false,
      verifying = false,
      emailVerified = false;
  PendingTokens? pendingTokens;
  String? error, notice;
  AuthChallenge? challenge;
  CognitoAuth? auth;
  CognitoAuth get cognito => auth ??= CognitoAuth(
    widget.store.cognitoIssuer,
    widget.store.cognitoClientId,
  );
  Timer? _warmUp;
  @override
  void initState() {
    super.initState();
    // Com a tela já desenhada e ociosa, deixa o cálculo pesado do SRP pronto antes do clique.
    if (!widget.store.started) {
      _warmUp = Timer(const Duration(milliseconds: 400), () {
        if (mounted && !saving && challenge == null) cognito.prepare();
      });
    }
  }

  @override
  void dispose() {
    _warmUp?.cancel();
    auth?.close();
    for (final c in [
      username,
      password,
      code,
      name,
      company,
      confirm,
      ...attributes.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> guard(Future<void> Function() action) async {
    setState(() {
      saving = true;
      error = null;
      notice = null;
    });
    try {
      await action();
    } catch (e, st) {
      if (mounted) setState(() => error = friendlyMessage(e, st));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> enter() => guard(() async {
    if (AppConfig.validateUrl(widget.store.baseUrl) != null)
      throw ApiFailure(
        'O acesso da organização ainda não foi configurado. Contate o responsável pelo sistema.',
      );
    if (username.text.trim().isEmpty)
      throw ApiFailure('Preencha seu usuário ou e-mail.');
    if (resetting) {
      if (code.text.trim().isEmpty || password.text.isEmpty)
        throw ApiFailure('Preencha o código recebido e a nova senha.');
      final secret = password.text;
      password.clear();
      await cognito.reset(username.text.trim(), code.text.trim(), secret);
      code.clear();
      if (mounted)
        setState(() {
          resetting = false;
          notice = 'Senha atualizada. Entre com sua nova senha.';
        });
      return;
    }
    final Object result;
    final currentChallenge = challenge;
    if (currentChallenge != null) {
      final value = currentChallenge.name == 'NEW_PASSWORD_REQUIRED'
          ? password.text
          : code.text.trim();
      if (value.isEmpty) throw ApiFailure('Preencha o campo para continuar.');
      password.clear();
      code.clear();
      result = await cognito.respond(currentChallenge, value, {
        for (final a in attributes.entries) a.key: a.value.text.trim(),
      });
    } else {
      if (password.text.isEmpty) throw ApiFailure('Preencha sua senha.');
      final secret = password.text;
      password.clear();
      result = await cognito.login(username.text.trim(), secret);
    }
    if (!mounted) return;
    if (result is AuthSession) {
      await widget.store.connect(result);
      widget.onSaved?.call();
    } else if (result is PendingTokens) {
      final pending = result;
      // Conta sem organização: cadastro que parou no meio. Completa em vez de recusar o login.
      final verified = await cognito.emailVerified(pending.accessToken);
      if (!verified) await cognito.sendEmailCode(pending.accessToken);
      if (!mounted) return;
      setState(() {
        pendingTokens = pending;
        emailVerified = verified;
        registering = true;
        verifying = true;
        code.clear();
        notice = verified
            ? 'Seu e-mail já está confirmado. Informe o nome da sua empresa para concluir o cadastro.'
            : 'Enviamos um código de verificação para o seu e-mail.';
      });
    } else if (result is AuthChallenge) {
      for (final c in attributes.values) {
        c.dispose();
      }
      attributes.clear();
      for (final name in result.attributes) {
        attributes[name] = TextEditingController();
      }
      final nextChallenge = result;
      setState(() => challenge = nextChallenge);
    }
  });

  /// Etapa 1: cria o usuário (e-mail ainda não verificado), entra com ele e pede o código ao e-mail.
  Future<void> register() => guard(() async {
    final email = username.text.trim();
    if (name.text.trim().isEmpty) throw ApiFailure('Informe seu nome.');
    if (company.text.trim().isEmpty)
      throw ApiFailure('Informe o nome da sua empresa.');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email))
      throw ApiFailure('Informe um e-mail válido.');
    if (password.text.length < 8)
      throw ApiFailure(
        'A senha precisa ter 8 ou mais caracteres, com maiúscula, minúscula, número e símbolo.',
      );
    if (password.text != confirm.text)
      throw ApiFailure('As senhas não conferem.');
    if (AppConfig.validateUrl(widget.store.baseUrl) != null)
      throw ApiFailure(
        'O acesso da organização ainda não foi configurado. Contate o responsável pelo sistema.',
      );
    final secret = password.text;
    final api = ApiClient(widget.store.baseUrl);
    final String user;
    try {
      user = await api.signup(
        name: name.text.trim(),
        email: email,
        password: secret,
      );
    } finally {
      api.http.close();
    }
    password.clear();
    confirm.clear();
    // Sem e-mail verificado o login só vale pelo nome interno que o servidor devolveu.
    final result = await cognito.login(user, secret, pending: true);
    if (result is! PendingTokens)
      throw ApiFailure('Não foi possível continuar o cadastro. Tente entrar.');
    await cognito.sendEmailCode(result.accessToken);
    if (!mounted) return;
    setState(() {
      pendingTokens = result;
      verifying = true;
      emailVerified = false;
      code.clear();
      notice = 'Enviamos um código de verificação para $email.';
    });
  });

  /// Etapa 2: confirma o código (se ainda não foi), cria a organização e entra já com ela. Cada passo
  /// que deu certo não se repete: se a criação da organização falhar, tentar de novo não pede outro código.
  Future<void> verifyAndEnter() => guard(() async {
    final tokens = pendingTokens;
    if (tokens == null) throw ApiFailure('Refaça o cadastro.');
    if (company.text.trim().isEmpty)
      throw ApiFailure('Informe o nome da sua empresa.');
    if (!emailVerified) {
      if (code.text.trim().isEmpty)
        throw ApiFailure('Preencha o código recebido por e-mail.');
      await cognito.verifyEmail(tokens.accessToken, code.text.trim());
      emailVerified = true;
    }
    final api = ApiClient(widget.store.baseUrl, token: tokens.accessToken);
    try {
      await api.activate(company.text.trim());
    } finally {
      api.http.close();
    }
    final session = await cognito.refreshPending(tokens);
    if (!mounted) return;
    pendingTokens = null;
    await widget.store.connect(session);
    widget.onSaved?.call();
  });

  Future<void> resendCode() => guard(() async {
    final tokens = pendingTokens;
    if (tokens == null) throw ApiFailure('Refaça o cadastro.');
    await cognito.sendEmailCode(tokens.accessToken);
    if (mounted) setState(() => notice = 'Enviamos um novo código.');
  });
  void switchMode({required bool toRegister}) => setState(() {
    registering = toRegister;
    verifying = false;
    emailVerified = false;
    pendingTokens = null;
    error = null;
    notice = null;
    password.clear();
    confirm.clear();
    code.clear();
  });
  Future<void> forgot() => guard(() async {
    if (username.text.trim().isEmpty)
      throw ApiFailure('Informe seu usuário ou e-mail primeiro.');
    await cognito.forgot(username.text.trim());
    password.clear();
    if (mounted)
      setState(() {
        resetting = true;
        notice = 'Se a conta permitir recuperação, você receberá um código no contato cadastrado.';
      });
  });
  Widget registerForm() => verifying
      ? verifyForm()
      : AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Crie sua conta',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 10),
              Text(
                'Você cria a sua empresa no OrganizAI e vira administrador dela. A equipe entra depois.',
                style: TextStyle(color: Palette.muted, height: 1.5),
              ),
              SizedBox(height: 24),
              FieldLabel(
                'Seu nome',
                child: TextField(
                  controller: name,
                  enabled: !saving,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                ),
              ),
              FieldLabel(
                'Empresa',
                child: TextField(
                  controller: company,
                  enabled: !saving,
                  autofillHints: const [AutofillHints.organizationName],
                  textInputAction: TextInputAction.next,
                ),
              ),
              FieldLabel(
                'E-mail',
                child: TextField(
                  controller: username,
                  enabled: !saving,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                ),
              ),
              FieldLabel(
                'Senha',
                child: TextField(
                  controller: password,
                  enabled: !saving,
                  obscureText: !showPassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  // Sem dica de autofill: o gerador de senha do navegador preenchia um campo e travava o outro.
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    helperMaxLines: 2,
                    helperText: '8 ou mais caracteres, com maiúscula, minúscula, número e símbolo.',
                    suffixIcon: IconButton(
                      tooltip: showPassword ? 'Ocultar senha' : 'Mostrar senha',
                      onPressed: () =>
                          setState(() => showPassword = !showPassword),
                      icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
              ),
              FieldLabel(
                'Confirmar senha',
                child: TextField(
                  controller: confirm,
                  enabled: !saving,
                  obscureText: !showPassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  onSubmitted: (_) {
                    if (!saving) register();
                  },
                ),
              ),
              if (error != null) ...[
                Text(error!, style: TextStyle(color: Palette.danger)),
                SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: saving ? null : register,
                child: Text(saving ? 'AGUARDE…' : 'CRIAR CONTA'),
              ),
              SizedBox(height: 10),
              TextButton(
                onPressed: saving ? null : () => switchMode(toRegister: false),
                child: Text('Já tenho conta. Entrar'),
              ),
            ],
          ),
        );
  Widget verifyForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        emailVerified ? 'Conclua seu cadastro' : 'Confirme seu e-mail',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      SizedBox(height: 10),
      Text(
        emailVerified ? 'Falta só criar a sua empresa no OrganizAI.' : 'Digite o código que chegou no seu e-mail. Só depois disso a sua empresa é criada.',
        style: TextStyle(color: Palette.muted, height: 1.5),
      ),
      SizedBox(height: 24),
      FieldLabel(
        'Empresa',
        child: TextField(
          controller: company,
          enabled: !saving,
          autofillHints: const [AutofillHints.organizationName],
          textInputAction: TextInputAction.next,
        ),
      ),
      if (!emailVerified)
        FieldLabel(
          'Código de verificação',
          child: TextField(
            controller: code,
            enabled: !saving,
            autofillHints: const [AutofillHints.oneTimeCode],
            keyboardType: TextInputType.number,
            onSubmitted: (_) {
              if (!saving) verifyAndEnter();
            },
          ),
        ),
      if (notice != null) ...[Notice(notice!), SizedBox(height: 16)],
      if (error != null) ...[
        Text(error!, style: TextStyle(color: Palette.danger)),
        SizedBox(height: 16),
      ],
      FilledButton(
        onPressed: saving ? null : verifyAndEnter,
        child: Text(saving ? 'AGUARDE…' : 'CONFIRMAR E ENTRAR'),
      ),
      SizedBox(height: 10),
      if (!emailVerified)
        TextButton(
          onPressed: saving ? null : resendCode,
          child: Text('Reenviar código'),
        ),
      TextButton(
        onPressed: saving ? null : () => switchMode(toRegister: false),
        child: Text('Cancelar'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (s.started && s.session != null)
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.userName,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 12),
          Text(s.company, style: TextStyle(color: Palette.muted)),
          SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: s.roles.map((r) => StatusPill(r)).toList(),
          ),
          SizedBox(height: 22),
          OutlinedButton(
            onPressed: s.working ? null : s.signOut,
            child: Text('SAIR DA CONTA'),
          ),
        ],
      );
    if (registering) return registerForm();
    final newPassword = resetting || challenge?.name == 'NEW_PASSWORD_REQUIRED';
    final needsCode = resetting || (challenge != null && !newPassword);
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Acesse sua conta',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10),
          Text(
            'Entre para acessar as obras e os documentos da sua organização.',
            style: TextStyle(color: Palette.muted, height: 1.5),
          ),
          SizedBox(height: 24),
          FieldLabel(
            'Usuário ou e-mail',
            child: TextField(
              controller: username,
              enabled: !saving && challenge == null && !resetting,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
            ),
          ),
          if (needsCode)
            FieldLabel(
              'Código de verificação',
              child: TextField(
                controller: code,
                enabled: !saving,
                autofillHints: const [AutofillHints.oneTimeCode],
                keyboardType: TextInputType.number,
              ),
            ),
          if (!needsCode || newPassword)
            FieldLabel(
              newPassword ? 'Nova senha' : 'Senha',
              child: TextField(
                controller: password,
                enabled: !saving,
                obscureText: !showPassword,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: [
                  newPassword
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onSubmitted: (_) {
                  if (!saving) enter();
                },
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    tooltip: showPassword ? 'Ocultar senha' : 'Mostrar senha',
                    onPressed: () =>
                        setState(() => showPassword = !showPassword),
                    icon: Icon(
                      showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
            ),
          for (final a in attributes.entries)
            FieldLabel(switch (a.key) {
              'name' => 'Nome',
              'email' => 'E-mail',
              'phone_number' => 'Telefone',
              _ => 'Dados da conta',
            }, child: TextField(controller: a.value, enabled: !saving)),
          if (notice != null) ...[Notice(notice!), SizedBox(height: 16)],
          if (error != null) ...[
            Text(error!, style: TextStyle(color: Palette.danger)),
            SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: saving ? null : enter,
            child: Text(
              saving
                  ? 'AGUARDE…'
                  : resetting
                  ? 'ATUALIZAR SENHA'
                  : challenge != null
                  ? 'CONTINUAR'
                  : 'ENTRAR',
            ),
          ),
          SizedBox(height: 10),
          if (challenge == null && !resetting)
            TextButton(
              onPressed: saving ? null : forgot,
              child: Text('Esqueci minha senha'),
            ),
          if (challenge == null && !resetting)
            TextButton(
              onPressed: saving ? null : () => switchMode(toRegister: true),
              child: Text('Não tenho conta. Criar conta'),
            ),
          if (challenge != null || resetting)
            TextButton(
              onPressed: saving
                  ? null
                  : () => setState(() {
                      challenge = null;
                      resetting = false;
                      error = null;
                      notice = null;
                      password.clear();
                      code.clear();
                    }),
              child: Text('Voltar ao login'),
            ),
        ],
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  final AppStore store;
  const AccountPage(this.store, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PageHeading(
        number: '10',
        title: 'Sua conta. Seu espaço.',
        description:
            'Acesse suas obras com a mesma conta no celular e no computador.',
      ),
      AdaptiveColumns(
        left: Panel(child: ConnectionForm(store)),
        right: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Eyebrow('DADOS DA ORGANIZAÇÃO', accent: true),
              SizedBox(height: 18),
              Text(
                'Obras, documentos e diários são consultados na sua organização. Atualize para buscar as alterações mais recentes.',
                style: TextStyle(color: Palette.muted, height: 1.6),
              ),
              SizedBox(height: 20),
              if (store.lastSync != null)
                Text(
                  'Última atualização: ${dateLabel(store.lastSync!)}',
                  style: mono(size: 10),
                ),
              if (store.syncError != null) ...[
                SizedBox(height: 12),
                Notice(store.syncError!),
              ],
              SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: store.working
                    ? null
                    : () => runAction(context, store.synchronize),
                icon: Icon(Icons.sync),
                label: Text('ATUALIZAR DADOS'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
