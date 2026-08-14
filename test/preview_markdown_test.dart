import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:notas_app/models/preview_markdown.dart';

/// Desenha o corpo pelo mesmo parser que o preview usa.
String _html(String corpo) => md.markdownToHtml(
  corpo,
  extensionSet: md.ExtensionSet.gitHubWeb,
);

void main() {
  group('item de lista ainda vazio', () {
    test('sem tratamento, o Markdown leria titulo', () {
      // O porque de tudo isto: um tracinho sozinho embaixo de um texto e a
      // forma antiga de escrever titulo. Este teste guarda o problema, para
      // ninguem "simplificar" a correçao sem saber o que ela resolvia.
      expect(_html('- Ferramenta: Python\n  - '), contains('<h2'));
    });

    test('depois de preparado, vira lista e nao titulo', () {
      final html = _html(PreviewMarkdown.preparar('- Ferramenta: Python\n  - '));

      expect(html, isNot(contains('<h2')));
      expect(html, contains('Ferramenta: Python'));
      // A lista aninhada aparece: e o recuo que se acabou de fazer com o Tab.
      expect('<ul>'.allMatches(html).length, 2);
    });

    test('vale para os outros marcadores', () {
      for (final marcador in ['*', '+', '1.', '2)']) {
        final html = _html(
          PreviewMarkdown.preparar('Texto qualquer\n$marcador '),
        );
        expect(html, isNot(contains('<h2')), reason: marcador);
      }
    });

    test('item de tarefa vazio nao e mexido', () {
      // `- [ ]` ja tem o que o desambigua; nada a fazer.
      const corpo = '- [ ] ';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });

    test('marcador com texto nao e mexido', () {
      const corpo = '- Um\n  - Dois\n';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });

    test('tracinho dentro de bloco de codigo fica como esta', () {
      const corpo = '```\n- \n```';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });

    test('a linha separadora de verdade continua separando', () {
      // `---` com tres tracinhos e regra horizontal, e nao item de lista.
      final html = _html(PreviewMarkdown.preparar('Antes\n\n---\n\nDepois'));
      expect(html, contains('<hr'));
    });
  });

  group('texto colado embaixo da lista', () {
    test('sem tratamento, o Markdown o joga para dentro do item', () {
      // O porque de tudo isto: `dsa` fica dentro do `<li>`, herdando o recuo
      // do item, quando no editor ele esta na margem.
      final html = _html('- Modernidade\n  - moveis\ndsa');
      expect(html, contains('moveis\ndsa'));
    });

    test('depois de preparado, e paragrafo na margem', () {
      final html = _html(
        PreviewMarkdown.preparar('- Modernidade\n  - moveis\ndsa'),
      );

      // Fora de qualquer `<li>`: a lista fechou antes.
      expect(html, contains('</ul>'));
      expect(html, contains('<p>dsa</p>'));
      expect(html, isNot(contains('moveis\ndsa')));
    });

    test('linha recuada continua sendo continuaçao do item', () {
      // Recuo e continuaçao pedida, e nao saida da lista.
      const corpo = '- um item\n  que continua\n';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });

    test('outro item, titulo e citaçao nao sao mexidos', () {
      for (final linha in ['- dois', '# Titulo', '> Citaçao', '2. dois']) {
        final corpo = '- um\n$linha\n';
        expect(PreviewMarkdown.preparar(corpo), corpo, reason: linha);
      }
    });

    test('texto ja separado por linha em branco fica como esta', () {
      const corpo = '- um\n\ndsa\n';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });

    test('lista dentro de bloco de codigo fica como esta', () {
      const corpo = '```\n- um\ndsa\n```\n';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });
  });

  group('linha em branco de sobra', () {
    test('sem tratamento, dez linhas em branco valem uma', () {
      // O porque do que vem abaixo: para o Markdown, o respiro que se abre
      // apertando Enter varias vezes nao existe.
      expect(_html('Antes\n\n\n\nDepois'), _html('Antes\n\nDepois'));
    });

    test('a segunda em diante vira uma linha vazia no preview', () {
      final html = _html(PreviewMarkdown.preparar('Antes\n\n\nDepois'));

      // Tres paragrafos: o de cima, o vazio, o de baixo.
      expect('<p>'.allMatches(html).length, 3);
      expect(html, contains('<p>​</p>'));
    });

    test('cada linha a mais e uma linha a mais', () {
      final html = _html(PreviewMarkdown.preparar('Antes\n\n\n\n\nDepois'));
      expect('<p>​</p>'.allMatches(html).length, 3);
    });

    test('uma linha em branco so continua separando os blocos', () {
      // O caso comum, que nao pode ganhar espaço nenhum a mais.
      const corpo = 'Antes\n\nDepois\n';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });

    test('linha em branco dentro de bloco de codigo fica como esta', () {
      const corpo = '```\num\n\n\ndois\n```\n';
      expect(PreviewMarkdown.preparar(corpo), corpo);
    });
  });

  test('os links internos continuam virando link', () {
    expect(
      PreviewMarkdown.preparar('Veja [[Tutorial]]'),
      'Veja [Tutorial](wikilink:Tutorial)',
    );
  });
}
