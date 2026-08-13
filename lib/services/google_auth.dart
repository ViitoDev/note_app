import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/email_message.dart';
import 'abrir_url.dart';

/// O resultado de um login concluido.
@immutable
class GoogleSession {
  const GoogleSession({required this.email, required this.refreshToken});

  /// Endereço da conta que autorizou, lido do `id_token`.
  final String email;

  /// A credencial de longa duraçao. E ela que faz o login seguinte ser
  /// automatico: o app troca este token por um de acesso novo sem abrir o
  /// navegador de novo.
  final String refreshToken;
}

/// Login com o Google pelo fluxo de aplicativo instalado (loopback + PKCE).
///
/// O navegador do sistema abre na tela de consentimento do Google e volta para
/// um servidor HTTP temporario em `127.0.0.1`, numa porta sorteada na hora. E o
/// fluxo que o Google recomenda para desktop: a senha nunca passa pelo app, e
/// o PKCE impede que outro processo na mesma maquina roube o codigo de volta.
///
/// Nao ha como fugir do cadastro no Google Cloud. O Google so emite token para
/// um `client_id` registrado, entao o app pede esse dado uma vez e guarda.
class GoogleAuth {
  const GoogleAuth({this.abrirNavegador = abrirNoNavegador});

  /// Injetavel para o teste nao abrir o navegador de verdade.
  final Future<void> Function(Uri url) abrirNavegador;

  static const _autorizacao = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _token = 'https://oauth2.googleapis.com/token';

  /// `mail.google.com` e o unico escopo que libera IMAP; os outros dois so
  /// servem para descobrir qual endereço autorizou.
  static const _escopos = 'https://mail.google.com/ openid email';

  /// Quanto tempo esperar o usuario terminar no navegador antes de desistir.
  static const _paciencia = Duration(minutes: 3);

  /// Abre o consentimento no navegador e espera o retorno.
  Future<GoogleSession> login({
    required String clientId,
    required String clientSecret,
  }) async {
    final verifier = _gerarVerifier();
    final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${servidor.port}';

    try {
      await abrirNavegador(
        Uri.parse(_autorizacao).replace(
          queryParameters: {
            'client_id': clientId,
            'redirect_uri': redirect,
            'response_type': 'code',
            'scope': _escopos,
            'code_challenge': _desafio(verifier),
            'code_challenge_method': 'S256',
            // Os dois juntos sao o que garante o refresh token. Sem
            // `prompt=consent`, uma conta que ja autorizou antes volta sem ele
            // — e ai o login automatico nao existiria.
            'access_type': 'offline',
            'prompt': 'consent',
          },
        ),
      );

      final code = await _esperarCodigo(servidor);

      return await _trocarCodigo(
        code: code,
        verifier: verifier,
        redirect: redirect,
        clientId: clientId,
        clientSecret: clientSecret,
      );
    } finally {
      await servidor.close(force: true);
    }
  }

  /// Troca o refresh token por um token de acesso novo.
  ///
  /// E este metodo que faz o "logar automatico": vale por cerca de uma hora, e
  /// o app repete sozinho sempre que o anterior expira.
  Future<String> accessToken({
    required String clientId,
    required String clientSecret,
    required String refreshToken,
  }) async {
    final json = await _postToken({
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    });

    final token = json['access_token'];
    if (token is! String) {
      throw const EmailException(
        FalhaEmail.credenciais,
        'O Google nao devolveu um token de acesso.',
      );
    }
    return token;
  }

  // ------------------------------------------------------------------ passos

  /// Espera o navegador bater no servidor local e devolve o `code`.
  Future<String> _esperarCodigo(HttpServer servidor) async {
    final HttpRequest req;
    try {
      req = await servidor.first.timeout(_paciencia);
    } on TimeoutException {
      // Quando o Google barra a conta, ele mostra o erro na propria pagina e
      // nunca volta para o loopback — daqui isso e indistinguivel de um
      // usuario que fechou a aba, entao a mensagem cobre os dois.
      throw const EmailException(
        FalhaEmail.credenciais,
        'O login no navegador nao foi concluido. Se apareceu "Acesso '
        'bloqueado", adicione a conta em "Usuarios de teste" na tela de '
        'permissao OAuth do projeto e tente de novo.',
      );
    }

    final code = req.uri.queryParameters['code'];
    final erro = req.uri.queryParameters['error'];

    // A aba do navegador fica aberta na mao do usuario; ela precisa dizer o
    // que aconteceu, senao ele volta para o app sem saber se deu certo.
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(_paginaDeRetorno(sucesso: code != null));
    await req.response.close();

    if (erro != null) {
      throw EmailException(
        FalhaEmail.credenciais,
        // `access_denied` cobre dois casos bem diferentes, e o segundo e o
        // mais provavel: com a tela de permissao em modo Teste, o Google
        // recusa qualquer conta que nao esteja em "Usuarios de teste".
        erro == 'access_denied'
            ? 'O Google recusou o acesso. Se apareceu "Acesso bloqueado", a '
                  'conta que voce escolheu nao esta em "Usuarios de teste" na '
                  'tela de permissao OAuth do projeto — adicione ela la, ou '
                  'entre com uma conta que ja esteja na lista.'
            : 'O Google recusou: $erro',
      );
    }
    if (code == null) {
      throw const EmailException(
        FalhaEmail.credenciais,
        'O Google voltou sem o codigo de autorizaçao.',
      );
    }
    return code;
  }

  Future<GoogleSession> _trocarCodigo({
    required String code,
    required String verifier,
    required String redirect,
    required String clientId,
    required String clientSecret,
  }) async {
    final json = await _postToken({
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'code_verifier': verifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirect,
    });

    final refresh = json['refresh_token'];
    if (refresh is! String) {
      // Acontece quando a conta ja autorizou este client antes e o pedido veio
      // sem `prompt=consent`. Sem refresh token nao ha login automatico, entao
      // e melhor falhar aqui do que descobrir isso no proximo inicio.
      throw const EmailException(
        FalhaEmail.credenciais,
        'O Google nao devolveu a credencial de longa duraçao. Remova o acesso '
        'do app em myaccount.google.com/permissions e entre de novo.',
      );
    }

    return GoogleSession(
      email: emailDoIdToken(json['id_token']),
      refreshToken: refresh,
    );
  }

  Future<Map<String, dynamic>> _postToken(Map<String, String> corpo) async {
    final http.Response resposta;
    try {
      resposta = await http.post(Uri.parse(_token), body: corpo);
    } on Exception catch (e) {
      throw EmailException(FalhaEmail.conexao, '$e');
    }

    final json = jsonDecode(resposta.body);
    if (json is! Map<String, dynamic>) {
      throw const EmailException(
        FalhaEmail.desconhecida,
        'Resposta inesperada do Google.',
      );
    }

    if (resposta.statusCode != 200) {
      throw EmailException(
        FalhaEmail.credenciais,
        json['error_description'] ?? json['error'] ?? resposta.body,
      );
    }
    return json;
  }

  // ---------------------------------------------------------------- utilidade

  /// Le o endereço direto do `id_token`, sem uma chamada extra.
  ///
  /// O token e assinado pelo Google e acabou de chegar por HTTPS do endpoint
  /// dele, entao aqui basta ler o miolo — validar a assinatura protegeria
  /// contra um emissor em quem ja estamos confiando.
  @visibleForTesting
  static String emailDoIdToken(Object? idToken) {
    if (idToken is! String) return '';
    final partes = idToken.split('.');
    if (partes.length < 2) return '';

    try {
      final json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(partes[1]))),
      );
      if (json is Map && json['email'] is String) {
        return json['email'] as String;
      }
    } on FormatException {
      // Endereço em branco so deixa o cabeçalho do painel mais pobre; nao
      // vale derrubar um login que deu certo.
    }
    return '';
  }

  static String _gerarVerifier() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(64, (_) => rnd.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _desafio(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  static String _paginaDeRetorno({required bool sucesso}) =>
      '''
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Notas</title></head>
<body style="font-family:system-ui;background:#0E1013;color:#E4E7EC;
display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
<div style="text-align:center">
<h2>${sucesso ? 'Conta ligada' : 'Nao deu certo'}</h2>
<p style="color:#8B93A1">${sucesso ? 'Pode fechar esta aba e voltar para o app.' : 'Volte ao app e tente de novo.'}</p>
</div></body></html>
''';
}
