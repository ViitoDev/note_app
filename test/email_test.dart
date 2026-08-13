import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/email_account.dart';
import 'package:notas_app/models/email_message.dart';
import 'package:notas_app/services/email_service.dart';
import 'package:notas_app/ui/email_screen.dart';
import 'package:notas_app/ui/ui_prefs.dart';
import 'package:notas_app/ui/vault_screen.dart';

import 'fake_email.dart';
import 'fake_vault.dart';

Future<void> _montarPainel(
  WidgetTester tester, {
  EmailAccount? conta,
  List<EmailMessage> mensagens = const [],
  bool carregando = false,
  EmailException? erro,
  ValueChanged<AcaoConta>? onConta,
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EmailScreen(
          conta: conta,
          mensagens: mensagens,
          carregando: carregando,
          erro: erro,
          onRefresh: () {},
          onConta: onConta ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _conta = EmailAccount(email: 'eu@exemplo.com', host: 'imap.exemplo.com');

void main() {
  group('EmailAccount', () {
    test('sobrevive a ida e volta do texto guardado', () {
      const conta = EmailAccount(
        email: 'eu@exemplo.com',
        host: 'imap.exemplo.com',
        porta: 143,
        usuario: 'login-diferente',
        caixa: 'Arquivo',
      );

      expect(EmailAccount.decode(conta.encode()), conta);
    });

    test('sem conta guardada devolve nulo', () {
      expect(EmailAccount.decode(null), isNull);
      expect(EmailAccount.decode('  '), isNull);
    });

    test('JSON quebrado ou incompleto devolve nulo', () {
      // Conta pela metade so produziria erro de conexao confuso mais tarde.
      expect(EmailAccount.decode('{nao e json'), isNull);
      expect(EmailAccount.decode('{"email": "a@b.c"}'), isNull);
      expect(EmailAccount.decode('["lista"]'), isNull);
    });

    test('o login cai no endereço quando nao ha usuario proprio', () {
      expect(_conta.login, 'eu@exemplo.com');
      expect(_conta.copyWith(usuario: 'outro').login, 'outro');
    });

    test('o provedor e reconhecido pelo host', () {
      expect(ProvedorEmail.porHost('imap.gmail.com'), ProvedorEmail.gmail);
      expect(ProvedorEmail.porHost('mail.empresa.com'), ProvedorEmail.manual);
    });

    test('a conta do Google ja vem com o servidor certo', () {
      final conta = EmailAccount.google('eu@gmail.com');

      expect(conta.host, 'imap.gmail.com');
      expect(conta.porta, 993);
      expect(conta.auth, TipoAuth.google);
    });

    test('o tipo de autenticaçao sobrevive ao texto guardado', () {
      final conta = EmailAccount.google('eu@gmail.com');
      expect(EmailAccount.decode(conta.encode())?.auth, TipoAuth.google);
    });

    test('conta gravada antes do Google existir vale como senha de app', () {
      // Formato antigo, sem o campo `auth`.
      final antiga = EmailAccount.decode(
        '{"email":"a@b.c","host":"imap.b.c","porta":993,"caixa":"INBOX"}',
      );

      expect(antiga?.auth, TipoAuth.senhaDeApp);
    });
  });

  group('EmailMessage', () {
    test('assunto vazio ganha rotulo em vez de linha em branco', () {
      expect(mensagemFalsa(uid: 1, assunto: '   ').titulo, '(sem assunto)');
    });

    test('mostra o nome quando ha um, senao o endereço', () {
      expect(mensagemFalsa(uid: 1, nome: 'Fulano').quem, 'Fulano');
      expect(mensagemFalsa(uid: 1).quem, 'alguem@exemplo.com');
      expect(mensagemFalsa(uid: 1, nome: '  ').quem, 'alguem@exemplo.com');
    });

    test('a previa pula linhas vazias e citaçoes', () {
      final m = mensagemFalsa(
        uid: 1,
        corpo: '\n\n> texto citado\nEsta e a resposta.',
      );
      expect(m.previa, 'Esta e a resposta.');
    });

    test('o filtro olha remetente, assunto e corpo', () {
      final m = mensagemFalsa(
        uid: 1,
        assunto: 'Reuniao',
        corpo: 'Sobre o orçamento',
      );

      expect(m.combina(''), isTrue);
      expect(m.combina('reuni'), isTrue);
      expect(m.combina('EXEMPLO'), isTrue);
      expect(m.combina('orçamento'), isTrue);
      expect(m.combina('nada disso'), isFalse);
    });
  });

  group('HTML para texto', () {
    test('tira as tags e mantem as quebras', () {
      final texto = EmailService.htmlParaTexto(
        '<p>Primeira</p><p>Segunda<br>com quebra</p>',
      );

      expect(texto, 'Primeira\nSegunda\ncom quebra');
    });

    test('descarta script e style junto com o conteudo deles', () {
      final texto = EmailService.htmlParaTexto(
        '<style>.a{color:red}</style><p>Visivel</p>'
        '<script>rastrear()</script>',
      );

      expect(texto, 'Visivel');
    });

    test('converte as entidades mais comuns', () {
      expect(
        EmailService.htmlParaTexto('<p>a &amp; b &lt;c&gt; &quot;d&quot;</p>'),
        'a & b <c> "d"',
      );
    });

    test('nao deixa blocos de linhas em branco', () {
      final texto = EmailService.htmlParaTexto(
        '<div>Um</div><div></div><div></div><div></div><div>Dois</div>',
      );

      expect(texto, 'Um\n\nDois');
    });
  });

  group('painel', () {
    setUp(UiPrefs.resetForTesting);

    testWidgets('sem conta, o botao do Google e o caminho principal', (
      tester,
    ) async {
      AcaoConta? pedida;
      await _montarPainel(tester, onConta: (a) => pedida = a);

      expect(find.text('Nenhuma conta ligada'), findsOneWidget);

      await tester.tap(find.text('Entrar com o Google'));
      expect(pedida, AcaoConta.entrarComGoogle);
    });

    testWidgets('sem conta, a senha de app continua disponivel', (
      tester,
    ) async {
      AcaoConta? pedida;
      await _montarPainel(tester, onConta: (a) => pedida = a);

      await tester.tap(find.text('Outro provedor, com senha de app'));
      expect(pedida, AcaoConta.senhaDeApp);
    });

    testWidgets('enquanto o navegador esta aberto, os botoes travam', (
      tester,
    ) async {
      // Dois consentimentos ao mesmo tempo abririam dois servidores locais, e
      // so um deles receberia a volta do navegador.
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmailScreen(
              conta: null,
              mensagens: const [],
              carregando: false,
              erro: null,
              entrando: true,
              onRefresh: () {},
              onConta: (_) {},
            ),
          ),
        ),
      );
      // `pump` e nao `pumpAndSettle`: o indicador de espera gira sem parar, e
      // esperar ele assentar nunca terminaria.
      await tester.pump();

      expect(find.text('Aguardando o navegador...'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    });

    testWidgets('lista as mensagens com remetente e assunto', (tester) async {
      await _montarPainel(
        tester,
        conta: _conta,
        mensagens: [
          mensagemFalsa(uid: 1, nome: 'Ana', assunto: 'Primeira'),
          mensagemFalsa(uid: 2, nome: 'Bruno', assunto: 'Segunda'),
        ],
      );

      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Primeira'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
    });

    testWidgets('clicar abre o corpo da mensagem', (tester) async {
      await _montarPainel(
        tester,
        conta: _conta,
        mensagens: [
          mensagemFalsa(
            uid: 1,
            assunto: 'Convite',
            // A previa na lista mostra so a primeira linha, entao a segunda
            // serve para distinguir "aberta" de "listada".
            corpo: 'Primeira linha.\nSo aparece ao abrir.',
          ),
        ],
      );

      expect(find.textContaining('So aparece ao abrir.'), findsNothing);

      await tester.tap(find.text('Convite'));
      await tester.pumpAndSettle();

      expect(find.textContaining('So aparece ao abrir.'), findsOneWidget);
    });

    testWidgets('o filtro esconde o que nao combina', (tester) async {
      await _montarPainel(
        tester,
        conta: _conta,
        mensagens: [
          mensagemFalsa(uid: 1, assunto: 'Contrato'),
          mensagemFalsa(uid: 2, assunto: 'Ferias'),
        ],
      );

      await tester.enterText(find.byType(TextField), 'ferias');
      await tester.pumpAndSettle();

      expect(find.text('Ferias'), findsOneWidget);
      expect(find.text('Contrato'), findsNothing);
    });

    testWidgets('erro de senha explica que precisa de senha de app', (
      tester,
    ) async {
      await _montarPainel(
        tester,
        conta: _conta,
        erro: const EmailException(FalhaEmail.credenciais),
      );

      expect(find.textContaining('senha de app'), findsOneWidget);
      expect(find.text('Rever a conta'), findsOneWidget);
    });

    testWidgets('caixa vazia nao vira tela de erro', (tester) async {
      await _montarPainel(tester, conta: _conta);

      expect(find.text('Caixa de entrada vazia'), findsOneWidget);
    });
  });

  group('na tela principal', () {
    setUp(UiPrefs.resetForTesting);

    Future<void> montar(WidgetTester tester, FakeEmail email) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: VaultScreen(repository: FakeVault(), email: email),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('o e-mail so e buscado quando o painel esta a vista', (
      tester,
    ) async {
      final email = FakeEmail(conta: _conta);
      await montar(tester, email);

      // Painel fechado: nao custa uma conexao IMAP.
      expect(email.buscas, 0);

      await tester.tap(find.byKey(const ValueKey('rail-item-email')));
      await tester.pumpAndSettle();

      expect(email.buscas, 1);
    });

    testWidgets('o botao do Google pede o cadastro na primeira vez', (
      tester,
    ) async {
      final email = FakeEmail();
      await montar(tester, email);

      await tester.tap(find.byKey(const ValueKey('rail-item-email')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entrar com o Google'));
      await tester.pumpAndSettle();

      // Sem Client ID guardado, o passo a passo do Google Cloud vem antes.
      expect(find.text('Cadastrar o app no Google'), findsOneWidget);
      expect(email.loginsComGoogle, 0);
    });

    testWidgets('com o cadastro feito, o botao vai direto ao login', (
      tester,
    ) async {
      final email = FakeEmail()
        ..clientId = 'ja-cadastrado.apps.googleusercontent.com';
      await montar(tester, email);

      await tester.tap(find.byKey(const ValueKey('rail-item-email')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entrar com o Google'));
      await tester.pumpAndSettle();

      expect(find.text('Cadastrar o app no Google'), findsNothing);
      expect(email.loginsComGoogle, 1);
    });

    testWidgets('login recusado vira erro na tela, e nao um travamento', (
      tester,
    ) async {
      final email = FakeEmail()
        ..clientId = 'ja-cadastrado.apps.googleusercontent.com'
        ..erroDeLogin = const EmailException(
          FalhaEmail.credenciais,
          'Voce recusou o acesso na tela do Google.',
        );
      await montar(tester, email);

      await tester.tap(find.byKey(const ValueKey('rail-item-email')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entrar com o Google'));
      await tester.pumpAndSettle();

      expect(find.textContaining('recusou o acesso'), findsOneWidget);
      // O botao volta a funcionar em vez de ficar preso em "aguardando".
      expect(find.text('Aguardando o navegador...'), findsNothing);
    });

    testWidgets('a aba de e-mail abre mesmo sem vault escolhido', (
      tester,
    ) async {
      // O e-mail nao sai do vault: nao ha motivo para depender dele.
      final email = FakeEmail(
        conta: _conta,
        mensagens: [mensagemFalsa(uid: 1, assunto: 'Chegou')],
      );
      await montar(tester, email);

      await tester.tap(find.byKey(const ValueKey('rail-item-email')));
      await tester.pumpAndSettle();

      expect(find.text('Chegou'), findsOneWidget);
      expect(find.text('Escolha a pasta do vault'), findsNothing);
    });
  });
}
