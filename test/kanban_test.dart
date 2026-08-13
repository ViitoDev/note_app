import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/frontmatter_writer.dart';
import 'package:notas_app/models/kanban_card.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/ui/kanban_screen.dart';
import 'package:notas_app/ui/ui_prefs.dart';
import 'package:notas_app/ui/vault_screen.dart';
import 'package:path/path.dart' as p;

import 'fake_vault.dart';

Note _nota(String nome, String conteudo) =>
    Note.parse('/v/$nome.md', conteudo, name: '$nome.md');

Note _card(String nome, String status) =>
    _nota(nome, '---\nstatus: $status\n---\n\nCorpo de $nome.\n');

/// Vault em memoria que guarda o que foi criado e gravado.
class _VaultDeArquivos extends FakeVault {
  final arquivos = <String, String>{};

  @override
  Future<VaultFolder> scan(String rootId) async => VaultFolder(
    id: rootPath,
    name: 'vault',
    children: [
      for (final id in arquivos.keys) VaultFile(id: id, name: p.basename(id)),
    ],
  );

  @override
  Future<Note> readNote(String noteId) async =>
      Note.parse(noteId, arquivos[noteId] ?? '', name: p.basename(noteId));

  @override
  Future<void> writeNote(String noteId, String content) async =>
      arquivos[noteId] = content;

  @override
  Future<String> createNote(String folderId, String title) async {
    final id = p.join(folderId, '$title.md');
    // Espelha o modelo que o VaultService grava numa nota nova.
    arquivos[id] = '---\ntipo: nota\ntags: []\n---\n\n# $title\n\n';
    return id;
  }
}

void main() {
  group('coluna pelo status', () {
    test('reconhece o valor canonico de cada coluna', () {
      for (final coluna in KanbanColumn.values) {
        expect(KanbanColumn.porValor(coluna.valor), coluna);
      }
    });

    test('aceita acento, maiuscula e espaço', () {
      // O `.md` e escrito a mao: quem digita "Em Andamento" espera ver o card
      // na coluna, nao sumido.
      expect(KanbanColumn.porValor('Em Andamento'), KanbanColumn.fazendo);
      expect(KanbanColumn.porValor('REVISÃO'), KanbanColumn.revisao);
      expect(KanbanColumn.porValor('  concluído  '), KanbanColumn.pronto);
      expect(KanbanColumn.porValor('a_fazer'), KanbanColumn.aFazer);
    });

    test('aceita os termos em ingles', () {
      expect(KanbanColumn.porValor('todo'), KanbanColumn.aFazer);
      expect(KanbanColumn.porValor('doing'), KanbanColumn.fazendo);
      expect(KanbanColumn.porValor('review'), KanbanColumn.revisao);
      expect(KanbanColumn.porValor('done'), KanbanColumn.pronto);
    });

    test('status desconhecido ou ausente nao vira card', () {
      expect(KanbanColumn.porValor('qualquer coisa'), isNull);
      expect(KanbanColumn.porValor(null), isNull);
      expect(KanbanColumn.porValor(''), isNull);
      expect(KanbanColumn.porValor(42), isNull);
    });
  });

  group('montar o quadro', () {
    test('so entram notas com status reconhecido', () {
      final board = KanbanBoard.build([
        _card('A', 'a-fazer'),
        _card('B', 'fazendo'),
        _nota('C', '---\ntipo: nota\n---\n\nSem status.'),
        _nota('D', 'Nem frontmatter tem.'),
      ]);

      expect(board.total, 2);
      expect(board.of(KanbanColumn.aFazer).single.titulo, 'A');
      expect(board.of(KanbanColumn.fazendo).single.titulo, 'B');
      expect(board.of(KanbanColumn.pronto), isEmpty);
    });

    test('dentro da coluna a ordem e alfabetica', () {
      // Sem ordem definida a lista mudaria de arranjo a cada varredura: o
      // disco nao promete ordem nenhuma.
      final board = KanbanBoard.build([
        _card('Zebra', 'fazendo'),
        _card('abacate', 'fazendo'),
        _card('Melancia', 'fazendo'),
      ]);

      expect(board.of(KanbanColumn.fazendo).map((c) => c.titulo), [
        'abacate',
        'Melancia',
        'Zebra',
      ]);
    });

    test('todos os cards saem na ordem das colunas', () {
      final board = KanbanBoard.build([
        _card('Feito', 'pronto'),
        _card('Novo', 'a-fazer'),
        _card('Andando', 'fazendo'),
      ]);

      expect(board.todos.map((c) => c.titulo), ['Novo', 'Andando', 'Feito']);
    });

    test('le tags e prazo do frontmatter', () {
      final board = KanbanBoard.build([
        _nota(
          'X',
          '---\nstatus: fazendo\ntags: [estudos, flutter]\n'
              'data: 2026-08-20\n---\n\nCorpo.',
        ),
      ]);

      final card = board.of(KanbanColumn.fazendo).single;
      expect(card.tags, ['estudos', 'flutter']);
      expect(card.prazo, DateTime(2026, 8, 20));
    });

    test('o resumo pula titulo e linha vazia', () {
      final board = KanbanBoard.build([
        _nota(
          'Y',
          '---\nstatus: pronto\n---\n\n# Titulo\n\n\nA primeira '
              'frase util.',
        ),
      ]);

      expect(
        board.of(KanbanColumn.pronto).single.resumo,
        'A primeira frase util.',
      );
    });

    test('quadro sem nenhum card e vazio', () {
      expect(KanbanBoard.build(const []).isEmpty, isTrue);
      expect(KanbanBoard.vazio.isEmpty, isTrue);
    });
  });

  group('gravar o status na nota', () {
    test('troca o valor de um status que ja existe', () {
      expect(
        FrontmatterWriter.definir(
          '---\ntipo: nota\nstatus: a-fazer\n---\n\nCorpo.',
          'status',
          'pronto',
        ),
        '---\ntipo: nota\nstatus: pronto\n---\n\nCorpo.',
      );
    });

    test('acrescenta o campo quando o frontmatter nao tem', () {
      expect(
        FrontmatterWriter.definir(
          '---\ntipo: nota\n---\n\nCorpo.',
          'status',
          'fazendo',
        ),
        '---\ntipo: nota\nstatus: fazendo\n---\n\nCorpo.',
      );
    });

    test('cria o bloco inteiro numa nota sem frontmatter', () {
      expect(
        FrontmatterWriter.definir('# Titulo\n\nCorpo.', 'status', 'a-fazer'),
        '---\nstatus: a-fazer\n---\n\n# Titulo\n\nCorpo.',
      );
    });

    test('nao mexe nos outros campos nem no corpo', () {
      // Reserializar o YAML destruiria comentarios, aspas e ordem — o arquivo
      // e do usuario, escrito do jeito dele.
      const antes =
          '---\n# comentario\ntipo: "evento"\nstatus: todo\n'
          'tags: [a, b]\n---\n\n- [ ] Item\n\nFim.\n';

      final depois = FrontmatterWriter.definir(antes, 'status', 'pronto');

      expect(depois, contains('# comentario'));
      expect(depois, contains('tipo: "evento"'));
      expect(depois, contains('tags: [a, b]'));
      expect(depois, contains('- [ ] Item'));
      expect(depois, contains('status: pronto'));
      expect(depois, isNot(contains('status: todo')));
    });

    test('preserva CRLF', () {
      // O Drive replica os bytes sem normalizar quebra de linha; misturar
      // CRLF e LF no mesmo arquivo bagunça diff e alguns editores.
      final depois = FrontmatterWriter.definir(
        '---\r\ntipo: nota\r\n---\r\n\r\nCorpo.',
        'status',
        'fazendo',
      );

      expect(
        depois,
        '---\r\ntipo: nota\r\nstatus: fazendo\r\n---\r\n\r\nCorpo.',
      );
      expect(depois.contains('\n\n'), isFalse);
    });

    test('o status gravado e lido de volta na mesma coluna', () {
      for (final coluna in KanbanColumn.values) {
        final texto = FrontmatterWriter.definir(
          '---\ntipo: nota\n---\n\nCorpo.',
          'status',
          coluna.valor,
        );
        final nota = Note.parse('/v/n.md', texto);

        expect(KanbanColumn.porValor(nota.frontmatter['status']), coluna);
      }
    });
  });

  group('tela do quadro', () {
    setUp(UiPrefs.resetForTesting);

    testWidgets('quadro vazio explica como criar um card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanScreen(
              board: KanbanBoard.vazio,
              onMover: (_, _) {},
              onOpenNote: (_) {},
              onRefresh: () {},
              onNovoCard: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Nenhum card ainda'), findsOneWidget);
      expect(find.textContaining('status: a-fazer'), findsOneWidget);
    });

    testWidgets('o quadro vazio oferece criar o primeiro card', (tester) async {
      final pedidos = <KanbanColumn>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanScreen(
              board: KanbanBoard.vazio,
              onMover: (_, _) {},
              onOpenNote: (_) {},
              onRefresh: () {},
              onNovoCard: pedidos.add,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Criar o primeiro card'));
      await tester.pump();

      // Comece pelo começo: card novo nasce na primeira coluna.
      expect(pedidos, [KanbanColumn.aFazer]);
    });

    testWidgets('cada coluna cria card na propria coluna', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final pedidos = <KanbanColumn>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanScreen(
              board: KanbanBoard.build([_card('A', 'a-fazer')]),
              onMover: (_, _) {},
              onOpenNote: (_) {},
              onRefresh: () {},
              onNovoCard: pedidos.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Novo card em Revisao'));
      await tester.pump();

      // Nao e "criar e depois arrastar": o card ja nasce onde foi pedido.
      expect(pedidos, [KanbanColumn.revisao]);
    });

    testWidgets('desenha as quatro colunas', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanScreen(
              board: KanbanBoard.build([_card('A', 'a-fazer')]),
              onMover: (_, _) {},
              onOpenNote: (_) {},
              onRefresh: () {},
              onNovoCard: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      for (final coluna in KanbanColumn.values) {
        expect(find.text(coluna.label), findsWidgets);
      }
    });

    testWidgets('o resumo lista todos os cards, de todas as colunas', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanScreen(
              board: KanbanBoard.build([
                _card('Alfa', 'a-fazer'),
                _card('Beta', 'fazendo'),
                _card('Gama', 'pronto'),
              ]),
              onMover: (_, _) {},
              onOpenNote: (_) {},
              onRefresh: () {},
              onNovoCard: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Cada card aparece duas vezes: uma no quadro, uma no resumo embaixo.
      for (final titulo in ['Alfa', 'Beta', 'Gama']) {
        expect(find.text(titulo), findsNWidgets(2));
      }
      expect(find.text('3 cards'), findsOneWidget);
    });

    testWidgets('arrastar um card para outra coluna pede a troca', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      KanbanCard? movido;
      KanbanColumn? destino;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanScreen(
              board: KanbanBoard.build([_card('Alfa', 'a-fazer')]),
              onMover: (c, d) {
                movido = c;
                destino = d;
              },
              onOpenNote: (_) {},
              onRefresh: () {},
              onNovoCard: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final origem = tester.getCenter(find.text('Alfa').first);
      final alvo = tester.getCenter(find.text('Fazendo'));

      final gesto = await tester.startGesture(origem);
      await gesto.moveBy(const Offset(0, 20));
      await tester.pump();
      await gesto.moveTo(alvo);
      await tester.pump();
      await gesto.up();
      await tester.pumpAndSettle();

      expect(movido?.titulo, 'Alfa');
      expect(destino, KanbanColumn.fazendo);
    });
  });

  group('criar card pelo quadro', () {
    setUp(UiPrefs.resetForTesting);

    testWidgets('o card novo nasce como nota com o status da coluna', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final vault = _VaultDeArquivos();
      await tester.pumpWidget(
        MaterialApp(home: VaultScreen(repository: vault)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('rail-item-kanban')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Criar o primeiro card'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Revisar o capitulo 3');
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();

      // Uma nota de verdade no vault, com o campo que a faz virar card.
      final nota =
          vault.arquivos[p.join(vault.rootPath, 'Revisar o capitulo 3.md')];
      expect(nota, isNotNull);
      expect(nota, contains('status: a-fazer'));
      // O frontmatter que a nota ja tinha continua ali.
      expect(nota, contains('tipo: nota'));
      expect(nota, contains('# Revisar o capitulo 3'));

      // E o quadro deixou de estar vazio.
      expect(find.text('Nenhum card ainda'), findsNothing);
      expect(find.text('Revisar o capitulo 3'), findsWidgets);
    });
  });
}
