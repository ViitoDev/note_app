import 'bloco_no_texto.dart';
import 'quadro_da_nota.dart';

/// Onde um quadro novo entra no texto da nota.
abstract final class QuadroMarkdown {
  /// Escreve um quadro vazio em [texto], na posiçao [cursor].
  ///
  /// Vazio de proposito: o quadro nasce com a area limpa e a barra de formas a
  /// vista, do mesmo jeito que a tabela nasce sem nomes de exemplo nas celulas.
  /// Devolve onde ele começou, para o editor abrir logo aquele quadro.
  static ({String texto, int inicio}) inserir(String texto, int cursor) =>
      BlocoNoTexto.inserir(texto, cursor, QuadroDaNota.vazio.markdown);
}
