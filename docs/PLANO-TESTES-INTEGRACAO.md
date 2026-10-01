# Plano de testes de integração: front Flutter web × API Spring (EC2)

Elaborado com apoio dos agentes `ecc:planner`, `ecc:security-reviewer` e `ecc:silent-failure-hunter`, a partir do código atual do front e do back. Base: `https://api.organizaii.com.br`, front em `http://localhost:8081`.

## 1. Escopo

Todas as rotas que o front chama, em dois níveis:

- **API:** HTTP direto com access token real (login SRP).
- **E2E no navegador:** Playwright contra o front (Flutter CanvasKit, com a árvore de semântica ativada).

Fora do escopo: conferência de documento e download do original (só locais, sem rota), app mobile, carga além do rate limit.

Rotas testadas: `GET /api/conta`; `GET/POST/PATCH /api/obras`; `POST /api/documentos/upload-url` → PUT S3 → `POST .../versoes/{v}/confirmar-upload` → `GET /api/documentos/{id}/ocr`; `POST /api/diario/upload-url` → PUT S3 → `POST /api/diario/{id}/confirmar-upload` → `GET /api/diario/{id}/transcricao`; `PATCH /api/diario/{id}/texto`; `POST /api/diario/{id}/aprovar`; `GET /api/diario/clima`; `PATCH /api/diario/{id}/clima`; `POST /api/assistente/perguntas`. Auxiliares (o front não chama): `GET /api/obras/{id}/documentos` e `/diarios`.

## 2. Pré-condições

- EC2 ligado; `organizai-api` e `organizai-worker` de pé; `GET /actuator/health` = 200.
- Buckets `organizai-dev-docs` e `organizai-buckets-diario-obras` com CORS para `http://localhost:8081`.
- Usuário `teste@organizai.dev` (grupo admin, `custom:org_id` no access token). Senha em `E2E_PASSWORD`, nunca no repositório.
- Usuários temporários por perfil (`teste+gestor`, `+colaborador`, `+revisor`, `+auditor` @organizai.dev), removidos na limpeza.
- Token: SRP obrigatório. Um script Dart fora do repo faz o login e grava o token em arquivo temporário; tokens nunca vão para logs ou relatório.
- Fixtures: `teste.pdf`, `teste.png`, `teste.xlsx`, `teste.docx`, `teste.txt`, `falso.pdf` (conteúdo PNG), `binario.txt`, `grande.png` (>10 MB), `diario.webm`/`diario.ogg` (fala real com o termo `TESTE-ZETA`, gerada pelo Polly), `falso.webm` (bytes de mp3).

## 3. Dados de teste e limpeza

Tudo criado com prefixo `[TESTE]`, sempre em obras de teste (`[TESTE] Obra A` sem coordenadas, `[TESTE] Obra B clima` com coordenadas), nunca na obra seed `...0002`. O título de documento perde o prefixo (`sanitizarNome`), então a limpeza é por `project_id` das obras de teste.

Limpeza ao final, com inventário salvo antes: SQL em transação (chunks, chat, extractions, classifications, ocr_results, versões, documentos, revisões, diários, obras), objetos S3 pelo prefixo `org/<org>/proj/<obraTeste>/`, usuários Cognito `teste+*`, cache do navegador. **Só apago com confirmação.**

## 4. Matriz de casos (resumo)

Convenções: **[W]** exige o worker/pipeline assíncrono. Erros em RFC 7807.

### 4.1 Autenticação, CORS, conta
| ID | Caso | Esperado |
|---|---|---|
| A01 | `GET /api/conta` com admin | 200 `{subject, organizationId, company, name, roles}` |
| A02 | sem Authorization | 401 + `WWW-Authenticate: Bearer` |
| A03 | assinatura adulterada / `alg=none` | 401 |
| A04 | ID token no lugar do access token | 401 |
| A05 | token expirado | 401 |
| A06 | `client_id` fora da lista | 401 |
| A07 | preflight com origem `http://localhost:8081` | 200, ACAO igual à origem, sem credenciais |
| A08 | preflight com origem `https://evil.example` | 403, sem ACAO |
| A09 | preflight com método DELETE/PUT | 403 |
| A10 | HSTS presente | header |
| A11 | senha errada na UI | "Acesso não autorizado", sem chamadas `/api` |
| A12 | rota inexistente, `PATCH /api/conta`, `Content-Type: text/plain` | 404/405/415 (achado F1: hoje pode ser 500) |

### 4.2 Obras
| ID | Caso | Esperado |
|---|---|---|
| O01 | `GET /api/obras?page=0` | 200, contém a seed, só da organização |
| O02 | `page=-1` / `page=abc` | 400 |
| O03 | todos os 5 perfis listam | 200 |
| O04 | `POST {name}` | 201; executora = organização, responsável = usuário, datas vazias |
| O05 | `POST` com lat/long/UF/data | 201 com coordenadas |
| O06 | `name` vazio | 400 |
| O07 | UF `SPX`, data `01/10/2026`, `2026-13-45`, type/status inválidos | 400 |
| O10 | `latitude=999` / `1234.5` (API direta) | esperado 400; registrar o real (F11) |
| O11 | POST/PATCH por colaborador, revisor, auditor | 403 |
| O12 | `PATCH` da obra de teste | 200 |
| O13 | PATCH com UUID inexistente | 404 genérico |
| O14 | PATCH com `abc` | 400 |
| O17 | listas auxiliares de documentos/diários | 200 com os itens criados |
| O18 | auditor lista diários | 403 |

### 4.3 Documentos
| ID | Caso | Esperado |
|---|---|---|
| D01-D03 | upload-url, PUT S3 (sem Authorization), confirmar | 201, 200, 200 `EM_OCR` |
| D04/D05 [W] | OCR de pdf e png | 202 depois 200 `PROCESSADO`, texto com o termo; alvo < 3 min |
| D06 | xlsx, docx, txt | 1º GET já 200 (síncrono) |
| D07 | mesmo arquivo de novo | 409 duplicado |
| D08 | confirmar sem PUT | 400 |
| D10/D11 | conteúdo falso (png como pdf; byte 0 em txt) | 415 |
| D12 | confirmar duas vezes | 409 |
| D13 | `sha256` maiúsculo ou curto | 400 |
| D14 | `versionId` de outro documento | 400 |
| D15/D16 | `.exe`; `contentType` que não confere | 415 / 400 |
| D17 | `grande.png` 11 MB | 413 (o front aceita até 50 MB: divergência) |
| D18 | `projectId` inexistente | 404 |
| D19 | `tamanhoBytes` ausente/0 | 400 |
| D20 | revisor/auditor enviam | 403 |
| D21 | auditor/revisor consultam OCR | 200 |
| D22/D23 | OCR de UUID aleatório; doc não confirmado | 404 genérico; 202 |
| D25/D26 | PUT com Content-Type errado ou vencido | 403 do S3 |

### 4.4 Diário
| ID | Caso | Esperado |
|---|---|---|
| DI01-DI03 | upload-url, PUT, confirmar (`audio/webm`) | 201, 200, 200 `EM_TRANSCRICAO` |
| DI04/DI05 [W] | transcrição de webm e ogg | 202 depois 200 `AGUARDANDO_REVISAO`; alvo < 5 min |
| DI06 | `audio/mpeg`, `audio/wav` | 415 |
| DI07/DI08 | conteúdo falso; sem PUT | 415; 400 |
| DI09 | 60 MB | 413 (o front aceita até 120 MB: divergência) |
| DI10 | sem `entryDate`/`authorRole` | 400 |
| DI11 | auditor cria | 403 |
| DI12 | `PATCH texto` em `AGUARDANDO_REVISAO` | 200 |
| DI13 | `PATCH texto` em `EM_TRANSCRICAO` | 409 |
| DI14 | texto vazio / 50001 | 400 |
| DI15 | aprovar (admin/revisor) | 200 `FECHADO` + `sequenceNumber` |
| DI16 | aprovar de novo | 409 |
| DI17 | aprovar como colaborador | 403 |
| DI18 | editar diário fechado (API) | 200 `RETIFICADO` (UI bloqueia) |

### 4.5 Clima
| ID | Caso | Esperado |
|---|---|---|
| C01 | `GET clima` na obra com coordenadas | 200 com `tokenConsulta` |
| C02 | obra sem coordenadas | 409 |
| C03/C04 | sem `projectId`; obra inexistente | 400; 404 |
| C05 | PATCH com valores idênticos + token + `corrigidoPeloUsuario=false` | 200 `Open-Meteo` |
| C06/C07/C09 | corrigido; manual; `corrigidoPeloUsuario=null` | 200 `MANUAL` |
| C08 | valor alterado com `false`, token de outra obra ou adulterado | 400 |
| C10 | fora da faixa (temp 61, umidade 101, vento -1, chuva 1001) | 400 |
| C11 | auditor | 403 |
| C12 | token com mais de 2 h | 400 |

### 4.6 Assistente
| ID | Caso | Esperado |
|---|---|---|
| S01/S02 [W] | pergunta com termo indexado; mesma sessão | 200, ≥1 citação; mesmo `sessionId` |
| S03 | pergunta sem relação | 200 `semFonte=true` |
| S04 | vazia / 2001 caracteres / sem `projectId` | 400 |
| S05/S06 | `sessionId` de outra obra; `projectId` inexistente | 404 |
| S07 | auditor pergunta | 200 |
| S08 | 11 perguntas em 1 min | 11ª = 429 com `Retry-After` |

### 4.7 Rate limit, isolamento, front-only
| ID | Caso | Esperado |
|---|---|---|
| R01/R02 | 31 chamadas de upload-url/confirmar (balde compartilhado, 30/min) | 31ª = 429 |
| R03 | 21 chamadas de clima em 1 min | 21ª = 429 |
| R04 | lote de 20 `.txt` pela UI | após ~15, FAILED com mensagem de 429 (registrar) |
| X01 | IDOR com UUID aleatório em todas as rotas com `{id}` | 404 idêntico ao de "inexistente" |
| X02 | conferência e original na UI | nenhuma chamada HTTP nova |

## 5. Jornadas E2E no navegador (Playwright)

Depois de cada navegação completa: esperar `flt-glass-pane`, clicar em `flt-semantics-placeholder`, esperar `flt-semantics-host`. Só então `getByRole`/`getByText` funcionam. Capturar requests/responses para validar rota e status contra a matriz.

| Jornada | Verificações |
|---|---|
| J1 Login | Cognito `InitiateAuth` (SRP) → `RespondToAuthChallenge` → `GetUser`; `GET /api/conta` 200; `GET /api/obras` 200; senha errada não chama `/api` |
| J2 Criar/editar obra | POST 201 com só o nome; "Mais detalhes"; PATCH 200; validação local de UF e coordenada |
| J3 Upload + OCR | fluxo por arquivo; PUT ao S3 sem `Authorization`; `falso.pdf` fica FAILED; duplicado vira DUPLICADO |
| J4 Diário por áudio | upload, confirmar, polling, editar, fechar; fechado bloqueia edição |
| J5 Clima manual | `PATCH` com `corrigidoPeloUsuario=true`; validação local |
| J6 Clima automático | `GET clima` → confirmar sem alterar (`false` + token) e alterando (`true`, sem token) |
| J7 Assistente | resposta com citação; sessão reaproveitada; fora do tema `semFonte`; máx. 5 perguntas |
| J8 Sair/sessão | logout limpa dados; 401 no meio da sessão (comportamento atual: não desloga, achado) |
| J9 Perfis | colaborador, revisor, auditor veem só as ações permitidas; sem 403 na rede |

## 6. Ordem de execução

0. Fumaça (health, A01-A10, O01); se A01 falhar, parar.
1. Dados base (O04, O05) e restante de obras.
2. Documentos síncronos e negativos.
3. Diário síncrono e clima (C01-C04, C07-C12).
4. **[W]** OCR, transcrição, edição/aprovação, clima confirmado.
5. Assistente.
6. E2E J1 → J9 (obras próprias `[TESTE] E2E ...`).
7. Rate limit (sempre por último, gasta o balde).
8. Limpeza (com confirmação).

Custo controlado: até ~3 OCR assíncronos, 2 áudios curtos e < 20 perguntas ao assistente.

## 7. Achados prévios da revisão de código (a confirmar rodando)

Segurança/back: F1 rotas inexistentes, método errado e `Content-Type` inválido caem em 500 no handler genérico; F2 verificar no Cognito que `custom:org_id` é somente leitura para o client; F6 `PATCH clima` aceito em diário `FECHADO` sem trilha; F8 `tokenConsulta` reutilizável em outro diário da mesma obra por 2 h; F10 `PATCH /api/obras` apaga coordenadas, tipo e status omitidos; F11/F12 latitude `1234.5` e `\u0000` em texto viram 500; F5 rate limit consome cota antes da autorização; F3/F4 mensagens de exceção e valores enviados refletidos no erro.

Front: erro 5xx, rede e timeout viram "Confira sua conexão" e o `detail` do servidor é descartado (`api_client.dart`); comparação de sessão por identidade descarta resultado após refresh; refresh de token com falha transitória desloga; erro de polling do diário vira `FALHA_TRANSCRICAO` definitivo; erros do `addDiary` não geram toast; loop de lote continua depois de 429; limites de tamanho diferentes (imagem 50 MB × 10 MB; áudio 120 MB × 50 MB); `docs/INTEGRACAO.md` desatualizado.

## 8. Critérios de aprovação

**Passa:** 100% dos casos happy conforme a matriz; 100% dos security com 401/403/404 genérico sem vazar dados; negativos com o status esperado (onde a matriz diz "registrar", basta documentar o real); J1-J9 sem erro não tratado no console; pipelines assíncronos dentro do SLA; PUT ao S3 sem `Authorization`; limpeza completa (inventário = 0 depois do DELETE).

**Falha:** qualquer 500 em caso happy ou security; 2xx em caso security; vazamento entre organizações; CORS aceitando origem não listada; token de clima aceito com valores alterados; dados de teste restantes.

**Bloqueado** (não é falha do sistema): pré-condições não atendidas.
