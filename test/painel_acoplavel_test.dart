import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/ui/calendar_screen.dart';
import 'package:notas_app/ui/dashboard_screen.dart';
import 'package:notas_app/ui/dock_area.dart';
import 'package:notas_app/ui/graph_screen.dart';
import 'package:notas_app/ui/note_tree.dart';
import 'package:notas_app/ui/ui_prefs.dart';
import 'package:notas_app/ui/vault_screen.dart';

import 'fake_vault.dart';

/// Vault com uma unica nota na raiz.
class _VaultFalso extends FakeVault {
  @override
  Future<VaultFolder> scan(String rootId) async => const VaultFolder(
    id: r'C:\vault',
    name: 'vault',
    children: [VaultFile(id: r'C:\vault\Nota.md', name: 'Nota.md')],
  );
}

Finder _itemRail(String nome) => find.byKey(ValueKey('rail-item-$nome'));

Finder _cabecalho(String painel) => find.byKey(ValueKey('cabecalho-$painel'));

/// A faixa de encaixe so existe enquanto ha um painel no ar.
Offset _faixaLivre(WidgetTester tester) =>
    tester.getRect(find.byType(EmptyDockTarget)).center;

Future<void> _montar(WidgetTester tester) async {
  // Janela larga: as barras laterais so existem acima do ponto de quebra.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: VaultScreen(repository: _VaultFalso())),
  );
  await tester.pumpAndSettle();

  // O app abre no painel; as barras acoplaveis so existem na aba de notas.
  await tester.tap(_itemRail('notas'));
  await tester.pumpAndSettle();
}

/// Arrasta [origem] ate [alvo], recalculando o alvo depois que o arrasto ja
/// comeceu — as faixas de encaixe aparecem nesse instante e mexem no layout.
Future<void> _arrastar(
  WidgetTester tester,
  Finder origem,
  Offset Function() alvo,
) async {
  final gesto = await tester.startGesture(tester.getCenter(origem));
  await gesto.moveBy(const Offset(40, 0));
  await tester.pump();
  await gesto.moveTo(alvo());
  await tester.pump();
  await gesto.up();
  await tester.pumpAndSettle();
}

/// Leva um item do rail para a barra da direita, que comeca vazia.
Future<void> _acoplarNaDireita(WidgetTester tester, String nome) =>
    _arrastar(tester, _itemRail(nome), () => _faixaLivre(tester));

void main() {
  // O cache de preferencias e estatico e sobrevive entre testes: sem zerar,
  // o arranjo de um teste vaza para o seguinte.
  setUp(UiPrefs.resetForTesting);

  testWidgets('comeca com a arvore a esquerda e nada a direita', (
    tester,
  ) async {
    await _montar(tester);

    expect(find.byType(NoteTree), findsOneWidget);
    expect(find.byType(CalendarScreen), findsNothing);
    expect(find.byType(GraphScreen), findsNothing);
  });

  testWidgets('clicar no item do rail abre a aba no centro, sem acoplar', (
    tester,
  ) async {
    await _montar(tester);

    await tester.tap(_itemRail('calendario'));
    await tester.pumpAndSettle();

    // Ocupou o centro: as barras somem enquanto a aba nao e a de notas.
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(NoteTree), findsNothing);
    expect(find.byType(PanelHeader), findsNothing);
  });

  testWidgets('arrastar o item do rail acopla o painel sem tirar a arvore', (
    tester,
  ) async {
    await _montar(tester);

    await _acoplarNaDireita(tester, 'calendario');

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(NoteTree), findsOneWidget);

    // Acoplado a direita: fica depois do centro da tela.
    final calendario = tester.getRect(find.byType(CalendarScreen));
    final arvore = tester.getRect(find.byType(NoteTree));
    expect(calendario.left, greaterThan(arvore.right));
  });

  testWidgets('o app abre no painel', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Sem o `_montar`, que troca para as notas: aqui o assunto e justamente o
    // que aparece primeiro.
    await tester.pumpWidget(
      MaterialApp(home: VaultScreen(repository: _VaultFalso())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(NoteTree), findsNothing);
  });

  testWidgets('o painel abre no centro e tambem acopla numa barra', (
    tester,
  ) async {
    await _montar(tester);

    await tester.tap(_itemRail('dashboard'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(NoteTree), findsNothing);

    // De volta as notas, o mesmo item vira painel quando arrastado.
    await tester.tap(_itemRail('notas'));
    await tester.pumpAndSettle();
    await _acoplarNaDireita(tester, 'dashboard');

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(NoteTree), findsOneWidget);
  });

  testWidgets('o painel abre a lista, acima das notas', (tester) async {
    await _montar(tester);

    expect(
      tester.getRect(_itemRail('dashboard')).top,
      lessThan(tester.getRect(_itemRail('notas')).top),
    );
  });

  testWidgets('painel acoplado nao deixa o item do rail aceso', (tester) async {
    await _montar(tester);

    // O icone cheio e a marca do aceso; o vazado e o estado normal.
    expect(find.byIcon(Icons.calendar_month), findsNothing);

    await _acoplarNaDireita(tester, 'calendario');
    expect(find.byType(CalendarScreen), findsOneWidget);
    // Esta na tela, mas nao e onde o usuario esta: o realce marca a aba
    // aberta, e nao o que mora numa barra.
    expect(find.byIcon(Icons.calendar_month), findsNothing);

    await tester.tap(_itemRail('calendario'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.calendar_month), findsOneWidget);
  });

  testWidgets('clicar em Arquivos fecha e devolve a arvore', (tester) async {
    await _montar(tester);
    expect(find.byType(NoteTree), findsOneWidget);

    await tester.tap(_itemRail('arquivos'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTree), findsNothing);

    await tester.tap(_itemRail('arquivos'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTree), findsOneWidget);
  });

  testWidgets('o X do cabecalho fecha o painel', (tester) async {
    await _montar(tester);

    await _acoplarNaDireita(tester, 'grafo');
    expect(find.byType(GraphScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Fechar o painel Grafo'));
    await tester.pumpAndSettle();

    expect(find.byType(GraphScreen), findsNothing);
    expect(find.byType(NoteTree), findsOneWidget);
  });

  testWidgets('soltar o grafo embaixo do calendario divide a barra', (
    tester,
  ) async {
    await _montar(tester);

    await _acoplarNaDireita(tester, 'calendario');

    await _arrastar(tester, _itemRail('grafo'), () {
      final area = tester.getRect(find.byType(CalendarScreen));
      return Offset(area.center.dx, area.bottom - 20);
    });

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(GraphScreen), findsOneWidget);
    // Arvore a esquerda, calendario e grafo empilhados a direita.
    expect(find.byType(PanelHeader), findsNWidgets(3));

    // Soltou na metade de baixo: o grafo ficou embaixo do calendario.
    expect(
      tester.getRect(_cabecalho('grafo')).top,
      greaterThan(tester.getRect(_cabecalho('calendario')).top),
    );
  });

  testWidgets('soltar na metade de cima poe o painel acima do outro', (
    tester,
  ) async {
    await _montar(tester);

    await _acoplarNaDireita(tester, 'calendario');

    await _arrastar(tester, _itemRail('grafo'), () {
      final area = tester.getRect(find.byType(CalendarScreen));
      return Offset(area.center.dx, area.top + 20);
    });

    // Arvore a esquerda, calendario e grafo empilhados a direita.
    expect(find.byType(PanelHeader), findsNWidgets(3));
    expect(
      tester.getRect(_cabecalho('grafo')).top,
      lessThan(tester.getRect(_cabecalho('calendario')).top),
    );
  });

  testWidgets('arrastar a arvore para a faixa da direita troca ela de lado', (
    tester,
  ) async {
    await _montar(tester);

    final arvoreAntes = tester.getRect(find.byType(NoteTree));

    await _arrastar(tester, _cabecalho('arquivos'), () => _faixaLivre(tester));

    expect(find.byType(NoteTree), findsOneWidget);
    expect(
      tester.getRect(find.byType(NoteTree)).left,
      greaterThan(arvoreAntes.left),
    );
  });

  testWidgets('o botao da esquerda nao mexe na barra da direita', (
    tester,
  ) async {
    await _montar(tester);

    await _acoplarNaDireita(tester, 'calendario');
    expect(find.byType(NoteTree), findsOneWidget);
    expect(find.byType(CalendarScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Ocultar a barra da esquerda  (Ctrl+B)'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTree), findsNothing);
    // A da direita e assunto de outro botao.
    expect(find.byType(CalendarScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Mostrar a barra da esquerda  (Ctrl+B)'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTree), findsOneWidget);
    expect(find.byType(CalendarScreen), findsOneWidget);
  });

  testWidgets('recolher a esquerda leva a barra de navegaçao junto', (
    tester,
  ) async {
    await _montar(tester);
    expect(_itemRail('grafo'), findsOneWidget);

    await tester.tap(find.byTooltip('Ocultar a barra da esquerda  (Ctrl+B)'));
    await tester.pumpAndSettle();

    // Nada de coluna de icones sobrando desse lado.
    expect(_itemRail('notas'), findsNothing);
    expect(_itemRail('arquivos'), findsNothing);
    expect(_itemRail('calendario'), findsNothing);
    expect(_itemRail('grafo'), findsNothing);

    await tester.tap(find.byTooltip('Mostrar a barra da esquerda  (Ctrl+B)'));
    await tester.pumpAndSettle();
    expect(_itemRail('grafo'), findsOneWidget);
  });

  testWidgets('com as duas barras vazias, arrastar escolhe o lado', (
    tester,
  ) async {
    await _montar(tester);

    // Fecha a arvore: nao sobra nenhum painel acoplado.
    await tester.tap(_itemRail('arquivos'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteTree), findsNothing);

    await _arrastar(tester, _itemRail('calendario'), () {
      // Sem painel nenhum, as duas faixas aparecem: pega a da direita.
      final faixas = find.byType(EmptyDockTarget);
      expect(tester.widgetList(faixas).length, 2);
      return tester.getRect(faixas.last).center;
    });

    expect(find.byType(CalendarScreen), findsOneWidget);
  });

  testWidgets('Ctrl+Shift+B recolhe e devolve a barra da direita', (
    tester,
  ) async {
    await _montar(tester);

    await _acoplarNaDireita(tester, 'calendario');
    expect(find.byType(CalendarScreen), findsOneWidget);

    Future<void> atalho() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await atalho();
    expect(find.byType(CalendarScreen), findsNothing);
    // A arvore, que esta na outra barra, nao foi junto.
    expect(find.byType(NoteTree), findsOneWidget);

    await atalho();
    expect(find.byType(CalendarScreen), findsOneWidget);
  });

  testWidgets('a nota aberta continua no centro quando os paineis mudam', (
    tester,
  ) async {
    await _montar(tester);

    await tester.tap(find.text('Nota'));
    await tester.pumpAndSettle();
    expect(find.text('# Nota'), findsWidgets);

    await _acoplarNaDireita(tester, 'calendario');
    expect(find.text('# Nota'), findsWidgets);

    await tester.tap(_itemRail('arquivos'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTree), findsNothing);
    expect(find.text('# Nota'), findsWidgets);
  });
}
