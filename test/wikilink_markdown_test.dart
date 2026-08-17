import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/wikilink.dart';

void main() {
  group('link interno vira link Markdown', () {
    test('o titulo vira texto e destino', () {
      expect(
        Wikilink.paraMarkdown('Veja [[Tutorial]] depois.'),
        'Veja [Tutorial](wikilink:Tutorial) depois.',
      );
    });

    test('espaço e acento no titulo nao quebram o destino', () {
      final saida = Wikilink.paraMarkdown('[[Plano de ensino]]');
      expect(saida, '[Plano de ensino](wikilink:Plano%20de%20ensino)');

      // E o caminho de volta devolve o titulo como estava.
      expect(
        Wikilink.tituloDe('wikilink:Plano%20de%20ensino'),
        'Plano de ensino',
      );
      expect(
        Wikilink.tituloDe(
          'wikilink:${Uri.encodeComponent('Educação a distância')}',
        ),
        'Educação a distância',
      );
    });

    test('apelido depois da barra vira o texto exibido', () {
      expect(
        Wikilink.paraMarkdown('[[Plano de ensino|o plano]]'),
        '[o plano](wikilink:Plano%20de%20ensino)',
      );
    });

    test('varios links na mesma linha', () {
      expect(
        Wikilink.paraMarkdown('[[Um]] e [[Dois]]'),
        '[Um](wikilink:Um) e [Dois](wikilink:Dois)',
      );
    });

    test('dentro de codigo continua texto', () {
      // Quem escreveu `[[assim]]` entre crases estava mostrando a sintaxe.
      expect(
        Wikilink.paraMarkdown('use `[[assim]]` para ligar'),
        'use `[[assim]]` para ligar',
      );
      expect(Wikilink.paraMarkdown('```\n[[Nota]]\n```'), '```\n[[Nota]]\n```');
    });

    test('colchete solto nao vira link', () {
      expect(Wikilink.paraMarkdown('[[]]'), '[[]]');
      expect(Wikilink.paraMarkdown('[nao e link]'), '[nao e link]');
    });

    test('endereço comum nao e link interno', () {
      expect(Wikilink.tituloDe('https://ufms.br'), isNull);
      expect(Wikilink.tituloDe('mailto:a@b.c'), isNull);
    });

    test('texto sem link nenhum sai intacto', () {
      const texto = '# Titulo\n\nUm paragrafo com [link](http://x) normal.\n';
      expect(Wikilink.paraMarkdown(texto), texto);
    });
  });
}
