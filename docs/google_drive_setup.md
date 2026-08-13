# Preparação do Google Drive

Este documento registra os dados externos necessários para o primeiro login.
Nenhuma credencial deve ser adicionada ao repositório antes de o projeto no
Google Cloud existir.

## Configuração no Google Cloud

1. Criar um projeto no [Google Cloud Console](https://console.cloud.google.com/).
2. Habilitar a [Google Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com).
3. Configurar a tela de consentimento OAuth.
4. Declarar inicialmente o escopo:
   `https://www.googleapis.com/auth/drive.file`.
5. Criar um cliente OAuth do tipo Android com:
   - package name: `com.joaov.notas_app`;
   - SHA-1 de debug:
     `83:62:66:C8:31:C5:56:EB:E5:9D:FF:B6:35:7B:48:A7:D8:F9:F1:3A`.
6. Criar um cliente OAuth do tipo Web para ser o `serverClientId` usado pelo
   plugin oficial `google_sign_in` no Android. Para este uso não é necessário
   cadastrar origem JavaScript ou URI de redirecionamento.
7. Criar um cliente OAuth do tipo Desktop para Windows e baixar seu JSON.

## Dados que o projeto precisará receber

- ID do projeto Google Cloud;
- client ID do Android;
- client ID do tipo Web, usado como `serverClientId` no Android;
- client ID do aplicativo Desktop;
- package name definitivo;
- SHA-1 de debug para desenvolvimento;
- SHA-1 da chave de release antes da distribuição.

O JSON do cliente Desktop e qualquer token OAuth devem ficar fora do Git. Uma
localizaçao sugerida nesta maquina e:

```text
C:\Users\joaov\Documents\notas-secrets\oauth_desktop.json
```

O fluxo Windows deve abrir o navegador do sistema e usar OAuth para aplicativo
instalado com PKCE. Tokens de longa duração deverão ficar no armazenamento
seguro do sistema, nunca no Git ou em `shared_preferences`.

## Decisão sobre a pasta

O primeiro login criará uma pasta visível chamada `App Notas` em Meu Drive. O
app persistirá seu `fileId`; não dependerá do nome ou de um caminho textual para
reencontrá-la.

## Referências

- [OAuth para aplicativos instalados](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Escopos da Drive API](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Criar arquivos no Drive](https://developers.google.com/workspace/drive/api/guides/create-file)
