import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/nota_de_quadro.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/models/quadro_da_nota.dart';

const _umaCaixa = NoDoQuadro(
  id: 'n1',
  forma: FormaDoNo.processo,
  x: 40,
  y: 40,
  largura: 160,
  altura: 56,
  texto: 'Passo',
);

void main() {
  group('que arquivo abre como tela', () {
    test('o `.quadro.md` abre como tela; o `.md` comum, nao', () {
      expect(NotaDeQuadro.eTela('mapa.quadro.md'), isTrue);
      expect(NotaDeQuadro.eTela('Mapa.Quadro.MD'), isTrue);
      expect(NotaDeQuadro.eTela('mapa.md'), isFalse);
      expect(NotaDeQuadro.eTela('quadro.md'), isFalse);
    });

    test('o `.excalidraw` e desenho de fora', () {
      expect(NotaDeQuadro.eDesenhoDeFora('diagrama.excalidraw'), isTrue);
      expect(NotaDeQuadro.eDesenhoDeFora('mapa.quadro.md'), isFalse);
    });

    test('os dois abrem desenhados', () {
      expect(NotaDeQuadro.desenhado('mapa.quadro.md'), isTrue);
      expect(NotaDeQuadro.desenhado('diagrama.excalidraw'), isTrue);
      expect(NotaDeQuadro.desenhado('aula.md'), isFalse);
    });

    test('o titulo nao carrega o `.quadro` pendurado', () {
      // `Note.title` tira so o `.md` e deixaria "mapa.quadro" no alto da tela.
      expect(NotaDeQuadro.tituloDe('mapa.quadro.md'), 'mapa');
      expect(NotaDeQuadro.tituloDe('aula.md'), 'aula');
      expect(NotaDeQuadro.tituloDe('diagrama.excalidraw'), 'diagrama');
    });
  });

  group('o quadro dentro da nota', () {
    test('a nota nova ja nasce com um quadro dentro', () {
      final nova = NotaDeQuadro.nova('Mapa', '2026-09-22');

      expect(nova, contains('tipo: quadro'));
      expect(nova, contains('criado_em: 2026-09-22'));
      // Com frontmatter como qualquer nota: ela tambem entra no painel e na
      // busca por tag.
      expect(
        NotaDeQuadro.doCorpo(Note.parse('/v/m.quadro.md', nova).body).semNada,
        isTrue,
      );
    });

    test('o corpo sem quadro nenhum devolve um quadro vazio', () {
      expect(NotaDeQuadro.doCorpo('So texto aqui.').semNada, isTrue);
      expect(NotaDeQuadro.doCorpo('').semNada, isTrue);
    });

    test('trocar o quadro deixa em paz o que estava escrito em volta', () {
      // Uma tela e uma nota comum que por acaso so tem um quadro dentro, e nada
      // impede alguem de ter escrito uma linha em cima dele. Essa linha nao
      // pode desaparecer na primeira caixa arrastada.
      final antes =
          'Um lembrete no alto.\n'
          '\n'
          '${QuadroDaNota.vazio.markdown}\n'
          '\n'
          'E uma nota no pe.\n';

      final depois = NotaDeQuadro.comQuadro(
        antes,
        const QuadroDaNota(nos: [_umaCaixa], ligacoes: []),
      );

      expect(depois, startsWith('Um lembrete no alto.'));
      expect(depois, endsWith('E uma nota no pe.\n'));
      expect(NotaDeQuadro.doCorpo(depois).nos.single.texto, 'Passo');
    });

    test('corpo sem quadro ganha um no fim, sem comer o texto', () {
      final depois = NotaDeQuadro.comQuadro(
        'Anotaçao solta.',
        const QuadroDaNota(nos: [_umaCaixa], ligacoes: []),
      );

      expect(depois, startsWith('Anotaçao solta.'));
      expect(NotaDeQuadro.doCorpo(depois).nos.single.id, 'n1');
    });

    test('corpo vazio ganha so o quadro, sem linha em branco no alto', () {
      const quadro = QuadroDaNota(nos: [_umaCaixa], ligacoes: []);
      final depois = NotaDeQuadro.comQuadro('', quadro);

      expect(depois, '${quadro.markdown}\n');
    });

    test('ida e volta pelo corpo nao muda o desenho', () {
      const quadro = QuadroDaNota(
        nos: [_umaCaixa],
        ligacoes: [],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [0, 0, 10, 12, 20, 4]),
        ],
      );

      final corpo = NotaDeQuadro.comQuadro('', quadro);
      final volta = NotaDeQuadro.doCorpo(corpo);

      expect(volta.nos.single.texto, 'Passo');
      expect(volta.tracos.single.pontos, [0, 0, 10, 12, 20, 4]);
    });
  });

  group('o desenho de um arquivo, seja ele qual for', () {
    test('a nota-tela entrega o quadro do corpo dela', () {
      final corpo = NotaDeQuadro.comQuadro(
        '',
        const QuadroDaNota(nos: [_umaCaixa], ligacoes: []),
      );
      final nota = Note.parse('/v/mapa.quadro.md', corpo);

      expect(NotaDeQuadro.doArquivo(nota).nos.single.texto, 'Passo');
    });

    test(
      'o `.excalidraw` entrega o desenho dele, e nao o texto do arquivo',
      () {
        final nota = Note.parse(
          '/v/diagrama.excalidraw',
          '{"type":"excalidraw","elements":['
              '{"id":"a","type":"ellipse","x":0,"y":0,"width":80,"height":80}'
              ']}',
        );

        expect(NotaDeQuadro.doArquivo(nota).nos.single.forma, FormaDoNo.elipse);
      },
    );

    test('`.excalidraw` estragado abre vazio, e nao derruba a tela', () {
      final nota = Note.parse('/v/quebrado.excalidraw', 'nao sou json');
      expect(NotaDeQuadro.doArquivo(nota).semNada, isTrue);
    });
  });
}
