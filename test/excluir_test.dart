import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/services/vault_service.dart';
import 'package:notas_app/ui/note_tree.dart';
import 'package:notas_app/ui/ui_prefs.dart';
import 'package:notas_app/ui/vault_screen.dart';
import 'package:path/path.dart' as p;

import 'fake_vault.dart';

/// Vault com uma pasta e duas notas, onde o que foi excluido some da proxima
/// varredura — como aconteceria no disco.
class _VaultFalso extends FakeVault {
  @override
  Future<VaultFolder> scan(String rootId) async {
    const solta = VaultFile(id: r'C:\vault\Solta.md', name: 'Solta.md');
    const dentro = VaultFile(
      id: r'C:\vault\Estudos\Dentro.md',
      name: 'Dentro.md',
    );
    const pasta = VaultFolder(
      id: r'C:\vault\Estudos',
      name: 'Estudos',
      children: [dentro],
    );

    return VaultFolder(
      id: r'C:\vault',
      name: 'vault',
      // O que ja foi excluido some da proxima varredura, como no disco.
      children: [
        if (!excluidos.contains(pasta.id)) pasta,
        if (!excluidos.contains(solta.id)) solta,
      ],
    );
  }
}

Future<void> _montar(WidgetTester tester, _VaultFalso vault) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: VaultScreen(repository: vault)));
  await tester.pumpAndSettle();

  // O app abre no painel; estes testes sao sobre a arvore, que vive na aba de
  // notas.
  await tester.tap(find.byKey(const ValueKey('rail-item-notas')));
  await tester.pumpAndSettle();
}

/// Clica com o botao direito sobre uma linha da arvore.
///
/// A busca e restrita a arvore porque o mesmo texto pode estar na
/// pre-visualizaçao da nota aberta — o titulo dela e o proprio nome.
Future<void> _botaoDireito(WidgetTester tester, String alvo) async {
  final linha = find.descendant(
    of: find.byType(NoteTree),
    matching: find.text(alvo),
  );
  final gesto = await tester.startGesture(
    tester.getCenter(linha),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesto.up();
  await tester.pumpAndSettle();
}

void main() {
  group('VaultService', () {
    late Directory vault;
    late VaultService service;

    setUp(() {
      vault = Directory.systemTemp.createTempSync('vault_excluir_');
      service = VaultService();
    });

    tearDown(() {
      if (vault.existsSync()) vault.deleteSync(recursive: true);
    });

    test('apaga a nota do disco', () async {
      final nota = await service.createNote(vault.path, 'Descartavel');
      expect(File(nota).existsSync(), isTrue);

      await service.delete(nota);

      expect(File(nota).existsSync(), isFalse);
    });

    test('apaga a pasta com o conteudo dentro', () async {
      final pasta = await service.createFolder(vault.path, 'Rascunhos');
      final nota = await service.createNote(pasta, 'Uma nota');

      await service.delete(pasta);

      expect(Directory(pasta).existsSync(), isFalse);
      expect(File(nota).existsSync(), isFalse);
    });

    test('apagar o que ja nao existe nao e erro', () async {
      // Nao vale explodir: o resultado pedido — o arquivo fora do vault — ja
      // esta valendo.
      await service.delete(p.join(vault.path, 'Fantasma.md'));
    });

    test('a nota apagada some da varredura', () async {
      await service.createNote(vault.path, 'Fica');
      final vai = await service.createNote(vault.path, 'Vai');

      await service.delete(vai);
      final arvore = await service.scan(vault.path);

      expect(arvore.children.map((c) => c.name), ['Fica.md']);
    });
  });

  group('tela', () {
    setUp(UiPrefs.resetForTesting);

    testWidgets('o botao direito na nota abre o menu de excluir', (
      tester,
    ) async {
      await _montar(tester, _VaultFalso());

      await _botaoDireito(tester, 'Solta');

      expect(find.text('Excluir'), findsOneWidget);
    });

    testWidgets('confirmar exclui a nota e tira ela da arvore', (tester) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _botaoDireito(tester, 'Solta');
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      expect(find.text('Excluir a nota?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await tester.pumpAndSettle();

      expect(vault.excluidos, [r'C:\vault\Solta.md']);
      expect(find.text('Solta'), findsNothing);
    });

    testWidgets('cancelar nao apaga nada', (tester) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _botaoDireito(tester, 'Solta');
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(vault.excluidos, isEmpty);
      expect(find.text('Solta'), findsOneWidget);
    });

    testWidgets('a pasta avisa quantas notas vao junto', (tester) async {
      await _montar(tester, _VaultFalso());

      await _botaoDireito(tester, 'Estudos');
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();

      expect(find.text('Excluir a pasta?'), findsOneWidget);
      expect(find.textContaining('(1 nota(s))'), findsOneWidget);
    });

    testWidgets('excluir a nota aberta fecha o editor', (tester) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await tester.tap(find.text('Solta'));
      await tester.pumpAndSettle();
      expect(find.text('# Solta'), findsWidgets);

      await _botaoDireito(tester, 'Solta');
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await tester.pumpAndSettle();

      expect(find.text('# Solta'), findsNothing);
      expect(find.text('Nenhuma nota aberta'), findsOneWidget);
    });

    testWidgets('excluir a pasta fecha a nota que estava dentro dela', (
      tester,
    ) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await tester.tap(find.text('Estudos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dentro'));
      await tester.pumpAndSettle();
      expect(find.text('# Dentro'), findsWidgets);

      await _botaoDireito(tester, 'Estudos');
      await tester.tap(find.text('Excluir'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Excluir'));
      await tester.pumpAndSettle();

      expect(vault.excluidos, [r'C:\vault\Estudos']);
      expect(find.text('# Dentro'), findsNothing);
      expect(find.text('Nenhuma nota aberta'), findsOneWidget);
    });

    testWidgets('a raiz do vault nao oferece exclusao', (tester) async {
      await _montar(tester, _VaultFalso());

      await _botaoDireito(tester, 'VAULT');

      expect(find.text('Excluir'), findsNothing);
    });
  });
}
