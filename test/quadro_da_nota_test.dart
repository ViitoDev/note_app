import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/quadro_da_nota.dart';

/// O conteudo de dentro das cercas de um bloco de quadro.
String _dentro(String markdown) {
  final linhas = markdown.split('\n');
  return linhas.sublist(1, linhas.length - 1).join('\n');
}

QuadroDaNota _ida(QuadroDaNota quadro) =>
    QuadroDaNota.ler(_dentro(quadro.markdown))!;

void main() {
  group('lendo o bloco', () {
    test('bloco vazio e um quadro legitimo — e assim que ele nasce', () {
      expect(QuadroDaNota.ler('')!.semNada, isTrue);
      expect(QuadroDaNota.ler('   \n  ')!.nos, isEmpty);
    });

    test('caixas e flechas viram modelo', () {
      final quadro = QuadroDaNota.ler('''
{"nos":[
{"id":"n1","forma":"terminal","x":40,"y":20,"largura":120,"altura":48,"texto":"Inicio"},
{"id":"n2","forma":"decisao","x":0,"y":120,"largura":200,"altura":100,"texto":"E par?"}
],"ligacoes":[
{"de":"n1","para":"n2","rotulo":"Sim"}
]}
''')!;

      expect(quadro.nos.length, 2);
      expect(quadro.no('n1')!.forma, FormaDoNo.terminal);
      expect(quadro.no('n1')!.texto, 'Inicio');
      expect(quadro.no('n2')!.forma, FormaDoNo.decisao);
      expect(quadro.ligacoes.single.rotulo, 'Sim');
    });

    test('lixo no lugar do quadro nao e quadro', () {
      // Devolvendo nulo, o bloco continua sendo texto no editor — e da para
      // consertar a mao em vez de perder o que estava escrito.
      expect(QuadroDaNota.ler('nao sou json'), isNull);
      expect(QuadroDaNota.ler('[1, 2, 3]'), isNull);
    });

    test('caixa sem id e descartada: nada poderia apontar para ela', () {
      final quadro = QuadroDaNota.ler('{"nos":[{"x":1,"y":2},{"id":"n1"}]}')!;
      expect(quadro.nos.single.id, 'n1');
    });

    test('id repetido entra uma vez so', () {
      final quadro = QuadroDaNota.ler(
        '{"nos":[{"id":"n1","texto":"a"},{"id":"n1","texto":"b"}]}',
      )!;

      expect(quadro.nos.length, 1);
      expect(quadro.nos.single.texto, 'a');
    });

    test('caixa sem tamanho ganha o tamanho da forma dela', () {
      final quadro = QuadroDaNota.ler('{"nos":[{"id":"n1"}]}')!;
      final padrao = FormaDoNo.processo.tamanhoInicial;

      expect(quadro.nos.single.largura, padrao.largura);
      expect(quadro.nos.single.altura, padrao.altura);
    });

    test('flecha para caixa que nao existe nao tem onde encostar', () {
      final quadro = QuadroDaNota.ler(
        '{"nos":[{"id":"n1"}],"ligacoes":[{"de":"n1","para":"n9"}]}',
      )!;

      expect(quadro.ligacoes, isEmpty);
    });
  });

  group('escrevendo o bloco', () {
    test('o bloco sai com as cercas e a palavra do quadro', () {
      final linhas = QuadroDaNota.vazio.markdown.split('\n');

      expect(linhas.first, '```${QuadroDaNota.marcador}');
      expect(linhas.last, '```');
    });

    test('ida e volta preserva as caixas e as flechas', () {
      const original = QuadroDaNota(
        nos: [
          NoDoQuadro(
            id: 'n1',
            forma: FormaDoNo.terminal,
            x: 8,
            y: 16,
            largura: 128,
            altura: 48,
            texto: 'Inicio',
          ),
          NoDoQuadro(
            id: 'n2',
            forma: FormaDoNo.processo,
            x: 8,
            y: 120,
            largura: 168,
            altura: 56,
            texto: 'Ler o numero\ncom acento e "aspas"',
          ),
        ],
        ligacoes: [LigacaoDoQuadro(de: 'n1', para: 'n2', rotulo: 'Nao')],
      );

      final volta = _ida(original);

      expect(volta.nos.length, 2);
      expect(volta.no('n2')!.texto, original.nos[1].texto);
      expect(volta.no('n2')!.forma, FormaDoNo.processo);
      expect(volta.ligacoes.single.de, 'n1');
      expect(volta.ligacoes.single.rotulo, 'Nao');
    });

    test('uma entidade por linha: mover uma caixa muda uma linha', () {
      const quadro = QuadroDaNota(
        nos: [
          NoDoQuadro(
            id: 'n1',
            forma: FormaDoNo.processo,
            x: 0,
            y: 0,
            largura: 100,
            altura: 40,
          ),
          NoDoQuadro(
            id: 'n2',
            forma: FormaDoNo.processo,
            x: 0,
            y: 80,
            largura: 100,
            altura: 40,
          ),
        ],
        ligacoes: [LigacaoDoQuadro(de: 'n1', para: 'n2')],
      );

      final antes = quadro.markdown.split('\n');
      final depois = quadro
          .comNo(quadro.no('n2')!.com(x: 40))
          .markdown
          .split('\n');

      expect(depois.length, antes.length);
      final diferentes = [
        for (var i = 0; i < antes.length; i++)
          if (antes[i] != depois[i]) i,
      ];
      expect(diferentes.length, 1);
    });

    test('coordenada redonda sai sem casa decimal', () {
      const quadro = QuadroDaNota(
        nos: [
          NoDoQuadro(
            id: 'n1',
            forma: FormaDoNo.processo,
            x: 320,
            y: 40,
            largura: 160,
            altura: 48,
          ),
        ],
        ligacoes: [],
      );

      expect(quadro.markdown, contains('"x":320'));
      expect(quadro.markdown, isNot(contains('320.0')));
    });

    test('rotulo vazio nao ocupa lugar no arquivo', () {
      const quadro = QuadroDaNota(
        nos: [
          NoDoQuadro(
            id: 'n1',
            forma: FormaDoNo.processo,
            x: 0,
            y: 0,
            largura: 80,
            altura: 40,
          ),
          NoDoQuadro(
            id: 'n2',
            forma: FormaDoNo.processo,
            x: 0,
            y: 80,
            largura: 80,
            altura: 40,
          ),
        ],
        ligacoes: [LigacaoDoQuadro(de: 'n1', para: 'n2')],
      );

      expect(quadro.markdown, isNot(contains('rotulo')));
      expect(quadro.markdown, isNot(contains('"texto"')));
    });
  });

  group('os traços', () {
    const rabisco = TracoDoQuadro(
      id: 't1',
      pontos: [10, 20, 14.5, 26, 22, 24],
      cor: CorDoTraco.ceu,
      grossura: 4,
    );

    test('ida e volta preserva o caminho, a tinta e a grossura', () {
      const quadro = QuadroDaNota(nos: [], ligacoes: [], tracos: [rabisco]);
      final volta = _ida(quadro);

      expect(volta.tracos.single.pontos, [10, 20, 14.5, 26, 22, 24]);
      expect(volta.tracos.single.cor, CorDoTraco.ceu);
      expect(volta.tracos.single.grossura, 4);
      expect(volta.tracos.single.tipo, TipoDoTraco.livre);
    });

    test('o que e padrao nao ocupa lugar no arquivo', () {
      const simples = QuadroDaNota(
        nos: [],
        ligacoes: [],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [0, 0, 8, 8]),
        ],
      );

      expect(simples.markdown, isNot(contains('"cor"')));
      expect(simples.markdown, isNot(contains('"grossura"')));
      expect(simples.markdown, isNot(contains('"tipo"')));
    });

    test('um traço cabe numa linha, como as caixas', () {
      const quadro = QuadroDaNota(
        nos: [],
        ligacoes: [],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [0, 0, 8, 8]),
          TracoDoQuadro(id: 't2', pontos: [1, 1, 9, 9]),
        ],
      );

      final linhas = quadro.markdown
          .split('\n')
          .where((l) => l.startsWith('{"id":"t'))
          .toList();
      expect(linhas.length, 2);
    });

    test('nota sem traço nenhum nao ganha a seçao deles', () {
      // Sem isto, abrir e fechar uma nota antiga acrescentaria duas linhas ao
      // `.md` dela sem que nada tivesse sido desenhado.
      expect(QuadroDaNota.vazio.markdown, isNot(contains('tracos')));
    });

    test('meio ponto nao entra: o arquivo guarda uma casa decimal', () {
      const quadro = QuadroDaNota(
        nos: [],
        ligacoes: [],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [18.437261, 4.0, 20, 9.96]),
        ],
      );

      expect(quadro.markdown, contains('[18.4,4,20,10]'));
    });

    test('traço pela metade nao e traço', () {
      // Numero impar de coordenadas e um ponto sem par: nao da para saber se o
      // que sobrou era um x sem y ou lixo no fim da linha.
      expect(
        QuadroDaNota.ler('{"tracos":[{"id":"t1","pontos":[0,0,5]}]}')!.tracos,
        isEmpty,
      );
      expect(
        QuadroDaNota.ler('{"tracos":[{"id":"t1","pontos":[0,0]}]}')!.tracos,
        isEmpty,
      );
      expect(
        QuadroDaNota.ler('{"tracos":[{"pontos":[0,0,1,1]}]}')!.tracos,
        isEmpty,
      );
    });

    test('a reta guarda duas pontas, mesmo vindo com mais', () {
      final quadro = QuadroDaNota.ler(
        '{"tracos":[{"id":"t1","tipo":"reta","pontos":[0,0,5,5,9,9]}]}',
      )!;

      expect(quadro.tracos.single.pontos, [0, 0, 9, 9]);
    });

    test('mover o traço move o caminho inteiro', () {
      expect(rabisco.movido(10, -5).pontos, [20, 15, 24.5, 21, 32, 19]);
    });

    test('o id novo do traço tem a letra dele', () {
      // `t1` e um traço e `n1` e uma caixa, e quem abre o `.md` ve isso sem
      // precisar procurar.
      const quadro = QuadroDaNota(nos: [], ligacoes: [], tracos: [rabisco]);
      expect(quadro.idLivreDoTraco, 't2');
      expect(QuadroDaNota.vazio.idLivreDoTraco, 't1');
    });

    test('so de traço o quadro ja nao esta vazio', () {
      const quadro = QuadroDaNota(nos: [], ligacoes: [], tracos: [rabisco]);
      expect(quadro.semNada, isFalse);
    });

    test('apagar o traço tira so ele', () {
      const quadro = QuadroDaNota(
        nos: [],
        ligacoes: [],
        tracos: [
          rabisco,
          TracoDoQuadro(id: 't2', pontos: [0, 0, 4, 4]),
        ],
      );

      expect(quadro.semTraco('t1').tracos.single.id, 't2');
      expect(quadro.semTraco('nao existe').tracos.length, 2);
    });
  });

  group('o traço a mao', () {
    test('o arquivo calado quer dizer desenhado a mao', () {
      // Verdadeiro por omissao: um quadro dentro de uma nota quase sempre e um
      // rascunho, e o traço torto e o que diz isso sem legenda.
      expect(QuadroDaNota.ler('{"nos":[]}')!.aMao, isTrue);
      expect(QuadroDaNota.vazio.aMao, isTrue);
    });

    test('desligar a mao fica escrito; ligar volta ao silencio', () {
      const quadro = QuadroDaNota(nos: [], ligacoes: []);

      expect(quadro.comMao(false).markdown, contains('"mao":false'));
      expect(
        quadro.comMao(false).comMao(true).markdown,
        isNot(contains('mao')),
      );
      expect(QuadroDaNota.ler('{"nos":[],"mao":false}')!.aMao, isFalse);
    });
  });

  group('mexendo no quadro', () {
    QuadroDaNota comDuas() => QuadroDaNota.ler(
      '{"nos":[{"id":"n1"},{"id":"n2"}],'
      '"ligacoes":[{"de":"n1","para":"n2"}]}',
    )!;

    test('o id novo e o primeiro livre', () {
      expect(comDuas().idLivre, 'n3');
      expect(comDuas().semNo('n1').idLivre, 'n1');
    });

    test('tirar a caixa tira as flechas dela', () {
      final quadro = comDuas().semNo('n2');

      expect(quadro.nos.single.id, 'n1');
      expect(quadro.ligacoes, isEmpty);
    });

    test('a mesma ligaçao nao entra duas vezes', () {
      final quadro = comDuas().comLigacao('n1', 'n2');
      expect(quadro.ligacoes.length, 1);
    });

    test('caixa nao se liga a si mesma nem ao que nao existe', () {
      expect(comDuas().comLigacao('n1', 'n1').ligacoes.length, 1);
      expect(comDuas().comLigacao('n1', 'n9').ligacoes.length, 1);
    });

    test('o rotulo entra na flecha certa', () {
      final quadro = comDuas().comRotulo(0, 'Sim');
      expect(quadro.ligacoes.single.rotulo, 'Sim');
    });

    test('mexer em indice que nao existe nao explode', () {
      expect(comDuas().comRotulo(7, 'Sim').ligacoes.single.rotulo, '');
      expect(comDuas().semLigacao(7).ligacoes.length, 1);
    });

    test('juntar renumera o que chega', () {
      // Dois quadros feitos em separado tem ambos um `n1`. Sem renumerar, a
      // caixa que chega sumiria dentro da que ja estava — [comNo] troca quem
      // tem o mesmo id — e as flechas apontariam para a caixa errada.
      const daqui = QuadroDaNota(
        nos: [
          NoDoQuadro(
            id: 'n1',
            forma: FormaDoNo.processo,
            x: 0,
            y: 0,
            largura: 80,
            altura: 40,
            texto: 'daqui',
          ),
        ],
        ligacoes: [],
      );
      const dela = QuadroDaNota(
        nos: [
          NoDoQuadro(
            id: 'n1',
            forma: FormaDoNo.decisao,
            x: 0,
            y: 0,
            largura: 80,
            altura: 40,
            texto: 'de fora',
          ),
          NoDoQuadro(
            id: 'n2',
            forma: FormaDoNo.processo,
            x: 0,
            y: 100,
            largura: 80,
            altura: 40,
          ),
        ],
        ligacoes: [LigacaoDoQuadro(de: 'n1', para: 'n2')],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [0, 0, 10, 10]),
        ],
      );

      final junto = daqui.juntar(dela, dx: 500, dy: 20);

      expect(junto.nos.length, 3);
      expect(junto.no('n1')!.texto, 'daqui');
      // A flecha que veio junto aponta para os nomes novos, e nao para os
      // velhos.
      final ligacao = junto.ligacoes.single;
      expect(junto.no(ligacao.de)!.texto, 'de fora');
      expect(junto.no(ligacao.de)!.x, 500);
      expect(junto.no(ligacao.de)!.y, 20);
      expect(junto.tracos.single.pontos, [500, 20, 510, 30]);
    });

    test('trocar a caixa nao duplica: o id e quem manda', () {
      final quadro = comDuas();
      final novo = quadro.comNo(quadro.no('n1')!.com(texto: 'Ola'));

      expect(novo.nos.length, 2);
      expect(novo.no('n1')!.texto, 'Ola');
    });
  });
}
