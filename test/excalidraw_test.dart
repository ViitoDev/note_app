import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/excalidraw.dart';
import 'package:notas_app/models/quadro_da_nota.dart';

/// Um desenho do Excalidraw com os elementos pedidos dentro.
///
/// So os campos que a leitura olha. O arquivo de verdade traz mais de vinte
/// campos por elemento — `seed`, `versionNonce`, `updated` —, e enche-los aqui
/// so faria o teste dizer duas vezes o que ja esta dito no codigo.
String _desenho(List<Map<String, Object?>> elementos, {String? tipo}) =>
    jsonEncode({
      'type': tipo ?? Excalidraw.tipoDoArquivo,
      'version': 2,
      'source': 'https://excalidraw.com',
      'elements': elementos,
      'appState': <String, Object?>{},
    });

Map<String, Object?> _caixa(
  String id,
  String tipo, {
  double x = 0,
  double y = 0,
  double largura = 200,
  double altura = 100,
}) => {
  'id': id,
  'type': tipo,
  'x': x,
  'y': y,
  'width': largura,
  'height': altura,
  'isDeleted': false,
};

void main() {
  group('reconhecendo o formato', () {
    test('o arquivo e o que vem colado sao os dois lidos', () {
      final arquivo = Excalidraw.ler(_desenho([_caixa('a', 'rectangle')]));
      final colado = Excalidraw.ler(
        _desenho([_caixa('a', 'rectangle')], tipo: Excalidraw.tipoColado),
      );

      expect(arquivo!.nos.single.forma, FormaDoNo.processo);
      expect(colado!.nos.single.forma, FormaDoNo.processo);
    });

    test('o que nao e do Excalidraw nao e lido como se fosse', () {
      expect(Excalidraw.ler('nao sou json'), isNull);
      expect(Excalidraw.ler('{"type":"outra coisa","elements":[]}'), isNull);
      expect(Excalidraw.ler('{"type":"excalidraw"}'), isNull);
    });

    test('desenho vazio e legitimo: e um arquivo novo', () {
      expect(Excalidraw.ler(_desenho([]))!.semNada, isTrue);
    });

    test('a farejada barata concorda com a leitura', () {
      // Ela existe para nao gastar um `jsonDecode` inteiro em cada coisa que
      // alguem copiou — entao dizer "nao" no que da certo seria pior que
      // inutil.
      expect(
        Excalidraw.pareceExcalidraw(_desenho([_caixa('a', 'rectangle')])),
        isTrue,
      );
      expect(Excalidraw.pareceExcalidraw('Um texto qualquer'), isFalse);
      expect(Excalidraw.pareceExcalidraw('{"elements":[]}'), isFalse);
    });
  });

  group('trazendo o desenho', () {
    test('cada forma de la vira a forma daqui', () {
      final quadro = Excalidraw.ler(
        _desenho([
          _caixa('a', 'rectangle'),
          _caixa('b', 'diamond'),
          _caixa('c', 'ellipse'),
          _caixa('d', 'frame'),
        ]),
      )!;

      expect(quadro.nos.map((n) => n.forma), [
        FormaDoNo.processo,
        FormaDoNo.decisao,
        FormaDoNo.elipse,
        FormaDoNo.fundo,
      ]);
    });

    test('os nomes sao renumerados: `n1`, e nao `a1b2c3d4`', () {
      // O bloco do quadro mora dentro da nota, e a nota e lida por gente e por
      // `diff`. Um punhado de ids aleatorios de trinta letras acabaria com isso.
      final quadro = Excalidraw.ler(
        _desenho([
          _caixa('Xk9_2aB', 'rectangle'),
          _caixa('Qz-11pL', 'rectangle', y: 200),
        ]),
      )!;

      expect(quadro.nos.map((n) => n.id), ['n1', 'n2']);
    });

    test('o texto de dentro da caixa vai para a caixa', () {
      final quadro = Excalidraw.ler(
        _desenho([
          _caixa('a', 'rectangle'),
          {
            'id': 't',
            'type': 'text',
            'x': 10,
            'y': 10,
            'width': 80,
            'height': 20,
            'text': 'Ler o\nnumero',
            'originalText': 'Ler o numero',
            'containerId': 'a',
          },
        ]),
      )!;

      // `originalText` ganha de `text`: o segundo ja vem quebrado em linhas
      // pela largura da caixa de la, e essas quebras nao sao das palavras.
      expect(quadro.nos.single.texto, 'Ler o numero');
    });

    test('texto solto e anotaçao, e nao caixa com texto', () {
      final quadro = Excalidraw.ler(
        _desenho([
          {
            'id': 't',
            'type': 'text',
            'x': 0,
            'y': 0,
            'width': 90,
            'height': 24,
            'text': 'Um lembrete',
            'containerId': null,
          },
        ]),
      )!;

      expect(quadro.nos.single.forma, FormaDoNo.texto);
      expect(quadro.nos.single.texto, 'Um lembrete');
    });

    test('a flecha presa nas duas pontas vira ligaçao, com o rotulo', () {
      final quadro = Excalidraw.ler(
        _desenho([
          _caixa('a', 'rectangle'),
          _caixa('b', 'rectangle', y: 300),
          {
            'id': 'f',
            'type': 'arrow',
            'x': 100,
            'y': 100,
            'width': 0,
            'height': 200,
            'points': [
              [0, 0],
              [0, 200],
            ],
            'startBinding': {'elementId': 'a'},
            'endBinding': {'elementId': 'b'},
          },
          {
            'id': 'r',
            'type': 'text',
            'x': 100,
            'y': 190,
            'width': 30,
            'height': 20,
            'text': 'Sim',
            'containerId': 'f',
          },
        ]),
      )!;

      expect(quadro.ligacoes.single.de, 'n1');
      expect(quadro.ligacoes.single.para, 'n2');
      expect(quadro.ligacoes.single.rotulo, 'Sim');
      // A flecha virou ligaçao: nao pode ter virado traço tambem.
      expect(quadro.tracos, isEmpty);
    });

    test('a flecha solta vira traço, porque nao ha em que ela se prender', () {
      final quadro = Excalidraw.ler(
        _desenho([
          {
            'id': 'f',
            'type': 'arrow',
            'x': 10,
            'y': 20,
            'width': 100,
            'height': 0,
            'points': [
              [0, 0],
              [100, 0],
            ],
            'endArrowhead': 'arrow',
          },
        ]),
      )!;

      final traco = quadro.tracos.single;
      expect(traco.tipo, TipoDoTraco.seta);
      // Os pontos de la sao relativos ao canto do elemento.
      expect(traco.pontos, [10.0, 20.0, 110.0, 20.0]);
    });

    test('o rabisco a mao vira traço a mao', () {
      final quadro = Excalidraw.ler(
        _desenho([
          {
            'id': 'r',
            'type': 'freedraw',
            'x': 5,
            'y': 5,
            'width': 20,
            'height': 20,
            'points': [
              [0, 0],
              [10, 10],
              [20, 5],
            ],
            'strokeColor': '#2f9e44',
            'strokeWidth': 4,
          },
        ]),
      )!;

      final traco = quadro.tracos.single;
      expect(traco.tipo, TipoDoTraco.livre);
      expect(traco.quantos, 3);
      expect(traco.cor, CorDoTraco.verde);
      expect(traco.grossura, 4);
    });

    test('o apagado de la nao entra: ele nao esta no desenho', () {
      final quadro = Excalidraw.ler(
        _desenho([
          {..._caixa('a', 'rectangle'), 'isDeleted': true},
          _caixa('b', 'rectangle'),
        ]),
      )!;

      expect(quadro.nos.length, 1);
    });

    test('elemento sem tamanho e resto de um gesto que nao terminou', () {
      final quadro = Excalidraw.ler(
        _desenho([_caixa('a', 'rectangle', largura: 0, altura: 0)]),
      )!;

      expect(quadro.nos, isEmpty);
    });
  });

  group('as cores', () {
    test('a paleta de fabrica do Excalidraw cai em cheio na nossa', () {
      expect(Excalidraw.corDe('#1e1e1e'), CorDoTraco.tinta);
      expect(Excalidraw.corDe('#6741d9'), CorDoTraco.indigo);
      expect(Excalidraw.corDe('#1971c2'), CorDoTraco.ceu);
      expect(Excalidraw.corDe('#2f9e44'), CorDoTraco.verde);
      expect(Excalidraw.corDe('#f08c00'), CorDoTraco.ambar);
      expect(Excalidraw.corDe('#e03131'), CorDoTraco.rosa);
    });

    test('a cor de fora cai na mais parecida, e nao em preto', () {
      // O Excalidraw deixa escolher qualquer cor. Uma tabela de nomes acertaria
      // so as seis de fabrica, e jogaria todo o resto na tinta.
      expect(Excalidraw.corDe('#00ff00'), CorDoTraco.verde);
      expect(Excalidraw.corDe('#ffcc55'), CorDoTraco.ambar);
      expect(Excalidraw.corDe('#000000'), CorDoTraco.tinta);
    });

    test('a forma curta e a com transparencia tambem sao lidas', () {
      expect(Excalidraw.corDe('#0f0'), CorDoTraco.verde);
      expect(Excalidraw.corDe('#2f9e44ff'), CorDoTraco.verde);
    });

    test('cor que nao e cor vira tinta, e nao derruba a leitura', () {
      expect(Excalidraw.corDe('transparent'), CorDoTraco.tinta);
      expect(Excalidraw.corDe(null), CorDoTraco.tinta);
      expect(Excalidraw.corDe(42), CorDoTraco.tinta);
    });
  });

  group('levando o desenho de volta', () {
    const quadro = QuadroDaNota(
      nos: [
        NoDoQuadro(
          id: 'n1',
          forma: FormaDoNo.terminal,
          x: 0,
          y: 0,
          largura: 128,
          altura: 48,
          texto: 'Inicio',
        ),
        NoDoQuadro(
          id: 'n2',
          forma: FormaDoNo.decisao,
          x: 0,
          y: 200,
          largura: 208,
          altura: 104,
          texto: 'E par?',
        ),
      ],
      ligacoes: [LigacaoDoQuadro(de: 'n1', para: 'n2', rotulo: 'Sim')],
      tracos: [
        TracoDoQuadro(
          id: 't1',
          pontos: [0, 0, 10, 10, 20, 0],
          cor: CorDoTraco.rosa,
        ),
      ],
    );

    test('o que sai daqui e lido la — e volta igual', () {
      // A prova mais util que um formato de troca aceita: o desenho atravessa a
      // ponte nos dois sentidos sem perder o que ele e.
      final volta = Excalidraw.ler(Excalidraw.escrever(quadro))!;

      expect(volta.nos.length, 2);
      expect(volta.nos.first.texto, 'Inicio');
      expect(volta.nos.last.forma, FormaDoNo.decisao);
      expect(volta.nos.last.texto, 'E par?');
      expect(volta.ligacoes.single.rotulo, 'Sim');
      expect(volta.tracos.single.cor, CorDoTraco.rosa);
      expect(volta.tracos.single.quantos, 3);
    });

    test('a capsula volta como retangulo: e o mais perto que la existe', () {
      // O Excalidraw nao tem capsula. Perder a moldura e o preço de atravessar,
      // e esta na documentaçao de [Excalidraw] — o que nao se pode e perder o
      // texto junto.
      final volta = Excalidraw.ler(Excalidraw.escrever(quadro))!;
      expect(volta.nos.first.forma, FormaDoNo.processo);
      expect(volta.nos.first.texto, 'Inicio');
    });

    test('para colar leva o tipo da area de transferencia', () {
      final colar = jsonDecode(Excalidraw.escrever(quadro, paraColar: true));
      final arquivo = jsonDecode(Excalidraw.escrever(quadro));

      expect(colar['type'], Excalidraw.tipoColado);
      expect(arquivo['type'], Excalidraw.tipoDoArquivo);
      // O arquivo carrega o estado da tela; o que se cola, nao — ele entra numa
      // tela que ja esta aberta, com o estado de quem colou.
      expect(arquivo.containsKey('appState'), isTrue);
      expect(colar.containsKey('appState'), isFalse);
    });

    test('a flecha sai presa nas duas caixas', () {
      final bruto = jsonDecode(Excalidraw.escrever(quadro));
      final flecha = (bruto['elements'] as List).firstWhere(
        (e) => e['type'] == 'arrow',
      );

      // Sem isto, arrastar a caixa la deixaria a flecha para tras.
      expect(flecha['startBinding']['elementId'], 'n1');
      expect(flecha['endBinding']['elementId'], 'n2');
    });

    test('quadro vazio sai como desenho vazio, e nao como lixo', () {
      final volta = Excalidraw.ler(Excalidraw.escrever(QuadroDaNota.vazio))!;
      expect(volta.semNada, isTrue);
    });
  });
}
