import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/quadro_da_nota.dart';
import 'package:notas_app/ui/app_theme.dart';
import 'package:notas_app/ui/desenho_do_quadro.dart';
import 'package:notas_app/ui/quadro_tela_cheia.dart';

void main() {
  /// A area de desenho, entre as duas barras.
  final tela = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is QuadroPintado,
  );

  /// Monta a tela cheia e devolve o quadro como ele esta a cada momento.
  ///
  /// Começa vazio de proposito: sem caixa nenhuma a camera fica parada na
  /// origem, e ai a conta entre pixel da tela e pixel do quadro e uma soma —
  /// o que deixa os gestos deste teste caírem em lugares conhecidos.
  Future<QuadroDaNota Function()> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var atual = QuadroDaNota.vazio;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: QuadroTelaCheia(
            quadro: QuadroDaNota.vazio,
            onMudar: (novo) => atual = novo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => atual;
  }

  /// De coordenada do quadro para coordenada da tela, com a camera parada.
  Offset paraTela(WidgetTester tester, Offset noQuadro) =>
      tester.getTopLeft(tela) + noQuadro;

  /// Cria uma caixa pela barra de formas e sai do modo de escrita.
  Future<void> criar(WidgetTester tester, String rotulo) async {
    await tester.tap(find.byTooltip('Criar $rotulo'));
    await tester.pumpAndSettle();
    // A caixa nova nasce com o cursor dentro dela; Esc devolve o teclado a
    // area, que e onde os testes de gesto trabalham.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> clicarEm(WidgetTester tester, Offset noQuadro) async {
    await tester.tapAt(paraTela(tester, noQuadro));
    await tester.pumpAndSettle();
  }

  /// Arrasta de um ponto a outro do quadro em passos curtos.
  ///
  /// Curtos de proposito: e assim que um mouse relata o movimento da mao, e e
  /// o caso em que o arrasto costuma falhar sem ninguem notar.
  Future<void> arrastar(
    WidgetTester tester,
    Offset de,
    Offset ate, {
    int passos = 12,
  }) async {
    final gesto = await tester.startGesture(
      paraTela(tester, de),
      kind: PointerDeviceKind.mouse,
    );
    final passo = (ate - de) / passos.toDouble();
    for (var i = 0; i < passos; i++) {
      await gesto.moveBy(passo);
      await tester.pump();
    }
    await gesto.up();
    await tester.pumpAndSettle();
  }

  /// Pega uma ferramenta da barra de desenho.
  Future<void> pegar(WidgetTester tester, String dica) async {
    await tester.tap(find.byTooltip(dica));
    await tester.pumpAndSettle();
  }

  group('desenhando a mao', () {
    testWidgets('a caneta deixa um traço, e ela fica na mao', (tester) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Caneta (C)');

      await arrastar(tester, const Offset(60, 60), const Offset(160, 120));

      final traco = quadro().tracos.single;
      expect(traco.tipo, TipoDoTraco.livre);
      // O caminho inteiro, e nao so as duas pontas: e isso que separa o
      // rabisco da reta.
      expect(traco.quantos, greaterThan(2));
      expect(traco.x(0), closeTo(60, 2));
      expect(traco.y(traco.quantos - 1), closeTo(120, 2));

      // A caneta continua pega: quem rabisca quase nunca rabisca uma vez so.
      await arrastar(tester, const Offset(60, 200), const Offset(160, 240));
      expect(quadro().tracos.length, 2);
    });

    testWidgets('a reta guarda duas pontas, e a mao volta para a seta', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Reta (R)');

      await arrastar(tester, const Offset(40, 40), const Offset(240, 140));

      expect(quadro().tracos.single.tipo, TipoDoTraco.reta);
      expect(quadro().tracos.single.quantos, 2);

      // A mao voltou sozinha para a seta: o gesto seguinte passeia pela area
      // em vez de riscar outra reta por cima.
      await arrastar(tester, const Offset(300, 300), const Offset(360, 340));
      expect(quadro().tracos.length, 1);
    });

    testWidgets('a seta solta sai com ponta, sem se prender a caixa nenhuma', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Seta solta (F)');

      await arrastar(tester, const Offset(40, 40), const Offset(200, 40));

      expect(quadro().tracos.single.tipo, TipoDoTraco.seta);
      // Traço, e nao ligaçao: ligaçao gruda em duas caixas, e aqui nao ha
      // caixa nenhuma.
      expect(quadro().ligacoes, isEmpty);
    });

    testWidgets('o clique parado nao vira traço', (tester) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Caneta (C)');

      await clicarEm(tester, const Offset(100, 100));

      // Um clique que nao andou nao e desenho, e guardar isso encheria a nota
      // de traços invisiveis.
      expect(quadro().tracos, isEmpty);
    });

    testWidgets('a borracha tira o traço, e nao a caixa embaixo dele', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await criar(tester, 'Processo');
      final caixa = quadro().nos.single;

      await pegar(tester, 'Caneta (C)');
      await arrastar(
        tester,
        Offset(caixa.x + 10, caixa.centroY),
        Offset(caixa.x + caixa.largura - 10, caixa.centroY),
      );
      expect(quadro().tracos.length, 1);

      await pegar(tester, 'Borracha (B)');
      await arrastar(
        tester,
        Offset(caixa.x + 10, caixa.centroY),
        Offset(caixa.x + caixa.largura - 10, caixa.centroY),
      );

      expect(quadro().tracos, isEmpty);
      // A caixa ficou. Apagar de raspao uma caixa com texto e flechas seria
      // perda demais para um gesto tao solto — ela se apaga com Delete.
      expect(quadro().nos.length, 1);
    });

    testWidgets('clicar no traço seleciona, e Delete apaga', (tester) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Caneta (C)');
      await arrastar(tester, const Offset(60, 60), const Offset(260, 60));

      await pegar(tester, 'Selecionar (V)');
      await clicarEm(tester, const Offset(160, 60));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(quadro().tracos, isEmpty);
    });

    testWidgets('arrastar o traço leva o caminho inteiro junto', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Caneta (C)');
      await arrastar(tester, const Offset(60, 60), const Offset(260, 60));
      final antes = quadro().tracos.single;

      await pegar(tester, 'Selecionar (V)');
      await arrastar(tester, const Offset(160, 60), const Offset(160, 160));

      final depois = quadro().tracos.single;
      expect(depois.quantos, antes.quantos);
      expect(depois.y(0) - antes.y(0), closeTo(100, 4));
      expect(depois.x(0) - antes.x(0), closeTo(0, 4));
    });
  });

  group('escrevendo solto', () {
    /// O texto que o campo aberto por cima do desenho esta mostrando.
    Finder campo(WidgetTester tester) => find.descendant(
      of: find.byType(QuadroTelaCheia),
      matching: find.byType(TextField),
    );

    testWidgets('um clique escreve onde se apontou, sem caixa em volta', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Escrever solto (T)');
      await clicarEm(tester, const Offset(200, 140));

      final no = quadro().nos.single;
      expect(no.forma, FormaDoNo.texto);
      // A esquerda no ponto apontado: escrever começa onde o cursor esta.
      expect(no.x, closeTo(200, 1));
      expect(no.centroY, closeTo(140, 1));
      // E o cursor ja esta aberto, sem precisar de um segundo clique.
      expect(campo(tester), findsOneWidget);
    });

    testWidgets('duplo clique no vazio escreve, em vez de criar uma caixa', (
      tester,
    ) async {
      // O primeiro gesto que se tenta num quadro em branco — e o que se quer
      // nele quase sempre e anotar, nao montar um fluxograma. Criava um
      // retangulo, e quem so queria escrever uma palavra ganhava uma moldura em
      // volta dela sem ter pedido.
      final quadro = await montar(tester);

      final onde = paraTela(tester, const Offset(240, 180));
      await tester.tapAt(onde);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tapAt(onde);
      await tester.pumpAndSettle();

      final no = quadro().nos.single;
      expect(no.forma, FormaDoNo.texto);
      expect(campo(tester), findsOneWidget);
    });

    testWidgets('a mao volta para a seta depois de escrever', (tester) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Escrever solto (T)');
      await clicarEm(tester, const Offset(200, 140));
      await tester.enterText(campo(tester), 'Uma anotaçao');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // O clique seguinte nao escreve outra: escrever num lugar e um gesto que
      // se encerra.
      await clicarEm(tester, const Offset(600, 500));
      expect(quadro().nos.length, 1);
      expect(quadro().nos.single.texto, 'Uma anotaçao');
    });

    testWidgets('a area acompanha o que foi escrito', (tester) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Escrever solto (T)');
      await clicarEm(tester, const Offset(200, 140));

      await tester.enterText(campo(tester), 'oi');
      await tester.pumpAndSettle();
      final curta = quadro().nos.single;

      await tester.enterText(
        campo(tester),
        'uma anotaçao bem mais comprida que a primeira',
      );
      await tester.pumpAndSettle();
      final longa = quadro().nos.single;

      expect(longa.largura, greaterThan(curta.largura));
      // A esquerda nao sai do lugar: o texto cresce para a direita.
      expect(longa.x, curta.x);
      // E cresce para os dois lados na vertical, em vez de descer.
      expect(longa.centroY, closeTo(curta.centroY, 0.51));
    });

    testWidgets('anotaçao sem nada escrito nao fica no quadro', (tester) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Escrever solto (T)');
      await clicarEm(tester, const Offset(200, 140));
      expect(quadro().nos.length, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Sem moldura, ela ficaria como uma area invisivel que so se descobre
      // quando o ponteiro esbarra nela.
      expect(quadro().nos, isEmpty);
    });

    testWidgets('em cima de uma caixa, escreve nela em vez de criar outra', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await criar(tester, 'Processo');
      final caixa = quadro().nos.single;

      await pegar(tester, 'Escrever solto (T)');
      await clicarEm(tester, Offset(caixa.centroX, caixa.centroY));
      await tester.enterText(campo(tester), 'dentro');
      await tester.pumpAndSettle();

      expect(quadro().nos.length, 1);
      expect(quadro().no(caixa.id)!.texto, 'dentro');
    });

    testWidgets('a caixa com moldura nao muda de tamanho ao ser escrita', (
      tester,
    ) async {
      // O oposto da anotaçao: um retangulo que encolhesse ao se apagar uma
      // palavra sairia dançando no meio do fluxograma, e desalinharia as
      // flechas presas a ele.
      final quadro = await montar(tester);
      await criar(tester, 'Processo');
      final antes = quadro().nos.single;

      await clicarEm(tester, Offset(antes.centroX, antes.centroY));
      await tester.tapAt(
        paraTela(tester, Offset(antes.centroX, antes.centroY)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(campo(tester), 'um texto bem comprido aqui');
      await tester.pumpAndSettle();

      expect(quadro().nos.single.largura, antes.largura);
      expect(quadro().nos.single.altura, antes.altura);
    });
  });

  group('desfazer', () {
    testWidgets('Ctrl+Z tira o traço que acabou de ser feito', (tester) async {
      final quadro = await montar(tester);
      await pegar(tester, 'Caneta (C)');
      await arrastar(tester, const Offset(60, 60), const Offset(160, 120));
      expect(quadro().tracos.length, 1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Uma borracha sem desfazer e uma faca sem cabo: foi a caneta que
      // trouxe o desfazer para esta tela.
      expect(quadro().tracos, isEmpty);
    });

    testWidgets('Ctrl+Shift+Z traz de volta o que Ctrl+Z tirou', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await criar(tester, 'Processo');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(quadro().nos, isEmpty);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(quadro().nos.length, 1);
    });
  });

  testWidgets('o interruptor da mao fica escrito no arquivo', (tester) async {
    final quadro = await montar(tester);
    await criar(tester, 'Processo');

    // Ligado sem nada escrito: e o que o arquivo ja diz calado.
    expect(quadro().aMao, isTrue);
    expect(quadro().markdown, isNot(contains('mao')));

    await tester.tap(find.byTooltip('Desenhar com regua, em vez de a mao'));
    await tester.pumpAndSettle();

    expect(quadro().aMao, isFalse);
    expect(quadro().markdown, contains('"mao":false'));
  });

  testWidgets('a caixa acompanha a mao em passos de tres pixels', (
    tester,
  ) async {
    // O defeito que este teste guarda: a posiçao era somada a cada quadro e
    // encaixada na malha em seguida, entao passos menores que meia malha
    // arredondavam de volta ao mesmo lugar — a caixa ficava presa no chao e so
    // pulava quando a mao dava um tranco.
    final quadro = await montar(tester);
    await criar(tester, 'Processo');

    final antes = quadro().nos.single;
    final centro = Offset(antes.centroX, antes.centroY);

    // Doze passos de tres pixels: 36 na horizontal, 24 na vertical.
    await arrastar(tester, centro, centro + const Offset(36, 24));

    final depois = quadro().nos.single;
    expect(depois.x - antes.x, closeTo(36, DesenhoDoQuadro.malha));
    expect(depois.y - antes.y, closeTo(24, DesenhoDoQuadro.malha));
    // O tamanho nao entra na conversa: quem pega o meio da caixa move.
    expect(depois.largura, antes.largura);
    expect(depois.altura, antes.altura);
  });

  testWidgets('a segunda forma cria outra caixa, sem transformar a primeira', (
    tester,
  ) async {
    // O que este teste guarda: os botoes de forma tambem trocavam a forma do
    // que estava selecionado, e a caixa nova nasce selecionada — entao pedir
    // duas caixas seguidas transformava a primeira em vez de criar a segunda.
    final quadro = await montar(tester);
    await criar(tester, 'Processo');
    await criar(tester, 'Decisao');

    expect(quadro().nos.length, 2);
    expect(quadro().nos.first.forma, FormaDoNo.processo);
    expect(quadro().nos.last.forma, FormaDoNo.decisao);

    // Trocar a forma continua possivel, no grupo proprio, sobre a caixa
    // selecionada.
    final primeira = quadro().nos.first;
    await clicarEm(tester, Offset(primeira.centroX, primeira.centroY));
    await tester.tap(find.byTooltip('Deixar em Decisao'));
    await tester.pumpAndSettle();

    expect(quadro().nos.length, 2);
    expect(quadro().no(primeira.id)!.forma, FormaDoNo.decisao);
    // E cresce para caber o proprio texto, por ainda estar no tamanho de
    // fabrica do retangulo.
    expect(
      quadro().no(primeira.id)!.largura,
      FormaDoNo.decisao.tamanhoInicial.largura,
    );
  });

  testWidgets('arrastar a bolinha ate outra caixa cria a flecha', (
    tester,
  ) async {
    final quadro = await montar(tester);
    await criar(tester, 'Processo');
    await criar(tester, 'Decisao');

    final primeira = quadro().nos.first;
    final segunda = quadro().nos.last;

    // A primeira volta a ser a selecionada, que e de quem as bolinhas sao.
    await clicarEm(tester, Offset(primeira.centroX, primeira.centroY));

    await arrastar(
      tester,
      DesenhoDoQuadro.ancorasDe(primeira)[1],
      Offset(segunda.centroX, segunda.centroY),
    );

    expect(quadro().ligacoes.length, 1);
    expect(quadro().ligacoes.single.de, primeira.id);
    expect(quadro().ligacoes.single.para, segunda.id);
    // Ligar nao move nem redimensiona nada.
    expect(quadro().no(primeira.id)!.x, primeira.x);
    expect(quadro().no(primeira.id)!.largura, primeira.largura);
  });

  testWidgets('o canto de baixo a direita muda o tamanho, nao o lugar', (
    tester,
  ) async {
    final quadro = await montar(tester);
    await criar(tester, 'Processo');

    final antes = quadro().nos.single;
    await clicarEm(tester, Offset(antes.centroX, antes.centroY));

    final canto = DesenhoDoQuadro.retanguloDe(antes).bottomRight;
    await arrastar(tester, canto, canto + const Offset(48, 24));

    final depois = quadro().nos.single;
    expect(depois.largura - antes.largura, closeTo(48, DesenhoDoQuadro.malha));
    expect(depois.altura - antes.altura, closeTo(24, DesenhoDoQuadro.malha));
    expect(depois.x, antes.x);
    expect(depois.y, antes.y);
  });

  testWidgets('as setas empurram a caixa selecionada', (tester) async {
    final quadro = await montar(tester);
    await criar(tester, 'Processo');

    final antes = quadro().nos.single;
    await clicarEm(tester, Offset(antes.centroX, antes.centroY));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(quadro().nos.single.x - antes.x, DesenhoDoQuadro.malha);

    // Com Shift, de um em um pixel: e o ajuste que a malha nao alcança.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(quadro().nos.single.y - antes.y, 1);
  });

  group('escrevendo dentro da caixa', () {
    /// O campo que fica por cima da caixa que esta sendo escrita.
    final campo = find.descendant(
      of: find.byType(QuadroTelaCheia),
      matching: find.byType(TextField),
    );

    testWidgets('apagar apaga a letra, e nao a caixa', (tester) async {
      // O defeito que este teste guarda: as teclas sobem do campo focado para
      // os ancestrais dele, e a area de desenho e ancestral do campo — entao o
      // Backspace de quem estava escrevendo chegava ao atalho de excluir antes
      // de chegar a quem apaga letra, e o fluxograma perdia a caixa.
      final quadro = await montar(tester);
      await tester.tap(find.byTooltip('Criar Processo'));
      await tester.pumpAndSettle();

      await tester.enterText(campo, 'Ler');
      await tester.pumpAndSettle();
      expect(quadro().nos.single.texto, 'Ler');

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(quadro().nos.length, 1);
      expect(quadro().nos.single.texto, 'Le');

      // Delete, do outro lado do cursor, tambem e do texto.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(quadro().nos.length, 1);
    });

    testWidgets('as setas andam no texto, e nao arrastam a caixa', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await tester.tap(find.byTooltip('Criar Processo'));
      await tester.pumpAndSettle();
      await tester.enterText(campo, 'Ler');
      await tester.pumpAndSettle();

      final antes = quadro().nos.single;
      // Esquerda e direita, que e o que anda no texto de uma caixa. As
      // verticais nao entram aqui: elas caem numa asserçao do proprio Flutter
      // (`VerticalCaretMovementRun`) antes de chegar a este widget, e o que
      // este teste guarda e a guarda de teclado daqui.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(quadro().nos.single.x, antes.x);
      expect(quadro().nos.single.y, antes.y);
      expect(quadro().nos.single.texto, 'Ler');
    });

    testWidgets('Esc sai da escrita sem apagar o que foi escrito', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await tester.tap(find.byTooltip('Criar Processo'));
      await tester.pumpAndSettle();
      await tester.enterText(campo, 'Ler o numero');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(campo, findsNothing);
      expect(quadro().nos.single.texto, 'Ler o numero');

      // Fora da escrita, a tecla volta a ser da area: a caixa continua
      // selecionada, e apagar apaga ela.
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(quadro().nos, isEmpty);
    });

    testWidgets('apagar no rotulo da flecha nao apaga a flecha', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await criar(tester, 'Processo');
      await criar(tester, 'Decisao');

      final primeira = quadro().nos.first;
      final segunda = quadro().nos.last;
      await clicarEm(tester, Offset(primeira.centroX, primeira.centroY));
      await arrastar(
        tester,
        DesenhoDoQuadro.ancorasDe(primeira)[1],
        Offset(segunda.centroX, segunda.centroY),
      );
      expect(quadro().ligacoes.length, 1);

      // Clicar na flecha abre o campo do rotulo.
      final meio = DesenhoDoQuadro.meioDaRota(
        DesenhoDoQuadro.rotaEntre(primeira, segunda),
      );
      await clicarEm(tester, meio);
      expect(campo, findsOneWidget);

      await tester.enterText(campo, 'Sim');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(quadro().ligacoes.length, 1);
      expect(quadro().ligacoes.single.rotulo, 'Si');
    });
  });

  group('alinhamento', () {
    testWidgets('a caixa nova nasce embaixo da anterior, no eixo dela', (
      tester,
    ) async {
      // Assim a flecha entre as duas sai reta sem ninguem mirar: e o caso que
      // aparecia torto, com o degrauzinho entre "Inicio" e o passo seguinte.
      final quadro = await montar(tester);
      await criar(tester, 'Inicio/Fim');
      await criar(tester, 'Processo');

      final primeira = quadro().nos.first;
      final segunda = quadro().nos.last;

      expect(segunda.centroX, primeira.centroX);
      expect(segunda.y, greaterThan(primeira.y + primeira.altura));

      // E a rota entre elas e uma reta de dois pontos, sem quebra.
      final rota = DesenhoDoQuadro.rotaEntre(primeira, segunda);
      expect(rota.length, 2);
      expect(rota.first.dx, rota.last.dx);
    });

    testWidgets('arrastar encosta no eixo da caixa de cima', (tester) async {
      final quadro = await montar(tester);
      await criar(tester, 'Inicio/Fim');
      await criar(tester, 'Processo');

      final debaixo = quadro().nos.last;
      final centro = Offset(debaixo.centroX, debaixo.centroY);

      // Sai do eixo por poucos pixels — menos que o imã — e volta a encostar.
      await arrastar(tester, centro, centro + const Offset(5, 0));

      expect(quadro().nos.last.centroX, quadro().nos.first.centroX);
      expect(
        DesenhoDoQuadro.rotaEntre(quadro().nos.first, quadro().nos.last).length,
        2,
      );
    });

    testWidgets('longe do eixo, o imã nao puxa', (tester) async {
      final quadro = await montar(tester);
      await criar(tester, 'Inicio/Fim');
      await criar(tester, 'Processo');

      final debaixo = quadro().nos.last;
      final centro = Offset(debaixo.centroX, debaixo.centroY);
      await arrastar(tester, centro, centro + const Offset(200, 0));

      expect(
        quadro().nos.last.centroX - quadro().nos.first.centroX,
        closeTo(200, DesenhoDoQuadro.malha),
      );
    });
  });

  group('painel de fundo', () {
    testWidgets('o clique pega a caixa que esta em cima, e nao o painel', (
      tester,
    ) async {
      final quadro = await montar(tester);
      await criar(tester, 'Processo');
      final caixa = quadro().nos.single;

      // O painel nasce no meio da area, cobrindo a caixa que ja estava ali.
      await criar(tester, 'Fundo');
      final fundo = quadro().nos.last;
      expect(fundo.forma, FormaDoNo.fundo);
      expect(
        DesenhoDoQuadro.retanguloDe(
          fundo,
        ).contains(Offset(caixa.centroX, caixa.centroY)),
        isTrue,
      );

      await clicarEm(tester, Offset(caixa.centroX, caixa.centroY));
      await tester.tap(find.byTooltip('Deixar em Decisao'));
      await tester.pumpAndSettle();

      // Quem mudou de forma foi a caixa, e nao o painel debaixo dela.
      expect(quadro().no(caixa.id)!.forma, FormaDoNo.decisao);
      expect(quadro().no(fundo.id)!.forma, FormaDoNo.fundo);
    });

    testWidgets('o painel anda sozinho: nada esta preso a ele', (tester) async {
      final quadro = await montar(tester);
      await criar(tester, 'Processo');
      await criar(tester, 'Fundo');

      final caixa = quadro().nos.first;
      final fundo = quadro().nos.last;
      // A caixa esta por cima do painel — e continua nao sendo dele.
      expect(
        DesenhoDoQuadro.retanguloDe(
          fundo,
        ).contains(Offset(caixa.centroX, caixa.centroY)),
        isTrue,
      );

      // Pelo canto de cima do painel, longe da caixa.
      final pega = Offset(fundo.x + 20, fundo.y + 6);
      await arrastar(tester, pega, pega + const Offset(96, 48));

      expect(
        quadro().no(fundo.id)!.x - fundo.x,
        closeTo(96, DesenhoDoQuadro.malha),
      );
      expect(quadro().no(caixa.id)!.x, caixa.x);
      expect(quadro().no(caixa.id)!.y, caixa.y);
    });

    testWidgets('o painel fica fora das flechas e do imã', (tester) async {
      final quadro = await montar(tester);
      await criar(tester, 'Fundo');
      final fundo = quadro().nos.single;

      // Uma caixa fora do painel, para tentar liga-la a ele.
      await clicarEm(tester, Offset(fundo.x - 200, fundo.y));
      await tester.tap(find.byTooltip('Criar Processo'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final caixa = quadro().nos.firstWhere((n) => n.id != fundo.id);
      await clicarEm(tester, Offset(caixa.centroX, caixa.centroY));
      await arrastar(
        tester,
        DesenhoDoQuadro.ancorasDe(caixa)[1],
        Offset(fundo.centroX, fundo.centroY),
      );

      // A flecha nao nasce: ela ficaria presa a uma area, e nao a um passo.
      expect(quadro().ligacoes, isEmpty);

      // E o imã tambem nao o considera.
      final aoLado = DesenhoDoQuadro.alinhar(
        quadro(),
        caixa.com(x: fundo.centroX - caixa.largura / 2 + 3),
      );
      expect(aoLado.guiaX, isNull);
    });
  });

  testWidgets('arrastar no vazio passeia pela area, sem mexer nas caixas', (
    tester,
  ) async {
    final quadro = await montar(tester);
    await criar(tester, 'Processo');

    final antes = quadro().nos.single;
    // Bem longe da caixa, no canto da area.
    await arrastar(tester, const Offset(20, 20), const Offset(140, 90));

    final depois = quadro().nos.single;
    expect(depois.x, antes.x);
    expect(depois.y, antes.y);
  });
}
