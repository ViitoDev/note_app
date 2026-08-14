import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/kanban_card.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/ui/app_theme.dart';
import 'package:notas_app/ui/note_editor.dart';
import 'package:notas_app/ui/wikilink_suggestions.dart';

void main() {
  group('salvar sozinho', () {
    /// Monta o editor e devolve o registro do que foi gravado, em ordem.
    Future<List<String>> montar(WidgetTester tester) async {
      final gravacoes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/nota.md', 'original'),
              onSave: (texto) async => gravacoes.add(texto),
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      return gravacoes;
    }

    testWidgets('grava sozinho depois da pausa, sem ninguem clicar em nada', (
      tester,
    ) async {
      final gravacoes = await montar(tester);

      await tester.enterText(find.byType(TextField), 'escrito');
      // Ainda escrevendo: nada foi para o disco.
      await tester.pump(const Duration(milliseconds: 400));
      expect(gravacoes, isEmpty);

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();

      expect(gravacoes, ['escrito']);
      expect(find.text('Salvo'), findsOneWidget);
    });

    testWidgets('cada tecla adia a gravaçao, em vez de gravar por letra', (
      tester,
    ) async {
      final gravacoes = await montar(tester);

      // Tres pausas curtas seguidas: nenhuma completa o prazo sozinha.
      for (final texto in ['um', 'um do', 'um dois']) {
        await tester.enterText(find.byType(TextField), texto);
        await tester.pump(const Duration(milliseconds: 700));
      }
      expect(gravacoes, isEmpty);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // Uma gravaçao so, com o texto final.
      expect(gravacoes, ['um dois']);
    });

    testWidgets('sair do campo grava na hora, sem esperar a pausa', (
      tester,
    ) async {
      final gravacoes = await montar(tester);

      await tester.enterText(find.byType(TextField), 'escrito');
      await tester.pump(const Duration(milliseconds: 100));
      expect(gravacoes, isEmpty);

      // Clicar em qualquer outra coisa do app tira o foco daqui.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump();

      expect(gravacoes, ['escrito']);
    });

    testWidgets('Ctrl+S continua gravando na hora', (tester) async {
      final gravacoes = await montar(tester);

      await tester.enterText(find.byType(TextField), 'escrito');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump();

      expect(gravacoes, ['escrito']);

      // E a pausa que ja estava marcada nao grava de novo o mesmo texto.
      await tester.pump(const Duration(seconds: 2));
      expect(gravacoes, ['escrito']);
    });

    testWidgets('o que foi digitado durante a gravaçao nao se perde', (
      tester,
    ) async {
      final gravacoes = <String>[];
      final primeira = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/nota.md', 'original'),
              onSave: (texto) {
                gravacoes.add(texto);
                // A primeira gravaçao fica pendurada; as seguintes passam.
                return gravacoes.length == 1
                    ? primeira.future
                    : Future<void>.value();
              },
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'primeiro');
      await tester.pump(const Duration(seconds: 1));
      expect(gravacoes, ['primeiro']);

      // Escreve mais enquanto a gravaçao anterior ainda esta no ar.
      await tester.enterText(find.byType(TextField), 'primeiro e segundo');
      await tester.pump(const Duration(seconds: 1));

      primeira.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(gravacoes, ['primeiro', 'primeiro e segundo']);
    });
  });

  testWidgets('so limpa alteracoes depois que o salvamento termina', (
    tester,
  ) async {
    final completer = Completer<void>();
    final key = GlobalKey<NoteEditorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            key: key,
            note: Note.parse('/vault/nota.md', 'original'),
            onSave: (_) => completer.future,
            onDirtyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'alterado');

    final saving = key.currentState!.save();
    await tester.pump();
    expect(key.currentState!.isDirty, isTrue);
    expect(find.text('Salvando'), findsOneWidget);

    completer.complete();
    expect(await saving, isTrue);
    await tester.pump();
    expect(key.currentState!.isDirty, isFalse);
  });

  testWidgets('mantem alteracoes pendentes quando o salvamento falha', (
    tester,
  ) async {
    final key = GlobalKey<NoteEditorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            key: key,
            note: Note.parse('/vault/nota.md', 'original'),
            onSave: (_) =>
                Future<void>.error(const FileSystemException('falha simulada')),
            onDirtyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'alterado');

    expect(await key.currentState!.save(), isFalse);
    await tester.pump();
    expect(key.currentState!.isDirty, isTrue);
  });

  group('caixas de tarefa no preview', () {
    /// Monta o editor numa janela larga: abaixo de 900px ele cai no modo so
    /// texto, e ai nao ha preview nem caixa para clicar.
    Future<ValueGetter<String?>> montar(
      WidgetTester tester,
      String conteudo,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? gravado;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/n.md', conteudo),
              onSave: (texto) async => gravado = texto,
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return () => gravado;
    }

    testWidgets('clicar numa caixa vazia marca e grava', (tester) async {
      final gravado = await montar(tester, '- [ ] Um\n- [ ] Dois');

      await tester.tap(
        find.byIcon(Icons.check_box_outline_blank_rounded).first,
      );
      await tester.pumpAndSettle();

      expect(gravado(), '- [x] Um\n- [ ] Dois');
    });

    testWidgets('a segunda caixa mexe na segunda linha', (tester) async {
      final gravado = await montar(tester, '- [ ] Um\n- [ ] Dois');

      await tester.tap(
        find.byIcon(Icons.check_box_outline_blank_rounded).at(1),
      );
      await tester.pumpAndSettle();

      expect(gravado(), '- [ ] Um\n- [x] Dois');
    });

    testWidgets('clicar numa caixa marcada desmarca', (tester) async {
      final gravado = await montar(tester, '- [ ] Um\n- [x] Dois');

      await tester.tap(find.byIcon(Icons.check_box_rounded));
      await tester.pumpAndSettle();

      expect(gravado(), '- [ ] Um\n- [ ] Dois');
    });

    testWidgets('o frontmatter sai intacto', (tester) async {
      // O preview desenha so o corpo, mas o que e gravado e o arquivo inteiro:
      // o indice da caixa nao pode escorregar por causa do cabeçalho.
      final gravado = await montar(
        tester,
        '---\ntipo: nota\ntags: [a]\n---\n\n- [ ] Tarefa\n',
      );

      await tester.tap(find.byIcon(Icons.check_box_outline_blank_rounded));
      await tester.pumpAndSettle();

      expect(gravado(), '---\ntipo: nota\ntags: [a]\n---\n\n- [x] Tarefa\n');
    });
  });

  group('ficha de propriedades da nota', () {
    /// Janela larga: e no preview que vive a ficha.
    Future<ValueGetter<String?>> montar(
      WidgetTester tester,
      String conteudo,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? gravado;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/n.md', conteudo),
              onSave: (texto) async => gravado = texto,
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return () => gravado;
    }

    /// O texto que esta no campo de edicao — o corpo, sem o cabecalho.
    String noEditor(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField).first).controller!.text;

    /// A caixa de digitar tag, e nao o editor de texto da nota. Os dois sao
    /// `TextField` e vivem no mesmo painel; so a dica os separa.
    final campoDeTag = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'estudos, ufms',
    );

    testWidgets('o bloco --- nao aparece no editor de texto', (tester) async {
      await montar(
        tester,
        '---\ntipo: nota\ntags: [ufms]\n---\n\n# Plano de ensino\nOi\n',
      );

      // O frontmatter deixou de ser algo que se digita: quem mexe nele e a
      // ficha, e ter as duas coisas na tela era editar o mesmo dado por dois
      // caminhos, um deles sujeito a erro de sintaxe.
      expect(noEditor(tester), isNot(contains('---')));
      expect(noEditor(tester), isNot(contains('tipo:')));
      expect(noEditor(tester), contains('# Plano de ensino'));
    });

    testWidgets('escrever no corpo grava o arquivo com o cabeçalho', (
      tester,
    ) async {
      final gravado = await montar(tester, '---\ntipo: nota\n---\n\nAntigo\n');

      await tester.enterText(find.byType(TextField).first, '# Novo corpo\n');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // O que o editor segura e so o corpo, mas o que vai para o disco continua
      // sendo o arquivo inteiro.
      expect(gravado(), '---\ntipo: nota\n---\n# Novo corpo\n');
    });

    testWidgets('frontmatter quebrado continua a mostra', (tester) async {
      // Escondido, nao haveria por onde conserta-lo: a ficha nao consegue ler
      // um YAML invalido, e o pedaço do arquivo ficaria sem dono.
      await montar(tester, '---\ntipo: [nota\n---\n\nCorpo\n');

      expect(noEditor(tester), contains('---'));
      expect(noEditor(tester), contains('tipo: [nota'));
    });

    testWidgets('no modo so texto a ficha vem para cima do editor', (
      tester,
    ) async {
      await montar(tester, '---\ntipo: nota\n---\n\nCorpo\n');

      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      // Sem preview na tela, a ficha e o unico acesso ao frontmatter.
      expect(find.text('Tipo'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
    });

    // No modo dividido a ficha encabeça os dois paines, entao cada campo dela
    // aparece duas vezes na tela.
    const nosDois = 2;

    testWidgets('a ficha encabeça os dois paines', (tester) async {
      await montar(tester, '---\ntipo: nota\ntags: [ufms, ead]\n---\n\nOi\n');

      // A lista de campos e o que ensina o que uma nota pode virar; por isso
      // ela aparece inteira mesmo numa nota que so tem tipo e tags.
      for (final campo in ['Tipo', 'Data', 'Hora', 'Status', 'Tags']) {
        expect(find.text(campo), findsNWidgets(nosDois), reason: campo);
      }

      expect(find.text('Nota'), findsNWidgets(nosDois));
      expect(find.text('#ufms'), findsNWidgets(nosDois));
      expect(find.text('#ead'), findsNWidgets(nosDois));

      // Data, hora e status estao vazios: tres convites para preencher, de
      // cada lado.
      expect(find.text('definir'), findsNWidgets(3 * nosDois));
    });

    testWidgets('campo vazio nao chega a existir no arquivo', (tester) async {
      final gravado = await montar(tester, 'Só o corpo.\n');

      // A ficha inteira aparece, mas o `.md` continua sem frontmatter nenhum
      // ate alguem escolher alguma coisa.
      expect(find.text('definir'), findsNWidgets(4 * nosDois));
      expect(gravado(), isNull);
    });

    testWidgets('mexer numa ficha aparece na outra', (tester) async {
      // As duas nao guardam estado proprio: ambas leem o frontmatter do
      // arquivo. Sem isso, um campo mudado num lado ficaria velho no outro.
      await montar(tester, 'Corpo\n');

      await tester.tap(find.text('definir').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evento — entra no calendario'));
      await tester.pumpAndSettle();

      expect(
        find.text('Evento — entra no calendario'),
        findsNWidgets(nosDois),
      );
    });

    testWidgets('data ISO do frontmatter sai por extenso', (tester) async {
      await montar(tester, '---\ndata: 2026-08-10\n---\n\nOi\n');

      expect(find.text('Data'), findsNWidgets(nosDois));
      expect(find.text('10 de agosto de 2026'), findsNWidgets(nosDois));
    });

    testWidgets('campo que a ficha nao edita continua a vista', (tester) async {
      // A ficha nao e dona do frontmatter: o que o usuario escreveu a mao
      // aparece embaixo, em vez de sumir da tela.
      await montar(tester, '---\ncriado_em: 2026-08-10\n---\n\nOi\n');

      expect(find.text('Criado em'), findsNWidgets(nosDois));
      expect(find.text('10 de agosto de 2026'), findsNWidgets(nosDois));
    });

    testWidgets('escolher o tipo grava a linha no frontmatter', (tester) async {
      final gravado = await montar(tester, 'Corpo\n');

      // Os campos vazios saem na ordem da ficha — tipo, data, hora, status —
      // e a do painel da esquerda vem primeiro.
      await tester.tap(find.text('definir').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Evento — entra no calendario'));
      await tester.pumpAndSettle();

      expect(gravado(), '---\ntipo: evento\n---\n\nCorpo\n');
    });

    testWidgets('o status oferece as colunas do quadro', (tester) async {
      final gravado = await montar(tester, 'Corpo\n');

      await tester.tap(find.text('definir').at(3));
      await tester.pumpAndSettle();
      for (final coluna in KanbanColumn.values) {
        expect(find.text(coluna.label), findsOneWidget, reason: coluna.label);
      }

      await tester.tap(find.text('Fazendo'));
      await tester.pumpAndSettle();

      // O mesmo valor que arrastar o card para a coluna gravaria.
      expect(gravado(), '---\nstatus: fazendo\n---\n\nCorpo\n');
    });

    testWidgets('a hora sai da lista de horarios', (tester) async {
      final gravado = await montar(tester, 'Corpo\n');

      await tester.tap(find.text('definir').at(2));
      await tester.pumpAndSettle();

      // A lista abre perto da manha, e nao a meia-noite.
      await tester.tap(find.text('09:30'));
      await tester.pumpAndSettle();

      expect(gravado(), '---\nhora: 09:30\n---\n\nCorpo\n');
    });

    testWidgets('a data sai do calendario', (tester) async {
      final gravado = await montar(tester, 'Corpo\n');

      await tester.tap(find.text('definir').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();

      // O calendario abre no mes corrente quando a nota ainda nao tem data.
      final hoje = DateTime.now();
      final mes = hoje.month.toString().padLeft(2, '0');
      expect(gravado(), '---\ndata: ${hoje.year}-$mes-15\n---\n\nCorpo\n');
    });

    testWidgets('limpar o campo tira a linha do arquivo', (tester) async {
      final gravado = await montar(tester, '---\ntipo: nota\n---\n\nCorpo\n');

      // O `x` so responde com o ponteiro em cima do campo — e o que o mantem
      // fora do caminho enquanto se le a nota.
      final rato = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await rato.addPointer(location: Offset.zero);
      addTearDown(rato.removePointer);
      await rato.moveTo(tester.getCenter(find.text('Nota').first));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Limpar').first);
      await tester.pumpAndSettle();

      // Sem nenhum campo, o bloco inteiro sai: `---` seguido de `---` nao e
      // metadado nenhum.
      expect(gravado(), 'Corpo\n');
    });

    testWidgets('marcar a nota escreve a tag no frontmatter', (tester) async {
      final gravado = await montar(tester, 'Só o corpo.\n');

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      await tester.enterText(campoDeTag, 'estudos');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Nota sem frontmatter ganha o bloco; o corpo continua onde estava.
      expect(gravado(), '---\ntags: [estudos]\n---\n\nSó o corpo.\n');
      expect(find.text('#estudos'), findsNWidgets(nosDois));
    });

    testWidgets('uma digitada marca varias tags de uma vez', (tester) async {
      final gravado = await montar(tester, '---\ntags: [ufms]\n---\n\nOi\n');

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      await tester.enterText(campoDeTag, '#ead, flutter');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // O `#` digitado por costume nao entra duas vezes no arquivo.
      expect(gravado(), '---\ntags: [ufms, ead, flutter]\n---\n\nOi\n');
    });

    testWidgets('tirar a etiqueta tira a tag do arquivo', (tester) async {
      final gravado = await montar(
        tester,
        '---\ntipo: nota\ntags: [ufms, ead]\n---\n\nOi\n',
      );

      // O `x` da primeira etiqueta — o rosa das tags e o que o separa do `x`
      // de limpar campo. So aparece com o ponteiro em cima, mas continua
      // clicavel: o que some e a tinta, nao o alvo.
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.close && w.color == AppTheme.tag,
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(gravado(), '---\ntipo: nota\ntags: [ead]\n---\n\nOi\n');
      expect(find.text('#ufms'), findsNothing);
    });

    testWidgets('o resto do frontmatter fica como estava', (tester) async {
      // O arquivo e do usuario: mexer na linha `tags:` nao pode reescrever o
      // bloco inteiro nem reordenar o que ele digitou.
      final gravado = await montar(
        tester,
        '---\ntipo: nota\n# um comentario\ntags: [a]\nstatus: fazendo\n'
            '---\n\nOi\n',
      );

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.enterText(campoDeTag, 'b');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        gravado(),
        '---\ntipo: nota\n# um comentario\ntags: [a, b]\nstatus: fazendo\n'
        '---\n\nOi\n',
      );
    });
  });

  group('continuar a lista sozinho', () {
    /// Monta o editor e devolve o campo de texto do painel de escrita.
    Future<TextEditingController> montar(
      WidgetTester tester,
      String corpo,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/n.md', corpo),
              onSave: (_) async {},
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
    }

    /// Digita, deixando o cursor no fim, e aperta a tecla.
    Future<void> teclar(
      WidgetTester tester,
      TextEditingController campo,
      String texto,
      LogicalKeyboardKey tecla,
    ) async {
      await tester.enterText(find.byType(TextField).first, texto);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(tecla);
      await tester.pumpAndSettle();
    }

    testWidgets('Enter abre a linha seguinte com o mesmo marcador', (
      tester,
    ) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '- Um', LogicalKeyboardKey.enter);

      expect(campo.text, '- Um\n- ');
      // Cursor logo depois do marcador, pronto para escrever o item.
      expect(campo.selection.baseOffset, campo.text.length);
    });

    testWidgets('vale para os outros marcadores de lista', (tester) async {
      final campo = await montar(tester, '');

      for (final marcador in ['*', '+']) {
        await teclar(tester, campo, '$marcador Um', LogicalKeyboardKey.enter);
        expect(campo.text, '$marcador Um\n$marcador ');
      }
    });

    testWidgets('lista numerada segue a contagem', (tester) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '3. Terceiro', LogicalKeyboardKey.enter);

      expect(campo.text, '3. Terceiro\n4. ');
    });

    testWidgets('tarefa nova nasce desmarcada', (tester) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '- [x] Feito', LogicalKeyboardKey.enter);

      expect(campo.text, '- [x] Feito\n- [ ] ');
    });

    testWidgets('o recuo do item aninhado e mantido', (tester) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '- Um\n  - Dentro', LogicalKeyboardKey.enter);

      expect(campo.text, '- Um\n  - Dentro\n  - ');
    });

    testWidgets('Enter num item vazio encerra a lista', (tester) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '- Um\n- ', LogicalKeyboardKey.enter);

      // O marcador solto sai; a linha fica em branco para seguir escrevendo.
      expect(campo.text, '- Um\n');
    });

    testWidgets('fora de lista, Enter nao e mexido', (tester) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, 'Texto comum', LogicalKeyboardKey.enter);

      // Nada foi inserido por aqui: a quebra de linha continua sendo do campo.
      expect(campo.text, 'Texto comum');
    });

    testWidgets('um backspace tira o marcador inteiro', (tester) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '- Um\n- ', LogicalKeyboardKey.backspace);

      expect(campo.text, '- Um\n');
      expect(campo.selection.baseOffset, campo.text.length);
    });

    testWidgets('backspace com o item ja escrito apaga so uma letra', (
      tester,
    ) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '- Um', LogicalKeyboardKey.backspace);

      // Aqui o backspace nao e nosso: o campo faz o de sempre e come uma
      // letra, em vez de o item inteiro sumir debaixo da mao.
      expect(campo.text, '- U');
    });

    testWidgets('backspace tira o marcador e mantem o recuo', (tester) async {
      final campo = await montar(tester, '');
      await teclar(tester, campo, '- Um\n  - ', LogicalKeyboardKey.backspace);

      expect(campo.text, '- Um\n  ');
    });
  });

  group('Tab recua como numa IDE', () {
    Future<TextEditingController> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/n.md', ''),
              onSave: (_) async {},
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
    }

    Future<void> tab(WidgetTester tester, {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('no meio do texto, escreve o recuo no cursor', (tester) async {
      final campo = await montar(tester);
      await tester.enterText(find.byType(TextField).first, 'Texto');
      await tester.pumpAndSettle();

      await tab(tester);

      expect(campo.text, 'Texto  ');
      expect(campo.selection.baseOffset, campo.text.length);
    });

    testWidgets('num item de lista, aninha a linha inteira', (tester) async {
      final campo = await montar(tester);
      await tester.enterText(find.byType(TextField).first, '- Um\n- Dois');
      await tester.pumpAndSettle();

      // Cursor no fim do segundo item, e nao no começo da linha.
      await tab(tester);

      expect(campo.text, '- Um\n  - Dois');
      // O cursor anda junto com o texto que ele estava acompanhando.
      expect(campo.selection.baseOffset, campo.text.length);
    });

    testWidgets('Shift+Tab desfaz o aninhamento', (tester) async {
      final campo = await montar(tester);
      await tester.enterText(find.byType(TextField).first, '- Um\n  - Dois');
      await tester.pumpAndSettle();

      await tab(tester, shift: true);

      expect(campo.text, '- Um\n- Dois');
    });

    testWidgets('Shift+Tab numa linha sem recuo nao mexe em nada', (
      tester,
    ) async {
      final campo = await montar(tester);
      await tester.enterText(find.byType(TextField).first, '- Um');
      await tester.pumpAndSettle();

      await tab(tester, shift: true);

      expect(campo.text, '- Um');
    });

    testWidgets('com varias linhas selecionadas, recua todas', (tester) async {
      final campo = await montar(tester);
      await tester.enterText(
        find.byType(TextField).first,
        '- Um\n- Dois\n- Tres',
      );
      await tester.pumpAndSettle();

      // Selecao do meio da primeira linha ate o meio da terceira.
      campo.selection = const TextSelection(baseOffset: 3, extentOffset: 14);
      await tester.pumpAndSettle();
      await tab(tester);

      expect(campo.text, '  - Um\n  - Dois\n  - Tres');
    });

    testWidgets('linha em branco no meio da selecao nao ganha espaço solto', (
      tester,
    ) async {
      final campo = await montar(tester);
      await tester.enterText(find.byType(TextField).first, '- Um\n\n- Dois');
      await tester.pumpAndSettle();

      campo.selection = const TextSelection(baseOffset: 0, extentOffset: 11);
      await tester.pumpAndSettle();
      await tab(tester);

      expect(campo.text, '  - Um\n\n  - Dois');
    });

    testWidgets('Tab nao tira mais o foco do campo', (tester) async {
      // Antes disto, Tab passava o foco adiante e nao escrevia nada: a tecla
      // era do sistema de navegaçao, nao do texto.
      final campo = await montar(tester);
      await tester.enterText(find.byType(TextField).first, 'Texto');
      await tester.pumpAndSettle();

      await tab(tester);
      await tab(tester);

      expect(campo.text, 'Texto    ');
    });
  });

  group('os dois lados acompanham a mesma parte da nota', () {
    testWidgets('rolar o texto leva o preview junto', (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Nota longa o bastante para os dois lados rolarem.
      final longa = [
        for (var i = 0; i < 120; i++) 'Linha $i',
      ].join('\n\n');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/n.md', longa),
              onSave: (_) async {},
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final rolagens = find.byType(SingleChildScrollView);
      double posicao(int qual) =>
          tester.widget<SingleChildScrollView>(rolagens.at(qual)).controller!
              .offset;

      expect(posicao(1), 0);

      // Arrasta o painel de escrita para baixo.
      await tester.drag(rolagens.first, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(posicao(0), greaterThan(0));
      // O preview foi junto, na mesma altura relativa.
      expect(posicao(1), greaterThan(0));
    });
  });

  group('link interno no preview', () {
    Future<List<String>> montar(WidgetTester tester, String corpo) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final abertas = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/n.md', corpo),
              onAbrirLink: abertas.add,
              onSave: (_) async {},
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return abertas;
    }

    testWidgets('os colchetes somem do preview', (tester) async {
      await montar(tester, 'Veja [[Plano de ensino]] hoje.\n');

      // No preview le-se o nome da nota, e nao a sintaxe do link. Os `[[` do
      // editor, do outro lado da tela, continuam onde estavam — dai a busca
      // ser so aqui dentro.
      expect(
        find.descendant(
          of: find.byType(MarkdownBody),
          matching: find.textContaining('[['),
        ),
        findsNothing,
      );

      final desenhado = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(desenhado.data, 'Veja [Plano de ensino](wikilink:Plano%20de%20ensino) hoje.\n');
    });

    testWidgets('clicar no link avisa qual nota abrir', (tester) async {
      final abertas = await montar(tester, 'Veja [[Plano de ensino]] hoje.\n');

      // O texto do link, dentro do paragrafo renderizado.
      await tester.tap(find.textContaining('Plano de ensino').last);
      await tester.pumpAndSettle();

      // Titulo inteiro, com os espaços de volta — o destino vai codificado.
      expect(abertas, ['Plano de ensino']);
    });

    testWidgets('titulo com acento volta como foi escrito', (tester) async {
      final abertas = await montar(
        tester,
        'Veja [[Educação a distância]].\n',
      );

      await tester.tap(find.textContaining('Educação a distância').last);
      await tester.pumpAndSettle();

      expect(abertas, ['Educação a distância']);
    });

    testWidgets('o editor continua mostrando os colchetes', (tester) async {
      await montar(tester, 'Veja [[Tutorial]].\n');

      // O `.md` e a fonte da verdade: o que sai de vista e so o desenho.
      final campo = tester.widget<TextField>(find.byType(TextField).first);
      expect(campo.controller!.text, contains('[[Tutorial]]'));
    });
  });

  group('autocompletar de [[', () {
    const vault = ['Plano de ensino', 'Metodologia do curso', 'Tutorial'];

    Future<TextEditingController> montar(
      WidgetTester tester, {
      List<String> notas = vault,
    }) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: NoteEditor(
              note: Note.parse('/vault/n.md', 'Veja '),
              notasDoVault: notas,
              onSave: (_) async {},
              onDirtyChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
    }

    /// Digita no corpo da nota, deixando o cursor no fim.
    Future<void> digitar(WidgetTester tester, String texto) async {
      await tester.enterText(find.byType(TextField).first, texto);
      await tester.pumpAndSettle();
    }

    testWidgets('abrir [[ lista as notas do vault', (tester) async {
      await montar(tester);
      await digitar(tester, 'Veja [[');

      for (final titulo in vault) {
        expect(find.text(titulo), findsOneWidget, reason: titulo);
      }
    });

    testWidgets('o que se digita filtra a lista', (tester) async {
      await montar(tester);
      await digitar(tester, 'Veja [[plano');

      expect(find.text('Plano de ensino'), findsOneWidget);
      expect(find.text('Metodologia do curso'), findsNothing);
    });

    testWidgets('clicar na sugestao escreve o link inteiro', (tester) async {
      final campo = await montar(tester);
      await digitar(tester, 'Veja [[plano');

      await tester.tap(find.text('Plano de ensino'));
      await tester.pumpAndSettle();

      expect(campo.text, 'Veja [[Plano de ensino]]');
      // O cursor fica depois do link, pronto para continuar a frase.
      expect(campo.selection.baseOffset, campo.text.length);
      // E a lista se fecha sozinha: nao ha mais link em aberto.
      expect(find.text('Metodologia do curso'), findsNothing);
    });

    testWidgets('Enter escreve a sugestao marcada', (tester) async {
      final campo = await montar(tester);
      await digitar(tester, 'Veja [[');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // A primeira da lista, em ordem alfabetica.
      expect(campo.text, 'Veja [[Metodologia do curso]]');
    });

    testWidgets('as setas andam pela lista', (tester) async {
      final campo = await montar(tester);
      await digitar(tester, 'Veja [[');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Desceu duas, subiu uma: a segunda da lista.
      expect(campo.text, 'Veja [[Plano de ensino]]');
    });

    testWidgets('Esc fecha a lista sem escrever nada', (tester) async {
      final campo = await montar(tester);
      await digitar(tester, 'Veja [[');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Tutorial'), findsNothing);
      expect(campo.text, 'Veja [[');
    });

    testWidgets('link ja fechado nao reabre a lista', (tester) async {
      await montar(tester);
      await digitar(tester, 'Veja [[Tutorial]]');

      expect(find.text('Metodologia do curso'), findsNothing);
    });

    testWidgets('vault vazio nao mostra lista nenhuma', (tester) async {
      // O editor nao le o vault: sem a lista vinda de fora, digitar `[[`
      // continua funcionando na mao, so que sem sugestao.
      final campo = await montar(tester, notas: const []);
      await digitar(tester, 'Veja [[');

      expect(find.byType(WikilinkSuggestions), findsNothing);
      expect(campo.text, 'Veja [[');
    });

    testWidgets('o ]] que ja existe e reaproveitado', (tester) async {
      final campo = await montar(tester);

      // Cursor no meio de um link ja escrito, trocando o alvo dele.
      await digitar(tester, 'Veja [[Tut]]');
      final antes = campo.text.indexOf(']]');
      campo.selection = TextSelection.collapsed(offset: antes);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tutorial'));
      await tester.pumpAndSettle();

      // E nao `[[Tutorial]]]]`.
      expect(campo.text, 'Veja [[Tutorial]]');
    });
  });

  testWidgets('nota curta começa no topo do preview, nao no meio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            note: Note.parse('/vault/n.md', '# Titulo\n\nUma linha so.\n'),
            onSave: (_) async {},
            onDirtyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Centralizado no eixo vertical, este texto nasceria perto de y=400 numa
    // janela de 800. Encostado no topo, ele fica logo abaixo da barra e da
    // ficha de propriedades, que ocupa uma altura fixa acima do texto.
    expect(tester.getRect(find.byType(MarkdownBody)).top, lessThan(320));
  });

  testWidgets('titulos e negrito tem azul proprio, diferente do link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: NoteEditor(
            note: Note.parse('/vault/n.md', '# Titulo\n\nUm **negrito**.\n'),
            onSave: (_) async {},
            onDirtyChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final estilo = tester
        .widget<MarkdownBody>(find.byType(MarkdownBody))
        .styleSheet!;
    const azul = AppTheme.realce;
    final indigoDoApp = AppTheme.dark.colorScheme.primary;

    // Os seis niveis, para uma nota mais funda nao perder o realce no meio.
    for (final t in [
      estilo.h1,
      estilo.h2,
      estilo.h3,
      estilo.h4,
      estilo.h5,
      estilo.h6,
    ]) {
      expect(t?.color, azul);
    }
    expect(estilo.strong?.color, azul);
    expect(estilo.strong?.fontWeight, FontWeight.w700);

    // O ponto da separaçao: titulo nao pode sair na cor de link, porque link e
    // clicavel e titulo nao.
    expect(azul, isNot(indigoDoApp));
    expect(estilo.a?.color, indigoDoApp);

    // O texto corrido nao vai junto: se tudo fosse azul, nada seria destaque.
    expect(estilo.p?.color, isNot(azul));
  });

  testWidgets('trocar de nota volta o preview para o topo', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final longa = List.generate(120, (i) => 'Linha $i').join('\n\n');

    Future<void> abrir(String id, String texto) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            note: Note.parse(id, texto),
            onSave: (_) async {},
            onDirtyChanged: (_) {},
          ),
        ),
      ),
    );

    await abrir('/vault/a.md', longa);
    await tester.pumpAndSettle();

    final preview = find.byType(SingleChildScrollView).first;
    await tester.drag(preview, const Offset(0, -400));
    await tester.pumpAndSettle();

    double posicao() =>
        tester.widget<SingleChildScrollView>(preview).controller!.offset;
    expect(posicao(), greaterThan(0));

    await abrir('/vault/b.md', longa);
    await tester.pumpAndSettle();

    // Sem isto a nota nova abriria no meio, na altura em que a anterior tinha
    // parado — o editor e o mesmo widget entre uma nota e outra.
    expect(posicao(), 0);
  });
}
