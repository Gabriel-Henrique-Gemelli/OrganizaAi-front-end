import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../core/config.dart';
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
      code = TextEditingController();
  final attributes = <String, TextEditingController>{};
  bool saving = false, resetting = false, showPassword = false;
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
    for (final c in [username, password, code, ...attributes.values]) {
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
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is ApiFailure
              ? e.message
              : 'Não foi possível concluir. Tente novamente.',
        );
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
