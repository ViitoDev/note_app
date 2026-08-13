import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/models/vault_order.dart';
import 'package:notas_app/services/vault_service.dart';
import 'package:notas_app/ui/note_tree.dart';
import 'package:notas_app/ui/ui_prefs.dart';
import 'package:notas_app/ui/vault_screen.dart';
import 'package:path/path.dart' as p;

import 'fake_vault.dart';

/// Vault com uma pasta e duas notas, onde renomear se reflete na varredura
/// seguinte — como no disco.
class _VaultFalso extends FakeVault {
  /// Nome atual de cada entrada, para a arvore mudar depois do renomear.
  final nomes = <String, String>{
    r'C:\vault\Solta.md': 'Solta.md',
    r'C:\vault\Estudos': 'Estudos',
    r'C:\vault\Estudos\Dentro.md': 'Dentro.md',
  };

  String _id(String original) =>
      p.join(p.dirname(original), nomes[original] ?? p.basename(original));

  @override
  Future<VaultFolder> scan(String rootId) async {
    final dentro = VaultFile(
      id: p.join(
        _id(r'C:\vault\Estudos'),
        nomes[r'C:\vault\Estudos\Dentro.md']!,
      ),
      name: nomes[r'C:\vault\Estudos\Dentro.md']!,
    );
    final pasta = VaultFolder(
      id: _id(r'C:\vault\Estudos'),
      name: nomes[r'C:\vault\Estudos']!,
      children: [dentro],
    );

    return VaultFolder(
      id: r'C:\vault',
      name: 'vault',
      children: [
        pasta,
        VaultFile(
          id: _id(r'C:\vault\Solta.md'),
          name: nomes[r'C:\vault\Solta.md']!,
        ),
      ],
    );
  }

  @override
  Future<String> rename(String id, String novoNome) async {
    renomeados.add((id: id, nome: novoNome));

    final original = nomes.keys.firstWhere(
      (k) => _id(k) == id,
      orElse: () => id,
    );
    final ehPasta = p.extension(id).isEmpty;
    nomes[original] = ehPasta ? novoNome : '$novoNome.md';
    return p.join(p.dirname(id), nomes[original]!);
  }
}

Future<void> _montar(WidgetTester tester, _VaultFalso vault) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: VaultScreen(repository: vault)));
  await tester.pumpAndSettle();

  // O app abre no painel; a arvore vive na aba de notas.
  await tester.tap(find.byKey(const ValueKey('rail-item-notas')));
  await tester.pumpAndSettle();
}

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
      vault = Directory.systemTemp.createTempSync('vault_renomear_');
      service = VaultService();
    });

    tearDown(() {
      if (vault.existsSync()) vault.deleteSync(recursive: true);
    });

    test('troca o nome da nota mantendo a extensao e o conteudo', () async {
      final nota = await service.createNote(vault.path, 'Antiga');
      final texto = await File(nota).readAsString();

      final novo = await service.rename(nota, 'Nova');

      expect(p.basename(novo), 'Nova.md');
      expect(File(nota).existsSync(), isFalse);
      expect(await File(novo).readAsString(), texto);
    });

    test('quem digita o .md no fim nao ganha .md.md', () async {
      final nota = await service.createNote(vault.path, 'Antiga');

      final novo = await service.rename(nota, 'Nova.md');

      expect(p.basename(novo), 'Nova.md');
    });

    test('ponto no meio do nome nao e confundido com extensao', () async {
      final nota = await service.createNote(vault.path, 'Antiga');

      final novo = await service.rename(nota, 'Aula 1.2');

      expect(p.basename(novo), 'Aula 1.2.md');
    });

    test('a pasta muda de nome levando o conteudo junto', () async {
      final pasta = await service.createFolder(vault.path, 'Antiga');
      await service.createNote(pasta, 'Dentro');

      final novo = await service.rename(pasta, 'Nova');

      expect(p.basename(novo), 'Nova');
      expect(Directory(pasta).existsSync(), isFalse);
      expect(File(p.join(novo, 'Dentro.md')).existsSync(), isTrue);
    });

    test('nome ja usado ganha sufixo em vez de sobrescrever', () async {
      await service.createNote(vault.path, 'Ocupada');
      final outra = await service.createNote(vault.path, 'Outra');

      final novo = await service.rename(outra, 'Ocupada');

      expect(p.basename(novo), 'Ocupada 2.md');
      // A que ja estava ali continua inteira.
      expect(
        await File(p.join(vault.path, 'Ocupada.md')).readAsString(),
        contains('# Ocupada'),
      );
    });

    test('renomear para o mesmo nome nao cria copia', () async {
      final nota = await service.createNote(vault.path, 'Igual');

      final novo = await service.rename(nota, 'Igual');

      expect(novo, nota);
      expect(File(nota).existsSync(), isTrue);
    });

    test('caractere proibido no Windows e trocado', () async {
      final nota = await service.createNote(vault.path, 'Antiga');

      final novo = await service.rename(nota, 'A/B:C');

      expect(p.basename(novo), 'A-B-C.md');
    });
  });

  group('ordem manual acompanha o nome', () {
    test('a nota renomeada fica onde estava, em vez de cair para o fim', () {
      const ordem = VaultOrder({
        '': ['C.md', 'A.md', 'B.md'],
      });

      final depois = ordem.renomeado(
        pasta: '',
        de: 'A.md',
        para: 'Z.md',
        ehPasta: false,
      );

      expect(depois.of(''), ['C.md', 'Z.md', 'B.md']);
    });

    test('renomear pasta leva a chave dela e a de tudo abaixo', () {
      // A chave e o caminho: sem reescrever, a ordem de "Estudos/UFMS" ficaria
      // presa a uma pasta que nao existe mais.
      const ordem = VaultOrder({
        '': ['Estudos', 'Outra'],
        'Estudos': ['b.md', 'a.md'],
        'Estudos/UFMS': ['prova.md'],
        'Outra': ['x.md'],
      });

      final depois = ordem.renomeado(
        pasta: '',
        de: 'Estudos',
        para: 'Faculdade',
        ehPasta: true,
      );

      expect(depois.of(''), ['Faculdade', 'Outra']);
      expect(depois.of('Faculdade'), ['b.md', 'a.md']);
      expect(depois.of('Faculdade/UFMS'), ['prova.md']);
      expect(depois.of('Estudos'), isEmpty);
      // O que nao tem nada com o renomeado fica intacto.
      expect(depois.of('Outra'), ['x.md']);
    });

    test('nome que so parece prefixo nao e arrastado junto', () {
      const ordem = VaultOrder({
        'Estudos': ['a.md'],
        'Estudos2': ['b.md'],
      });

      final depois = ordem.renomeado(
        pasta: '',
        de: 'Estudos',
        para: 'Faculdade',
        ehPasta: true,
      );

      expect(depois.of('Faculdade'), ['a.md']);
      expect(depois.of('Estudos2'), ['b.md']);
    });

    test('renomear nota nao mexe em chave nenhuma', () {
      const ordem = VaultOrder({
        '': ['a.md'],
        'a.md': ['nada'],
      });

      final depois = ordem.renomeado(
        pasta: '',
        de: 'a.md',
        para: 'b.md',
        ehPasta: false,
      );

      expect(depois.of(''), ['b.md']);
      // So pasta re-chaveia; uma nota nao tem filhos.
      expect(depois.of('a.md'), ['nada']);
    });
  });

  group('renomear pela arvore', () {
    setUp(UiPrefs.resetForTesting);

    testWidgets('o menu do botao direito traz Renomear acima de Excluir', (
      tester,
    ) async {
      await _montar(tester, _VaultFalso());
      await _botaoDireito(tester, 'Solta');

      expect(find.text('Renomear'), findsOneWidget);
      expect(find.text('Excluir'), findsOneWidget);
      // A destrutiva fica embaixo: na primeira posiçao ela convida ao clique
      // errado.
      expect(
        tester.getRect(find.text('Renomear')).top,
        lessThan(tester.getRect(find.text('Excluir')).top),
      );
    });

    testWidgets('renomear uma nota grava o nome novo e atualiza a arvore', (
      tester,
    ) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _botaoDireito(tester, 'Solta');
      await tester.tap(find.text('Renomear'));
      await tester.pumpAndSettle();

      // O campo ja vem com o nome atual, sem a extensao.
      expect(find.widgetWithText(TextField, 'Solta'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Renomeada');
      await tester.tap(find.text('Renomear').last);
      await tester.pumpAndSettle();

      expect(vault.renomeados.single.nome, 'Renomeada');
      expect(
        find.descendant(
          of: find.byType(NoteTree),
          matching: find.text('Renomeada'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(NoteTree),
          matching: find.text('Solta'),
        ),
        findsNothing,
      );
    });

    testWidgets('renomear uma pasta funciona igual', (tester) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _botaoDireito(tester, 'Estudos');
      await tester.tap(find.text('Renomear'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Faculdade');
      await tester.tap(find.text('Renomear').last);
      await tester.pumpAndSettle();

      expect(vault.renomeados.single.id, r'C:\vault\Estudos');
      expect(
        find.descendant(
          of: find.byType(NoteTree),
          matching: find.text('Faculdade'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelar nao renomeia nada', (tester) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await _botaoDireito(tester, 'Solta');
      await tester.tap(find.text('Renomear'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(vault.renomeados, isEmpty);
    });

    testWidgets('a nota aberta continua aberta com o nome novo', (
      tester,
    ) async {
      final vault = _VaultFalso();
      await _montar(tester, vault);

      await tester.tap(
        find.descendant(
          of: find.byType(NoteTree),
          matching: find.text('Solta'),
        ),
      );
      await tester.pumpAndSettle();

      await _botaoDireito(tester, 'Solta');
      await tester.tap(find.text('Renomear'));
      await tester.pumpAndSettle();

      // Com a nota aberta ha dois campos de texto na tela: o do editor e o do
      // dialogo. O alvo aqui e o do dialogo.
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Renomeada',
      );
      await tester.tap(find.text('Renomear').last);
      await tester.pumpAndSettle();

      // O editor mostra o titulo da nota; sem reabrir no caminho novo ele
      // ficaria apontando para um arquivo que nao existe mais.
      expect(find.text('Renomeada'), findsWidgets);
    });
  });
}
