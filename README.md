# OrganizAI · Flutter

Aplicativo integrado ao backend Java da branch Gemas-Dev incluída nesta entrega. Interface responsiva em grafite e laranja para mobile e desktop. O catálogo é carregado da API após login Cognito; o projeto não cria obras ou documentos de demonstração.

## Executar

Use Flutter 3.47.x e Dart 3.13.x. A validação foi realizada com Flutter 3.47.5 e Dart 3.13.4; as versões resolvidas das dependências estão em `pubspec.lock`.

```powershell
# API local em execução na porta 8080:
Copy-Item config.local.example.json config.json
.\iniciar.ps1 -d chrome --web-hostname localhost --web-port 7357
```

No Linux/macOS, copie o mesmo arquivo e use `bash iniciar.sh -d chrome --web-hostname localhost --web-port 7357`. Os scripts resolvem as dependências, preparam permissões com `tool/bootstrap.dart` e passam `config.json` ao Flutter. Para Windows nativo, use `-d windows` em um host Windows preparado para Flutter.

Para API publicada, copie `config.example.json` e preencha `API_BASE_URL` com a raiz HTTPS da API Java, sem `/api` ao final. A URL do Supabase em JDBC não serve neste campo. O Cognito já está configurado com os identificadores públicos recebidos; habilite o fluxo de login conforme [COGNITO.md](docs/COGNITO.md).

```sh
flutter pub get
dart tool/bootstrap.dart
flutter run --dart-define-from-file=config.json
flutter build web --release --no-tree-shake-icons --dart-define-from-file=config.json
```

`config.json` contém apenas configuração pública de build. Não coloque senha do banco, senha de usuário, token, secret de App Client ou chave AWS nele.

## Módulos

| Tela | Funções |
| --- | --- |
| Hoje | Resumo da obra, pendências e atualização do catálogo |
| Enviar | Arquivos em lote, câmera, arrastar, upload assinado, confirmação e OCR |
| Revisar | Original, texto extraído, categoria e campos de conferência salvos na API |
| Acervo | Documentos da obra, filtros, busca, CSV e download do original |
| Diário | Gravação/importação, transcrição, edição, campos manuais, clima, aprovação e PDF |
| Perguntar | Perguntas por obra, respostas e citações retornadas pelo servidor |
| Conta | Login, senha inicial, MFA configurado, recuperação de senha, perfil e saída |

Administradores e gestores podem cadastrar e editar obras pelo seletor. O cadastro é persistido no banco pela API; não exige digitar UUIDs. BIM, certificados e avisos de segurança não fazem parte desta versão.

## Comportamento e limites

- A API é a autoridade sobre organização, identidade e permissões. O cache é separado por API, emissor Cognito, organização e usuário autenticado.
- Obras, documentos e diários são paginados e sincronizados. O original de documento é baixado sob demanda por URL assinada e tem o hash conferido. O cache não é um backup do servidor.
- Uma falha de API impede a abertura inicial do catálogo. Falhas de processamento são exibidas; não são substituídas por resultados inventados.
- Tokens e senhas ficam em memória. Reiniciar o aplicativo exige novo login. Os arquivos e metadados locais não têm criptografia adicional à proteção do dispositivo.
- Diário aprovado fica fechado na interface. Retificação e consulta de histórico de versões não foram adicionadas. Áudio original está disponível quando foi mantido no dispositivo que o enviou.
- Arquivos Word/Excel/TIFF podem exigir um aplicativo externo para abrir o original. O texto extraído aparece na revisão. Citações da IA não ganham páginas ou links que a API não tenha retornado.
- Câmera, microfone, permissões nativas, assinatura e instaladores exigem validação na plataforma de destino. Não foram gerados APK, IPA ou instaladores desktop.

Consulte [INTEGRACAO.md](docs/INTEGRACAO.md), [COGNITO.md](docs/COGNITO.md), [DESIGN.md](docs/DESIGN.md) e [VALIDACAO.md](docs/VALIDACAO.md).
