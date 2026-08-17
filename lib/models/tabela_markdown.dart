import 'tabela_da_nota.dart';

/// Onde uma tabela nova entra no texto da nota.
///
/// O cabeçalho nao e opcional: sem ele, e sem a linha de tracinhos logo abaixo,
/// o que se escreve entre barras continua sendo texto com barras, e nao vira
/// tabela nenhuma. Por isso a primeira linha escolhida na grade e sempre o
/// cabeçalho, e nao uma linha de dados a mais.
abstract final class TabelaMarkdown {
  /// A maior tabela que a grade oferece.
  ///
  /// Nao e limite do Markdown, e de leitura: passando disso a tabela deixa de
  /// caber na largura do preview, e o que se ganha em celulas se perde em
  /// linha quebrada.
  static const maxLinhas = 20;
  static const maxColunas = 12;

  /// Escreve uma tabela vazia em [texto], na posiçao [cursor].
  ///
  /// Devolve tambem onde ela começou, para o editor por o cursor na primeira
  /// celula dela.
  static ({String texto, int inicio}) inserir(
    String texto,
    int cursor, {
    required int linhas,
    required int colunas,
  }) {
    final ponto = cursor.clamp(0, texto.length);
    final antes = _folgaAntes(texto.substring(0, ponto));
    final depois = _folgaDepois(texto.substring(ponto));
    final tabela = TabelaDaNota.vazia(linhas: linhas, colunas: colunas);

    return (
      texto: texto.replaceRange(
        ponto,
        ponto,
        '$antes${tabela.markdown}$depois',
      ),
      inicio: ponto + antes.length,
    );
  }

  /// Uma tabela precisa de linha em branco antes dela para ser lida como
  /// tabela; colada num paragrafo, vira mais uma linha dele.
  ///
  /// Sao as que faltam, e nao duas fixas: inserir num ponto que ja esta
  /// separado abriria um buraco no meio da nota.
  static String _folgaAntes(String antes) {
    if (antes.trim().isEmpty) return '';
    return '\n' * (2 - _quebrasNoFim(antes)).clamp(0, 2);
  }

  /// Do outro lado a conta e a mesma, com um detalhe: no fim do arquivo basta
  /// uma quebra, que e o que fecha a ultima linha da tabela.
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
