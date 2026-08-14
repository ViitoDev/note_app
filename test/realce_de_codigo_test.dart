import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/ui/realce_de_codigo.dart';

/// Percorre o span e devolve a cor com que cada trecho sai desenhado.
Map<String, Color?> _cores(TextSpan span) {
  final saida = <String, Color?>{};
  void varrer(TextSpan atual, Color? herdada) {
    final cor = atual.style?.color ?? herdada;
    final texto = atual.text;
    if (texto != null && texto.trim().isNotEmpty) saida[texto] = cor;
    for (final filho in atual.children ?? const <InlineSpan>[]) {
      if (filho is TextSpan) varrer(filho, cor);
    }
  }

  varrer(span, null);
  return saida;
}

void main() {
  const fonte = TextStyle(fontFamily: 'Consolas', fontSize: 12.5);

  RealceDeCodigo realce(String codigo, String linguagem) => RealceDeCodigo(
    porTrecho: {codigo: linguagem},
    base: fonte,
  );

  test('Java sai com as cores do Darcula', () {
    const codigo = 'public class Hello {\n'
        '  // comentario\n'
        '  int idade = 42;\n'
        '  String nome = "mundo";\n'
        '}';

    final cores = _cores(realce(codigo, 'java').format(codigo));

    Color? corDe(String trecho) => cores.entries
        .firstWhere((e) => e.key.contains(trecho))
        .value;

    // As quatro cores que o olho reconhece de imediato na IDE.
    expect(corDe('public'), Darcula.palavraChave, reason: 'palavra chave');
    expect(corDe('comentario'), Darcula.comentario, reason: 'comentario');
    expect(corDe('42'), Darcula.numero, reason: 'numero');
    expect(corDe('mundo'), Darcula.literal, reason: 'texto');
  });

  test('a fonte do bloco e mantida', () {
    const codigo = 'int a = 1;';
    final span = realce(codigo, 'java').format(codigo);

    expect(span.style?.fontFamily, 'Consolas');
    expect(span.style?.fontSize, 12.5);
  });

  test('sem linguagem declarada, sai sem realce', () {
    // Adivinhar a linguagem erra em codigo curto, e um `for` pintado de
    // Python num trecho de Java confunde mais do que ajuda.
    const codigo = 'public class Hello {}';
    final span = RealceDeCodigo(porTrecho: const {}, base: fonte).format(codigo);

    expect(span.children, isNull);
    expect(span.text, codigo);
    expect(span.style?.color, Darcula.texto);
  });

  test('linguagem que o app nao conhece sai sem realce', () {
    const codigo = 'PROGRAM Teste;';
    final span = realce(codigo, 'pascal').format(codigo);

    expect(span.children, isNull);
    expect(span.text, codigo);
  });

  test('os apelidos comuns valem', () {
    // Ninguem escreve ```cs; escreve ```c#.
    for (final par in {'py': 'x = 1', 'c#': 'int a = 1;', 'js': 'let a = 1;'}
        .entries) {
      final span = realce(par.value, par.key).format(par.value);
      expect(span.children, isNotNull, reason: par.key);
    }
  });

  test('o realce nao muda uma letra do codigo', () {
    // O que se le tem que ser exatamente o que esta no arquivo.
    const codigo = 'if (a < b && c > d) {\n  print("ok");\n}';
    final span = realce(codigo, 'java').format(codigo);

    expect(span.toPlainText(), codigo);
  });
}
