import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/ui/wikilink_suggestions.dart';

void main() {
  group('achar o [[ que esta sendo escrito', () {
    WikilinkAberto? achar(String texto) =>
        WikilinkAberto.em(texto.replaceAll('|', ''), texto.indexOf('|'));

    test('logo depois de abrir, a consulta e vazia', () {
      final link = achar('texto [[|');
      expect(link, isNotNull);
      expect(link!.inicio, 6);
      expect(link.consulta, '');
    });

    test('pega o que ja foi digitado dentro do link', () {
      expect(achar('veja [[plano de|')?.consulta, 'plano de');
    });

    test('link ja fechado nao conta', () {
      // O cursor esta depois do `]]`: nao ha nada a sugerir.
      expect(achar('veja [[Plano]]|'), isNull);
    });

    test('o cursor dentro de um link ja fechado ainda conta', () {
      // Editar o meio de um link existente e o caso de trocar o alvo dele.
      final link = achar('veja [[Pla|no]]');
      expect(link?.consulta, 'Pla');
    });

    test('pega o ultimo [[ da linha, nao o primeiro', () {
      expect(achar('[[Um]] e [[do|')?.consulta, 'do');
    });

    test('quebra de linha fecha o link', () {
      // O `[[` ficou numa linha que o usuario ja deixou para tras.
      expect(achar('[[comeco\nfim|'), isNull);
    });

    test('colchete solto no meio nao conta', () {
      expect(achar('[[a[b|'), isNull);
    });

    test('sem [[ nenhum nao ha o que sugerir', () {
      expect(achar('texto comum|'), isNull);
    });

    test('cursor no comeco do texto nao quebra', () {
      expect(WikilinkAberto.em('', 0), isNull);
      expect(WikilinkAberto.em('[[', 1), isNull);
      expect(WikilinkAberto.em('[[', 9), isNull);
    });
  });

  group('ordenar as notas sugeridas', () {
    const titulos = [
      'Reensino do basico',
      'Plano de ensino',
      'Ensino a distancia',
      'Metodologia do curso',
    ];

    test('quem começa com o que foi digitado vem primeiro', () {
      expect(sugestoesDeNotas(titulos, 'ensino'), [
        'Ensino a distancia',
        'Plano de ensino',
        'Reensino do basico',
      ]);
    });

    test('consulta vazia devolve o vault em ordem alfabetica', () {
      expect(sugestoesDeNotas(titulos, ''), [
        'Ensino a distancia',
        'Metodologia do curso',
        'Plano de ensino',
        'Reensino do basico',
      ]);
    });

    test('nao diferencia maiusculas nem sobra o que nao combina', () {
      expect(sugestoesDeNotas(titulos, 'METODO'), ['Metodologia do curso']);
      expect(sugestoesDeNotas(titulos, 'zzz'), isEmpty);
    });

    test('corta a lista no limite', () {
      final muitos = [for (var i = 0; i < 40; i++) 'Nota $i'];
      expect(sugestoesDeNotas(muitos, 'nota').length, 8);
      expect(sugestoesDeNotas(muitos, 'nota', limite: 3).length, 3);
    });
  });
}
