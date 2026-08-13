import 'package:enough_mail/enough_mail.dart';

import '../models/email_account.dart';

/// Descobre o servidor IMAP a partir do endereço de e-mail.
///
/// Existe para o usuario nao precisar saber o que e "servidor IMAP". Ele digita
/// e-mail e senha; o resto e trabalho do app.
///
/// A busca nunca manda a senha para adivinhar: primeiro descobre *qual* e o
/// servidor, so depois tenta entrar. E as adivinhaçoes ficam restritas ao
/// dominio do proprio usuario — sair testando servidor de terceiro com a senha
/// dele na mao seria entregar credencial para quem nao devia ver.
class EmailAutoconfig {
  const EmailAutoconfig({this.sonda = _sondarDeVerdade});

  /// Injetavel para o teste nao abrir conexao de rede.
  final Future<bool> Function(String host, int porta) sonda;

  /// Provedores conhecidos pelo dominio do endereço.
  static const _porDominio = <String, ProvedorEmail>{
    'gmail.com': ProvedorEmail.gmail,
    'googlemail.com': ProvedorEmail.gmail,
    'outlook.com': ProvedorEmail.outlook,
    'outlook.com.br': ProvedorEmail.outlook,
    'hotmail.com': ProvedorEmail.outlook,
    'hotmail.com.br': ProvedorEmail.outlook,
    'live.com': ProvedorEmail.outlook,
    'msn.com': ProvedorEmail.outlook,
    'yahoo.com': ProvedorEmail.yahoo,
    'yahoo.com.br': ProvedorEmail.yahoo,
    'zoho.com': ProvedorEmail.zoho,
    'uol.com.br': ProvedorEmail.uol,
    'bol.com.br': ProvedorEmail.uol,
    'terra.com.br': ProvedorEmail.terra,
  };

  /// O dominio depois do `@`, em minusculas.
  static String dominioDe(String email) {
    final i = email.lastIndexOf('@');
    return i < 0 ? '' : email.substring(i + 1).trim().toLowerCase();
  }

  /// Provedor conhecido para este endereço, sem tocar na rede.
  static ProvedorEmail? provedorDe(String email) =>
      _porDominio[dominioDe(email)];

  /// Descobre a conta de [email], ou nulo se nao achar.
  ///
  /// Nulo nao e erro: quer dizer que o servidor tem que ser informado a mao,
  /// que e o caso de dominio proprio hospedado fora do padrao.
  Future<EmailAccount?> descobrir(String email) async {
    final conhecido = provedorDe(email);
    if (conhecido != null) {
      return EmailAccount(
        email: email,
        host: conhecido.host,
        porta: conhecido.porta,
      );
    }

    final dominio = dominioDe(email);
    if (dominio.isEmpty) return null;

    // So nomes dentro do dominio do usuario. Sao os dois padroes que quase
    // todo provedor de dominio proprio publica.
    for (final host in ['imap.$dominio', 'mail.$dominio']) {
      if (await sonda(host, 993)) {
        return EmailAccount(email: email, host: host);
      }
    }
    return null;
  }

  /// Abre uma conexao e ve se ha um servidor IMAP do outro lado.
  ///
  /// Sem credencial nenhuma: o objetivo e so saber se o nome existe e fala
  /// IMAP, e nao entrar na conta.
  static Future<bool> _sondarDeVerdade(String host, int porta) async {
    final client = ImapClient();
    try {
      await client.connectToServer(
        host,
        porta,
        timeout: const Duration(seconds: 6),
      );
      return true;
    } on Exception {
      return false;
    } finally {
      client.disconnect().ignore();
    }
  }
}
