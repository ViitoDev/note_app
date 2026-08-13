import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Servidores conhecidos, para o usuario nao precisar caçar host e porta.
///
/// A lista e curta de proposito: cobre os provedores em que uma conta pessoal
/// costuma estar, e o modo manual atende o resto.
enum ProvedorEmail {
  gmail('Gmail / Workspace', 'imap.gmail.com', 993, senhaDeApp: true),
  outlook('Outlook / Hotmail', 'outlook.office365.com', 993, senhaDeApp: true),
  hostinger('Hostinger', 'imap.hostinger.com', 993),
  titan('Titan / HostGator', 'imap.titan.email', 993),
  locaweb('Locaweb', 'imap.locaweb.com.br', 993),
  uol('UOL / BOL', 'imap.uol.com.br', 993),
  terra('Terra', 'imap.terra.com.br', 993),
  yahoo('Yahoo', 'imap.mail.yahoo.com', 993, senhaDeApp: true),
  zoho('Zoho', 'imap.zoho.com', 993, senhaDeApp: true),
  manual('Outro (informar servidor)', '', 993);

  const ProvedorEmail(
    this.label,
    this.host,
    this.porta, {
    this.senhaDeApp = false,
  });

  final String label;
  final String host;
  final int porta;

  /// O provedor recusa a senha normal no IMAP e exige senha de app.
  ///
  /// Vale para quem tem verificaçao em duas etapas ligada por padrao — hoje,
  /// os grandes. Em hospedagem de dominio proprio a senha da caixa funciona.
  final bool senhaDeApp;

  /// O provedor cujo host bate com [host], ou [manual].
  static ProvedorEmail porHost(String host) => values.firstWhere(
    (p) => p != manual && p.host == host,
    orElse: () => manual,
  );
}

/// Como o app prova ao servidor que a conta e sua.
enum TipoAuth {
  /// Senha de app colada no formulario, valida em qualquer provedor.
  senhaDeApp,

  /// Login com o Google. O que fica guardado e um refresh token, trocado por
  /// um token de acesso novo a cada sessao — e por isso o login seguinte nao
  /// abre o navegador.
  google,
}

/// Dados de conexao de uma conta IMAP.
///
/// O segredo nao mora aqui: senha de app e refresh token vivem cifrados pelo
/// DPAPI, fora deste objeto, e por isso a conta inteira pode ser guardada em
/// texto puro sem risco.
@immutable
class EmailAccount {
  const EmailAccount({
    required this.email,
    required this.host,
    this.porta = 993,
    this.usuario,
    this.caixa = 'INBOX',
    this.auth = TipoAuth.senhaDeApp,
  });

  /// Conta do Google, com servidor ja preenchido.
  factory EmailAccount.google(String email) => EmailAccount(
    email: email,
    host: ProvedorEmail.gmail.host,
    porta: ProvedorEmail.gmail.porta,
    auth: TipoAuth.google,
  );

  final String email;
  final String host;
  final int porta;
  final TipoAuth auth;

  /// Login, quando difere do endereço. A maioria dos provedores usa o proprio
  /// e-mail, e ai isto fica nulo.
  final String? usuario;

  final String caixa;

  String get login => usuario?.trim().isNotEmpty ?? false ? usuario! : email;

  /// Toda conta precisa de endereço e servidor; sem um dos dois nao ha o que
  /// tentar conectar.
  bool get completa => email.trim().isNotEmpty && host.trim().isNotEmpty;

  EmailAccount copyWith({
    String? email,
    String? host,
    int? porta,
    String? usuario,
    String? caixa,
    TipoAuth? auth,
  }) => EmailAccount(
    email: email ?? this.email,
    host: host ?? this.host,
    porta: porta ?? this.porta,
    usuario: usuario ?? this.usuario,
    caixa: caixa ?? this.caixa,
    auth: auth ?? this.auth,
  );

  String encode() => jsonEncode({
    'email': email,
    'host': host,
    'porta': porta,
    if (usuario != null) 'usuario': usuario,
    'caixa': caixa,
    'auth': auth.name,
  });

  /// Le o formato de [encode]. Qualquer coisa fora do esperado vira nulo: uma
  /// conta pela metade so produziria erro de conexao confuso mais tarde.
  static EmailAccount? decode(String? bruto) {
    if (bruto == null || bruto.trim().isEmpty) return null;

    try {
      final json = jsonDecode(bruto);
      if (json is! Map) return null;

      final email = json['email'];
      final host = json['host'];
      if (email is! String || host is! String) return null;

      final porta = json['porta'];
      final usuario = json['usuario'];
      final caixa = json['caixa'];

      return EmailAccount(
        email: email,
        host: host,
        porta: porta is int ? porta : 993,
        usuario: usuario is String ? usuario : null,
        caixa: caixa is String && caixa.isNotEmpty ? caixa : 'INBOX',
        // Conta gravada antes do login com o Google existir nao tem o campo:
        // ela e, por definiçao, senha de app.
        auth: json['auth'] == TipoAuth.google.name
            ? TipoAuth.google
            : TipoAuth.senhaDeApp,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is EmailAccount &&
      other.email == email &&
      other.host == host &&
      other.porta == porta &&
      other.usuario == usuario &&
      other.caixa == caixa &&
      other.auth == auth;

  @override
  int get hashCode => Object.hash(email, host, porta, usuario, caixa, auth);

  @override
  String toString() => 'EmailAccount($email @ $host:$porta)';
}
