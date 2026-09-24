/// Onde um bloco novo — tabela, quadro — entra no texto da nota.
///
/// Tabela e quadro sao coisas diferentes, mas entram do mesmo jeito: precisam
/// de linha em branco em volta para o Markdown le-los como bloco proprio.
/// Colados num paragrafo, viram mais uma linha dele.
abstract final class BlocoNoTexto {
  /// Escreve [bloco] em [texto], na posiçao [cursor], com a folga que faltar em
  /// volta. Devolve tambem onde o bloco começou, para o editor levar o cursor
  /// — ou o foco — para dentro dele.
  static ({String texto, int inicio}) inserir(
    String texto,
    int cursor,
    String bloco,
  ) {
    final ponto = cursor.clamp(0, texto.length);
    final antes = _folgaAntes(texto.substring(0, ponto));
    final depois = _folgaDepois(texto.substring(ponto));

    return (
      texto: texto.replaceRange(ponto, ponto, '$antes$bloco$depois'),
      inicio: ponto + antes.length,
    );
  }

  /// Sao as quebras que faltam, e nao duas fixas: inserir num ponto que ja esta
  /// separado abriria um buraco no meio da nota.
  static String _folgaAntes(String antes) {
    if (antes.trim().isEmpty) return '';
    return '\n' * (2 - _quebrasNoFim(antes)).clamp(0, 2);
  }

  /// Do outro lado a conta e a mesma, com um detalhe: no fim do arquivo basta
  /// uma quebra, que e o que fecha a ultima linha do bloco.
  static String _folgaDepois(String depois) {
    if (depois.trim().isEmpty) return '\n';
    return '\n' * (2 - _quebrasNoComeco(depois)).clamp(0, 2);
  }

  static int _quebrasNoFim(String texto) {
    var quantas = 0;
    while (quantas < texto.length &&
        texto[texto.length - 1 - quantas] == '\n') {
      quantas++;
    }
    return quantas;
  }

  static int _quebrasNoComeco(String texto) {
    var quantas = 0;
    while (quantas < texto.length && texto[quantas] == '\n') {
      quantas++;
    }
    return quantas;
  }
}
