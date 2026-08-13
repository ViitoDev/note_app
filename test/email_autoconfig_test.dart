import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/email_account.dart';
import 'package:notas_app/models/email_message.dart';
import 'package:notas_app/services/email_autoconfig.dart';
import 'package:notas_app/ui/email_config_dialog.dart';

import 'fake_email.dart';

/// Autoconfig que so "acha" os hosts da lista, sem tocar na rede.
EmailAutoconfig _com(Set<String> existentes) =>
    EmailAutoconfig(sonda: (host, _) async => existentes.contains(host));

/// Abre o dialogo e devolve um getter do resultado.
///
/// Getter, e nao Future: o dialogo so devolve quando fecha, e esperar por ele
/// aqui travaria o teste antes de ele conseguir preencher os campos.
Future<ValueGetter<EmailAccount?>> _abrir(
  WidgetTester tester,
  FakeEmail repositorio, {
  EmailAccount? atual,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  EmailAccount? resultado;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              resultado = await showEmailConfigDialog(
                context,
                repositorio: repositorio,
                atual: atual,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  return () => resultado;
}

void main() {
  group('dominio', () {
    test('extrai o que vem depois do arroba', () {
      expect(EmailAutoconfig.dominioDe('Eu@Exemplo.COM'), 'exemplo.com');
      expect(EmailAutoconfig.dominioDe('sem-arroba'), '');
    });

    test('reconhece os provedores grandes sem tocar na rede', () {
      expect(EmailAutoconfig.provedorDe('a@gmail.com'), ProvedorEmail.gmail);
      expect(
        EmailAutoconfig.provedorDe('a@hotmail.com'),
        ProvedorEmail.outlook,
      );
      expect(EmailAutoconfig.provedorDe('a@uol.com.br'), ProvedorEmail.uol);
      expect(EmailAutoconfig.provedorDe('a@dominio-proprio.com'), isNull);
    });
  });

  group('descobrir', () {
    test('provedor conhecido nem chega a sondar', () async {
      var sondou = false;
      final auto = EmailAutoconfig(
        sonda: (_, _) async {
          sondou = true;
          return true;
        },
      );

      final conta = await auto.descobrir('eu@gmail.com');

      expect(conta?.host, 'imap.gmail.com');
      expect(conta?.porta, 993);
      expect(sondou, isFalse);
    });

    test('dominio proprio: acha imap.<dominio>', () async {
      final conta = await _com({
        'imap.empresa.com.br',
      }).descobrir('eu@empresa.com.br');

      expect(conta?.host, 'imap.empresa.com.br');
    });

    test('cai para mail.<dominio> quando imap nao existe', () async {
      final conta = await _com({
        'mail.empresa.com.br',
      }).descobrir('eu@empresa.com.br');

      expect(conta?.host, 'mail.empresa.com.br');
    });

    test('nada encontrado devolve nulo, e nao um chute', () async {
      // Nulo manda o usuario para o campo de servidor; um chute mandaria a
      // senha dele para um host qualquer.
      expect(await _com(const {}).descobrir('eu@empresa.com.br'), isNull);
    });

    test('so tenta hosts dentro do dominio do usuario', () async {
      final tentados = <String>[];
      final auto = EmailAutoconfig(
        sonda: (host, _) async {
          tentados.add(host);
          return false;
        },
      );

      await auto.descobrir('eu@empresa.com.br');

      // Nenhum servidor de terceiro entra na lista: sondar um host de outra
      // empresa seria o primeiro passo para entregar a senha para ela.
      expect(tentados, ['imap.empresa.com.br', 'mail.empresa.com.br']);
    });

    test('endereço sem arroba nao vira busca', () async {
      expect(await _com(const {}).descobrir('sem-arroba'), isNull);
    });
  });

  group('formulario', () {
    testWidgets('pede so e-mail e senha', (tester) async {
      await _abrir(tester, FakeEmail());

      expect(find.text('E-mail'), findsOneWidget);
      expect(find.text('Senha'), findsOneWidget);
      // O servidor fica escondido: saber o que e IMAP nao pode ser condiçao
      // para ler a propria caixa.
      expect(find.text('Servidor IMAP'), findsNothing);
    });

    testWidgets('ligar devolve a conta descoberta', (tester) async {
      final repo = FakeEmail()
        ..contaDaSenha = const EmailAccount(
          email: 'eu@empresa.com',
          host: 'imap.empresa.com',
        );

      final resultado = await _abrir(tester, repo);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'eu@empresa.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'segredo',
      );
      await tester.tap(find.text('Ligar'));
      await tester.pumpAndSettle();

      expect(resultado()?.host, 'imap.empresa.com');
      expect(repo.ligacoesComSenha, 1);
      expect(repo.senhaGuardada, 'segredo');
    });

    testWidgets('senha recusada mostra o motivo sem fechar', (tester) async {
      final repo = FakeEmail()
        ..erroDaSenha = const EmailException(
          FalhaEmail.credenciais,
          'Usuario ou senha recusados pelo servidor.',
        );

      await _abrir(tester, repo);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'eu@empresa.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'errada',
      );
      await tester.tap(find.text('Ligar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('recusados'), findsOneWidget);
      // O dialogo fica aberto para o usuario corrigir ali mesmo.
      expect(find.text('Ligar'), findsOneWidget);
    });

    testWidgets('falha de conexao abre o campo de servidor', (tester) async {
      final repo = FakeEmail()
        ..erroDaSenha = const EmailException(
          FalhaEmail.conexao,
          'Nao encontrei o servidor deste dominio.',
        );

      await _abrir(tester, repo);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail'),
        'eu@obscuro.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Senha'),
        'segredo',
      );
      await tester.tap(find.text('Ligar'));
      await tester.pumpAndSettle();

      // O proximo passo util e informar o servidor, entao ele aparece sozinho.
      expect(find.text('Servidor IMAP'), findsOneWidget);
    });

    testWidgets('o aviso de senha de app so aparece para quem precisa', (
      tester,
    ) async {
      await _abrir(tester, FakeEmail());

      final email = find.widgetWithText(TextFormField, 'E-mail');

      await tester.enterText(email, 'eu@dominio-proprio.com.br');
      await tester.pumpAndSettle();
      expect(find.textContaining('senha de app'), findsNothing);

      await tester.enterText(email, 'eu@gmail.com');
      await tester.pumpAndSettle();
      expect(find.textContaining('senha de app'), findsOneWidget);
    });
  });
}
