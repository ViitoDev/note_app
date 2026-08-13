import 'package:flutter/foundation.dart';

/// Uma mensagem da caixa de entrada, ja reduzida ao que a tela mostra.
///
/// O objeto do `enough_mail` nao passa daqui de proposito: ele carrega o MIME
/// inteiro, com anexos e cabeçalhos, e deixar isso vazar para a UI amarraria a
/// tela a biblioteca de IMAP.
@immutable
class EmailMessage {
  const EmailMessage({
    required this.uid,
    required this.remetente,
    required this.assunto,
    required this.data,
    required this.corpo,
    this.nomeRemetente,
    this.lida = false,
  });

  final int uid;
  final String remetente;
  final String? nomeRemetente;
  final String assunto;
  final DateTime data;

  /// Texto puro. HTML e convertido antes de chegar aqui — o painel e estreito
  /// e renderizar HTML de e-mail traria fontes, tabelas e rastreadores junto.
  final String corpo;

  final bool lida;

  /// O que aparece na lista: o nome, se houver, senao o endereço.
  String get quem => nomeRemetente?.trim().isNotEmpty ?? false
      ? nomeRemetente!.trim()
      : remetente;

  /// Assunto vazio e comum o bastante para valer um rotulo proprio, em vez de
  /// uma linha em branco na lista.
  String get titulo =>
      assunto.trim().isEmpty ? '(sem assunto)' : assunto.trim();

  /// Primeira linha util do corpo, para a previa embaixo do assunto.
  String get previa {
    for (final linha in corpo.split('\n')) {
      final limpa = linha.trim();
      // Linha de citaçao nao diz nada sobre a mensagem nova.
      if (limpa.isNotEmpty && !limpa.startsWith('>')) {
        return limpa.length > 120 ? '${limpa.substring(0, 120)}...' : limpa;
      }
    }
    return '';
  }

  bool combina(String filtro) {
    final alvo = filtro.trim().toLowerCase();
    if (alvo.isEmpty) return true;
    return assunto.toLowerCase().contains(alvo) ||
        remetente.toLowerCase().contains(alvo) ||
        (nomeRemetente?.toLowerCase().contains(alvo) ?? false) ||
        corpo.toLowerCase().contains(alvo);
  }

  @override
  bool operator ==(Object other) => other is EmailMessage && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

/// Motivo pelo qual a leitura falhou.
///
/// Existe porque as tres causas pedem respostas diferentes do usuario, e um
/// "erro de conexao" generico nao diz qual delas foi.
enum FalhaEmail {
  /// Servidor recusou usuario ou senha.
  credenciais,

  /// Nao chegou ao servidor: sem rede, host errado, porta errada.
  conexao,

  /// Conectou e autenticou, mas a caixa pedida nao existe.
  caixaInexistente,

  /// Qualquer outra coisa.
  desconhecida;

  String get mensagem => switch (this) {
    credenciais =>
      'Usuario ou senha recusados. Se a conta tem verificaçao em duas etapas, '
          'e preciso usar uma senha de app, nao a senha normal.',
    conexao =>
      'Nao foi possivel falar com o servidor. Confira o endereço, a porta e a '
          'conexao com a internet.',
    caixaInexistente => 'A caixa pedida nao existe nesta conta.',
    desconhecida => 'Nao foi possivel ler os e-mails.',
  };
}

/// Erro de leitura ja classificado.
class EmailException implements Exception {
  const EmailException(this.falha, [this.detalhe]);

  final FalhaEmail falha;
  final String? detalhe;

  @override
  String toString() =>
      detalhe == null ? falha.mensagem : '${falha.mensagem}\n\n$detalhe';
}
