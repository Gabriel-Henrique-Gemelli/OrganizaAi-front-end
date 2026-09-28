# Validação desta entrega

Data: 24/09/2026. Backend de origem: `OrganizAi-back-end-Gemas-Dev (1)(1).zip`. Resultados de execução desta revisão, sem acesso ao banco ou simulação apresentada como dado real no aplicativo.

## Executado

| Verificação | Resultado |
| --- | --- |
| Dependências Flutter, com lockfile | Resolvidas |
| `flutter analyze --no-pub` | Nenhum problema encontrado |
| `flutter test --no-pub --reporter expanded` | **28 testes aprovados** |
| Núcleo Dart, `tool/core_check.dart` | **15 verificações aprovadas** |
| Compilação Java e compilação dos testes | Concluídas com JDK 21 |
| Seleção de testes Maven/JUnit da integração | **146 testes aprovados**, zero falhas, erros ou ignorados |
| Build web release | Concluído com `--no-tree-shake-icons` |
| Chamada real ao Cognito, cliente principal | Bloqueada: `USER_PASSWORD_AUTH` desabilitado |
| Chamada real ao Cognito, segundo cliente | Bloqueada: exige secret |

Ambiente de compilação: Flutter 3.47.5, Dart 3.13.4 e Amazon Corretto 21.0.12.9.1. O build web padrão falhou na ferramenta de otimização de ícones do SDK (`ConstFinder`, leitura do kernel). A repetição com `--no-tree-shake-icons` concluiu. Esse parâmetro mantém os ícones completos no pacote; foi registrado também na CI.

O build de verificação não tinha `API_BASE_URL` pública, pois ela não foi informada. A compilação aprovada não comprova a execução ponta a ponta. O pacote entregue contém o código para gerar um novo build com a configuração correta.

## Cobertura exercitada

Os 28 testes Flutter incluem contrato HTTP e URLs assinadas, isolamento do token, paginação, validação de sessão com GetUser, recusa de tokens e emissores indevidos, catálogo sem demonstração, falha de API no login, isolamento de organização, cadastro remoto, revisão persistida, deduplicação e estados do diário. Testes de widgets renderizam as sete telas em 390, 800 e 1440 pixels e verificam navegação móvel/desktop e login sem configuração técnica.

As 15 verificações Dart exercitam validação de URL, MIME e limites, serialização de documentos e diários, Unicode, exportação CSV e neutralização de fórmulas.

As 13 classes Java executadas foram:

| Classe | Testes |
| --- | --- |
| `WorkspaceServiceTest` | 8 |
| `WorkspaceControllerTest` | 4 |
| `SecurityConfigTest` | 22 |
| `DocumentVersionTest` | 5 |
| `DocumentIngestionServiceTest` | 11 |
| `DiaryReviewServiceTest` | 18 |
| `DiaryUploadServiceTest` | 11 |
| `DiaryUploadServiceContratoLambdaTest` | 4 |
| `DiaryTranscriptionServiceTest` | 15 |
| `FlutterWavContractTest` | 3 |
| `CognitoTokenValidatorsTest` | 9 |
| `CurrentUserTest` | 7 |
| `DiarioControllerTest` | 29 |

Essa seleção cobre rotas novas, organização ativa, vínculos entre obra/documento/versão, revisão atual, download, documentos pendentes, permissões, identidade do token, upload e processamento de diário. É uma seleção da suíte Java, não a execução de todos os testes do repositório. Dependências externas foram simuladas nesses testes.

## Repetir

No Flutter:

```sh
flutter pub get
dart tool/bootstrap.dart
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
dart run tool/core_check.dart
flutter build web --release --no-tree-shake-icons --dart-define-from-file=config.json
```

Em `backend/back-end`, com JDK 21:

```sh
./mvnw test -Dtest=WorkspaceServiceTest,WorkspaceControllerTest,SecurityConfigTest,DocumentVersionTest,DocumentIngestionServiceTest,DiaryReviewServiceTest,DiaryUploadServiceTest,DiaryUploadServiceContratoLambdaTest,DiaryTranscriptionServiceTest,FlutterWavContractTest,CognitoTokenValidatorsTest,CurrentUserTest,DiarioControllerTest
```

No Windows use `mvnw.cmd` e coloque o argumento `-Dtest=...` entre aspas se o shell o exigir. Neste ambiente restrito, o Mockito foi carregado explicitamente com `-javaagent` apontando para o `mockito-core` resolvido pelo Maven. Em ambientes que bloqueiem autoanexação da JVM, use essa mesma configuração em `argLine`.

## Pendente no ambiente real

- Login concluído após corrigir o App Client; validação de grupo, organização, primeiro acesso e MFA com usuários reais.
- Conexão ao Supabase, migrações e persistência transacional em banco real.
- API/worker publicados e acessíveis, upload S3, OCR, Transcribe, clima e Bedrock.
- Sincronização entre dois dispositivos conectados ao mesmo ambiente, download e conferência de documento real.
- Permissões e uso de câmera/microfone em aparelho, emulador e desktop nativos; assinatura e distribuição.
- Execução dos scripts PowerShell e da CI em um repositório/host do usuário.

Para a validação integrada, entre em dois dispositivos com a mesma conta, cadastre uma obra com admin/gestor, envie um documento, aguarde o OCR, salve uma conferência e atualize o acervo no segundo dispositivo. Em seguida, teste diário e uma pergunta com fonte real. Repita a consulta com uma conta de outra organização: os dados não devem aparecer. Essas ações dependem do ambiente configurado e ainda não foram executadas nesta entrega.
