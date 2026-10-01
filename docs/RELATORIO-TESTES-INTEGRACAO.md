# Relatório: testes de integração front × API (EC2)

Data: 30/09/2026. Plano: `PLANO-TESTES-INTEGRACAO.md`. Scripts: `test/integracao_api/` (API, Python, login SRP) e `test/e2e_web/` (navegador, Playwright). Nenhuma senha ou token foi gravada.

## Resumo

| Camada | Executados | Passou | Falhou | Registrar | Não executado |
|---|---|---|---|---|---|
| API (HTTP direto) | 92 | 85 | 2 (mesma causa) | 5 | 10 por fail2ban + fases 3b, 4, 5 e 7 |
| E2E no navegador | 9 jornadas | 7 | 2 (J3, J8) | - | 1 item bloqueado no J9 |

**Encerrado antes do fim:** o fail2ban do EC2 baniu o IP de teste três vezes no dia (jail `nginx-bad-request`: 5 respostas 400 em 10 min = 1 h; `recidive`: 3 bans em 24 h = 24 h). Por decisão do usuário, os testes de API pararam aí. Não rodaram: clima (C01 a C11), transcrição/OCR assíncronos por API, assistente por API e rate limit. OCR, transcrição, clima e assistente **foram exercitados no E2E** (todos passaram).

## Defeitos confirmados

### Back-end
1. **Hash do documento nunca é gravado (alta).** `DocumentVersion.java:66` declara `sha256` com `updatable = false`, mas `confirmarUpload()` tenta alterá-lo. Consulta no Supabase: 0 das 15 versões de teste têm o hash real; todas guardam o hash provisório aleatório. Efeito: a deduplicação nunca dispara (D07 devolveu 200 em vez de 409; o E2E viu o mesmo), e o índice `uq_document_versions_org_project_sha256` não protege nada. Correção: permitir a atualização da coluna (remover `updatable = false` ou atualizar por query).
2. **Rota inexistente, método errado e `Content-Type` inválido devolvem 500** (A12a, A12b, A12c). O handler genérico de `ApiExceptionHandler` captura `NoResourceFoundException`, `HttpRequestMethodNotSupportedException` e `HttpMediaTypeNotSupportedException`. Esperado: 404, 405 e 415.
3. **Latitude `1234.5` devolve 500** (O10b): sem `@DecimalMin/@DecimalMax` no `ObraRequest` e a coluna é `numeric(9,6)`.
4. **`PATCH /api/obras/{id}` apaga latitude e longitude omitidas** (O16), além de voltar `type` e `status` ao padrão. O PATCH é substituição total. Isso quebra o clima automático. Código novo desta entrega; deve virar atualização parcial.

### Front-end (E2E)
5. **Logout não limpa o cache local** (J8): obra, documentos, diários, conversas e bytes dos arquivos continuam no IndexedDB e voltam no login seguinte.
6. **401 no meio da sessão não desloga** (J8, simulado): só aparece o toast "Entre novamente.".
7. **Duplicata descartada em silêncio** (J3): o front ignora qualquer arquivo de hash igual a um item da obra, inclusive de um item que falhou; quem corrige a extensão de um arquivo rejeitado não consegue reenviar.
8. **Contadores e acervo dependem só do cache local:** em contexto novo o rodapé mostra "0 documentos · 0 diários" com 6 documentos e 2 diários no servidor.
9. **Botões enganosos por perfil:** revisor e auditor veem "ENVIAR DOCUMENTO" e "REGISTRAR O DIA", que levam a "Acesso restrito". O colaborador vê APROVAR DIÁRIO desabilitado, não escondido.
10. **A obra seed fica selecionada após o login:** quem envia sem trocar de obra grava na seed.
11. **Assistente:** respostas com Markdown cru (`**...**`) e marcadores `[1]` sem link.
12. **Mensagens de erro genéricas** (revisão de código): 5xx, rede e timeout viram "Confira sua conexão" e o `detail` do servidor é descartado (`api_client.dart`); 409 de estado inválido aparece como "já existe ou foi alterado".
13. **Limites diferentes entre front e back:** imagem aceita até 50 MB no front e 10 MB no back; áudio 120 MB contra 50 MB (o servidor devolve 413, confirmado em D17 e DI09).

### Operação
14. **fail2ban pune erros normais de validação:** qualquer resposta HTTP 400 conta. Um usuário que erra 5 vezes em 10 minutos fica 1 h sem acesso, e 3 bans em um dia viram 24 h. Vale revisar o filtro `nginx-bad-request` (contar só 400 sem corpo de aplicação, ou subir o limiar).

## O que passou (resumo)

- **Autenticação e CORS:** 401 para ausência, lixo, assinatura adulterada, `alg=none`, ID token, token expirado forjado e `Basic`; `WWW-Authenticate: Bearer`; HSTS; preflight só para a origem do front, sem credenciais; origem estranha e DELETE recusados.
- **Perfis:** colaborador, revisor e auditor recebem 403 nas rotas proibidas (obras, upload de documento, diário); gestor cria e edita obra; todos leem obras.
- **Obras:** criação só com nome (executora = organização, responsável = usuário), coordenadas, `mass assignment` ignorado, 404 genérico, 400 de validação.
- **Documentos:** upload em 3 passos, PUT ao S3 sem `Authorization`, txt/xlsx/docx síncronos, 415 para conteúdo falso e extensão proibida, 413 acima do limite, 409 na dupla confirmação, 403 do S3 com `Content-Type` trocado.
- **Diário:** upload, confirmação, transcrição (24 s), edição, aprovação e bloqueio depois de fechado (E2E); 415 para mp3 e wav; 403 para auditor.
- **Clima:** manual, automático confirmado sem alterar (fonte Open-Meteo) e corrigido (MANUAL) no E2E.
- **Assistente:** resposta com citação e sem fonte (E2E), sessão reaproveitada.
- **OCR:** pdf em 30 s e png em 13 s no E2E (worker no EC2).

## Dados de teste (limpeza pendente)

Inventário no Supabase: 10 obras `[TESTE]*`, 15 documentos e versões, 8 resultados de OCR, 6 diários, 3 sessões de chat e 10 chunks. Mais: objetos nos buckets S3 sob `proj/<obra de teste>/`, e 4 usuários Cognito `teste-gestor`, `teste-colaborador`, `teste-revisor`, `teste-auditor`. Cinco documentos criados nos últimos dois dias na obra seed vêm de testes manuais anteriores e **não** são `[TESTE]`. Nada foi apagado ainda; a limpeza espera confirmação.

## Estado da AWS ao final

EC2 desligado. Continuam cobrando: Elastic IP `52.45.28.137` (cerca de US$ 3,60/mês), disco EBS de 16 GB, health check do Route 53 (HTTPS a cada 30 s; a exclusão foi bloqueada pelo classificador e fica a critério do usuário), 13 alarmes do CloudWatch e GuardDuty (custo por uso).
