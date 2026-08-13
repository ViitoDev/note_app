import '../models/email_account.dart';
import '../models/email_message.dart';

/// Contrato de acesso ao e-mail usado pela interface.
///
/// Existe pelo mesmo motivo do [VaultRepository]: a tela nao pode depender do
/// IMAP. Sem ele, testar o painel exigiria um servidor de verdade.
abstract interface class EmailRepository {
  /// A conta configurada, ou nulo se ainda nao houver nenhuma.
  Future<EmailAccount?> loadAccount();

  /// Guarda a conta e a senha. A senha vai cifrada; a conta, nao.
  Future<void> save(EmailAccount conta, String senha);

  /// Liga uma conta a partir so de endereço e senha.
  ///
  /// Descobre o servidor, confere a senha entrando de verdade e so entao
  /// guarda. [manual] pula a descoberta, para quando o servidor nao e
  /// adivinhavel. Lanca [EmailException] com o motivo se nao der.
  Future<EmailAccount> ligarComSenha(
    String email,
    String senha, {
    EmailAccount? manual,
  });

  /// O Client ID ja cadastrado no Google Cloud, ou nulo se ainda nao houver.
  /// Usado so pela tela, para saber se precisa pedir o cadastro.
  Future<String?> loadClientId();

  /// Abre o consentimento do Google no navegador e guarda o resultado.
  ///
  /// [clientId] e [clientSecret] vem do projeto do usuario no Google Cloud;
  /// nulos reaproveitam os ja guardados.
  Future<EmailAccount> loginComGoogle({String? clientId, String? clientSecret});

  /// Apaga conta e senha.
  Future<void> forget();

  /// Le as mensagens mais recentes da caixa configurada, da mais nova para a
  /// mais antiga. Lanca [EmailException] quando nao consegue.
  Future<List<EmailMessage>> fetchInbox({int limite});
}
