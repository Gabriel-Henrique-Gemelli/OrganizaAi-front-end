# Login e conta

Configuração pública incorporada nesta entrega:

| Item | Valor |
| --- | --- |
| Região | `us-east-1` |
| User Pool | `us-east-1_gdkHR3WCT` |
| App Client do Flutter | `1v7oqsn5g97smst2hsrlhlhvep` |
| Emissor | `https://cognito-idp.us-east-1.amazonaws.com/us-east-1_gdkHR3WCT` |

## Resultado da consulta real

Em 24/09/2026, a tentativa de `InitiateAuth` com `USER_PASSWORD_AUTH` no cliente acima retornou `InvalidParameterException`, indicando que o fluxo não está habilitado. Não houve autenticação nem validação da senha, dos grupos ou da organização.

O segundo cliente fornecido, `5iacc6b8inci73o8nq1g2h0voe`, retornou exigência de secret. Ele permanece na lista de clientes aceitos pela API, mas não é usado pelo Flutter. Um secret não deve ser distribuído no aplicativo.

O comando administrativo enviado usa `AdminInitiateAuth` e IAM. O Flutter implementa o fluxo público `InitiateAuth` com `USER_PASSWORD_AUTH`; são operações distintas.

## Preparar o cliente público

O script `backend/habilitar-login-app.ps1` lê a configuração atual antes de atualizá-la, mantém os demais atributos reconhecidos pelo AWS CLI e habilita `ALLOW_USER_PASSWORD_AUTH` e `ALLOW_REFRESH_TOKEN_AUTH`. Ele pode ser inspecionado com `-WhatIf` e exige um perfil autorizado a `DescribeUserPoolClient` e `UpdateUserPoolClient`. Não foi executado contra a conta AWS nesta entrega.

O aplicativo usa `REFRESH_TOKEN_AUTH`, portanto precisa de um cliente com rotação de refresh tokens desativada. A leitura dos atributos deve incluir `name`, `email` e `custom:org_id`. A escrita de `custom:org_id` deve ser reservada à administração: o usuário não pode alterar a própria organização.

Se o cliente principal também tiver secret, crie um cliente público sem secret, ajuste `COGNITO_CLIENT_ID` no arquivo de configuração do Flutter e inclua o ID em `COGNITO_APP_CLIENT_IDS` no servidor. A resposta de fluxo desabilitado não permite concluir sozinha se esse cliente tem secret.

## Preparar o usuário

O usuário deve estar confirmado, ter um dos grupos `admin`, `gestor`, `colaborador`, `revisor` ou `auditor` e possuir `custom:org_id` com o UUID de uma organização ativa no PostgreSQL.

O código de Pre Token Generation V2 já existe em `backend/infra/aws/pre-token-generation`. Confira sua implantação e associação ao User Pool: a API exige `custom:org_id` no **access token**, além de `sub`, `client_id` e `cognito:groups`. Ter a claim somente no ID token não atende ao contrato.

## Fluxos implementados

| Ação | Operação |
| --- | --- |
| Entrar | `InitiateAuth` / `USER_PASSWORD_AUTH` |
| Trocar senha temporária | `RespondToAuthChallenge` / `NEW_PASSWORD_REQUIRED` |
| MFA já configurado | Resposta a SMS, TOTP ou `EMAIL_OTP` |
| Recuperar senha | `ForgotPassword` e `ConfirmForgotPassword` |
| Validar usuário | `GetUser` com o access token |
| Renovar sessão aberta | `InitiateAuth` / `REFRESH_TOKEN_AUTH` |

Não foram implementados cadastro inicial de TOTP, passkeys, desafios customizados ou dispositivos lembrados. A API Java valida o JWT independentemente da interface. O cliente só abre o catálogo após `GetUser`, confirmação de conta/organização na API e sincronização inicial bem-sucedida.

Tokens ficam em memória. Sair encerra a sessão local; não encerra sessões de outros dispositivos. A configuração Cognito é fornecida no build, sem campos técnicos na tela de login.

## Referências oficiais

- [InitiateAuth](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html)
- [UpdateUserPoolClient](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_UpdateUserPoolClient.html)
- [Refresh tokens](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-the-refresh-token.html)
