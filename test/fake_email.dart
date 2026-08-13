import 'package:notas_app/models/email_account.dart';
import 'package:notas_app/models/email_message.dart';
import 'package:notas_app/repositories/email_repository.dart';

/// Caixa de entrada falsa, para a tela rodar sem servidor IMAP.
class FakeEmail implements EmailRepository {
  FakeEmail({this.conta, this.mensagens = const [], this.erro});

  EmailAccount? conta;
  List<EmailMessage> mensagens;

  /// Quando preenchido, [fetchInbox] falha com ele em vez de devolver a lista.
  EmailException? erro;

  int buscas = 0;
  int loginsComGoogle = 0;
  String? senhaGuardada;
  String? clientId;

  /// Conta que o login com o Google devolve, se ele for chamado.
  EmailAccount contaDoGoogle = EmailAccount.google('eu@gmail.com');

  /// Quando preenchido, [loginComGoogle] falha com ele.
  EmailException? erroDeLogin;

  @override
  Future<EmailAccount?> loadAccount() async => conta;

  /// Conta que [ligarComSenha] devolve. Nula faz a chamada falhar.
  EmailAccount? contaDaSenha;

  /// Quando preenchido, [ligarComSenha] falha com ele.
  EmailException? erroDaSenha;

  int ligacoesComSenha = 0;

  @override
  Future<EmailAccount> ligarComSenha(
    String email,
    String senha, {
    EmailAccount? manual,
  }) async {
    ligacoesComSenha++;
    final falha = erroDaSenha;
    if (falha != null) throw falha;

    final nova =
        manual ??
        contaDaSenha ??
        EmailAccount(email: email, host: 'imap.exemplo.com');
    conta = nova;
    senhaGuardada = senha;
    return nova;
  }

  @override
  Future<String?> loadClientId() async => clientId;

  @override
  Future<EmailAccount> loginComGoogle({
    String? clientId,
    String? clientSecret,
  }) async {
    loginsComGoogle++;
    if (clientId != null) this.clientId = clientId;
    final falha = erroDeLogin;
    if (falha != null) throw falha;
    conta = contaDoGoogle;
    return contaDoGoogle;
  }

  @override
  Future<void> save(EmailAccount conta, String senha) async {
    this.conta = conta;
    senhaGuardada = senha;
  }

  @override
  Future<void> forget() async {
    conta = null;
    senhaGuardada = null;
  }

  @override
  Future<List<EmailMessage>> fetchInbox({int limite = 40}) async {
    buscas++;
    final falha = erro;
    if (falha != null) throw falha;
    return mensagens.take(limite).toList();
  }
}

EmailMessage mensagemFalsa({
  required int uid,
  String remetente = 'alguem@exemplo.com',
  String? nome,
  String assunto = 'Assunto',
  String corpo = 'Corpo da mensagem.',
  DateTime? data,
  bool lida = false,
}) => EmailMessage(
  uid: uid,
  remetente: remetente,
  nomeRemetente: nome,
  assunto: assunto,
  corpo: corpo,
  data: data ?? DateTime(2026, 8, 7, 10),
  lida: lida,
);
