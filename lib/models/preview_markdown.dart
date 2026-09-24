import 'package:markdown/markdown.dart' as md;

import 'quadro_da_nota.dart';
import 'wikilink.dart';

/// O que o preview faz com o texto da nota antes de desenha-lo.
///
/// Nada disso e gravado: o `.md` continua exatamente como foi escrito. Sao
/// ajustes de leitura, aplicados no caminho entre o arquivo e a tela.
abstract final class PreviewMarkdown {
  static String preparar(String corpo) => Wikilink.paraMarkdown(
    _seta(_linhaEmBranco(_finalizarLista(_saidaDaLista(_itemVazio(corpo))))),
  );

  /// As extensoes do parser, usadas em todo lugar que le o corpo da nota.
  ///
  /// `gitHubWeb` traz o que se espera de Markdown moderno — tabela, lista de
  /// tarefa, ~~riscado~~ —, e na frente dele vem a cerca do quadro: ela precisa
  /// ser reconhecida *antes* de a cerca virar bloco de codigo, senao o quadro
  /// aparece no preview como um punhado de JSON.
  static final extensoes = md.ExtensionSet([
    const _CercaDeQuadro(),
    ...md.ExtensionSet.gitHubWeb.blockSyntaxes,
  ], md.ExtensionSet.gitHubWeb.inlineSyntaxes);

  /// De cada bloco ``` para a linguagem escrita na cerca dele.
  ///
  /// Quem desenha o bloco recebe so o texto de dentro dele, sem a cerca — e
  /// portanto sem a linguagem. Este mapa faz a ponte, e e montado pelo mesmo
  /// parser que desenha o preview: a chave sai exatamente igual ao texto que
  /// vai chegar la, sem depender de recontar recuo ou fim de linha na mao.
  static Map<String, String> linguagensDeCodigo(String corpo) {
    final linhas = corpo.split('\n');
    final documento = md.Document(extensionSet: extensoes);

    final mapa = <String, String>{};
    void varrer(List<md.Node> nos) {
      for (final no in nos) {
        if (no is! md.Element) continue;

        final classe = no.attributes['class'];
        if (no.tag == 'code' && classe != null) {
          final lingua = classe
              .split(' ')
              .firstWhere((c) => c.startsWith('language-'), orElse: () => '');
          if (lingua.length > 'language-'.length) {
            mapa[_semEscape(no.textContent).trimRight()] = lingua
                .substring('language-'.length)
                .toLowerCase();
          }
        }

        final filhos = no.children;
        if (filhos != null) varrer(filhos);
      }
    }

    varrer(documento.parseLines(linhas));
    return mapa;
  }

  /// Desfaz o escape de HTML que o parser aplica ao texto.
  ///
  /// O parser guarda o conteudo pronto para virar HTML — uma aspa dentro do
  /// codigo vira `&quot;` la dentro. Quem desenha recebe o texto cru, entao a
  /// chave tem que voltar a ser crua tambem, senao todo bloco com aspas deixa
  /// de ser encontrado. `&amp;` por ultimo: antes dele, `&amp;lt;` viraria `<`.
  static String _semEscape(String texto) => texto
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

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

  /// Uma linha em branco entre dois itens do mesmo tipo de lista — mesmo
  /// marcador, mesmo recuo — e o pedido de separar uma lista da outra.
  ///
  /// O Markdown le esses dois blocos como uma lista so, so que "soltas"
  /// (cada item vira um paragrafo por dentro): a linha em branco que devia
  /// separar as duas listas so muda o espaçamento interno de uma lista unica,
  /// e o corte que a pessoa pediu desaparece.
  ///
  /// Um paragrafo de largura zero entre as duas encerra a primeira lista de
  /// verdade — o que vem depois da linha em branco deixa de ser item, entao a
  /// lista acaba ali e a proxima começa do zero, como duas listas de fato.
  static final _finalDeLista = RegExp(
    // Codigo primeiro, como nas outras passadas.
    r'(```.*?```|~~~.*?~~~)'
    r'|(^([ \t]*)([-*+])[ \t][^\n]*)\n[ \t]*\n(?=\3\4[ \t])'
    r'|(^([ \t]*)\d+([.)])[ \t][^\n]*)\n[ \t]*\n(?=\6\d+\7[ \t])',
    multiLine: true,
    dotAll: true,
  );

  static String _finalizarLista(String corpo) {
    return corpo.replaceAllMapped(_finalDeLista, (m) {
      final codigo = m.group(1);
      if (codigo != null) return codigo;
      final linha = m.group(2) ?? m.group(5)!;
      return '$linha\n\n$_larguraZero\n\n';
    });
  }

  /// `->` solto no meio do texto e uma seta, e e como seta que ele e lido.
  ///
  /// Digitando, o `->` ja vira `→` no proprio texto. Esta passada e para o que
  /// foi escrito antes disso — e para quem escreve o `.md` em outro editor: a
  /// nota antiga passa a ser *lida* com a seta sem que uma linha do arquivo
  /// mude. E o mesmo trato dos `[[links]]`.
  ///
  /// Solto, e nao qualquer um: `ptr->campo` e codigo mesmo fora da crase, e
  /// `-->` foi escrito assim de proposito. A regra e a mesma da tecla.
  static final _setas = RegExp(
    // Codigo primeiro — inclusive o de uma crase so, na mesma linha.
    r'(```.*?```|~~~.*?~~~|`[^`\n]*`)'
    r'|(?<![^\s])->(?![^\s])',
    multiLine: true,
    dotAll: true,
  );

  static String _seta(String corpo) {
    return corpo.replaceAllMapped(_setas, (m) {
      final codigo = m.group(1);
      return codigo ?? '→';
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

/// A cerca ```quadro vira um no proprio da arvore, e nao um bloco de codigo.
///
/// O parser nao sabe desenhar quadro nenhum — e nem precisa. Ele so separa o
/// bloco do resto e entrega o conteudo inteiro num no de tag
/// [QuadroDaNota.marcador]; quem desenha e o preview, que reconhece essa tag e
/// monta o widget do quadro no lugar dela.
class _CercaDeQuadro extends md.BlockSyntax {
  const _CercaDeQuadro();

  @override
  RegExp get pattern =>
      RegExp('^ {0,3}(```|~~~)[ \t]*${QuadroDaNota.marcador}[ \t]*\$');

  @override
  md.Node parse(md.BlockParser parser) {
    final marca = pattern.firstMatch(parser.current.content)!.group(1)!;
    final fechamento = RegExp('^ {0,3}$marca[ \t]*\$');

    parser.advance();
    final dentro = <String>[];
    while (!parser.isDone && !fechamento.hasMatch(parser.current.content)) {
      dentro.add(parser.current.content);
      parser.advance();
    }
    // A cerca de baixo e consumida junto: ela pertence a este bloco, e deixada
    // para tras abriria um bloco de codigo vazio na linha seguinte.
    if (!parser.isDone) parser.advance();

    return md.Element.text(QuadroDaNota.marcador, dentro.join('\n'));
  }
}
