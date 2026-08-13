import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/vault_entry.dart';
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

Future<void> _montar(WidgetTester tester) async {
  // Janela larga: a barra lateral so existe acima do ponto de quebra; abaixo
  // dele a arvore vive num Drawer e nao ha o que ocultar.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(home: VaultScreen(repository: _VaultFalso())),
  );
  await tester.pumpAndSettle();

  // O app abre no painel, onde nao ha barra lateral nenhuma: estes testes sao
  // sobre a aba de notas.
  await tester.tap(find.byKey(const ValueKey('rail-item-notas')));
  await tester.pumpAndSettle();
}

void main() {
  // O cache de preferencias e estatico e sobrevive entre testes: sem zerar,
  // um teste que oculta a barra faz o proximo comecar sem ela.
  setUp(UiPrefs.resetForTesting);

  testWidgets('a barra lateral comeca visivel', (tester) async {
    await _montar(tester);
    expect(find.byType(NoteTree), findsOneWidget);
    expect(
      find.byTooltip('Ocultar a barra da esquerda  (Ctrl+B)'),
      findsOneWidget,
    );
  });

  testWidgets('o botao oculta e mostra a barra lateral', (tester) async {
    await _montar(tester);

    await tester.tap(find.byTooltip('Ocultar a barra da esquerda  (Ctrl+B)'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTree), findsNothing);
    expect(
      find.byTooltip('Mostrar a barra da esquerda  (Ctrl+B)'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Mostrar a barra da esquerda  (Ctrl+B)'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTree), findsOneWidget);
  });

  testWidgets('Ctrl+B alterna a barra lateral', (tester) async {
    await _montar(tester);
    expect(find.byType(NoteTree), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(NoteTree), findsNothing);
  });

  testWidgets('ocultar a barra nao fecha a nota aberta', (tester) async {
    await _montar(tester);

    await tester.tap(find.text('Nota'));
    await tester.pumpAndSettle();
    expect(find.text('# Nota'), findsWidgets);

    await tester.tap(find.byTooltip('Ocultar a barra da esquerda  (Ctrl+B)'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteTree), findsNothing);
    expect(find.text('# Nota'), findsWidgets);
  });

  testWidgets('no calendario nao ha barra lateral para ocultar', (
    tester,
  ) async {
    await _montar(tester);

    await tester.tap(find.text('Calendario'));
    await tester.pumpAndSettle();

    expect(
      find.byTooltip('Ocultar a barra da esquerda  (Ctrl+B)'),
      findsNothing,
    );
  });
}
