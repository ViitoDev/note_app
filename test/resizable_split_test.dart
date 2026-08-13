import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/ui/resizable_split.dart';

const _esquerda = Key('esquerda');
const _direita = Key('direita');

Future<void> _montar(
  WidgetTester tester, {
  Axis axis = Axis.horizontal,
  double? initialFirst,
  double? initialSecond,
  double minFirst = 100,
  double minSecond = 100,
  Size janela = const Size(1000, 700),
}) async {
  tester.view.physicalSize = janela;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ResizableSplit(
          axis: axis,
          initialFirst: initialFirst,
          initialSecond: initialSecond,
          minFirst: minFirst,
          minSecond: minSecond,
          first: Container(key: _esquerda, color: const Color(0xFF111111)),
          second: Container(key: _direita, color: const Color(0xFF222222)),
        ),
      ),
    ),
  );
}

double _largura(WidgetTester tester, Key key) =>
    tester.getSize(find.byKey(key)).width;

double _altura(WidgetTester tester, Key key) =>
    tester.getSize(find.byKey(key)).height;

/// Arrasta o divisor, que fica entre os dois paineis.
///
/// O reconhecedor de gestos consome os primeiros pixels do movimento antes de
/// aceitar o arrasto, entao o deslocamento aplicado nunca e exatamente o pedido.
/// Por isso os testes verificam direcao e limites, nao a aritmetica do gesto.
Future<void> _arrastar(WidgetTester tester, Offset delta) async {
  final divisor = find.byType(MouseRegion).last;
  await tester.drag(divisor, delta);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('respeita o tamanho inicial do primeiro painel', (tester) async {
    await _montar(tester, initialFirst: 300);
    expect(_largura(tester, _esquerda), 300);
  });

  testWidgets('initialSecond dimensiona o segundo painel', (tester) async {
    await _montar(tester, initialSecond: 250);
    expect(_largura(tester, _direita), 250);
  });

  testWidgets('arrastar para a direita aumenta o primeiro painel', (
    tester,
  ) async {
    await _montar(tester, initialFirst: 300);
    await _arrastar(tester, const Offset(120, 0));
    expect(_largura(tester, _esquerda), greaterThan(300));
  });

  testWidgets('arrastar para a esquerda diminui o primeiro painel', (
    tester,
  ) async {
    await _montar(tester, initialFirst: 300);
    await _arrastar(tester, const Offset(-120, 0));
    expect(_largura(tester, _esquerda), lessThan(300));
  });

  testWidgets('o que um painel ganha o outro perde', (tester) async {
    await _montar(tester, initialFirst: 300);
    await _arrastar(tester, const Offset(120, 0));

    final esquerda = _largura(tester, _esquerda);
    final direita = _largura(tester, _direita);
    expect(esquerda + direita + 9, closeTo(1000, 0.5));
  });

  testWidgets('nao encolhe o primeiro painel abaixo do minimo', (tester) async {
    await _montar(tester, initialFirst: 300, minFirst: 150);
    await _arrastar(tester, const Offset(-900, 0));
    expect(_largura(tester, _esquerda), 150);
  });

  testWidgets('nao encolhe o segundo painel abaixo do minimo', (tester) async {
    await _montar(tester, initialFirst: 300, minSecond: 200);
    await _arrastar(tester, const Offset(900, 0));
    // 1000 de largura - 9 do divisor - 200 do minimo do segundo.
    expect(_largura(tester, _esquerda), 791);
  });

  testWidgets('duplo clique volta ao tamanho padrao', (tester) async {
    await _montar(tester, initialFirst: 300);
    await _arrastar(tester, const Offset(200, 0));
    expect(_largura(tester, _esquerda), isNot(300));

    // Dois toques dentro da janela de duplo clique (300ms no Flutter).
    await tester.tap(find.byType(MouseRegion).last);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(MouseRegion).last);
    await tester.pumpAndSettle();

    expect(_largura(tester, _esquerda), 300);
  });

  testWidgets('no eixo vertical o arrasto muda a altura', (tester) async {
    await _montar(tester, axis: Axis.vertical, initialFirst: 300);
    expect(_altura(tester, _esquerda), 300);

    await _arrastar(tester, const Offset(0, 80));
    expect(_altura(tester, _esquerda), greaterThan(300));
  });

  testWidgets('janela apertada demais divide ao meio em vez de estourar', (
    tester,
  ) async {
    // Os dois minimos somam 700, mas a janela tem 400 de largura util.
    await _montar(
      tester,
      initialFirst: 300,
      minFirst: 350,
      minSecond: 350,
      janela: const Size(400, 600),
    );

    final esquerda = _largura(tester, _esquerda);
    final direita = _largura(tester, _direita);
    expect(esquerda, greaterThan(0));
    expect(direita, greaterThan(0));
    expect(esquerda + direita + 9, closeTo(400, 0.5));
  });

  group('painel que encolhe ocupa a faixa inteira mesmo assim', () {
    /// Conteudo baixinho dos dois lados: e ele que denuncia o alinhamento.
    /// Um painel que preenche a faixa sozinho — o campo de texto do editor,
    /// por exemplo — esconderia o problema.
    Future<void> montarBaixinho(WidgetTester tester, Axis axis) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResizableSplit(
              axis: axis,
              first: const SizedBox(key: _esquerda, height: 20, width: 20),
              second: const SizedBox(key: _direita, height: 20, width: 20),
            ),
          ),
        ),
      );
    }

    testWidgets('na horizontal, os dois lados vao do topo ao pe', (
      tester,
    ) async {
      await montarBaixinho(tester, Axis.horizontal);

      // Sem `crossAxisAlignment: stretch` estes 20px ficariam centrados na
      // vertical, e o conteudo nasceria no meio da tela.
      final altura = tester.getSize(find.byType(ResizableSplit)).height;
      expect(_altura(tester, _esquerda), altura);
      expect(_altura(tester, _direita), altura);
      expect(tester.getRect(find.byKey(_direita)).top, 0);
    });

    testWidgets('na vertical, os dois lados vao de ponta a ponta', (
      tester,
    ) async {
      await montarBaixinho(tester, Axis.vertical);

      final largura = tester.getSize(find.byType(ResizableSplit)).width;
      expect(_largura(tester, _esquerda), largura);
      expect(_largura(tester, _direita), largura);
      expect(tester.getRect(find.byKey(_direita)).left, 0);
    });
  });
}
