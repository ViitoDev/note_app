import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/ui/app_theme.dart';
import 'package:notas_app/ui/markdown_ao_vivo.dart';
import 'package:notas_app/ui/realce_de_codigo.dart';

void main() {
  const base = TextStyle(fontSize: 14.5, color: Colors.white);

  /// Desenha [texto] e devolve cada pedaço com o estilo que ele ganhou,
  /// descendo pelos spans e herdando o estilo de cima.
  Future<List<(String, TextStyle)>> desenhar(
    WidgetTester tester,
    String texto, {
    int? cursor,
  }) async {
    late BuildContext contexto;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (c) {
            contexto = c;
            return const SizedBox();
          },
        ),
      ),
    );

    final campo = MarkdownAoVivo(text: texto);
    if (cursor != null) {
      campo
        ..comFoco = (() => true)
        ..selection = TextSelection.collapsed(offset: cursor);
    }
    final span = campo.buildTextSpan(
      context: contexto,
      style: base,
      withComposing: false,
    );

    // O desenho nao pode trocar uma letra: o campo edita o texto que o span
    // mostra, e qualquer diferença desalinharia o cursor.
    expect(span.toPlainText(), texto);

    final saida = <(String, TextStyle)>[];
    void descer(InlineSpan atual, TextStyle herdado) {
      if (atual is! TextSpan) return;
      final estilo = herdado.merge(atual.style);
      if ((atual.text ?? '').isNotEmpty) saida.add((atual.text!, estilo));
      for (final filho in atual.children ?? const <InlineSpan>[]) {
        descer(filho, estilo);
      }
    }

    descer(span, const TextStyle());
    return saida;
  }

  TextStyle estiloDe(List<(String, TextStyle)> pedacos, String texto) =>
      pedacos.firstWhere((p) => p.$1 == texto).$2;

  bool escondido(TextStyle estilo) =>
      estilo.color == Colors.transparent && estilo.fontSize! < 1;

  testWidgets('titulo sai grande, na cor do nivel, e sem os #', (tester) async {
    final pedacos = await desenhar(tester, '# Titulo\nTexto');

    expect(escondido(estiloDe(pedacos, '# ')), isTrue);
    expect(estiloDe(pedacos, 'Titulo').fontSize, greaterThan(20));
    expect(estiloDe(pedacos, 'Texto').fontSize, 14.5);
  });

  testWidgets('cada nivel de titulo tem sua cor, e nenhum e a do link', (
    tester,
  ) async {
    final pedacos = await desenhar(
      tester,
      '# a\n## b\n### c\n#### d\n##### e\n###### f\n[[g]]',
    );

    final cores = [
      for (final t in 'abcdef'.split('')) estiloDe(pedacos, t).color,
    ];
    expect(cores.toSet(), hasLength(6));
    expect(cores, isNot(contains(estiloDe(pedacos, 'g').color)));

    final tamanhos = [
      for (final t in 'abcdef'.split('')) estiloDe(pedacos, t).fontSize!,
    ];
    for (var i = 0; i < tamanhos.length - 1; i++) {
      expect(tamanhos[i], greaterThan(tamanhos[i + 1]));
    }
  });

  testWidgets('negrito tem peso e cor propria', (tester) async {
    final pedacos = await desenhar(tester, '# T\nUm **forte** aqui');

    final forte = estiloDe(pedacos, 'forte');
    expect(forte.fontWeight, FontWeight.w700);
    expect(forte.color, isNot(estiloDe(pedacos, 'T').color));
    expect(forte.color, isNot(estiloDe(pedacos, 'Um ').color));
    expect(escondido(estiloDe(pedacos, '**')), isTrue);
  });

  testWidgets('na linha do cursor os marcadores voltam a mostra', (
    tester,
  ) async {
    // Cursor na segunda linha: o `**` dela aparece, o `#` da primeira nao.
    final pedacos = await desenhar(tester, '# T\nUm **forte**', cursor: 6);

    expect(escondido(estiloDe(pedacos, '# ')), isTrue);
    final marca = estiloDe(pedacos, '**');
    expect(escondido(marca), isFalse);
    expect(marca.color, isNot(Colors.transparent));
  });

  testWidgets('sem foco, nem a linha do cursor mostra os marcadores', (
    tester,
  ) async {
    final pedacos = await desenhar(tester, 'Um **forte**');
    expect(escondido(estiloDe(pedacos, '**')), isTrue);
  });

  testWidgets('link interno mostra so o nome, ou o apelido', (tester) async {
    final pedacos = await desenhar(tester, 'Veja [[Nota|aqui]] e [[Outra]]');

    expect(escondido(estiloDe(pedacos, '[[')), isTrue);
    expect(escondido(estiloDe(pedacos, 'Nota|')), isTrue);
    expect(estiloDe(pedacos, 'aqui').decoration, TextDecoration.underline);
    expect(estiloDe(pedacos, 'Outra').decoration, TextDecoration.underline);
  });

  testWidgets('dentro de crase nada vira formataçao', (tester) async {
    final pedacos = await desenhar(tester, 'Use `**x**` assim');
    expect(estiloDe(pedacos, '**x**').fontFamily, 'Consolas');
  });

  testWidgets('bloco de codigo sai em letra monoespaçada', (tester) async {
    final pedacos = await desenhar(tester, '```dart\n# nao e titulo\n```');
    // O realce pode partir a linha em varios pedaços; todos saem em codigo.
    final linha = pedacos.firstWhere((p) => p.$1.contains('titulo')).$2;
    expect(linha.fontFamily, 'Consolas');
    expect(linha.fontSize, isNot(greaterThan(14.5)));
  });

  testWidgets('tarefa feita sai riscada, e a caixa continua a vista', (
    tester,
  ) async {
    final pedacos = await desenhar(tester, '- [x] Pronto\n- [ ] Falta');

    expect(escondido(estiloDe(pedacos, '[x] ')), isFalse);
    expect(estiloDe(pedacos, 'Pronto').decoration, TextDecoration.lineThrough);
    expect(
      estiloDe(pedacos, 'Falta').decoration,
      isNot(TextDecoration.lineThrough),
    );
  });

  testWidgets('o bloco sai com as cores da linguagem da cerca', (tester) async {
    // Com espaço entre a cerca e o nome, e com maiuscula — como se escreve.
    final pedacos = await desenhar(
      tester,
      '``` Java\n'
      '// comentario\n'
      'public class Hello {\n'
      '  int vezes = 42;\n'
      '  String oi = "Hello world!";\n'
      '}\n'
      '```\n'
      'depois',
    );

    Color? corDe(String trecho) =>
        pedacos.firstWhere((p) => p.$1.contains(trecho)).$2.color;

    expect(corDe('public'), Darcula.palavraChave, reason: 'palavra reservada');
    expect(corDe('comentario'), Darcula.comentario, reason: 'comentario');
    expect(corDe('42'), Darcula.numero, reason: 'numero');
    expect(corDe('Hello world!'), Darcula.literal, reason: 'texto entre aspas');
    // Depois da cerca de fechamento, volta a ser texto da nota.
    expect(estiloDe(pedacos, 'depois').fontFamily, isNot('Consolas'));
  });

  testWidgets('aspas tortas nao apagam o realce do bloco', (tester) async {
    // O trema no lugar da aspa fazia o tokenizador desistir do bloco todo.
    const texto =
        '```Python\nop = input(¨Somar?¨)\nif (op == “S”):\n  x = 1\n```';
    final pedacos = await desenhar(tester, texto);

    Color? corDe(String trecho) =>
        pedacos.firstWhere((p) => p.$1.contains(trecho)).$2.color;

    expect(corDe('if'), Darcula.palavraChave);
    expect(corDe('1'), Darcula.numero);
    // O que aparece e o que foi escrito: o trema continua trema.
    expect(corDe('¨Somar?¨'), Darcula.literal);
    expect(corDe('“S”'), Darcula.literal);
  });

  testWidgets('python tambem, pelo apelido py', (tester) async {
    final pedacos = await desenhar(tester, '```py\nprint("oi")\n```');
    expect(estiloDe(pedacos, '"oi"').color, Darcula.literal);
  });

  testWidgets('linguagem desconhecida sai sem realce, mas como codigo', (
    tester,
  ) async {
    final pedacos = await desenhar(tester, '```terminal\n3+4+5\n```');
    final saida = pedacos.firstWhere((p) => p.$1.contains('3+4+5')).$2;
    expect(saida.fontFamily, 'Consolas');
    expect(saida.color, Darcula.texto);
  });

  testWidgets('bloco ainda aberto ja sai realçado', (tester) async {
    // Quem esta escrevendo o bloco ainda nao fechou a cerca.
    final pedacos = await desenhar(tester, '```java\nreturn 1;');
    expect(
      pedacos.firstWhere((p) => p.$1.contains('return')).$2.color,
      Darcula.palavraChave,
    );
  });

  testWidgets('fora do bloco, as crases e a linguagem somem', (tester) async {
    const texto = 'Antes\n```Python\nprint(1)\n```\nDepois';
    final pedacos = await desenhar(tester, texto);

    expect(escondido(estiloDe(pedacos, '```Python')), isTrue);
    expect(escondido(estiloDe(pedacos, '```')), isTrue);
    // A quebra depois de cada cerca some junto, senao sobraria uma linha em
    // branco no lugar dela.
    final quebras = pedacos.where((p) => p.$1 == '\n').toList();
    expect(quebras.where((p) => escondido(p.$2)), hasLength(2));
    expect(escondido(estiloDe(pedacos, 'Antes')), isFalse);
  });

  testWidgets('com o cursor dentro do bloco, as crases voltam', (tester) async {
    const texto = 'Antes\n```Python\nprint(1)\n```\nDepois';
    // Cursor no meio do `print`, e nao na linha da cerca: basta estar no bloco.
    final pedacos = await desenhar(
      tester,
      texto,
      cursor: texto.indexOf('print') + 2,
    );

    expect(escondido(estiloDe(pedacos, '```Python')), isFalse);
    expect(escondido(estiloDe(pedacos, '```')), isFalse);
  });

  testWidgets('o cursor num bloco nao mostra as crases do outro', (
    tester,
  ) async {
    const texto = '```java\nint a;\n```\n\n```py\nb = 1\n```';
    final pedacos = await desenhar(tester, texto, cursor: texto.indexOf('b ='));

    expect(escondido(estiloDe(pedacos, '```java')), isTrue);
    expect(escondido(estiloDe(pedacos, '```py')), isFalse);
  });

  testWidgets('o recuo sai mais largo, e o arquivo nao muda', (tester) async {
    // O `toPlainText` conferido dentro de `desenhar` garante os mesmos dois
    // espaços; aqui se confere que eles ganharam largura no desenho.
    final pedacos = await desenhar(tester, '- Pai\n  - Filho\n  Paragrafo');

    final recuos = pedacos.where((p) => p.$1 == '  ').toList();
    expect(recuos, hasLength(2));
    for (final r in recuos) {
      expect(r.$2.letterSpacing, greaterThan(4));
    }
  });

  group('o que ha debaixo do clique', () {
    test('a caixa responde de dentro dela e da borda esquerda', () {
      final campo = MarkdownAoVivo(text: 'Oi\n  - [ ] Tarefa');
      final caixa = campo.text.indexOf('[');

      expect(campo.caixaEm(caixa + 1), caixa + 1);
      expect(campo.caixaEm(campo.text.indexOf('-')), caixa + 1);
      expect(campo.caixaEm(campo.text.indexOf('Tarefa') + 2), isNull);
      expect(campo.caixaEm(1), isNull);
    });

    test('lista sem caixa nao e tarefa', () {
      final campo = MarkdownAoVivo(text: '- item');
      expect(campo.caixaEm(0), isNull);
    });

    test('o link devolve o titulo, sem o apelido', () {
      final campo = MarkdownAoVivo(text: 'Veja [[Plano|o plano]] ja');
      expect(campo.linkEm(campo.text.indexOf('o plano')), 'Plano');
      expect(campo.linkEm(campo.text.indexOf('ja')), isNull);
    });
  });
}
