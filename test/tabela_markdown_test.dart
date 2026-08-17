import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:notas_app/models/tabela_markdown.dart';

/// Desenha o corpo pelo mesmo parser que o preview usa.
String _html(String corpo) =>
    md.markdownToHtml(corpo, extensionSet: md.ExtensionSet.gitHubWeb);

void main() {
  test('a tabela nasce vazia, so com o cabeçalho e os tracinhos', () {
    // Os nomes das colunas se digitam na grade; nome de exemplo no arquivo so
    // daria trabalho de apagar.
    final feito = TabelaMarkdown.inserir('', 0, linhas: 2, colunas: 2);

    expect(feito.texto, '|  |  |\n| --- | --- |\n|  |  |\n');
    expect(_html(feito.texto), contains('<table'));
  });

  test('a contagem de linhas inclui o cabeçalho', () {
    final feito = TabelaMarkdown.inserir('', 0, linhas: 1, colunas: 1);
    expect(feito.texto, '|  |\n| --- |\n');
  });

  group('onde ela entra no texto', () {
    test('depois de um paragrafo, abre a linha em branco que falta', () {
      // O porque disto: colada no paragrafo, a tabela seria lida como mais
      // uma linha dele — e sairia no preview como texto com barras.
      final feito = TabelaMarkdown.inserir('Antes', 5, linhas: 1, colunas: 1);

      expect(feito.texto, 'Antes\n\n|  |\n| --- |\n');
      expect(_html(feito.texto), contains('<table'));
    });

    test('a linha em branco que ja existe nao e repetida', () {
      final feito = TabelaMarkdown.inserir(
        'Antes\n\n',
        7,
        linhas: 1,
        colunas: 1,
      );

      expect(feito.texto, 'Antes\n\n|  |\n| --- |\n');
    });

    test('no meio do texto, abre espaço dos dois lados', () {
      final feito = TabelaMarkdown.inserir(
        'Antes\nDepois',
        5,
        linhas: 1,
        colunas: 1,
      );

      expect(feito.texto, 'Antes\n\n|  |\n| --- |\n\nDepois');
      // Os dois paragrafos continuam la, com a tabela entre eles.
      final html = _html(feito.texto);
      expect(html, contains('<table'));
      expect(html, contains('<p>Antes</p>'));
      expect(html, contains('<p>Depois</p>'));
    });

    test('cursor fora do texto nao estoura', () {
      final feito = TabelaMarkdown.inserir('Antes', -1, linhas: 1, colunas: 1);
      expect(feito.texto, startsWith('|  |'));
    });
  });

  test(
    'devolve onde a tabela começou, para o cursor achar a primeira celula',
    () {
      final feito = TabelaMarkdown.inserir('Antes', 5, linhas: 2, colunas: 2);

      expect(feito.texto.substring(feito.inicio), startsWith('|  |  |'));
    },
  );
}
