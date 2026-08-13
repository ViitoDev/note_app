import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/email_message.dart';
import 'package:notas_app/services/google_auth.dart';

/// Um `id_token` de mentira: o codigo so le o miolo, entao cabeçalho e
/// assinatura podem ser qualquer coisa.
String _idToken(Map<String, Object?> conteudo) {
  String parte(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${parte({'alg': 'none'})}.${parte(conteudo)}.assinatura';
}

/// Faz o papel do navegador: volta na URL de redirecionamento com [resposta].
///
/// Quem chama **nao deve** aguardar este future dentro de `abrirNavegador`. O
/// `login` so passa a escutar o loopback depois que `abrirNavegador` retorna,
/// entao esperar a resposta ali travaria os dois. Um navegador de verdade e
/// outro processo, e o `rundll32` volta na hora — o teste imita isso.
Future<String> _navegadorResponde(Uri url, Map<String, String> resposta) async {
  final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
  final req = await HttpClient().getUrl(
    redirect.replace(queryParameters: resposta),
  );
  final resp = await req.close();
  return resp.transform(utf8.decoder).join();
}

void main() {
  // O ambiente de teste do Flutter troca o HttpClient por um dublê que recusa
  // tudo; aqui o cliente precisa falar de verdade com o servidor local.
  setUp(() => HttpOverrides.global = null);

  group('login', () {
    test('leva o PKCE e o pedido de refresh token na URL', () async {
      Uri? aberta;
      final auth = GoogleAuth(
        abrirNavegador: (url) async {
          aberta = url;
          unawaited(_navegadorResponde(url, {'error': 'access_denied'}));
        },
      );

      await expectLater(
        auth.login(clientId: 'abc', clientSecret: 'seg'),
        throwsA(isA<EmailException>()),
      );

      final q = aberta!.queryParameters;
      expect(q['client_id'], 'abc');
      expect(q['code_challenge_method'], 'S256');
      expect(q['code_challenge'], isNotEmpty);
      // Sem estes dois o Google nao devolve refresh token, e o login
      // automatico nao existiria.
      expect(q['access_type'], 'offline');
      expect(q['prompt'], 'consent');
      expect(q['scope'], contains('https://mail.google.com/'));
      expect(q['redirect_uri'], startsWith('http://127.0.0.1:'));
    });

    test('o desafio PKCE muda a cada login', () async {
      final desafios = <String>{};
      final auth = GoogleAuth(
        abrirNavegador: (url) async {
          desafios.add(url.queryParameters['code_challenge']!);
          unawaited(_navegadorResponde(url, {'error': 'x'}));
        },
      );

      for (var i = 0; i < 3; i++) {
        await auth
            .login(clientId: 'abc', clientSecret: 's')
            .catchError(
              (_) => const GoogleSession(email: '', refreshToken: ''),
            );
      }

      // Repetir o verifier deixaria um codigo interceptado utilizavel duas
      // vezes — e a razao de o PKCE existir.
      expect(desafios.length, 3);
    });

    test('recusar o acesso vira um erro legivel', () async {
      final auth = GoogleAuth(
        abrirNavegador: (url) async =>
            unawaited(_navegadorResponde(url, {'error': 'access_denied'})),
      );

      await expectLater(
        auth.login(clientId: 'abc', clientSecret: 's'),
        throwsA(
          isA<EmailException>()
              .having((e) => e.falha, 'falha', FalhaEmail.credenciais)
              .having((e) => e.detalhe, 'detalhe', contains('recusou')),
        ),
      );
    });

    test('volta sem codigo tambem falha, em vez de seguir em frente', () async {
      final auth = GoogleAuth(
        abrirNavegador: (url) async =>
            unawaited(_navegadorResponde(url, {'nada': 'aqui'})),
      );

      await expectLater(
        auth.login(clientId: 'abc', clientSecret: 's'),
        throwsA(isA<EmailException>()),
      );
    });

    test('a aba do navegador recebe uma pagina dizendo o que houve', () async {
      Future<String>? corpo;
      final auth = GoogleAuth(
        abrirNavegador: (url) async {
          corpo = _navegadorResponde(url, {'error': 'access_denied'});
        },
      );

      await auth
          .login(clientId: 'abc', clientSecret: 's')
          .catchError((_) => const GoogleSession(email: '', refreshToken: ''));

      // O usuario esta olhando para o navegador, nao para o app: e ali que ele
      // precisa saber se deu certo.
      expect(await corpo, contains('Nao deu certo'));
    });

    test('o servidor local fecha mesmo quando o login falha', () async {
      int? porta;
      final auth = GoogleAuth(
        abrirNavegador: (url) async {
          porta = Uri.parse(url.queryParameters['redirect_uri']!).port;
          unawaited(_navegadorResponde(url, {'error': 'x'}));
        },
      );

      await auth
          .login(clientId: 'a', clientSecret: 's')
          .catchError((_) => const GoogleSession(email: '', refreshToken: ''));

      // Porta presa deixaria o app sem jeito de reautenticar ate reiniciar.
      final servidor = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        porta!,
      );
      addTearDown(() => servidor.close(force: true));
      expect(servidor.port, porta);
    });
  });

  group('endereço no id_token', () {
    test('sai do miolo do token', () {
      expect(
        GoogleAuth.emailDoIdToken(_idToken({'email': 'pessoa@gmail.com'})),
        'pessoa@gmail.com',
      );
    });

    test('token estranho devolve vazio em vez de derrubar o login', () {
      // Endereço em branco so empobrece o cabeçalho do painel; perder um login
      // que ja deu certo seria bem pior.
      expect(GoogleAuth.emailDoIdToken(null), '');
      expect(GoogleAuth.emailDoIdToken('sem-pontos'), '');
      expect(GoogleAuth.emailDoIdToken('a.nao-e-base64!!.c'), '');
      expect(GoogleAuth.emailDoIdToken(_idToken({'sub': '1'})), '');
    });
  });
}
