import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/models/vault_graph.dart';
import 'package:notas_app/ui/graph_screen.dart';

Note _nota(String nome, String corpo) =>
    Note.parse('/v/$nome.md', corpo, name: '$nome.md');

Future<void> _montar(
  WidgetTester tester,
  VaultGraph grafo, {
  ValueChanged<String>? onOpenNote,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GraphScreen(
          graph: grafo,
          // Sem ticker: a simulacao roda de uma vez e o teste nao fica
          // dependente de quantos frames foram bombeados.
          animate: false,
          onOpenNote: onOpenNote ?? (_) {},
          onRefresh: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('vault sem tags nem links mostra o aviso', (tester) async {
    await _montar(tester, VaultGraph.build(const []));
    expect(find.text('Nada para exibir'), findsOneWidget);
  });

  testWidgets('conta notas, tags e ligacoes na barra', (tester) async {
    final grafo = VaultGraph.build([
      _nota('A', '---\ntags: [estudos]\n---\n'),
      _nota('B', '---\ntags: [estudos, flutter]\n---\n'),
    ]);

    await _montar(tester, grafo);

    expect(find.text('2 notas'), findsOneWidget);
    expect(find.text('2 tags'), findsOneWidget);
    expect(find.text('3 ligaçoes'), findsOneWidget);
  });

  testWidgets('o grafo e desenhado num canvas', (tester) async {
    final grafo = VaultGraph.build([_nota('A', '---\ntags: [x]\n---\n')]);
    await _montar(tester, grafo);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('tem campo de filtro e botao de enquadrar', (tester) async {
    final grafo = VaultGraph.build([_nota('A', '---\ntags: [x]\n---\n')]);
    await _montar(tester, grafo);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Filtrar notas e tags'), findsOneWidget);
    expect(find.byTooltip('Enquadrar o grafo'), findsOneWidget);
    expect(find.byTooltip('Reler o vault'), findsOneWidget);
  });

  testWidgets('da para pedir todos os nomes de volta', (tester) async {
    // O grafo nomeia so os nos mais ligados para nao virar mancha de texto;
    // este botao e a saida para quem quer ver o vault inteiro escrito.
    final grafo = VaultGraph.build([
      for (var i = 0; i < 12; i++) _nota('N$i', '---\ntags: [t${i % 3}]\n---\n'),
    ]);
    await _montar(tester, grafo);

    expect(find.byTooltip('Mostrando so os nomes principais'), findsOneWidget);

    await tester.tap(find.byTooltip('Mostrando so os nomes principais'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Mostrando todos os nomes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o filtro aceita texto sem quebrar o desenho', (tester) async {
    final grafo = VaultGraph.build([
      _nota('Alpha', '---\ntags: [x]\n---\n'),
      _nota('Beta', '---\ntags: [y]\n---\n'),
    ]);
    await _montar(tester, grafo);

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('o desenho fica dentro da area do painel', (tester) async {
    // Regressao: sem ClipRect o CustomPaint desenhava os nos por cima do resto
    // da tela quando o grafo era maior que o espaço dele.
    final notas = [
      for (var i = 0; i < 40; i++)
        _nota('N$i', '---\ntags: [t${i % 5}]\n---\n'),
    ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // O grafo ocupa so a faixa de cima; o resto e area alheia.
              SizedBox(
                height: 260,
                child: GraphScreen(
                  graph: VaultGraph.build(notas),
                  animate: false,
                  onOpenNote: (_) {},
                  onRefresh: () {},
                ),
              ),
              const Expanded(child: Placeholder()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // O canvas do grafo tem que estar debaixo de um recorte.
    expect(
      find.ancestor(
        of: find.descendant(
          of: find.byType(GraphScreen),
          matching: find.byType(CustomPaint),
        ),
        matching: find.byType(ClipRect),
      ),
      findsWidgets,
    );
  });

  testWidgets('grafo grande nao estoura o layout', (tester) async {
    final notas = [
      for (var i = 0; i < 60; i++)
        _nota('N$i', '---\ntags: [t${i % 7}]\n---\n'),
    ];
    await _montar(tester, VaultGraph.build(notas));

    expect(tester.takeException(), isNull);
    expect(find.text('60 notas'), findsOneWidget);
    expect(find.text('7 tags'), findsOneWidget);
  });
}
