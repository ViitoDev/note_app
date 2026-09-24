import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/quadro_da_nota.dart';
import 'package:notas_app/ui/desenho_do_quadro.dart';

/// Uma caixa centrada em [centro], do tamanho de fabrica da forma.
NoDoQuadro caixa(
  String id,
  FormaDoNo forma,
  Offset centro, {
  double? largura,
  double? altura,
}) {
  final tamanho = forma.tamanhoInicial;
  final l = largura ?? tamanho.largura;
  final a = altura ?? tamanho.altura;

  return NoDoQuadro(
    id: id,
    forma: forma,
    x: centro.dx - l / 2,
    y: centro.dy - a / 2,
    largura: l,
    altura: a,
  );
}

/// Se o trecho reto de [a] a [b] entra em [area] — a mesma conta que o
/// desenho faz, escrita a parte para o teste conferir o resultado dele.
bool _cruza(Offset a, Offset b, Rect area) =>
    math.min(a.dx, b.dx) < area.right &&
    math.max(a.dx, b.dx) > area.left &&
    math.min(a.dy, b.dy) < area.bottom &&
    math.max(a.dy, b.dy) > area.top;

void main() {
  group('a rota entre duas caixas', () {
    test('alinhadas, e uma reta de dois pontos', () {
      final rota = DesenhoDoQuadro.rotaEntre(
        caixa('a', FormaDoNo.terminal, const Offset(300, 100)),
        caixa('b', FormaDoNo.processo, const Offset(300, 300)),
      );

      expect(rota.length, 2);
      expect(rota.first.dx, rota.last.dx);
      expect(rota.first.dy, lessThan(rota.last.dy));
    });

    test('quase alinhadas, tambem — o degrauzinho nao aparece', () {
      // Cinco pixels de desencontro nao se veem nas caixas, mas se veriam no
      // passo de lado da flecha.
      final rota = DesenhoDoQuadro.rotaEntre(
        caixa('a', FormaDoNo.terminal, const Offset(300, 100)),
        caixa('b', FormaDoNo.processo, const Offset(305, 300)),
      );

      expect(rota.length, 2);
      expect(rota.first.dx, rota.last.dx);
    });

    test('desencontro grande volta a ter cotovelo', () {
      final rota = DesenhoDoQuadro.rotaEntre(
        caixa('a', FormaDoNo.terminal, const Offset(300, 100)),
        caixa('b', FormaDoNo.processo, const Offset(340, 300)),
      );

      expect(rota.length, greaterThan(2));
    });

    test('ramo de decisao: sai pelo lado e entra por cima', () {
      final decisao = caixa('a', FormaDoNo.decisao, const Offset(360, 300));
      final ramo = caixa('b', FormaDoNo.processo, const Offset(140, 460));

      final rota = DesenhoDoQuadro.rotaEntre(decisao, ramo);

      expect(rota.length, 3);
      // Sai pela ponta esquerda do losango, na altura do centro dele.
      expect(rota.first, DesenhoDoQuadro.bordaDe(decisao, LadoDoNo.esquerda));
      // Vira uma vez e desce na cabeça do ramo.
      expect(rota[1].dy, rota.first.dy);
      expect(rota.last, DesenhoDoQuadro.bordaDe(ramo, LadoDoNo.topo));
    });

    test('volta ao fim: sai por baixo e entra pelo lado', () {
      // Queda maior que o passo de lado: a flecha desce primeiro.
      final ramo = caixa('a', FormaDoNo.processo, const Offset(152, 496));
      final fim = caixa('b', FormaDoNo.terminal, const Offset(360, 730));

      final rota = DesenhoDoQuadro.rotaEntre(ramo, fim);

      expect(rota.length, 3);
      expect(rota.first, DesenhoDoQuadro.bordaDe(ramo, LadoDoNo.base));
      expect(rota[1].dx, rota.first.dx);
      expect(rota.last, DesenhoDoQuadro.bordaDe(fim, LadoDoNo.esquerda));
    });

    test('caixas sobrepostas no outro eixo ganham o degrau em Z', () {
      // O L passaria por dentro do alvo; com dois cotovelos, a flecha contorna.
      final rota = DesenhoDoQuadro.rotaEntre(
        caixa('a', FormaDoNo.processo, const Offset(200, 300)),
        caixa('b', FormaDoNo.processo, const Offset(560, 320)),
      );

      expect(rota.length, 4);
      expect(rota[1].dx, rota[2].dx);
    });

    test('tres flechas saindo da mesma caixa nao se empilham', () {
      // O caso da tela: uma caixa a esquerda presa a outras tres, uma delas
      // bem na frente. Sem desvio as tres rotas corriam pelo mesmo trecho e
      // atravessavam a caixa do meio, e o que se via era uma linha cruzando
      // uma caixa — nao tres setas.
      final fonte = caixa('a', FormaDoNo.terminal, const Offset(140, 300));
      final meio = caixa('b', FormaDoNo.processo, const Offset(420, 300));
      final cima = caixa('c', FormaDoNo.processo, const Offset(420, 140));
      final baixo = caixa('d', FormaDoNo.processo, const Offset(420, 460));
      final todas = [fonte, meio, cima, baixo];

      final paraMeio = DesenhoDoQuadro.rotaEntre(fonte, meio, desviarDe: todas);
      final paraCima = DesenhoDoQuadro.rotaEntre(fonte, cima, desviarDe: todas);
      final paraBaixo = DesenhoDoQuadro.rotaEntre(
        fonte,
        baixo,
        desviarDe: todas,
      );

      // Nenhuma das tres passa por dentro da caixa do meio.
      final area = DesenhoDoQuadro.retanguloDe(meio);
      for (final rota in [paraCima, paraBaixo]) {
        for (var i = 1; i < rota.length; i++) {
          expect(
            _cruza(rota[i - 1], rota[i], area),
            isFalse,
            reason: 'trecho $i de $rota atravessa a caixa do meio',
          );
        }
      }

      // E cada uma sai por um lado seu: nada de tres flechas no mesmo ponto.
      expect({paraMeio.first, paraCima.first, paraBaixo.first}.length, 3);
    });

    test('sem ninguem no caminho, a rota natural nao muda', () {
      final de = caixa('a', FormaDoNo.terminal, const Offset(140, 300));
      final para = caixa('b', FormaDoNo.processo, const Offset(420, 140));

      expect(
        DesenhoDoQuadro.rotaEntre(de, para, desviarDe: [de, para]),
        DesenhoDoQuadro.rotaEntre(de, para),
      );
    });

    test('o painel de fundo nao desvia flecha nenhuma', () {
      // Ele e cenario: as caixas moram em cima dele, e uma flecha que fugisse
      // dele fugiria do proprio quadro.
      final de = caixa('a', FormaDoNo.terminal, const Offset(140, 300));
      final para = caixa('b', FormaDoNo.processo, const Offset(420, 140));
      final fundo = caixa('f', FormaDoNo.fundo, const Offset(280, 220));

      expect(
        DesenhoDoQuadro.rotaEntre(de, para, desviarDe: [de, para, fundo]),
        DesenhoDoQuadro.rotaEntre(de, para),
      );
    });

    test('o rotulo cai sobre a linha, e nao ao lado dela', () {
      final decisao = caixa('a', FormaDoNo.decisao, const Offset(360, 320));
      final ramo = caixa('b', FormaDoNo.processo, const Offset(152, 496));
      final rota = DesenhoDoQuadro.rotaEntre(decisao, ramo);

      final meio = DesenhoDoQuadro.meioDaRota(rota);

      // No trecho de saida, que e horizontal e na altura do centro do losango.
      expect(meio.dy, rota.first.dy);
      expect(meio.dx, lessThan(rota.first.dx));
      expect(meio.dx, greaterThan(rota[1].dx));
    });
  });

  group('a borda de cada forma', () {
    test('no paralelogramo, o lado desconta a inclinaçao', () {
      final entrada = caixa('a', FormaDoNo.entrada, const Offset(300, 100));
      final meia = DesenhoDoQuadro.inclinacaoDe(entrada) / 2;

      expect(
        DesenhoDoQuadro.bordaDe(entrada, LadoDoNo.esquerda).dx,
        entrada.x + meia,
      );
      expect(
        DesenhoDoQuadro.bordaDe(entrada, LadoDoNo.direita).dx,
        entrada.x + entrada.largura - meia,
      );
      // Em cima e embaixo os lados sao retos, e o meio deles e o meio da caixa.
      expect(
        DesenhoDoQuadro.bordaDe(entrada, LadoDoNo.topo).dx,
        entrada.centroX,
      );
    });

    test('nas outras formas, o lado e a borda do retangulo', () {
      for (final forma in [
        FormaDoNo.terminal,
        FormaDoNo.processo,
        FormaDoNo.decisao,
        FormaDoNo.texto,
      ]) {
        final no = caixa('a', forma, const Offset(300, 100));
        expect(
          DesenhoDoQuadro.bordaDe(no, LadoDoNo.esquerda).dx,
          no.x,
          reason: forma.name,
        );
      }
    });
  });

  group('o imã de alinhamento', () {
    test('encosta o centro no centro da vizinha', () {
      final acima = caixa('a', FormaDoNo.terminal, const Offset(300, 100));
      final movida = caixa('b', FormaDoNo.processo, const Offset(305, 300));
      final quadro = QuadroDaNota(nos: [acima, movida], ligacoes: const []);

      final encostada = DesenhoDoQuadro.alinhar(quadro, movida);

      expect(encostada.no.centroX, acima.centroX);
      expect(encostada.guiaX, acima.centroX);
      expect(encostada.guiaY, isNull);
    });

    test('longe, nao puxa', () {
      final acima = caixa('a', FormaDoNo.terminal, const Offset(300, 100));
      final movida = caixa('b', FormaDoNo.processo, const Offset(400, 300));
      final quadro = QuadroDaNota(nos: [acima, movida], ligacoes: const []);

      final encostada = DesenhoDoQuadro.alinhar(quadro, movida);

      expect(encostada.no.centroX, movida.centroX);
      expect(encostada.guiaX, isNull);
    });
  });

  group('achando o traço debaixo do ponteiro', () {
    const risco = QuadroDaNota(
      nos: [],
      ligacoes: [],
      tracos: [
        TracoDoQuadro(id: 't1', pontos: [0, 0, 100, 0, 100, 100]),
      ],
    );

    test('em cima do traço, acha; longe dele, nao', () {
      expect(DesenhoDoQuadro.tracoEm(risco, const Offset(50, 0), 4)?.id, 't1');
      // No cotovelo, que e onde dois trechos se encontram.
      expect(
        DesenhoDoQuadro.tracoEm(risco, const Offset(100, 50), 4)?.id,
        't1',
      );
      expect(DesenhoDoQuadro.tracoEm(risco, const Offset(50, 60), 4), isNull);
    });

    test('a folga conta a partir da tinta, e nao do fio do meio', () {
      // Encostar num traço gordo e encostar na tinta dele.
      const gordo = QuadroDaNota(
        nos: [],
        ligacoes: [],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [0, 0, 100, 0], grossura: 16),
        ],
      );

      expect(DesenhoDoQuadro.tracoEm(gordo, const Offset(50, 7), 0)?.id, 't1');
      expect(DesenhoDoQuadro.tracoEm(gordo, const Offset(50, 9), 0), isNull);
    });

    test('o de cima ganha: e nele que a mao pensa estar encostando', () {
      const dois = QuadroDaNota(
        nos: [],
        ligacoes: [],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [0, 0, 100, 0]),
          TracoDoQuadro(id: 't2', pontos: [0, 0, 100, 0]),
        ],
      );

      expect(DesenhoDoQuadro.tracoEm(dois, const Offset(50, 0), 4)?.id, 't2');
    });
  });

  group('a area que o quadro ocupa', () {
    test('os traços contam tanto quanto as caixas', () {
      // Um quadro que e so rabisco ainda precisa caber na tela quando se pede
      // para enquadrar.
      const so = QuadroDaNota(
        nos: [],
        ligacoes: [],
        tracos: [
          TracoDoQuadro(id: 't1', pontos: [100, 200, 300, 50]),
        ],
      );

      final limites = DesenhoDoQuadro.limitesDe(so, folga: 0);
      expect(limites.left, 100);
      expect(limites.top, 50);
      expect(limites.right, 300);
      expect(limites.bottom, 200);
    });

    test('caixa e traço juntos entram os dois na conta', () {
      final quadro = QuadroDaNota(
        nos: [caixa('a', FormaDoNo.processo, const Offset(0, 0))],
        ligacoes: const [],
        tracos: const [
          TracoDoQuadro(id: 't1', pontos: [500, 500, 600, 600]),
        ],
      );

      final limites = DesenhoDoQuadro.limitesDe(quadro, folga: 0);
      expect(limites.right, 600);
      expect(limites.bottom, 600);
    });
  });

  group('o traço a mao', () {
    final reta = [const Offset(0, 0), const Offset(100, 0)];

    test('a mesma semente torce sempre igual', () {
      // Sem isto o desenho ficaria tremendo na tela feito gelatina: cada quadro
      // de animaçao torceria a mesma caixa para um lado diferente.
      final uma = MaoLivre.linha(reta, 42).computeMetrics().first.length;
      final outra = MaoLivre.linha(reta, 42).computeMetrics().first.length;

      expect(uma, outra);
    });

    test('sementes diferentes torcem diferente', () {
      final uma = MaoLivre.linha(reta, 1).computeMetrics().first.length;
      final outra = MaoLivre.linha(reta, 999).computeMetrics().first.length;

      expect(uma, isNot(closeTo(outra, 0.0001)));
    });

    test('o torto fica perto do certo, e nao em outro lugar', () {
      // Passando de dois ou tres pixels a caixa deixa de parecer desenhada a
      // mao e passa a parecer torta por defeito.
      final torta = MaoLivre.forma(
        DesenhoDoQuadro.caminhoDe(
          caixa('a', FormaDoNo.processo, const Offset(200, 200)),
        ),
        7,
      );
      final certa = DesenhoDoQuadro.retanguloDe(
        caixa('a', FormaDoNo.processo, const Offset(200, 200)),
      );

      final saiu = torta.getBounds();
      expect(saiu.left, closeTo(certa.left, MaoLivre.folga));
      expect(saiu.top, closeTo(certa.top, MaoLivre.folga));
      expect(saiu.right, closeTo(certa.right, MaoLivre.folga));
      expect(saiu.bottom, closeTo(certa.bottom, MaoLivre.folga));
    });

    test('a aresta reta sai em um trecho, e nao numa onda de cristas', () {
      // O defeito que este teste guarda: o contorno era lido de 26 em 26 pixels
      // e *todo* ponto lido era sacudido, entao uma aresta reta de duzentos
      // pixels saía com oito juntas tremendo — amassada, e nao desenhada.
      //
      // Contar juntas direto no `Path` nao da; o que da para contar e o quanto
      // a linha sobe e desce entre as duas pontas. Uma aresta feita a mao vai
      // para um lado so.
      final medida = MaoLivre.linha([
        const Offset(0, 0),
        const Offset(200, 0),
      ], 7).computeMetrics().first;

      var viradas = 0;
      double? anterior;
      var subindo = false;

      for (var i = 0; i <= 40; i++) {
        final ponto = medida.getTangentForOffset(medida.length * i / 40)!;
        final y = ponto.position.dy;
        if (anterior != null && (y - anterior).abs() > 0.02) {
          final agora = y > anterior;
          if (i > 1 && agora != subindo) viradas++;
          subindo = agora;
        }
        anterior = y;
      }

      // Uma barriga e uma virada: sobe e desce. Duas ja seriam onda.
      expect(viradas, lessThanOrEqualTo(2));
    });

    test('a curva da capsula sobrevive ao enxugamento', () {
      // O outro lado do mesmo ajuste: enxugar demais cortaria a volta da
      // capsula em reta, e o "Inicio/Fim" viraria um retangulo torto.
      final capsula = caixa('a', FormaDoNo.terminal, const Offset(200, 200));
      final torta = MaoLivre.forma(
        DesenhoDoQuadro.caminhoDe(capsula),
        7,
      ).getBounds();
      final certa = DesenhoDoQuadro.retanguloDe(capsula);

      // Uma capsula cortada em reta encolheria meia altura de cada lado.
      expect(torta.width, closeTo(certa.width, MaoLivre.folga * 2));
      expect(torta.height, closeTo(certa.height, MaoLivre.folga * 2));
    });

    test('o nome da caixa vira sempre a mesma semente', () {
      expect(MaoLivre.sementeDe('n1'), MaoLivre.sementeDe('n1'));
      expect(MaoLivre.sementeDe('n1'), isNot(MaoLivre.sementeDe('n2')));
    });
  });
}
