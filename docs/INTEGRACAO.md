# Contratos e sincronização

Base: `OrganizAi-back-end-Gemas-Dev (1)(1).zip`, recebida nesta conversa. O backend alterado acompanha o aplicativo. Não aplique o antigo complemento de `integration/`: o suporte WAV já está incorporado ao Java desta entrega.

## Rotas adicionadas

| Método e rota | Uso |
| --- | --- |
| `GET /api/conta` | Identidade, organização ativa e perfis do token |
| `GET /api/obras?page=0` | Obras da organização |
| `POST /api/obras` | Criar obra, para admin/gestor |
| `PATCH /api/obras/{id}` | Editar obra, para admin/gestor |
| `GET /api/obras/{id}/documentos?page=0` | Acervo e estado de processamento/conferência |
| `GET /api/obras/{id}/diarios?page=0` | Diários, textos, campos, clima e aprovação |
| `PATCH /api/documentos/{id}/revisao` | Salvar `versionId`, `category` e `fields` |
| `GET /api/documentos/{id}/download` | URL assinada por 5 minutos, versão, hash e tamanho |

As listagens retornam `{items, hasNext}` em páginas de até 50 itens. O Flutter consome as páginas até o fim e reconcilia o catálogo com o cache da sessão atual. O cadastro de obra usa nome, código, contratante, executora, responsável, registro, tipo, estado, endereço, datas previstas e coordenadas opcionais.

Organização e identidade vêm do token. O servidor verifica os vínculos entre organização, obra, documento e versão; o cliente não pode conferir uma versão antiga como se fosse a atual. Registros excluídos não são disponibilizados pelas rotas novas.

## Rotas existentes utilizadas

| Método e rota | Uso |
| --- | --- |
| `POST /api/documentos/upload-url` | Solicitar upload com `projectId`, `nomeArquivo`, `contentType` |
| `POST /api/documentos/{id}/versoes/{versionId}/confirmar-upload` | Confirmar `sha256` após PUT |
| `GET /api/documentos/{id}/ocr` | Acompanhar OCR: 202 aguardando, 200 processado, 422 falhou |
| `POST /api/diario/upload-url` | Enviar `projectId`, `entryDate`, `authorRole`, `contentType` |
| `GET /api/diario/{id}/transcricao` | Consultar transcrição e clima |
| `PATCH /api/diario/{id}/texto` | Salvar `texto` e, agora, `campos` manuais opcionais |
| `POST /api/diario/{id}/aprovar` | Aprovar sem corpo; aprovador vem do token |
| `PATCH /api/diario/{id}/clima` | Salvar informações meteorológicas manuais |
| `POST /api/diario/{id}/clima/tentar-novamente` | Solicitar nova consulta assíncrona |
| `POST /api/assistente/perguntas` | Perguntar com `projectId`, `pergunta`, `sessionId` opcional |

Documentos e áudios são enviados diretamente ao S3 por URL assinada, em um cliente HTTP separado que não encaminha o bearer token da API. O mesmo isolamento se aplica ao download do original. O hash do documento é validado após o download; a atualização do hash confirmado no banco foi corrigida no Java.

## Perfis

| Operação | Admin | Gestor | Colaborador | Revisor | Auditor |
| --- | --- | --- | --- | --- | --- |
| Consultar obras/documentos e IA | Sim | Sim | Sim | Sim | Sim |
| Criar/editar obra | Sim | Sim | Não | Não | Não |
| Enviar documentos | Sim | Sim | Sim | Não | Não |
| Conferir documentos | Sim | Sim | Não | Sim | Não |
| Usar diário/clima | Sim | Sim | Sim | Sim | Não |
| Aprovar diário | Sim | Sim | Não | Sim | Não |

## Atualização e arquivos locais

O catálogo sincroniza ao entrar, pelo botão de atualização e a cada 30 segundos nas telas Hoje/Acervo quando o aplicativo está ocioso. Os dados só substituem o estado atual se a sessão ainda for a mesma. Conferências e edições confirmadas são persistidas na API.

O cache é separado por API, emissor Cognito, organização e usuário. Conteúdo de outra sessão não abre apenas porque existe no dispositivo. Access e refresh tokens ficam em memória. Conversas visuais e atividade do dispositivo são locais; isso não é um histórico de auditoria central.

O original de documento é recuperado sob demanda, com verificação SHA-256. Documentos legados podem ter tamanho zero no metadado; a tela mostra “—” até conhecer o tamanho real. Um arquivo confirmado por uma versão antiga do backend pode ter hash provisório no banco; se a verificação falhar, não a desative: confira objeto e metadado no servidor. A correção desta entrega vale para confirmações realizadas pelo código atualizado, sem reconstruir hashes históricos automaticamente.

Um registro de upload sem arquivo confirmado continua aparecendo como pendente e não interrompe a listagem. Em outro dispositivo, retomar um envio ainda não concluído exige o arquivo original. O backend não ganhou uma rota de exclusão ou de cancelamento de registros abandonados. A consulta de processamento pode ser interrompida no cliente sem cancelar a execução AWS.

O WAV de gravação está incorporado ao backend: PCM, 16 kHz e mono no cliente, com validação de RIFF/WAVE no servidor. Áudios locais e PDFs de diário podem ser exportados; não foi adicionada uma rota para baixar o áudio original em outro dispositivo. Diário aprovado fica fechado na interface.

## CORS e endereço da API

`API_BASE_URL` é a raiz da API Java: exemplo local `http://localhost:8080`, sem `/api` ao final. Produção deve usar HTTPS. No emulador Android, a máquina de desenvolvimento costuma ser alcançada por `http://10.0.2.2:8080`; no aparelho físico, use o endereço alcançável da rede ou HTTPS publicado.

Para Web, a API precisa de `CORS_ALLOWED_ORIGINS=http://localhost:7357` e o Flutter deve iniciar com `--web-hostname localhost --web-port 7357`. Configure também os buckets de documentos e diários para essa origem, usando `s3-cors.example.json` como referência. Em produção, substitua pela origem HTTPS real. Preserve regras CORS existentes que outros clientes ainda utilizam.

Os headers do exemplo devem corresponder aos retornados nas URLs assinadas. A API autoriza as requisições com `Authorization` e `Content-Type`; o S3 recebe apenas os headers do contrato assinado. Microfone no navegador exige um contexto seguro, como HTTPS ou localhost.
