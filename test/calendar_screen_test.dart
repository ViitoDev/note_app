import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/calendar_event.dart';
import 'package:notas_app/ui/calendar_screen.dart';

/// Data fixa para o teste nao depender do relogio da maquina.
final _hoje = DateTime(2026, 8, 6);

Future<void> _montar(
  WidgetTester tester,
  List<CalendarEvent> eventos, {
  ValueChanged<String>? onOpenNote,
}) {
  // Janela de desktop: na superficie padrao (800x600) a grade mensal so
  // renderiza as primeiras semanas, e os dias do fim do mes nem existem.
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CalendarScreen(
          events: eventos,
          today: _hoje,
          onOpenNote: onOpenNote ?? (_) {},
          onRefresh: () {},
        ),
      ),
    ),
  );
}

CalendarEvent _evento(
  String titulo,
  DateTime dia, {
  Duration? hora,
  String noteId = '/v/N.md',
}) => CalendarEvent(
  noteId: noteId,
  title: titulo,
  date: dia,
  time: hora,
  source: EventSource.frontmatter,
);

void main() {
  testWidgets('abre no mes de hoje', (tester) async {
    await _montar(tester, const []);
    expect(find.text('agosto 2026'), findsOneWidget);
  });

  testWidgets('mostra o evento na celula do dia', (tester) async {
    await _montar(tester, [
      _evento(
        'Consulta',
        DateTime(2026, 8, 10),
        hora: const Duration(hours: 14),
      ),
    ]);

    // Aparece na grade com o horario e tambem no painel lateral ao selecionar.
    expect(find.textContaining('Consulta'), findsWidgets);
  });

  testWidgets('navega entre meses', (tester) async {
    await _montar(tester, const []);

    await tester.tap(find.byTooltip('Proximo mes'));
    await tester.pumpAndSettle();
    expect(find.text('setembro 2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();
    expect(find.text('julho 2026'), findsOneWidget);
  });

  testWidgets('botao Hoje volta para o mes atual', (tester) async {
    await _montar(tester, const []);

    await tester.tap(find.byTooltip('Proximo mes'));
    await tester.pumpAndSettle();
    expect(find.text('setembro 2026'), findsOneWidget);

    await tester.tap(find.text('Hoje'));
    await tester.pumpAndSettle();
    expect(find.text('agosto 2026'), findsOneWidget);
  });

  testWidgets('dia sem evento mostra aviso no painel', (tester) async {
    await _montar(tester, const []);
    expect(find.text('Nenhum evento neste dia.'), findsOneWidget);
  });

  testWidgets('clicar no evento do painel abre a nota de origem', (
    tester,
  ) async {
    String? aberta;
    await _montar(tester, [
      _evento('Reuniao', _hoje, noteId: '/v/Projetos/Roadmap.md'),
    ], onOpenNote: (id) => aberta = id);

    // O dia de hoje ja vem selecionado, entao o evento esta no painel.
    await tester.tap(find.widgetWithIcon(ListTile, Icons.event_note));
    await tester.pumpAndSettle();

    expect(aberta, '/v/Projetos/Roadmap.md');
  });

  testWidgets('selecionar outro dia troca a lista do painel', (tester) async {
    await _montar(tester, [
      _evento('Entrega', DateTime(2026, 8, 20), hora: const Duration(hours: 9)),
    ]);

    expect(find.text('Nenhum evento neste dia.'), findsOneWidget);

    await tester.tap(find.text('20').first);
    await tester.pumpAndSettle();

    expect(find.text('Nenhum evento neste dia.'), findsNothing);
    expect(find.text('20 de agosto de 2026'), findsOneWidget);
  });

  testWidgets('conta os eventos do vault no cabeçalho', (tester) async {
    await _montar(tester, [
      _evento('A', DateTime(2026, 8, 10)),
      _evento('B', DateTime(2026, 9, 11)),
    ]);
    expect(find.text('2 evento(s) no vault'), findsOneWidget);
  });

  group('o mes inteiro cabe na tela', () {
    /// O 31 de agosto — e nao o 31 de julho, que a grade desenha antes como
    /// preenchimento da primeira semana. E ele que sumia embaixo da dobra.
    Finder ultimoDia() => find
        .descendant(of: find.byType(GridView), matching: find.text('31'))
        .last;

    testWidgets('agosto de 2026 tem seis semanas e nenhuma fica de fora', (
      tester,
    ) async {
      await _montar(tester, const []);
      await tester.pumpAndSettle();

      final grade = tester.getRect(find.byType(GridView));
      final dia31 = tester.getRect(ultimoDia());

      // Dentro da area da grade, e nao abaixo dela: era ali que ele estava
      // quando a altura da celula saia da largura e ignorava a tela.
      expect(dia31.bottom, lessThanOrEqualTo(grade.bottom + 1));
    });

    testWidgets('nao rola quando cabe', (tester) async {
      await _montar(tester, const []);
      await tester.pumpAndSettle();

      // Uma grade que rola um pixel a toa parece ter mais mes escondido.
      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isA<NeverScrollableScrollPhysics>(),
      );
    });

    testWidgets('numa faixa curta demais ele volta a rolar', (tester) async {
      // Abaixo do minimo por celula, espremer deixaria o numero do dia
      // ilegivel — ai rolar e o menor dos males.
      tester.view.physicalSize = const Size(1400, 260);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarScreen(
              events: const [],
              today: _hoje,
              onOpenNote: (_) {},
              onRefresh: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<GridView>(find.byType(GridView)).physics,
        isNot(isA<NeverScrollableScrollPhysics>()),
      );
    });
  });
}
