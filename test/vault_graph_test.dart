import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/models/vault_graph.dart';

Note _nota(String nome, String corpo) =>
    Note.parse('/v/$nome.md', corpo, name: '$nome.md');

void main() {
  group('extracao de tags', () {
    test('le tags do frontmatter', () {
      final tags = TagParser.fromNote(
        _nota('N', '---\ntags: [estudos, flutter]\n---\n\nCorpo.'),
      );
      expect(tags, {'estudos', 'flutter'});
    });

    test('le tags inline do corpo', () {
      final tags = TagParser.fromNote(
        _nota('N', 'Estudando #flutter e #dart.'),
      );
      expect(tags, {'flutter', 'dart'});
    });

    test('junta frontmatter e corpo sem repetir', () {
      final tags = TagParser.fromNote(
        _nota(
          'N',
          '---\ntags: [flutter]\n---\n\nMais sobre #flutter e #testes.',
        ),
      );
      expect(tags, {'flutter', 'testes'});
    });

    test('aceita tag hierarquica', () {
      final tags = TagParser.fromNote(
        _nota('N', 'Nota sobre #estudos/flutter'),
      );
      expect(tags, {'estudos/flutter'});
    });

    test('aceita acento na tag', () {
      final tags = TagParser.fromNote(
        _nota('N', 'Assunto #saúde e #matemática'),
      );
      expect(tags, {'saúde', 'matemática'});
    });

    test('cabecalho Markdown nao vira tag', () {
      final tags = TagParser.fromNote(_nota('N', '# Titulo\n\n## Subtitulo'));
      expect(tags, isEmpty);
    });

    test('codigo inline e bloco de codigo nao viram tag', () {
      final tags = TagParser.fromNote(
        _nota('N', 'Use `#include <stdio.h>`\n\n```\n#define X 1\n```'),
      );
      expect(tags, isEmpty);
    });

    test('numero apos cerquilha nao vira tag', () {
      final tags = TagParser.fromNote(_nota('N', 'Issue #42 resolvida.'));
      expect(tags, isEmpty);
    });

    test('tags como string unica no frontmatter tambem funcionam', () {
      final tags = TagParser.fromNote(
        _nota('N', '---\ntags: "estudos, flutter"\n---\n\nCorpo.'),
      );
      expect(tags, {'estudos', 'flutter'});
    });
  });

  group('links internos', () {
    test('extrai o alvo do wikilink', () {
      final links = TagParser.wikilinksFrom(_nota('N', 'Ver [[Outra nota]].'));
      expect(links, {'Outra nota'});
    });

    test('aceita apelido depois da barra vertical', () {
      final links = TagParser.wikilinksFrom(
        _nota('N', 'Ver [[Outra nota|como chamo ela]].'),
      );
      expect(links, {'Outra nota'});
    });
  });

  group('construcao do grafo', () {
    test('cria um no por nota e um por tag', () {
      final grafo = VaultGraph.build([
        _nota('A', '---\ntags: [x]\n---\n'),
        _nota('B', '---\ntags: [x, y]\n---\n'),
      ]);

      expect(grafo.notas.map((n) => n.label).toSet(), {'A', 'B'});
      expect(grafo.tags.map((n) => n.label).toSet(), {'x', 'y'});
    });

    test('liga cada nota as suas tags', () {
      final grafo = VaultGraph.build([_nota('A', '---\ntags: [x, y]\n---\n')]);
      expect(grafo.edges, hasLength(2));
    });

    test('tag compartilhada conecta notas pelo mesmo no', () {
      final grafo = VaultGraph.build([
        _nota('A', '---\ntags: [comum]\n---\n'),
        _nota('B', '---\ntags: [comum]\n---\n'),
      ]);

      final tag = grafo.tags.single;
      expect(tag.label, 'comum');
      // A tag e o ponto de encontro: recebe uma aresta de cada nota.
      expect(tag.degree, 2);
    });

    test('grau cresce com o numero de ligacoes', () {
      final grafo = VaultGraph.build([
        _nota('Central', '---\ntags: [a, b, c]\n---\n'),
        _nota('Solta', '---\ntags: [a]\n---\n'),
      ]);

      final central = grafo.notas.firstWhere((n) => n.label == 'Central');
      final solta = grafo.notas.firstWhere((n) => n.label == 'Solta');
      expect(central.degree, 3);
      expect(solta.degree, 1);
      expect(grafo.maiorGrau, 3);
    });

    test('wikilink liga duas notas diretamente', () {
      final grafo = VaultGraph.build([
        _nota('A', 'Aponta para [[B]].'),
        _nota('B', 'Corpo.'),
      ]);

      expect(grafo.edges, hasLength(1));
      expect(grafo.notas.firstWhere((n) => n.label == 'B').degree, 1);
    });

    test('wikilink para nota inexistente e ignorado', () {
      final grafo = VaultGraph.build([_nota('A', 'Aponta para [[Fantasma]].')]);
      expect(grafo.edges, isEmpty);
      expect(grafo.nodes, hasLength(1));
    });

    test('nota sem tag nem link continua no grafo, isolada', () {
      final grafo = VaultGraph.build([_nota('Sozinha', 'Só texto.')]);
      expect(grafo.nodes, hasLength(1));
      expect(grafo.edges, isEmpty);
      expect(grafo.nodes.single.degree, 0);
    });

    test('aresta repetida nao duplica', () {
      // A mesma tag citada no frontmatter e no corpo gera uma ligacao so.
      final grafo = VaultGraph.build([
        _nota('A', '---\ntags: [x]\n---\n\nFalando de #x de novo.'),
      ]);
      expect(grafo.edges, hasLength(1));
    });

    test('vault vazio gera grafo vazio', () {
      expect(VaultGraph.build(const []).isEmpty, isTrue);
    });
  });
}
