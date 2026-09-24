import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/quadro_da_nota.dart';
import '../models/wikilink.dart';
import 'app_theme.dart';

/// Por qual lado de uma caixa a flecha entra ou sai.
enum LadoDoNo { topo, direita, base, esquerda }

/// A geometria do quadro: onde cada caixa esta na area, por onde as flechas
/// passam e o que esta debaixo do ponteiro.
///
/// Tudo aqui trabalha em coordenadas do *quadro*, nao da tela. Zoom e
/// deslocamento sao assunto de quem desenha, e nada disso e gravado no `.md`.
abstract final class DesenhoDoQuadro {
  /// A malha invisivel em que as caixas se encaixam.
  ///
  /// Arrastar livre deixa tudo um grau fora de esquadro, e um fluxograma torto
  /// se le pior do que um alinhado. Oito pixels e fino o bastante para o
  /// arrasto continuar parecendo livre.
  static const malha = 8.0;

  /// A que distancia a caixa arrastada encosta no alinhamento de outra.
  ///
  /// Curto de proposito: o imã ajuda a acertar o que a mao ja estava tentando
  /// acertar, e nao decide onde a caixa fica.
  static const ima = 7.0;

  /// Espaço entre uma caixa e a seguinte, quando o quadro escolhe o lugar.
  static const respiro = 72.0;

  /// Raio dos pontos de ligar, e a folga com que o ponteiro os encontra.
  ///
  /// A folga e quase o triplo do desenho, de proposito. O ponto e pequeno
  /// porque um alvo grande e azul no meio do desenho pesa mais que o desenho;
  /// a area de pegada nao precisa encolher junto com ele, e acertar tres
  /// pixels seria pontaria.
  static const raioDaAncora = 3.0;
  static const folgaDaAncora = 9.0;

  /// O quanto as bolinhas ficam para fora da borda.
  ///
  /// Fora, e nao em cima: por dentro da borda a area delas era area da caixa,
  /// e um arrasto que devia mover a caixa saia puxando uma flecha. Assim quase
  /// toda a folga de pegada cai no lado de fora, onde nao ha o que atrapalhar.
  static const foraDaBorda = 5.0;

  /// Lado do quadradinho de redimensionar, no canto de baixo a direita, e a
  /// folga de pegada dele — curta, pelo mesmo motivo das bolinhas.
  static const cantoDeTamanho = 12.0;
  static const folgaDoCanto = 9.0;

  static Rect retanguloDe(NoDoQuadro no) =>
      Rect.fromLTWH(no.x, no.y, no.largura, no.altura);

  static Offset centroDe(NoDoQuadro no) => Offset(no.centroX, no.centroY);

  /// Quanto espaço a moldura come de cada lado antes de sobrar lugar para o
  /// texto.
  ///
  /// Uma conta so, e nao uma em quem pinta e outra em quem poe o campo por
  /// cima: eram duas, e bastava uma delas mudar para o texto saltar de lugar no
  /// instante em que se acabava de escreve-lo.
  static double folgaDoTexto(NoDoQuadro no) => switch (no.forma) {
    FormaDoNo.decisao => no.largura * 0.22,
    // A curva da elipse aperta menos que a ponta do losango, mas aperta.
    FormaDoNo.elipse => no.largura * 0.15,
    FormaDoNo.entrada => inclinacaoDe(no) + 6,
    FormaDoNo.fundo => 12.0,
    _ => 10.0,
  };

  /// O tamanho que uma anotaçao solta precisa ter para caber [texto].
  ///
  /// A anotaçao solta nao tem moldura: a "caixa" dela e so a area que o texto
  /// ocupa. Entao ela nao e redimensionada a mao como as outras — ela acompanha
  /// o que foi escrito, e quem escreve nao precisa pensar em tamanho nenhum.
  ///
  /// Os numeros aqui sao os mesmos com que [QuadroPintado] pinta o texto de uma
  /// anotaçao. Tem que ser: medir com uma fonte e pintar com outra poria o
  /// texto para fora da area que ele mesmo definiu.
  static ({double largura, double altura}) tamanhoDoTexto(
    String texto,
    NoDoQuadro no, {
    required bool aMao,
    double larguraMaxima = 420,
  }) {
    final folga = folgaDoTexto(no);

    final pintor = TextPainter(
      text: TextSpan(
        // Vazio, ele ainda precisa da altura de uma linha: sem isso a area
        // encolheria a nada no instante em que se apagasse a ultima letra, e o
        // cursor sumiria junto.
        text: texto.isEmpty ? ' ' : texto,
        style: const TextStyle(
          fontSize: 13,
          height: 1.3,
        ).merge(aMao ? MaoLivre.letra : null),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(40, larguraMaxima - folga * 2));

    return (
      largura: math.max(NoDoQuadro.larguraMinima, pintor.width + folga * 2),
      altura: math.max(NoDoQuadro.alturaMinima, pintor.height + 12),
    );
  }

  /// A tinta de cada cor com nome.
  ///
  /// E aqui que o nome guardado no `.md` vira cor de verdade — e e por isso que
  /// o mesmo arquivo continua legivel num tema que nao seja este. Fora do
  /// pintor porque a barra de ferramentas precisa da mesma resposta: os
  /// botoezinhos de cor tem que mostrar a tinta que vai sair, e nao uma segunda
  /// tabela parecida com esta.
  static Color tintaDe(CorDoTraco cor, ColorScheme cores) => switch (cor) {
    CorDoTraco.tinta => cores.onSurface,
    CorDoTraco.indigo => cores.primary,
    CorDoTraco.ceu => AppTheme.realce,
    CorDoTraco.verde => const Color(0xFF7FD1A3),
    CorDoTraco.ambar => const Color(0xFFE8C07A),
    CorDoTraco.rosa => AppTheme.tag,
  };

  /// O quanto o paralelogramo se inclina, em pixels de cada lado.
  static double inclinacaoDe(NoDoQuadro no) =>
      no.forma == FormaDoNo.entrada ? no.largura * 0.16 : 0;

  /// O contorno de cada forma. E ele que e preenchido, contornado e usado como
  /// recorte — desenhar losango e capsula a mao em cada lugar seria repetir a
  /// mesma conta em tres arquivos.
  static Path caminhoDe(NoDoQuadro no) {
    final r = retanguloDe(no);

    switch (no.forma) {
      case FormaDoNo.terminal:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)));
      case FormaDoNo.processo:
      case FormaDoNo.texto:
        return Path()..addRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(AppTheme.radiusSm)),
        );
      case FormaDoNo.fundo:
        return Path()..addRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(AppTheme.radiusLg)),
        );
      case FormaDoNo.entrada:
        final inclinacao = inclinacaoDe(no);
        return Path()
          ..moveTo(r.left + inclinacao, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right - inclinacao, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
      case FormaDoNo.decisao:
        return Path()
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, r.center.dy)
          ..close();
      case FormaDoNo.elipse:
        return Path()..addOval(r);
    }
  }

  /// O caminho de um traço solto.
  ///
  /// A mao livre passa por curvas, e nao de ponto a ponto: o ponteiro entrega
  /// uma coordenada por quadro de animaçao, e ligar isso com retas deixa o
  /// traço serrilhado justamente nas curvas, que e onde a mao faz o desenho. A
  /// curva passa pelo *meio* de cada par de pontos, usando o ponto entre eles
  /// como guia — o jeito barato de suavizar que nao precisa saber o traço
  /// inteiro de antemao.
  static Path caminhoDoTraco(TracoDoQuadro traco) {
    final caminho = Path()..moveTo(traco.x(0), traco.y(0));

    if (traco.tipo.ePonta || traco.quantos == 2) {
      caminho.lineTo(traco.x(traco.quantos - 1), traco.y(traco.quantos - 1));
      return caminho;
    }

    for (var i = 1; i < traco.quantos - 1; i++) {
      caminho.quadraticBezierTo(
        traco.x(i),
        traco.y(i),
        (traco.x(i) + traco.x(i + 1)) / 2,
        (traco.y(i) + traco.y(i + 1)) / 2,
      );
    }

    // O ultimo ponto e o unico que a curva nao alcança sozinha: ela para no
    // meio do penultimo par. Sem esta reta, o traço acaba um passo antes de
    // onde a mao soltou.
    caminho.lineTo(traco.x(traco.quantos - 1), traco.y(traco.quantos - 1));
    return caminho;
  }

  /// O traço que passa a menos de [folga] de [ponto].
  ///
  /// De tras para a frente, como em tudo o mais: o que foi desenhado por
  /// ultimo esta por cima, e e nele que a mao pensa estar encostando.
  static TracoDoQuadro? tracoEm(
    QuadroDaNota quadro,
    Offset ponto,
    double folga,
  ) {
    for (final traco in quadro.tracos.reversed) {
      // A grossura conta: encostar num traço gordo e encostar na tinta dele,
      // e nao na linha de espessura zero que passa pelo meio.
      final alcance = folga + traco.grossura / 2;

      for (var i = 0; i < traco.quantos - 1; i++) {
        final distancia = _distanciaDoTrecho(
          Offset(traco.x(i), traco.y(i)),
          Offset(traco.x(i + 1), traco.y(i + 1)),
          ponto,
        );
        if (distancia <= alcance) return traco;
      }
    }
    return null;
  }

  /// O ponto da borda por onde uma flecha entra ou sai de cada lado.
  ///
  /// E o meio do lado, e nao o canto: em qualquer das formas o meio do lado cai
  /// sobre a borda desenhada — inclusive na ponta do losango. No paralelogramo
  /// os lados sao inclinados, e o meio deles esta meia inclinaçao para dentro
  /// do retangulo; sem esse desconto a flecha encostaria no vazio ao lado da
  /// figura.
  static Offset bordaDe(NoDoQuadro no, LadoDoNo lado) {
    final r = retanguloDe(no);
    final meia = inclinacaoDe(no) / 2;

    return switch (lado) {
      LadoDoNo.topo => Offset(r.center.dx, r.top),
      LadoDoNo.base => Offset(r.center.dx, r.bottom),
      LadoDoNo.direita => Offset(r.right - meia, r.center.dy),
      LadoDoNo.esquerda => Offset(r.left + meia, r.center.dy),
    };
  }

  /// As quatro bolinhas de ligar, um dedo para fora do meio de cada lado —
  /// para fora para nao roubar area de arrasto da propria caixa.
  static List<Offset> ancorasDe(NoDoQuadro no) => [
    bordaDe(no, LadoDoNo.topo) - const Offset(0, foraDaBorda),
    bordaDe(no, LadoDoNo.direita) + const Offset(foraDaBorda, 0),
    bordaDe(no, LadoDoNo.base) + const Offset(0, foraDaBorda),
    bordaDe(no, LadoDoNo.esquerda) - const Offset(foraDaBorda, 0),
  ];

  /// O caminho de uma flecha, de borda a borda, em dois a quatro pontos.
  ///
  /// Em angulo reto, e nao em linha reta na diagonal: e assim que fluxograma
  /// se le, e e o que mantem duas flechas paralelas sem se cruzarem por acaso.
  ///
  /// [desviarDe] sao as outras caixas do quadro. O caminho natural — o que as
  /// duas caixas teriam se estivessem sozinhas — continua sendo a primeira
  /// escolha; as outras maneiras de fazer o mesmo trajeto so entram quando ele
  /// passaria por dentro de uma terceira caixa. Sem isso, prender tres caixas
  /// a uma so empilhava as flechas no mesmo trecho e furava quem estivesse no
  /// meio: o que aparecia na tela era uma linha atravessada numa caixa, e nao
  /// tres setas.
  static List<Offset> rotaEntre(
    NoDoQuadro de,
    NoDoQuadro para, {
    Iterable<NoDoQuadro> desviarDe = const [],
  }) {
    final natural = _rotaNatural(de, para);

    final atrapalham = [
      for (final no in desviarDe)
        if (no.id != de.id && no.id != para.id && ligavel(no))
          retanguloDe(no).inflate(_desvio),
    ];
    if (atrapalham.isEmpty) return natural;

    var melhor = natural;
    var furos = _quantasCorta(natural, atrapalham);

    for (final outro in _outrosCaminhos(de, para)) {
      if (furos == 0) break;
      // Caminho que passa por dentro da propria caixa de saida, ou da de
      // chegada, nao serve de alternativa: a flecha sairia de tras da figura.
      if (_quantasCorta(outro, _proprias(de, para)) > 0) continue;

      final quantas = _quantasCorta(outro, atrapalham);
      if (quantas < furos) {
        melhor = outro;
        furos = quantas;
      }
    }

    return melhor;
  }

  /// O caminho que as duas caixas teriam se estivessem sozinhas no quadro.
  ///
  /// A saida escolhida e a do lado para onde a outra caixa esta — para baixo
  /// quando ela esta embaixo, para o lado quando esta ao lado —, e a curva
  /// quebra na metade do caminho.
  ///
  /// Duas caixas *quase* alinhadas ganham um traço reto, saindo pelo meio do
  /// desencontro. Exigir alinhamento exato enchia o quadro de degrauzinhos:
  /// bastavam cinco pixels de diferença entre os centros — invisiveis nas
  /// caixas — para a flecha entre elas dar um passo de lado bem visivel. Perto
  /// o suficiente, portanto, e alinhado.
  static List<Offset> _rotaNatural(NoDoQuadro de, NoDoQuadro para) {
    final a = centroDe(de);
    final b = centroDe(para);

    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;

    // 1. Alinhadas: uma reta, saindo pelo meio do desencontro que sobrar.
    if (dx.abs() <= dy.abs() &&
        dx.abs() <= _tolerancia(de.largura, para.largura)) {
      return _retaEmPe(de, para);
    }
    if (dy.abs() < dx.abs() &&
        dy.abs() <= _tolerancia(de.altura, para.altura)) {
      return _retaDeitada(de, para);
    }

    // 2. Desencontro nos dois eixos: um L, com a virada unica.
    //
    // Sai pelo eixo em que a distancia e maior e entra pelo outro — e o
    // desenho da ramificaçao de um fluxograma: a decisao solta a flecha pelo
    // lado, ela corre na horizontal e desce na cabeça do passo seguinte; o
    // passo que volta para o fim solta por baixo, desce e entra pelo lado.
    //
    // Dois cotovelos (o degrau em Z) so quando o L passaria por dentro do
    // alvo, o que acontece quando as duas caixas se sobrepoem no outro eixo.
    final alvo = retanguloDe(para);

    if (dx.abs() >= dy.abs()) {
      return _pegaNaFaixa(a.dy, alvo.top, alvo.bottom)
          ? _degrauDeitado(de, para)
          : _cotoveloDeitado(de, para);
    }

    return _pegaNaFaixa(a.dx, alvo.left, alvo.right)
        ? _degrauEmPe(de, para)
        : _cotoveloEmPe(de, para);
  }

  /// As outras maneiras de ir de uma caixa a outra em angulo reto, na ordem em
  /// que o desenho as prefere: os dois cotovelos simples primeiro, e depois os
  /// degraus, que custam uma virada a mais.
  ///
  /// Quatro caminhos prontos, e nao um contorno calculado em volta de quem
  /// atrapalha: sao as formas que o fluxograma ja usa, e escolher entre elas
  /// mantem toda flecha do quadro com o mesmo desenho — a que desviou de
  /// alguem nao fica com um jeitao proprio.
  static List<List<Offset>> _outrosCaminhos(NoDoQuadro de, NoDoQuadro para) => [
    _cotoveloDeitado(de, para),
    _cotoveloEmPe(de, para),
    _degrauDeitado(de, para),
    _degrauEmPe(de, para),
  ];

  /// Reta em pe, pelo meio do desencontro entre os dois centros.
  static List<Offset> _retaEmPe(NoDoQuadro de, NoDoQuadro para) {
    final x = (de.centroX + para.centroX) / 2;
    final descendo = para.centroY >= de.centroY;

    return [
      Offset(x, bordaDe(de, descendo ? LadoDoNo.base : LadoDoNo.topo).dy),
      Offset(x, bordaDe(para, descendo ? LadoDoNo.topo : LadoDoNo.base).dy),
    ];
  }

  /// Reta deitada, pelo meio do desencontro entre os dois centros.
  static List<Offset> _retaDeitada(NoDoQuadro de, NoDoQuadro para) {
    final y = (de.centroY + para.centroY) / 2;
    final indo = para.centroX >= de.centroX;

    return [
      Offset(bordaDe(de, indo ? LadoDoNo.direita : LadoDoNo.esquerda).dx, y),
      Offset(bordaDe(para, indo ? LadoDoNo.esquerda : LadoDoNo.direita).dx, y),
    ];
  }

  /// L deitado: sai pelo lado, corre na horizontal e entra pela cabeça — ou
  /// pelo pe — da outra caixa.
  static List<Offset> _cotoveloDeitado(NoDoQuadro de, NoDoQuadro para) {
    final saida = bordaDe(
      de,
      para.centroX >= de.centroX ? LadoDoNo.direita : LadoDoNo.esquerda,
    );
    final chegada = bordaDe(
      para,
      para.centroY >= de.centroY ? LadoDoNo.topo : LadoDoNo.base,
    );

    return [saida, Offset(chegada.dx, saida.dy), chegada];
  }

  /// L em pe: sai por baixo — ou por cima —, corre na vertical e entra pelo
  /// lado da outra caixa.
  static List<Offset> _cotoveloEmPe(NoDoQuadro de, NoDoQuadro para) {
    final saida = bordaDe(
      de,
      para.centroY >= de.centroY ? LadoDoNo.base : LadoDoNo.topo,
    );
    final chegada = bordaDe(
      para,
      para.centroX >= de.centroX ? LadoDoNo.esquerda : LadoDoNo.direita,
    );

    return [saida, Offset(saida.dx, chegada.dy), chegada];
  }

  /// Degrau deitado: sai por um lado, atravessa o vao na metade do caminho e
  /// entra pelo lado oposto da outra caixa.
  static List<Offset> _degrauDeitado(NoDoQuadro de, NoDoQuadro para) {
    final indo = para.centroX >= de.centroX;
    final saida = bordaDe(de, indo ? LadoDoNo.direita : LadoDoNo.esquerda);
    final chegada = bordaDe(para, indo ? LadoDoNo.esquerda : LadoDoNo.direita);
    final meio = (saida.dx + chegada.dx) / 2;

    return [saida, Offset(meio, saida.dy), Offset(meio, chegada.dy), chegada];
  }

  /// Degrau em pe: sai por cima ou por baixo, atravessa o vao na metade do
  /// caminho e entra pela face oposta da outra caixa.
  static List<Offset> _degrauEmPe(NoDoQuadro de, NoDoQuadro para) {
    final descendo = para.centroY >= de.centroY;
    final saida = bordaDe(de, descendo ? LadoDoNo.base : LadoDoNo.topo);
    final chegada = bordaDe(para, descendo ? LadoDoNo.topo : LadoDoNo.base);
    final meio = (saida.dy + chegada.dy) / 2;

    return [saida, Offset(saida.dx, meio), Offset(chegada.dx, meio), chegada];
  }

  /// O quanto uma caixa alheia afasta a flecha de si.
  ///
  /// Passar raspando na borda de uma caixa parece erro tanto quanto
  /// atravessa-la. Meia malha e o bastante para tirar a flecha de cima da
  /// linha sem fechar o corredor entre duas caixas vizinhas.
  static const _desvio = malha / 2;

  /// A caixa de onde a flecha sai e a que ela procura, um fio para dentro.
  ///
  /// A rota encosta nas bordas das duas de proposito; e passar *por dentro*
  /// delas que desqualifica um caminho.
  static List<Rect> _proprias(NoDoQuadro de, NoDoQuadro para) => [
    retanguloDe(de).deflate(1),
    retanguloDe(para).deflate(1),
  ];

  /// De quantas das [areas] a rota passa por dentro.
  static int _quantasCorta(List<Offset> rota, List<Rect> areas) {
    var total = 0;

    for (final area in areas) {
      for (var i = 1; i < rota.length; i++) {
        if (_cortaArea(rota[i - 1], rota[i], area)) {
          total++;
          break;
        }
      }
    }

    return total;
  }

  /// Se o trecho reto de [a] a [b] entra em [area].
  ///
  /// Os trechos de uma rota sao sempre horizontais ou verticais, entao basta
  /// cruzar as duas faixas: nao ha diagonal para intersectar.
  static bool _cortaArea(Offset a, Offset b, Rect area) =>
      math.min(a.dx, b.dx) < area.right &&
      math.max(a.dx, b.dx) > area.left &&
      math.min(a.dy, b.dy) < area.bottom &&
      math.max(a.dy, b.dy) > area.top;

  /// Se [valor] cai dentro da faixa, com uma folga para a flecha nao passar
  /// raspando na quina do alvo.
  static bool _pegaNaFaixa(double valor, double de, double ate) =>
      valor > de - 12 && valor < ate + 12;

  /// Quanto desencontro ainda conta como alinhado, entre duas caixas dessas
  /// medidas.
  ///
  /// Uma fraçao da menor das duas, e nao um numero fixo: o que passa por
  /// alinhado num retangulo largo seria um deslocamento grosseiro numa caixa
  /// estreita. O teto existe para caixas enormes nao engolirem desencontro de
  /// verdade.
  static double _tolerancia(double umLado, double outroLado) =>
      math.min(20.0, math.min(umLado, outroLado) * 0.22);

  /// O ponto do caminho onde o rotulo da flecha e escrito.
  ///
  /// Sempre *sobre* a linha, nunca no meio geometrico entre as pontas: numa
  /// rota com cotovelo esse meio cai fora do caminho, e o "Sim" de uma decisao
  /// apareceria solto no vazio ao lado da flecha.
  static Offset meioDaRota(List<Offset> rota) {
    if (rota.length < 2) return rota.isEmpty ? Offset.zero : rota.first;

    // Com quatro pontos, o meio do trecho do meio — o que atravessa o vao
    // entre as duas caixas.
    if (rota.length >= 4) return _meioEntre(rota[1], rota[2]);

    // Com tres, o meio do trecho de saida: e ali, junto da caixa de onde a
    // flecha nasce, que o rotulo de um ramo precisa ser lido.
    if (rota.length == 3) return _meioEntre(rota[0], rota[1]);

    return _meioEntre(rota.first, rota.last);
  }

  static Offset _meioEntre(Offset a, Offset b) =>
      Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  /// Quao longe [ponto] esta do caminho — a menor distancia a algum trecho
  /// dele. E por aqui que um clique acha a flecha que quis acertar.
  static double distanciaDaRota(List<Offset> rota, Offset ponto) {
    var menor = double.infinity;
    for (var i = 0; i + 1 < rota.length; i++) {
      menor = math.min(menor, _distanciaDoTrecho(rota[i], rota[i + 1], ponto));
    }
    return menor;
  }

  static double _distanciaDoTrecho(Offset a, Offset b, Offset p) {
    final ab = b - a;
    final comprimento = ab.distanceSquared;
    if (comprimento == 0) return (p - a).distance;

    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / comprimento).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  /// A caixa que esta debaixo de [ponto], ou nulo. De frente para tras: a
  /// ultima desenhada e a que esta por cima.
  ///
  /// Os fundos ficam para o fim da fila, na mesma ordem em que sao desenhados:
  /// um painel cobre a area das caixas que ele agrupa, e se fosse pego antes
  /// delas nao daria mais para tocar em nada que estivesse em cima dele.
  ///
  /// [folga] alarga a caixa para os lados sem desenha-la maior. Serve para o
  /// que mora na beirada: as bolinhas de ligar ficam do lado de fora, e sem
  /// essa folga elas desapareceriam justamente quando a mao vai pega-las.
  static NoDoQuadro? noEm(
    QuadroDaNota quadro,
    Offset ponto, {
    double folga = 0,
  }) {
    for (final no in quadro.nos.reversed) {
      if (no.forma.eFundo) continue;
      if (retanguloDe(no).inflate(folga).contains(ponto)) return no;
    }
    for (final no in quadro.nos.reversed) {
      if (!no.forma.eFundo) continue;
      if (retanguloDe(no).inflate(folga).contains(ponto)) return no;
    }
    return null;
  }

  /// Se este no participa do fluxo — se pode receber flecha, encostar no imã
  /// de alinhamento e, no geral, ter algo preso a ele.
  ///
  /// O painel de fundo nao participa: ele e um item solto, que so ocupa uma
  /// area atras dos outros. Estar por cima dele nao prende uma caixa a ele, e
  /// arrasta-lo nao arrasta nada.
  static bool ligavel(NoDoQuadro no) => !no.forma.eFundo;

  /// A flecha que passa a menos de [folga] de [ponto], se houver, pelo indice
  /// dela na lista de ligaçoes.
  static int? ligacaoEm(QuadroDaNota quadro, Offset ponto, double folga) {
    var achada = -1;
    var menor = folga;

    for (var i = 0; i < quadro.ligacoes.length; i++) {
      final ligacao = quadro.ligacoes[i];
      final de = quadro.no(ligacao.de);
      final para = quadro.no(ligacao.para);
      if (de == null || para == null) continue;

      final distancia = distanciaDaRota(
        rotaEntre(de, para, desviarDe: quadro.nos),
        ponto,
      );
      if (distancia <= menor) {
        menor = distancia;
        achada = i;
      }
    }

    return achada < 0 ? null : achada;
  }

  /// Encosta [movido] no alinhamento das outras caixas de [quadro].
  ///
  /// Alinhar centro com centro e o que faz a flecha sair reta, e acertar isso
  /// so com a mao e trabalho de pontaria: dois pixels de diferença nao se veem
  /// na caixa, mas se veem no degrau da flecha. O imã resolve na hora do
  /// arrasto o que o olho so notaria depois.
  ///
  /// Devolve tambem por onde passa o alinhamento encontrado, para quem desenha
  /// poder mostrar a linha-guia — sem ela, a caixa "grudaria" sem explicaçao.
  static ({NoDoQuadro no, double? guiaX, double? guiaY}) alinhar(
    QuadroDaNota quadro,
    NoDoQuadro movido,
  ) {
    double? guiaX;
    double? guiaY;
    var x = movido.x;
    var y = movido.y;

    // O painel de fundo fica fora do imã, nos dois sentidos: alinhar o centro
    // de uma caixa com o centro de um painel nao quer dizer nada, e ele e um
    // item solto — nao ha por que ele grudar em nada.
    if (!ligavel(movido)) return (no: movido, guiaX: null, guiaY: null);

    // Do mais perto para o mais longe: com duas caixas dentro do imã, ganha a
    // que a mao estava mais perto de acertar.
    var menorX = ima;
    var menorY = ima;

    for (final outro in quadro.nos) {
      if (outro.id == movido.id || !ligavel(outro)) continue;

      final distanciaX = (outro.centroX - movido.centroX).abs();
      if (distanciaX <= menorX) {
        menorX = distanciaX;
        guiaX = outro.centroX;
        x = outro.centroX - movido.largura / 2;
      }

      final distanciaY = (outro.centroY - movido.centroY).abs();
      if (distanciaY <= menorY) {
        menorY = distanciaY;
        guiaY = outro.centroY;
        y = outro.centroY - movido.altura / 2;
      }
    }

    return (no: movido.com(x: x, y: y), guiaX: guiaX, guiaY: guiaY);
  }

  /// A area que o conteudo ocupa, com uma folga em volta. Vazio, devolve uma
  /// area de tamanho razoavel em volta da origem — e onde a primeira caixa vai
  /// cair.
  static Rect limitesDe(QuadroDaNota quadro, {double folga = 48}) {
    if (quadro.semNada) {
      return const Rect.fromLTWH(0, 0, 480, 320);
    }

    var esquerda = double.infinity;
    var topo = double.infinity;
    var direita = -double.infinity;
    var base = -double.infinity;

    for (final no in quadro.nos) {
      esquerda = math.min(esquerda, no.x);
      topo = math.min(topo, no.y);
      direita = math.max(direita, no.x + no.largura);
      base = math.max(base, no.y + no.altura);
    }

    // Os traços contam tanto quanto as caixas: um quadro que e so rabisco
    // ainda precisa caber na tela quando se pede para enquadrar.
    for (final traco in quadro.tracos) {
      final r = traco.limites;
      esquerda = math.min(esquerda, r.esquerda);
      topo = math.min(topo, r.topo);
      direita = math.max(direita, r.direita);
      base = math.max(base, r.base);
    }

    return Rect.fromLTRB(
      esquerda - folga,
      topo - folga,
      direita + folga,
      base + folga,
    );
  }

  /// O zoom e o deslocamento que fazem [conteudo] caber em [area], centrado.
  ///
  /// [maximo] segura a ampliaçao: um quadro de duas caixinhas esticado para
  /// preencher a tela fica com letras de cartaz e nenhum contexto em volta.
  static ({Offset pan, double escala}) enquadrar(
    Rect conteudo,
    Size area, {
    double maximo = 1,
    double minimo = 0.1,
  }) {
    if (area.isEmpty || conteudo.isEmpty) {
      return (pan: Offset.zero, escala: 1);
    }

    final escala = math
        .min(area.width / conteudo.width, area.height / conteudo.height)
        .clamp(minimo, maximo);

    return (
      pan: Offset(
        (area.width - conteudo.width * escala) / 2 - conteudo.left * escala,
        (area.height - conteudo.height * escala) / 2 - conteudo.top * escala,
      ),
      escala: escala,
    );
  }
}

/// O traço de quem desenhou a mao, em vez de a regua.
///
/// Um fluxograma de linhas perfeitas parece uma decisao ja tomada, e quase
/// nenhum quadro dentro de uma nota e isso: e um rascunho pensando alto. O
/// traço torto diz "ainda estou mexendo nisto" sem precisar de uma legenda, e e
/// por isso que o Excalidraw desenha assim.
///
/// O torto e sorteado, mas nao muda: a semente sai do nome da caixa, entao a
/// mesma caixa sai torta do mesmo jeito em todo quadro de animaçao. Sem isso o
/// desenho ficaria tremendo na tela feito gelatina.
abstract final class MaoLivre {
  /// O quanto cada ponto sai do lugar certo, em pixels do quadro.
  ///
  /// Pouco de proposito: passando de dois ou tres pixels a caixa deixa de
  /// parecer desenhada a mao e passa a parecer torta por defeito.
  static const desvio = 0.9;

  /// A barriga de um trecho: o quanto o meio dele se afasta da reta entre as
  /// duas pontas.
  ///
  /// Proporcional ao comprimento, com teto. Uma barriga fixa entortaria um
  /// traço de vinte pixels tanto quanto um de duzentos — e num traço curto isso
  /// nao le como mao livre, le como erro. O teto existe pelo motivo oposto: sem
  /// ele, a aresta de uma caixa larga viraria um arco.
  static const barrigaPorPixel = 0.012;
  static const barrigaMaxima = 1.4;

  /// O quanto, no total, o traço pode se afastar de onde a regua o poria.
  ///
  /// E a soma do que sai da ponta com o que sai do meio. Serve a quem precisa
  /// saber de quanto e a folga — o teste, sobretudo — sem refazer a conta.
  static const folga = desvio + barrigaMaxima;

  /// De quantos em quantos pixels o contorno de uma forma e lido.
  ///
  /// Curto, porque esta leitura so serve para *achar* o formato: o que sobra
  /// dela depois de [_enxugar] e que vira traço. Longo demais, a volta da
  /// capsula e o canto arredondado do retangulo eram cortados em reta — era o
  /// que fazia os cantos parecerem amassados para dentro.
  static const leitura = 6.0;

  /// O quanto um ponto lido pode estar fora da reta entre os vizinhos dele e
  /// ainda assim ser jogado fora.
  ///
  /// E o numero que separa "aresta reta" de "curva". Abaixo dele o ponto nao
  /// diz nada que a reta ja nao diga, e guarda-lo so daria a essa aresta mais
  /// uma junta para tremer — que era o defeito: uma aresta reta de duzentos
  /// pixels saía como uma onda de oito cristas em vez de uma linha.
  static const tolerancia = 0.7;

  /// A fonte do texto dentro das caixas.
  ///
  /// Uma fonte do sistema, e nao um arquivo dentro do app: uma manuscrita com
  /// licença para embarcar seria mais um binario no repositorio e mais uma
  /// licença para cuidar.
  ///
  /// E uma humanista, e nao uma manuscrita. A unica manuscrita que o Windows
  /// ainda traz e a Ink Free, e ela e garranchada demais para caber num desenho
  /// que se quer limpo: o desenho fica rascunho, o texto fica ilegivel, e os
  /// dois brigam. A Candara tem a letra aberta e um pouco irregular de quem
  /// escreveu com pena, sem nada de cursivo — ela acompanha o traço torto em vez
  /// de disputar com ele. Quem desenha e a forma; o texto so precisa nao parecer
  /// um campo de formulario.
  static const fonte = 'Candara';
  static const fontesAlternativas = ['Corbel', 'Segoe UI'];

  /// A fonte pronta para ser aplicada.
  ///
  /// Num lugar so porque tres partes precisam da *mesma* resposta: quem pinta
  /// o texto, quem poe o campo de escrita por cima dele, e quem mede o texto
  /// para a anotaçao solta crescer. Se uma delas usasse outra fonte, a palavra
  /// saltaria de tamanho no instante em que se parasse de escreve-la.
  static const letra = TextStyle(
    fontFamily: fonte,
    fontFamilyFallback: fontesAlternativas,
  );

  /// A mesma forma, torta. [semente] e o que faz duas caixas iguais saírem
  /// diferentes uma da outra, e cada uma delas sair sempre igual a si mesma.
  static Path forma(Path caminho, int semente, {double desvio = desvio}) {
    final saida = Path();

    for (final pontos in _contornos(caminho)) {
      if (pontos.length >= 2) {
        _torcer(saida, pontos, semente, desvio);
        semente++;
      }
    }

    return saida;
  }

  /// O mesmo para um caminho que ja veio em pontos — a rota de uma flecha, por
  /// exemplo, que nao precisa ser reamostrada porque ja e curta e reta.
  static Path linha(
    List<Offset> pontos,
    int semente, {
    double desvio = desvio,
  }) {
    final saida = Path();
    if (pontos.length >= 2) _torcer(saida, pontos, semente, desvio);
    return saida;
  }

  /// Um numero estavel tirado de um texto — o id da caixa, quase sempre.
  static int sementeDe(String texto) {
    var soma = 0x811C9DC5;
    for (final unidade in texto.codeUnits) {
      soma = ((soma ^ unidade) * 0x01000193) & 0x7FFFFFFF;
    }
    return soma;
  }

  /// Os contornos de [caminho], em poucos pontos: os que fazem o formato.
  ///
  /// Duas etapas. Primeiro o caminho e lido miudo, de [leitura] em [leitura]
  /// pixels, para nao perder nenhuma curva; depois [_enxugar] joga fora todo
  /// ponto que a reta entre os vizinhos ja explicava. O que sobra e o retangulo
  /// em quatro pontos, a capsula com a volta dela, a elipse com a curva — cada
  /// forma com o *minimo* de juntas que ela precisa.
  ///
  /// E esse minimo que faz a diferença: cada junta e um lugar onde o traço
  /// treme, e uma aresta reta cheia de juntas nao parece desenhada a mao,
  /// parece amassada.
  ///
  /// Pelo caminho ja pronto, e nao por uma tabela de pontos por forma: assim a
  /// capsula, o losango e a elipse passam pelo mesmo lugar, e uma forma nova
  /// fica torta sem escrever nada aqui.
  static List<List<Offset>> _contornos(Path caminho) {
    final contornos = <List<Offset>>[];

    for (final medida in caminho.computeMetrics()) {
      final comprimento = medida.length;
      if (comprimento <= 0) continue;

      final quantos = math.max(4, (comprimento / leitura).round());
      final lidos = <Offset>[];

      for (var i = 0; i <= quantos; i++) {
        final tangente = medida.getTangentForOffset(comprimento * i / quantos);
        if (tangente != null) lidos.add(tangente.position);
      }

      if (lidos.length >= 2) contornos.add(_enxugar(lidos));
    }

    return contornos;
  }

  /// Tira de [pontos] os que nao mudam o formato.
  ///
  /// Guarda as duas pontas e, entre elas, o ponto que mais se afasta da reta
  /// que as liga; se nem esse se afasta mais que [tolerancia], o trecho inteiro
  /// vira uma reta so. Depois repete dos dois lados do ponto guardado.
  static List<Offset> _enxugar(List<Offset> pontos) {
    if (pontos.length <= 2) return pontos;

    var maior = 0.0;
    var onde = 0;

    for (var i = 1; i < pontos.length - 1; i++) {
      final distancia = DesenhoDoQuadro._distanciaDoTrecho(
        pontos.first,
        pontos.last,
        pontos[i],
      );
      if (distancia > maior) {
        maior = distancia;
        onde = i;
      }
    }

    if (maior <= tolerancia) return [pontos.first, pontos.last];

    return [
      ..._enxugar(pontos.sublist(0, onde + 1)),
      // O ponto da dobra ja veio no fim da primeira metade.
      ..._enxugar(pontos.sublist(onde)).skip(1),
    ];
  }

  /// Torce [pontos] e escreve o resultado em [saida].
  ///
  /// Cada ponto sai um pouco do lugar *e* o meio de cada trecho ganha uma
  /// barriga para o lado. Sao as duas coisas: so mexendo nos pontos, os trechos
  /// continuariam retos entre eles — o desenho sairia com cara de poligono
  /// torto, e nao de linha feita a mao.
  static void _torcer(
    Path saida,
    List<Offset> pontos,
    int semente,
    double desvio,
  ) {
    final sorte = _Sorte(semente);

    Offset mexido(Offset ponto) =>
        ponto +
        Offset(sorte.entre(-desvio, desvio), sorte.entre(-desvio, desvio));

    var anterior = mexido(pontos.first);
    saida.moveTo(anterior.dx, anterior.dy);

    for (var i = 1; i < pontos.length; i++) {
      final atual = mexido(pontos[i]);
      final direcao = atual - anterior;
      final comprimento = direcao.distance;

      // A barriga cresce com o trecho, ate o teto: um traço longo arqueia, um
      // curto quase nao.
      final quanto = math.min(comprimento * barrigaPorPixel, barrigaMaxima);
      final meio = (anterior + atual) / 2;
      final barriga = comprimento == 0
          ? meio
          : meio +
                Offset(-direcao.dy, direcao.dx) /
                    comprimento *
                    sorte.entre(-quanto, quanto);

      saida.quadraticBezierTo(barriga.dx, barriga.dy, atual.dx, atual.dy);
      anterior = atual;
    }
  }
}

/// Um sorteio que sempre sorteia a mesma coisa, dada a mesma semente.
///
/// O `Random` do Dart serviria, mas custa um objeto e uma alocaçao por forma
/// por quadro de animaçao; esta conta de tres operaçoes cabe no lugar, e o
/// quanto ela e aleatoria nao importa — ninguem vai apostar dinheiro no
/// tremido de um retangulo.
class _Sorte {
  _Sorte(int semente) : _estado = semente == 0 ? 1 : semente & 0x7FFFFFFF;

  int _estado;

  double entre(double menor, double maior) {
    _estado = (_estado * 1103515245 + 12345) & 0x7FFFFFFF;
    return menor + (_estado / 0x7FFFFFFF) * (maior - menor);
  }
}

/// Desenha o quadro inteiro: malha, flechas, rotulos e caixas.
///
/// Um pintor so para os tres lugares onde um quadro aparece — o cartao no
/// editor, o cartao no preview e a area em tela cheia. O que muda entre eles e
/// o zoom e o que esta selecionado, nao o desenho.
class QuadroPintado extends CustomPainter {
  const QuadroPintado({
    required this.quadro,
    required this.cores,
    required this.pan,
    required this.escala,
    this.malha = false,
    this.noSelecionado,
    this.noEmFoco,
    this.ligacaoSelecionada,
    this.ligando,
    this.semTexto,
    this.guias,
    this.tracoSelecionado,
    this.tracando,
    this.borracha,
    this.ancoraEmFoco,
  });

  final QuadroDaNota quadro;
  final ColorScheme cores;

  /// Onde a origem do quadro cai na tela, e por quanto tudo e multiplicado.
  final Offset pan;
  final double escala;

  /// A malha de pontinhos do fundo. So na area em tela cheia: no meio da nota
  /// ela competiria com o texto em volta.
  final bool malha;

  final String? noSelecionado;

  /// A caixa sob o ponteiro: ganha as bolinhas de ligar antes de ser
  /// selecionada, que e o que faz a ligaçao ser descoberta sem instruçao.
  final String? noEmFoco;

  final int? ligacaoSelecionada;

  /// A ligaçao que esta sendo arrastada agora: de qual caixa saiu e onde o
  /// ponteiro esta.
  final ({String de, Offset ponto})? ligando;

  /// A caixa cujo texto esta sendo digitado num campo por cima do desenho —
  /// pintar o texto aqui tambem deixaria duas copias dele na tela.
  final String? semTexto;

  /// Por onde passa o alinhamento em que a caixa arrastada acabou de encostar.
  /// So enquanto a mao nao solta: e o aviso de que aquilo grudou de proposito.
  final ({double? x, double? y})? guias;

  final String? tracoSelecionado;

  /// O traço que a caneta esta fazendo agora.
  ///
  /// Fora do quadro de proposito: enquanto a mao nao solta, o traço ainda nao
  /// existe no `.md`, e cada ponto novo reescreveria a nota inteira.
  final TracoDoQuadro? tracando;

  /// Onde esta a borracha, e de que tamanho. So enquanto ela esta em uso: e o
  /// unico jeito de saber de antemao o que aquele passo vai apagar.
  final ({Offset ponto, double raio})? borracha;

  /// O ponto de ligar que o ponteiro esta prestes a pegar.
  ///
  /// So ele acende. Quatro pontos acesos ao mesmo tempo nao dizem qual deles a
  /// mao vai pegar — e era essa a unica coisa que eles tinham a dizer.
  final Offset? ancoraEmFoco;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(escala);

    if (malha) _malha(canvas, size);

    // Os paineis primeiro, atras de tudo: eles sao o cenario em que o resto
    // acontece, e uma flecha passando por baixo de um deles sumiria.
    for (final no in quadro.nos) {
      if (no.forma.eFundo) _no(canvas, no);
    }

    for (var i = 0; i < quadro.ligacoes.length; i++) {
      _ligacao(canvas, i);
    }

    final origem = ligando == null ? null : quadro.no(ligando!.de);
    if (origem != null) _emCurso(canvas, origem, ligando!.ponto);

    for (final no in quadro.nos) {
      if (!no.forma.eFundo) _no(canvas, no);
    }

    // Os traços por cima das caixas: rabisco e o que se poe *em cima* do que
    // ja estava — circular uma caixa so quer dizer alguma coisa se o circulo
    // aparecer por cima dela.
    for (final traco in quadro.tracos) {
      _traco(canvas, traco, selecionado: traco.id == tracoSelecionado);
    }
    if (tracando != null) _traco(canvas, tracando!, selecionado: false);

    // As alças por ultimo, ja que as do painel ficariam escondidas debaixo das
    // caixas que ele agrupa.
    for (final no in quadro.nos) {
      if (no.id == noEmFoco || no.id == noSelecionado) _alcas(canvas, no);
    }

    if (guias != null) _guias(canvas, size);
    if (borracha != null) _borracha(canvas);

    canvas.restore();
  }

  /// Um traço solto, com a ponta quando ele e seta.
  void _traco(Canvas canvas, TracoDoQuadro traco, {required bool selecionado}) {
    if (!traco.valido) return;

    // A reta e a seta sao as unicas que passam pela mao livre: a caneta ja
    // veio torta da mao de quem desenhou, e torce-la de novo so borraria o que
    // a pessoa fez.
    final caminho = quadro.aMao && traco.tipo.ePonta
        ? MaoLivre.linha([
            Offset(traco.x(0), traco.y(0)),
            Offset(traco.x(traco.quantos - 1), traco.y(traco.quantos - 1)),
          ], MaoLivre.sementeDe(traco.id))
        : DesenhoDoQuadro.caminhoDoTraco(traco);

    if (selecionado) {
      canvas.drawPath(
        caminho,
        Paint()
          ..color = cores.primary.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = traco.grossura + 7
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawPath(
      caminho,
      Paint()
        ..color = _tinta(traco.cor)
        ..style = PaintingStyle.stroke
        ..strokeWidth = traco.grossura
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (traco.tipo == TipoDoTraco.seta) {
      _ponta(
        canvas,
        Offset(traco.x(0), traco.y(0)),
        Offset(traco.x(traco.quantos - 1), traco.y(traco.quantos - 1)),
        _tinta(traco.cor),
        espessura: traco.grossura,
      );
    }
  }

  Color _tinta(CorDoTraco cor) => DesenhoDoQuadro.tintaDe(cor, cores);

  /// O circulo da borracha, para se saber onde ela pega antes de ela pegar.
  void _borracha(Canvas canvas) {
    canvas
      ..drawCircle(
        borracha!.ponto,
        borracha!.raio,
        Paint()..color = cores.error.withValues(alpha: 0.12),
      )
      ..drawCircle(
        borracha!.ponto,
        borracha!.raio,
        Paint()
          ..color = cores.error.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / escala.clamp(0.4, 2),
      );
  }

  /// As linhas de alinhamento, atravessando a area visivel.
  void _guias(Canvas canvas, Size size) {
    final visivel = Rect.fromLTWH(
      -pan.dx / escala,
      -pan.dy / escala,
      size.width / escala,
      size.height / escala,
    );

    final tinta = Paint()
      ..color = cores.primary.withValues(alpha: 0.55)
      ..strokeWidth = 1 / escala.clamp(0.4, 2);

    final x = guias!.x;
    if (x != null) {
      canvas.drawLine(Offset(x, visivel.top), Offset(x, visivel.bottom), tinta);
    }

    final y = guias!.y;
    if (y != null) {
      canvas.drawLine(Offset(visivel.left, y), Offset(visivel.right, y), tinta);
    }
  }

  /// Pontinhos de 24 em 24, so na parte visivel — a area do quadro nao tem
  /// fim, e desenhar malha fora da tela seria trabalho jogado fora.
  void _malha(Canvas canvas, Size size) {
    const passo = 24.0;
    final visivel = Rect.fromLTWH(
      -pan.dx / escala,
      -pan.dy / escala,
      size.width / escala,
      size.height / escala,
    );

    final tinta = Paint()..color = cores.outline.withValues(alpha: 0.55);
    final raio = 1 / escala.clamp(0.5, 2);

    final primeiroX = (visivel.left / passo).floor() * passo;
    final primeiroY = (visivel.top / passo).floor() * passo;

    for (var x = primeiroX; x <= visivel.right; x += passo) {
      for (var y = primeiroY; y <= visivel.bottom; y += passo) {
        canvas.drawCircle(Offset(x, y), raio, tinta);
      }
    }
  }

  void _ligacao(Canvas canvas, int indice) {
    final ligacao = quadro.ligacoes[indice];
    final de = quadro.no(ligacao.de);
    final para = quadro.no(ligacao.para);
    if (de == null || para == null) return;

    final selecionada = indice == ligacaoSelecionada;
    final cor = selecionada
        ? cores.primary
        : cores.onSurfaceVariant.withValues(alpha: 0.75);

    final rota = DesenhoDoQuadro.rotaEntre(de, para, desviarDe: quadro.nos);
    _linha(
      canvas,
      rota,
      cor,
      selecionada ? 2 : 1.4,
      // A semente sai das duas pontas: a flecha entre as mesmas duas caixas
      // sai torta sempre igual, e duas flechas paralelas saem tortas
      // diferente uma da outra.
      MaoLivre.sementeDe('${ligacao.de}>${ligacao.para}'),
    );
    _ponta(
      canvas,
      rota[rota.length - 2],
      rota.last,
      cor,
      espessura: selecionada ? 2 : 1.4,
    );

    if (ligacao.rotulo.isNotEmpty) {
      _rotulo(canvas, DesenhoDoQuadro.meioDaRota(rota), ligacao.rotulo);
    }
  }

  void _linha(
    Canvas canvas,
    List<Offset> rota,
    Color cor,
    double espessura,
    int semente,
  ) {
    final Path caminho;
    if (quadro.aMao) {
      caminho = MaoLivre.linha(rota, semente);
    } else {
      caminho = Path()..moveTo(rota.first.dx, rota.first.dy);
      for (final ponto in rota.skip(1)) {
        caminho.lineTo(ponto.dx, ponto.dy);
      }
    }

    canvas.drawPath(
      caminho,
      Paint()
        ..color = cor
        ..style = PaintingStyle.stroke
        ..strokeWidth = espessura
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  /// A ponta da flecha, apontando na direçao do ultimo trecho.
  ///
  /// Preenchida com a regua; dois riscos abertos a mao. E a diferença entre a
  /// flecha impressa e a flecha rabiscada, e desenhar o triangulo cheio no meio
  /// de um quadro todo torto seria o unico pedaço perfeito do desenho.
  void _ponta(
    Canvas canvas,
    Offset antes,
    Offset fim,
    Color cor, {
    double espessura = 1.4,
  }) {
    final direcao = fim - antes;
    if (direcao.distance == 0) return;

    final angulo = math.atan2(direcao.dy, direcao.dx);
    final comprimento = math.max(10.0, espessura * 4);
    const abertura = 0.42;

    final esquerda = Offset(
      fim.dx - comprimento * math.cos(angulo - abertura),
      fim.dy - comprimento * math.sin(angulo - abertura),
    );
    final direita = Offset(
      fim.dx - comprimento * math.cos(angulo + abertura),
      fim.dy - comprimento * math.sin(angulo + abertura),
    );

    if (!quadro.aMao) {
      canvas.drawPath(
        Path()
          ..moveTo(fim.dx, fim.dy)
          ..lineTo(esquerda.dx, esquerda.dy)
          ..lineTo(direita.dx, direita.dy)
          ..close(),
        Paint()..color = cor,
      );
      return;
    }

    final tinta = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(espessura, 1.4)
      ..strokeCap = StrokeCap.round;

    final semente = MaoLivre.sementeDe('${fim.dx.round()}:${fim.dy.round()}');
    canvas
      ..drawPath(MaoLivre.linha([esquerda, fim], semente, desvio: 0.8), tinta)
      ..drawPath(
        MaoLivre.linha([fim, direita], semente + 7, desvio: 0.8),
        tinta,
      );
  }

  /// O rotulo da flecha, num selo opaco: sem ele a linha atravessaria as
  /// letras do "Sim" e do "Nao".
  void _rotulo(Canvas canvas, Offset meio, String texto) {
    final pintor = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(
          color: cores.onSurface,
          fontSize: 11.5,
          height: 1.2,
        ).merge(letra),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: 140);

    final selo = Rect.fromCenter(
      center: meio,
      width: pintor.width + 10,
      height: pintor.height + 6,
    );

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(selo, const Radius.circular(4)),
        Paint()..color = cores.surfaceContainerLowest,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(selo, const Radius.circular(4)),
        Paint()
          ..color = cores.outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );

    pintor.paint(canvas, selo.topLeft + const Offset(5, 3));
  }

  /// A ligaçao em curso: tracejada, porque ainda nao existe — e o desenho de
  /// uma intençao, nao de uma flecha gravada.
  void _emCurso(Canvas canvas, NoDoQuadro de, Offset ponto) {
    // Sai pela bolinha mais perto do ponteiro: a linha acompanha a mao em vez
    // de nascer sempre do mesmo lado da caixa.
    final saida = DesenhoDoQuadro.ancorasDe(
      de,
    ).reduce((a, b) => (a - ponto).distance <= (b - ponto).distance ? a : b);

    final tinta = Paint()
      ..color = cores.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final total = (ponto - saida).distance;
    if (total > 0) {
      final passo = (ponto - saida) / total;
      for (var d = 0.0; d < total; d += 12) {
        canvas.drawLine(
          saida + passo * d,
          saida + passo * math.min(d + 6, total),
          tinta,
        );
      }
    }

    canvas
      ..drawCircle(ponto, 4, Paint()..color = cores.primary)
      // Um respiro em volta do ponto de saida, para nao parecer que a linha
      // nasce do meio do nada quando a caixa esta longe.
      ..drawCircle(
        saida,
        3,
        Paint()..color = cores.primary.withValues(alpha: 0.6),
      );
  }

  void _no(Canvas canvas, NoDoQuadro no) {
    final certo = DesenhoDoQuadro.caminhoDe(no);
    final selecionado = no.id == noSelecionado;
    final cara = _caraDaForma(no.forma);

    // Uma passada so.
    //
    // Eram duas, quase no mesmo lugar, que e como o esboço a lapis costuma ser
    // desenhado. Na tela isso vira uma borda grossa e embaralhada — o contorno
    // deixa de ser uma linha e vira uma faixa. Uma passada limpa, levemente
    // fora de esquadro, diz "feito a mao" com menos tinta.
    final torto = quadro.aMao
        ? MaoLivre.forma(certo, MaoLivre.sementeDe(no.id))
        : certo;

    if (cara.fundo.a > 0) {
      canvas.drawPath(torto, Paint()..color = cara.fundo);
    }

    if (cara.borda.a > 0 || selecionado) {
      // Selecionada, a caixa troca a cor da borda — e so isso.
      //
      // Havia tambem um halo de sete pixels por fora dela, para a borda nao se
      // confundir com a da caixa vizinha num quadro cheio. Mas a borda
      // selecionada e indigo claro contra um contorno quase preto: a diferença
      // ja e enorme sem ajuda nenhuma, e o halo so deixava a caixa com uma
      // auréola borrada em volta.
      canvas.drawPath(
        torto,
        Paint()
          ..color = selecionado ? cores.primary : cara.borda
          ..style = PaintingStyle.stroke
          ..strokeWidth = selecionado ? 1.5 : 1.3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    if (no.id != semTexto) _texto(canvas, no, cara.texto);
  }

  /// As bolinhas de ligar aparecem na caixa apontada ou selecionada, e o
  /// quadradinho de tamanho so na selecionada — arrastar o canto de uma caixa
  /// que o ponteiro apenas atravessou seria mudança sem pedido.
  /// As alças de uma caixa: os pontos de ligar e o canto de redimensionar.
  ///
  /// Os pontos de ligar aparecem so debaixo do ponteiro, e nao tambem no que
  /// esta selecionado.
  ///
  /// Eram nos dois, e o resultado era uma caixa cercada de quatro bolas azuis o
  /// tempo inteiro em que ela estivesse selecionada — ou seja, o tempo inteiro
  /// em que se estivesse escrevendo nela. Ligar e coisa que se faz com o
  /// ponteiro em cima da caixa; enquanto ele nao esta ali, as bolinhas so
  /// tapavam o desenho.
  void _alcas(Canvas canvas, NoDoQuadro no) {
    // O painel nao tem pontos de ligar: nao entra em flecha nenhuma. So o
    // canto de tamanho, que e o que se mexe nele.
    if (no.id == noEmFoco && DesenhoDoQuadro.ligavel(no)) _ancoras(canvas, no);
    if (no.id == noSelecionado) _canto(canvas, no);
  }

  void _texto(Canvas canvas, NoDoQuadro no, Color cor) {
    if (no.texto.isEmpty) return;

    // O nome do painel fica no alto, e nao no meio: no meio ele cairia atras
    // das caixas que o painel agrupa.
    if (no.forma.eFundo) {
      final pintor = TextPainter(
        text: TextSpan(
          text: no.texto,
          style: TextStyle(
            color: cor,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ).merge(letra),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(24, no.largura - 24));

      pintor.paint(canvas, Offset(no.centroX - pintor.width / 2, no.y + 10));
      return;
    }

    // O losango, a elipse e o paralelogramo comem as pontas: o texto util cabe
    // so no miolo deles.
    final folga = DesenhoDoQuadro.folgaDoTexto(no);
    final largura = math.max(24.0, no.largura - folga * 2);

    // Uma caixa cujo texto inteiro e um `[[link]]` nao e uma caixa escrita: e
    // um atalho para aquela nota. Ela mostra o nome da nota, com a cara de link
    // que o preview ja usa — a mesma cor e o mesmo sublinhado —, e nao os
    // colchetes, que sao sintaxe e nao conteudo.
    final atalho = Wikilink.sozinho(no.texto);

    final pintor = TextPainter(
      text: TextSpan(
        text: atalho?.texto ?? no.texto,
        style: TextStyle(
          color: atalho == null ? cor : cores.primary,
          fontSize: 13,
          height: 1.3,
          fontWeight: no.forma == FormaDoNo.terminal
              ? FontWeight.w600
              : FontWeight.w400,
          decoration: atalho == null ? null : TextDecoration.underline,
          decorationColor: cores.primary.withValues(alpha: 0.35),
        ).merge(letra),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      // A anotaçao solta nao tem limite de linhas: a caixa dela acompanha o que
      // for escrito (ver [DesenhoDoQuadro.tamanhoDoTexto]), entao cortar em
      // quatro linhas esconderia texto que cabe.
      maxLines: no.forma == FormaDoNo.texto ? null : 4,
      ellipsis: no.forma == FormaDoNo.texto ? null : '…',
    )..layout(maxWidth: largura);

    pintor.paint(
      canvas,
      Offset(no.centroX - pintor.width / 2, no.centroY - pintor.height / 2),
    );
  }

  /// Os quatro pontos de onde sai uma flecha.
  ///
  /// Pontinhos cheios e apagados, e nao aneis azuis. O anel tem duas linhas e um
  /// miolo — tres coisas para o olho ler — e em azul cheio ele pesa mais que a
  /// propria caixa: o desenho virava a moldura do enfeite. Cheio e discreto, ele
  /// diz "da para pegar aqui" sem disputar atençao com o que esta desenhado.
  ///
  /// O que esta debaixo do ponteiro e o unico que acende. E ele que vai ser
  /// pego, e dizer isso e a razao de os quatro estarem a vista.
  void _ancoras(Canvas canvas, NoDoQuadro no) {
    final apagado = Paint()
      ..color = cores.onSurfaceVariant.withValues(alpha: 0.55);
    final aceso = Paint()..color = cores.primary;

    for (final ancora in DesenhoDoQuadro.ancorasDe(no)) {
      final emFoco =
          ancoraEmFoco != null &&
          (ancora - ancoraEmFoco!).distance < DesenhoDoQuadro.raioDaAncora;

      canvas.drawCircle(
        ancora,
        emFoco
            ? DesenhoDoQuadro.raioDaAncora + 1.5
            : DesenhoDoQuadro.raioDaAncora,
        emFoco ? aceso : apagado,
      );
    }
  }

  /// O canto de onde se puxa o tamanho.
  ///
  /// Vazado, e nao um quadrado azul cheio: cheio ele virava um selo grudado na
  /// quina da caixa. Assim ele e a mesma coisa que uma alça de redimensionar em
  /// qualquer lugar — uma marca do fundo, com a borda da cor de quem esta
  /// selecionado.
  void _canto(Canvas canvas, NoDoQuadro no) {
    final r = DesenhoDoQuadro.retanguloDe(no);
    final canto = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: r.bottomRight,
        width: DesenhoDoQuadro.cantoDeTamanho * 0.58,
        height: DesenhoDoQuadro.cantoDeTamanho * 0.58,
      ),
      const Radius.circular(1.5),
    );

    canvas
      ..drawRRect(canto, Paint()..color = cores.surfaceContainerLowest)
      ..drawRRect(
        canto,
        Paint()
          ..color = cores.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
  }

  /// A letra do quadro. Manuscrita quando ele e desenhado a mao: um desenho
  /// todo torto com a letra da interface por dentro fica com cara de legenda
  /// colada por cima, e nao de coisa escrita ali.
  TextStyle? get letra => quadro.aMao ? MaoLivre.letra : null;

  /// Cada forma tem a sua cara. As cores saem do tema: o indigo e do app, o
  /// azul-ceu e do que voce escreveu — e um fluxograma e conteudo seu.
  ({Color fundo, Color borda, Color texto}) _caraDaForma(FormaDoNo forma) =>
      switch (forma) {
        FormaDoNo.terminal => (
          fundo: cores.primary.withValues(alpha: 0.16),
          borda: cores.primary.withValues(alpha: 0.55),
          texto: cores.onSurface,
        ),
        FormaDoNo.processo => (
          fundo: cores.surfaceContainerHigh,
          borda: cores.outline,
          texto: cores.onSurface,
        ),
        // Entrada e saida sao passos como o processo, e nao estrutura: mesma
        // cara dele, com a inclinaçao dizendo o que muda.
        FormaDoNo.entrada => (
          fundo: cores.surfaceContainerHigh,
          borda: cores.outline,
          texto: cores.onSurface,
        ),
        FormaDoNo.decisao => (
          fundo: AppTheme.realce.withValues(alpha: 0.13),
          borda: AppTheme.realce.withValues(alpha: 0.5),
          texto: cores.onSurface,
        ),
        // A elipse e forma de desenho antes de ser conector: nasce so com o
        // contorno, para nao competir com as caixas que sao passo do fluxo.
        FormaDoNo.elipse => (
          fundo: const Color(0x00000000),
          borda: cores.outline,
          texto: cores.onSurface,
        ),
        FormaDoNo.texto => (
          fundo: const Color(0x00000000),
          borda: const Color(0x00000000),
          texto: cores.onSurfaceVariant,
        ),
        // Discreto de proposito: ele existe para as caixas em cima dele serem
        // lidas como um conjunto, e nao para ser lido no lugar delas.
        FormaDoNo.fundo => (
          fundo: AppTheme.realce.withValues(alpha: 0.08),
          borda: AppTheme.realce.withValues(alpha: 0.32),
          texto: AppTheme.realce,
        ),
      };

  @override
  bool shouldRepaint(QuadroPintado antigo) =>
      antigo.quadro != quadro ||
      antigo.pan != pan ||
      antigo.escala != escala ||
      antigo.malha != malha ||
      antigo.noSelecionado != noSelecionado ||
      antigo.noEmFoco != noEmFoco ||
      antigo.ligacaoSelecionada != ligacaoSelecionada ||
      antigo.ligando != ligando ||
      antigo.semTexto != semTexto ||
      antigo.guias != guias ||
      antigo.tracoSelecionado != tracoSelecionado ||
      antigo.tracando != tracando ||
      antigo.borracha != borracha ||
      antigo.ancoraEmFoco != ancoraEmFoco ||
      antigo.cores != cores;
}
