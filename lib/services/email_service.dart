import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/email_account.dart';
import '../models/email_message.dart';
import '../repositories/email_repository.dart';
import 'email_autoconfig.dart';
import 'google_auth.dart';
import 'secret_store.dart';

/// Leitura da caixa de entrada por IMAP.
///
/// So le: nao marca como lida, nao apaga, nao envia. A busca usa `BODY.PEEK[]`
/// justamente por isso — `BODY[]` marcaria como lida toda mensagem aberta pelo
/// painel, o que mexeria na caixa de quem so queria dar uma olhada daqui.
class EmailService implements EmailRepository {
  EmailService({
    this.cofre = const SecretStore(),
    this.google = const GoogleAuth(),
    this.autoconfig = const EmailAutoconfig(),
  });

  /// Descobre o servidor a partir do endereço.
  final EmailAutoconfig autoconfig;

  /// Injetavel para o teste nao depender do DPAPI, que so existe no Windows.
  final SecretStore cofre;

  /// Injetavel para o teste nao abrir navegador nem falar com o Google.
  final GoogleAuth google;

  static const _chaveConta = 'email_conta';
  static const _chaveSenha = 'email_senha';
  static const _chaveClientId = 'email_google_client_id';
  static const _chaveClientSecret = 'email_google_client_secret';
  static const _chaveRefresh = 'email_google_refresh';

  /// Token de acesso em memoria, com a hora em que ele deixa de valer.
  ///
  /// Fica so aqui, nunca em disco: dura cerca de uma hora, e guardar algo tao
  /// perecivel so criaria mais um segredo para proteger sem ganho nenhum.
  String? _acesso;
  DateTime? _acessoAte;

  @override
  Future<EmailAccount?> loadAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return EmailAccount.decode(prefs.getString(_chaveConta));
  }

  @override
  Future<void> save(EmailAccount conta, String senha) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveConta, conta.encode());
    await cofre.write(_chaveSenha, senha);
  }

  @override
  Future<EmailAccount> ligarComSenha(
    String email,
    String senha, {
    EmailAccount? manual,
  }) async {
    final conta = manual ?? await autoconfig.descobrir(email);
    if (conta == null) {
      throw const EmailException(
        FalhaEmail.conexao,
        'Nao encontrei o servidor deste dominio. Escolha o provedor na lista '
        'ou informe o servidor IMAP em "Servidor".',
      );
    }

    // Entra de verdade antes de guardar: uma conta que so falha na primeira
    // leitura deixaria o usuario achando que ligou e o painel mudo.
    await _entrar(conta, senha: senha, aoConectar: (_) async {});
    await save(conta, senha);
    return conta;
  }

  @override
  Future<String?> loadClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_chaveClientId);
  }

  @override
  Future<EmailAccount> loginComGoogle({
    String? clientId,
    String? clientSecret,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final id = clientId ?? prefs.getString(_chaveClientId);
    final segredo = clientSecret ?? await cofre.read(_chaveClientSecret);
    if (id == null || id.isEmpty) {
      throw const EmailException(
        FalhaEmail.credenciais,
        'Falta o Client ID do Google.',
      );
    }

    final sessao = await google.login(
      clientId: id,
      clientSecret: segredo ?? '',
    );

    final conta = EmailAccount.google(sessao.email);
    await prefs.setString(_chaveConta, conta.encode());
    await prefs.setString(_chaveClientId, id);
    await cofre.write(_chaveClientSecret, segredo ?? '');
    await cofre.write(_chaveRefresh, sessao.refreshToken);

    // Sessao nova invalida o token da anterior.
    _acesso = null;
    _acessoAte = null;

    return conta;
  }

  @override
  Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveConta);
    await cofre.delete(_chaveSenha);
    await cofre.delete(_chaveRefresh);
    _acesso = null;
    _acessoAte = null;
  }

  /// Token de acesso do Google, renovado quando necessario.
  ///
  /// A margem de um minuto evita o caso chato: um token que ainda vale na hora
  /// da conferencia e expira no meio do handshake do IMAP.
  Future<String> _tokenDeAcesso() async {
    final agora = DateTime.now();
    final ate = _acessoAte;
    final atual = _acesso;
    if (atual != null && ate != null && agora.isBefore(ate)) return atual;

    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_chaveClientId);
    final segredo = await cofre.read(_chaveClientSecret);
    final refresh = await cofre.read(_chaveRefresh);

    if (id == null || refresh == null) {
      throw const EmailException(
        FalhaEmail.credenciais,
        'A conta do Google precisa ser ligada de novo.',
      );
    }

    final token = await google.accessToken(
      clientId: id,
      clientSecret: segredo ?? '',
      refreshToken: refresh,
    );

    _acesso = token;
    _acessoAte = agora.add(const Duration(minutes: 55));
    return token;
  }

  @override
  Future<List<EmailMessage>> fetchInbox({int limite = 40}) async {
    final conta = await loadAccount();
    if (conta == null) {
      throw const EmailException(FalhaEmail.credenciais, 'Conta nao definida.');
    }

    return _entrar(
      conta,
      aoConectar: (client) async {
        final Mailbox caixa;
        try {
          caixa = await client.selectMailboxByPath(conta.caixa);
        } on ImapException catch (e) {
          throw EmailException(FalhaEmail.caixaInexistente, e.message);
        }

        // Caixa vazia: `fetchRecentMessages` numa caixa sem mensagens vira um
        // intervalo invalido no servidor, entao nem chega a pedir.
        if (caixa.messagesExists == 0) return const <EmailMessage>[];

        final resultado = await client.fetchRecentMessages(
          messageCount: limite,
          criteria: '(FLAGS BODY.PEEK[])',
        );

        return [
          for (final (i, m) in resultado.messages.indexed) _converter(m, i),
        ]..sort((a, b) => b.data.compareTo(a.data));
      },
    );
  }

  /// Conecta, autentica e roda [aoConectar] com a sessao aberta.
  ///
  /// Ligar a conta e ler a caixa fazem exatamente os mesmos tres primeiros
  /// passos, e sao neles que mora toda a classificaçao de erro — duplicar isso
  /// seria duplicar tambem os lugares onde errar.
  Future<T> _entrar<T>(
    EmailAccount conta, {
    required Future<T> Function(ImapClient client) aoConectar,
    String? senha,
  }) async {
    // Cada tipo de conta prova a identidade de um jeito, e o segredo de cada
    // um mora numa chave diferente do cofre.
    String? token;
    var chave = senha;
    if (chave == null) {
      if (conta.auth == TipoAuth.google) {
        token = await _tokenDeAcesso();
      } else {
        chave = await cofre.read(_chaveSenha);
        if (chave == null) {
          throw const EmailException(
            FalhaEmail.credenciais,
            'A senha nao esta guardada.',
          );
        }
      }
    }

    final client = ImapClient();
    try {
      try {
        await client.connectToServer(conta.host, conta.porta);
      } on Exception catch (e) {
        // Nao chegou a falar IMAP: DNS, firewall, porta, TLS.
        throw EmailException(FalhaEmail.conexao, '$e');
      }

      try {
        if (token != null) {
          await client.authenticateWithOAuth2(conta.login, token);
        } else {
          await client.login(conta.login, chave!);
        }
      } on ImapException catch (e) {
        throw EmailException(FalhaEmail.credenciais, e.message);
      }

      return await aoConectar(client);
    } on EmailException {
      rethrow;
    } on SocketException catch (e) {
      throw EmailException(FalhaEmail.conexao, e.message);
    } on TimeoutException {
      throw const EmailException(FalhaEmail.conexao, 'O servidor demorou.');
    } on Exception catch (e) {
      throw EmailException(FalhaEmail.desconhecida, '$e');
    } finally {
      // Fechar nao pode derrubar uma leitura que ja deu certo.
      try {
        if (client.isLoggedIn) await client.logout();
      } on Exception {
        // ignorado de proposito
      }
      client.disconnect().ignore();
    }
  }

  /// Reduz a mensagem MIME ao punhado de campos que a tela usa.
  static EmailMessage _converter(MimeMessage m, int posicao) {
    final de = m.from?.firstOrNull;

    return EmailMessage(
      // Nem todo servidor devolve UID nesta busca; a posiçao serve de
      // identidade estavel dentro da lista que acabou de ser lida.
      uid: m.uid ?? m.sequenceId ?? posicao,
      remetente: de?.email ?? '(desconhecido)',
      nomeRemetente: de?.personalName,
      assunto: m.decodeSubject() ?? '',
      data: m.decodeDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      corpo: _corpoEmTexto(m),
      lida: m.isSeen,
    );
  }

  /// Texto puro da mensagem.
  ///
  /// Quando so ha HTML, ele e reduzido a texto em vez de renderizado: o painel
  /// e estreito, e desenhar HTML de e-mail traria fontes, tabelas de layout e
  /// pixels de rastreamento junto.
  static String _corpoEmTexto(MimeMessage m) {
    final texto = m.decodeTextPlainPart();
    if (texto != null && texto.trim().isNotEmpty) return texto.trim();

    final html = m.decodeTextHtmlPart();
    if (html != null && html.trim().isNotEmpty) return htmlParaTexto(html);

    return '';
  }

  /// Conversao de HTML para texto legivel.
  ///
  /// Deliberadamente simples: e-mail tem HTML mal formado demais para valer um
  /// parser completo, e o objetivo aqui e so poder ler a mensagem.
  static String htmlParaTexto(String html) {
    final texto = html
        // Script e style carregam conteudo que nao e texto da mensagem.
        .replaceAll(
          RegExp(
            r'<(script|style)[^>]*>.*?</\1>',
            dotAll: true,
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp('<br[^>]*>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp('</(p|div|tr|li|h[1-6])>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    // Sobra muita linha em branco depois de tirar as tags de layout.
    return texto
        .split('\n')
        .map((l) => l.trim())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
