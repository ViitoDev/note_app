import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/ui/note_tree.dart';

void main() {
  testWidgets('permite criar a primeira nota na raiz de vault vazio', (
    tester,
  ) async {
    const root = VaultFolder(id: '/vault', name: 'vault', children: []);
    VaultFolder? selectedFolder;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteTree(
            root: root,
            selectedId: null,
            onFileTap: (_) {},
            onNewNoteInFolder: (folder) => selectedFolder = folder,
            onNewFolderIn: (_) {},
            onDelete: (_) {},
            onRenomear: (_) {},
            onMover: (_, _, {antesDe}) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Nova nota na raiz do vault'));

    expect(selectedFolder, same(root));
  });

  testWidgets('permite criar pasta na raiz do vault', (tester) async {
    const root = VaultFolder(id: '/vault', name: 'vault', children: []);
    VaultFolder? alvo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteTree(
            root: root,
            selectedId: null,
            onFileTap: (_) {},
            onNewNoteInFolder: (_) {},
            onNewFolderIn: (folder) => alvo = folder,
            onDelete: (_) {},
            onRenomear: (_) {},
            onMover: (_, _, {antesDe}) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Nova pasta na raiz do vault'));

    expect(alvo, same(root));
  });

  testWidgets('permite criar subpasta dentro de uma pasta', (tester) async {
    const sub = VaultFolder(
      id: '/vault/Estudos',
      name: 'Estudos',
      children: [],
    );
    const root = VaultFolder(id: '/vault', name: 'vault', children: [sub]);
    VaultFolder? alvo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteTree(
            root: root,
            selectedId: null,
            onFileTap: (_) {},
            onNewNoteInFolder: (_) {},
            onNewFolderIn: (folder) => alvo = folder,
            onDelete: (_) {},
            onRenomear: (_) {},
            onMover: (_, _, {antesDe}) {},
          ),
        ),
      ),
    );

    // Os botoes da pasta so aparecem com o ponteiro sobre a linha.
    final rato = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await rato.addPointer(location: Offset.zero);
    addTearDown(rato.removePointer);
    await tester.pump();
    await rato.moveTo(tester.getCenter(find.text('Estudos')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nova pasta em Estudos'));

    expect(alvo, same(sub));
  });
}
