import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_test/flutter_test.dart' as ft;
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/models/vault_order.dart';
import 'package:notas_app/services/vault_service.dart';
import 'package:notas_app/ui/note_tree.dart';
import 'package:notas_app/ui/ui_prefs.dart';
import 'package:notas_app/ui/vault_screen.dart';
import 'package:path/path.dart' as p;

import 'fake_vault.dart';

/// Vault com duas notas soltas e uma pasta, e que reflete os movimentos
/// pedidos na varredura seguinte — como o disco faria.
class _VaultFalso extends FakeVault {
  /// Nome da nota "Alfa" e a pasta onde ela esta.
  String paiDaAlfa = r'C:\vault';

  @override
  Future<VaultFolder> scan(String rootId) async {
    final alfa = VaultFile(id: p.join(paiDaAlfa, 'Alfa.md'), name: 'Alfa.md');
    const beta = VaultFile(id: r'C:\vault\Beta.md', name: 'Beta.md');

    final estudos = VaultFolder(
      id: r'C:\vault\Estudos',
      name: 'Estudos',
      children: [if (paiDaAlfa != r'C:\vault') alfa],
    );

    return VaultFolder(
      id: r'C:\vault',
      name: 'vault',
      children: [estudos, if (paiDaAlfa == r'C:\vault') alfa, beta],
    );
  }

  @override
  Future<String> move(String id, String newParentId) async {
    await super.move(id, newParentId);
    if (p.basename(id) == 'Alfa.md') paiDaAlfa = newParentId;
    return p.join(newParentId, p.basename(id));
  }
}

Future<void> _montar(WidgetTester tester, FakeVault vault) async {
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

ft.Finder _linha(String texto) =>
    find.descendant(of: find.byType(NoteTree), matching: find.text(texto));

/// Arrasta uma linha da arvore ate um ponto do alvo, dado em fraçao da altura
/// dele: 0.1 e o topo (soltar acima), 0.5 o meio, 0.9 a base.
Future<void> _arrastarLinha(
  WidgetTester tester,
  String origem,
  String alvo, {
  required double altura,
}) async {
  final gesto = await tester.startGesture(tester.getCenter(_linha(origem)));
  await gesto.moveBy(const Offset(0, 12));
  await tester.pump();

  final area = tester.getRect(_linha(alvo));
  await gesto.moveTo(Offset(area.center.dx, area.top + area.height * altura));
  await tester.pump();
  await gesto.up();
  await tester.pumpAndSettle();
}

void main() {
  group('VaultService.move', () {
    late Directory vault;
    late VaultService service;

    setUp(() {
      vault = Directory.systemTemp.createTempSync('vault_mover_');
      service = VaultService();
    });

    tearDown(() => vault.deleteSync(recursive: true));

    test('leva a nota para dentro da pasta', () async {
      final nota = await service.createNote(vault.path, 'Anda');
      final pasta = await service.createFolder(vault.path, 'Destino');

      final novo = await service.move(nota, pasta);

      expect(File(nota).existsSync(), isFalse);
      expect(File(novo).existsSync(), isTrue);
      expect(p.dirname(novo), pasta);
    });

    test('leva a pasta inteira, com o conteudo', () async {
      final origem = await service.createFolder(vault.path, 'Origem');
      await service.createNote(origem, 'Dentro');
      final destino = await service.createFolder(vault.path, 'Destino');

      final novo = await service.move(origem, destino);

      expect(Directory(origem).existsSync(), isFalse);
      expect(File(p.join(novo, 'Dentro.md')).existsSync(), isTrue);
    });

    test(
      'nome ja ocupado no destino ganha sufixo em vez de sobrescrever',
      () async {
        final pasta = await service.createFolder(vault.path, 'Destino');
        await service.createNote(pasta, 'Igual');
        final outra = await service.createNote(vault.path, 'Igual');

        final novo = await service.move(outra, pasta);

        expect(p.basename(novo), 'Igual 2.md');
        expect(File(p.join(pasta, 'Igual.md')).existsSync(), isTrue);
      },
    );

    test('mover para a pasta onde ja esta nao faz nada', () async {
      final nota = await service.createNote(vault.path, 'Parada');

      expect(await service.move(nota, vault.path), nota);
      expect(File(nota).existsSync(), isTrue);
    });

    test('recusa mover uma pasta para dentro dela mesma', () async {
      final pai = await service.createFolder(vault.path, 'Pai');
      final filha = await service.createFolder(pai, 'Filha');

      // Sem esta guarda o rename levaria o pai junto com o destino e o
      // conteudo ficaria inalcançavel.
      expect(
        () => service.move(pai, filha),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(filha).existsSync(), isTrue);
    });
  });

  group('ordem no disco', () {
    late Directory vault;
    late VaultService service;

    setUp(() {
      vault = Directory.systemTemp.createTempSync('vault_ordem_');
      service = VaultService();
    });

    tearDown(() => vault.deleteSync(recursive: true));

    test('grava e le a ordem escolhida', () async {
      final ordem = VaultOrder.vazia.comOrdem('', ['B.md', 'A.md']);

      await service.saveOrder(vault.path, ordem);

      expect(await service.loadOrder(vault.path), ordem);
    });

    test('sem arquivo gravado a ordem e vazia', () async {
      expect(await service.loadOrder(vault.path), VaultOrder.vazia);
    });

    test('o arquivo de ordem nao aparece na arvore', () async {
      await service.saveOrder(
        vault.path,
        VaultOrder.vazia.comOrdem('', ['A.md']),
      );
      await service.createNote(vault.path, 'A');

      final arvore = await service.scan(vault.path);

      expect(arvore.children.map((e) => e.name), ['A.md']);
    });

    test('ordem vazia apaga o arquivo em vez de deixar lixo', () async {
      await service.saveOrder(
        vault.path,
        VaultOrder.vazia.comOrdem('', ['A.md']),
      );
      await service.saveOrder(vault.path, VaultOrder.vazia);

      expect(
        File(p.join(vault.path, '.notas-ordem.json')).existsSync(),
        isFalse,
      );
    });
  });

  group('arrastar na arvore', () {
    setUp(UiPrefs.resetForTesting);

    testWidgets('soltar no meio de uma pasta move a nota para dentro dela', (
      tester,
    ) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _arrastarLinha(tester, 'Alfa', 'Estudos', altura: 0.5);

      expect(vault.movidos, [
        (id: r'C:\vault\Alfa.md', destino: r'C:\vault\Estudos'),
      ]);
    });

    testWidgets('soltar em cima de uma nota irma so reordena', (tester) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _arrastarLinha(tester, 'Beta', 'Alfa', altura: 0.1);

      // Mesma pasta: nada de disco, so a ordem muda.
      expect(vault.movidos, isEmpty);
      expect(vault.ordem.of(''), ['Estudos', 'Beta.md', 'Alfa.md']);
    });

    testWidgets('soltar embaixo poe a linha depois da vizinha', (tester) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _arrastarLinha(tester, 'Beta', 'Estudos', altura: 0.95);

      expect(vault.ordem.of(''), ['Estudos', 'Beta.md', 'Alfa.md']);
    });

    testWidgets('a ordem escolhida aparece na arvore', (tester) async {
      final vault = _VaultFalso()
        ..ordem = VaultOrder.vazia.comOrdem('', ['Beta.md', 'Alfa.md']);
      await _montar(tester, vault);

      expect(
        tester.getRect(_linha('Beta')).top,
        lessThan(tester.getRect(_linha('Alfa')).top),
      );
    });

    testWidgets('a nota aberta continua aberta depois de mudar de pasta', (
      tester,
    ) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await tester.tap(_linha('Alfa'));
      await tester.pumpAndSettle();
      expect(find.text('# Alfa'), findsWidgets);

      await _arrastarLinha(tester, 'Alfa', 'Estudos', altura: 0.5);

      expect(find.text('# Alfa'), findsWidgets);
      expect(find.text('Nenhuma nota aberta'), findsNothing);
    });
  });
}
