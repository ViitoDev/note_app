import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:notas_app/models/preview_markdown.dart';

/// Desenha o corpo pelo mesmo parser que o preview usa.
String _html(String corpo) =>
    md.markdownToHtml(corpo, extensionSet: md.ExtensionSet.gitHubWeb);

void main() {
  group('item de lista ainda vazio', () {
    test('sem tratamento, o Markdown leria titulo', () {
      // O porque de tudo isto: um tracinho sozinho embaixo de um texto e a
      // forma antiga de escrever titulo. Este teste guarda o problema, para
      // ninguem "simplificar" a correçao sem saber o que ela resolvia.
      expect(_html('- Ferramenta: Python\n  - '), contains('<h2'));
    });

    test('depois de preparado, vira lista e nao titulo', () {
      final html = _html(
        PreviewMarkdown.preparar('- Ferramenta: Python\n  - '),
      );

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

  group('linguagem de cada bloco de codigo', () {
    test('acha a linguagem escrita na cerca', () {
      const corpo = '```java\npublic class A {}\n```\n';
      expect(PreviewMarkdown.linguagensDeCodigo(corpo), {
        'public class A {}': 'java',
      });
    });

    test('a chave e o texto que o desenho vai receber', () {
      // O renderizador entrega o miolo do bloco sem a cerca e sem a quebra
      // final. Se a chave nao sair identica, o realce nao acha a linguagem.
      const corpo = '```java\nint a = 1;\nint b = 2;\n```\n';
      expect(
        PreviewMarkdown.linguagensDeCodigo(corpo).keys.single,
        'int a = 1;\nint b = 2;',
      );
    });

    test('nome com maiuscula e espaço na cerca', () {
      // `\`\`\` Java` e como se escreve na pratica.
      const corpo = '``` Java\nint a;\n```\n';
      expect(PreviewMarkdown.linguagensDeCodigo(corpo).values.single, 'java');
    });

    test('varios blocos, cada um com a sua', () {
      const corpo = '```java\nA a;\n```\n\ntexto\n\n```python\nx = 1\n```\n';
      expect(PreviewMarkdown.linguagensDeCodigo(corpo), {
        'A a;': 'java',
        'x = 1': 'python',
      });
    });

    test('aspas e sinais voltam crus na chave', () {
      // O parser guarda o codigo ja escapado para HTML — `"` vira `&quot;`.
      // Quem desenha recebe o texto cru, entao a chave tem que ser crua: sem
      // isto, todo bloco com aspas — quase todo `println` — perdia o realce.
      const corpo =
          '```java\n'
          'System.out.println("Hello world!");\n'
          'if (a < b && c > d) {}\n'
          '```\n';

      expect(
        PreviewMarkdown.linguagensDeCodigo(corpo).keys.single,
        'System.out.println("Hello world!");\nif (a < b && c > d) {}',
      );
    });

    test('bloco sem linguagem fica de fora', () {
      // Sem linguagem declarada nao ha o que realçar: adivinhar erra em
      // codigo curto.
      expect(PreviewMarkdown.linguagensDeCodigo('```\nx\n```\n'), isEmpty);
    });

    test('codigo dentro de uma lista tambem conta', () {
      const corpo = '- Exemplo:\n\n  ```java\n  int a;\n  ```\n';
      expect(PreviewMarkdown.linguagensDeCodigo(corpo).values, ['java']);
    });
  });

  test('os links internos continuam virando link', () {
    expect(
      PreviewMarkdown.preparar('Veja [[Tutorial]]'),
      'Veja [Tutorial](wikilink:Tutorial)',
    );
  });

  group('a seta na leitura', () {
    test('o -> solto e lido como seta', () {
      expect(PreviewMarkdown.preparar('IA -> LLM'), 'IA → LLM');
      expect(PreviewMarkdown.preparar('->\n'), '→\n');
    });

    test('grudado numa palavra continua codigo', () {
      expect(PreviewMarkdown.preparar('ptr->campo'), 'ptr->campo');
    });

    test('a seta comprida fica como foi escrita', () {
      expect(PreviewMarkdown.preparar('a --> b'), 'a --> b');
    });

    test('dentro de codigo, nada muda', () {
      const bloco = '```dart\nint f() -> T\n```\n';
      expect(PreviewMarkdown.preparar(bloco), bloco);
      expect(
        PreviewMarkdown.preparar('use `a -> b` aqui'),
        'use `a -> b` aqui',
      );
    });

    test('o arquivo nao e tocado: isto e leitura', () {
      // A troca acontece no caminho entre o arquivo e a tela, como nos
      // `[[links]]` — o `.md` continua com o que foi escrito.
      const corpo = 'IA -> LLM';
      expect(corpo, 'IA -> LLM');
      expect(PreviewMarkdown.preparar(corpo), isNot(corpo));
    });
  });

  group('a cerca do quadro', () {
    /// A arvore que o preview desenha, pelas extensoes que ele usa.
    List<md.Node> arvore(String corpo) => md.Document(
      extensionSet: PreviewMarkdown.extensoes,
    ).parseLines(corpo.split('\n'));

    const bloco = '```quadro\n{"nos":[]}\n```';

    test('vira um no proprio, e nao um bloco de codigo', () {
      final nos = arvore('Antes\n\n$bloco\n\nDepois\n');
      final quadro = nos.whereType<md.Element>().firstWhere(
        (e) => e.tag == 'quadro',
      );

      expect(quadro.textContent, '{"nos":[]}');
      // O paragrafo de antes e o de depois continuam sendo paragrafos: a cerca
      // nao engoliu o resto da nota.
      expect(nos.whereType<md.Element>().where((e) => e.tag == 'p').length, 2);
      expect(nos.whereType<md.Element>().where((e) => e.tag == 'pre'), isEmpty);
    });

    test('cerca de codigo comum continua sendo codigo', () {
      final nos = arvore('```dart\nvar a = 1;\n```\n');

      expect(nos.whereType<md.Element>().single.tag, 'pre');
    });

    test('o realce de codigo nao reclama o bloco do quadro', () {
      expect(PreviewMarkdown.linguagensDeCodigo(bloco), isEmpty);
    });

    test('o preparo do preview nao mexe no conteudo do quadro', () {
      // As passadas de leitura tratam cerca como codigo, e la dentro o que
      // parece marcador de lista e coordenada.
      const corpo = 'Antes\n\n$bloco\n';
      expect(PreviewMarkdown.preparar(corpo), contains('{"nos":[]}'));
    });
  });
}
