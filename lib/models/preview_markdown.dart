import 'wikilink.dart';

/// O que o preview faz com o texto da nota antes de desenha-lo.
///
/// Nada disso e gravado: o `.md` continua exatamente como foi escrito. Sao
/// ajustes de leitura, aplicados no caminho entre o arquivo e a tela.
abstract final class PreviewMarkdown {
  static String preparar(String corpo) =>
      Wikilink.paraMarkdown(_linhaEmBranco(_saidaDaLista(_itemVazio(corpo))));

  /// Uma linha que so tem o marcador da lista — `-`, `*`, `+` ou `1.` — e a
  /// linha que existe entre apertar Enter e digitar o item.
  ///
  /// Sem tratamento ela e lida como titulo, e nao como lista: no Markdown, um
  /// tracinho sozinho embaixo de um texto e a forma antiga de escrever titulo
  /// (`Texto` na linha de cima, `---` na de baixo). O resultado e o item
  /// anterior virando titulo azul no meio da lista, e desmanchando de novo
  /// quando a primeira letra e digitada.
  ///
  /// Um espaço de largura zero depois do marcador desfaz a ambiguidade — a
  /// linha deixa de ser so tracinhos e volta a ser item de lista, aparecendo
  /// como a marca vazia, no recuo certo, ate o texto chegar.
  static final _marcadorSozinho = RegExp(
    // Codigo primeiro: ali dentro o tracinho e exemplo, nao lista.
    r'(```.*?```|~~~.*?~~~)'
    r'|^([ \t]*(?:[-*+]|\d+[.)]))[ \t]*$',
    multiLine: true,
    dotAll: true,
  );

  static const _larguraZero = '​';

  static String _itemVazio(String corpo) {
    return corpo.replaceAllMapped(_marcadorSozinho, (m) {
      final codigo = m.group(1);
      if (codigo != null) return codigo;
      return '${m.group(2)} $_larguraZero';
    });
  }

  /// Texto colado embaixo de uma lista, na coluna 0, e alguem que saiu dela.
  ///
  /// O Enter num item vazio ja apaga o marcador e devolve o cursor a margem —
  /// e o jeito de encerrar a lista sem apagar nada. Mas o Markdown le uma
  /// linha nao recuada logo abaixo de um item como continuaçao *daquele item*,
  /// e ai o que se escreve depois volta para dentro da lista, com o recuo
  /// dela. No editor o texto esta na margem; no preview, aninhado.
  ///
  /// Uma linha em branco antes dela desfaz o engano: fecha a lista e o que vem
  /// depois vira paragrafo, na margem, como foi escrito. Linha recuada nao
  /// entra aqui — recuo e continuaçao pedida. Nem outro item, citaçao ou
  /// titulo, que ja sabem interromper a lista sozinhos.
  static final _linhaColadaNaLista = RegExp(
    // Codigo primeiro, como nas outras passadas.
    r'(```.*?```|~~~.*?~~~)'
    // `[^\n]*`, e nao `.*`: com `dotAll` o ponto engoliria o resto da nota.
    r'|^([ \t]*(?:[-*+]|\d+[.)])[ \t][^\n]*)\n(?=\S)(?![-*+>#])(?!\d+[.)])',
    multiLine: true,
    dotAll: true,
  );

  static String _saidaDaLista(String corpo) {
    return corpo.replaceAllMapped(_linhaColadaNaLista, (m) {
      final codigo = m.group(1);
      if (codigo != null) return codigo;
      return '${m.group(2)}\n\n';
    });
  }

  /// Linha em branco de sobra — a segunda seguida, a terceira — e respiro que
  /// alguem abriu de proposito, e o Markdown descarta: uma linha em branco ou
  /// dez separam os mesmos dois blocos do mesmo jeito. Escrevendo com o
  /// preview do lado, o espaço fica so na metade esquerda da tela.
  ///
  /// A primeira continua sendo o que sempre foi, a separaçao entre um bloco e
  /// o seguinte, com o espaçamento de paragrafo que o preview ja da. Cada uma
  /// alem dela vira um paragrafo de um espaço de largura zero: nada para ler,
  /// mas com a altura de uma linha.
  static final _linhasEmBranco = RegExp(
    // Codigo primeiro, de novo: linha em branco dentro de um bloco de codigo e
    // parte do que esta sendo mostrado.
    r'(```.*?```|~~~.*?~~~)'
    r'|\n(?:[ \t]*\n){2,}',
    multiLine: true,
    dotAll: true,
  );

  static String _linhaEmBranco(String corpo) {
    return corpo.replaceAllMapped(_linhasEmBranco, (m) {
      final codigo = m.group(1);
      if (codigo != null) return codigo;
      // Duas quebras sao a separaçao; o que passa disso foi pedido na mao.
      final sobra = '\n'.allMatches(m[0]!).length - 2;
      return '\n\n${'$_larguraZero\n\n' * sobra}';
    });
  }
}
