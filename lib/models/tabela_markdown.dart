import 'bloco_no_texto.dart';
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
  }) => BlocoNoTexto.inserir(
    texto,
    cursor,
    TabelaDaNota.vazia(linhas: linhas, colunas: colunas).markdown,
  );
}
