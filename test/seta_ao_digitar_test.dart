import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/ui/seta_ao_digitar.dart';

/// Digita [tecla] no fim de [antes] e devolve o texto que sobra.
///
/// E assim que o campo entrega a mudança ao formatador: o texto novo inteiro,
/// com o cursor onde ele ficou.
String digitando(String antes, String tecla) {
  final depois = antes + tecla;
  return const SetaAoDigitar()
      .formatEditUpdate(
        TextEditingValue(
          text: antes,
          selection: TextSelection.collapsed(offset: antes.length),
        ),
        TextEditingValue(
          text: depois,
          selection: TextSelection.collapsed(offset: depois.length),
        ),
      )
      .text;
}

void main() {
  group('a seta', () {
    test('o > que fecha o -> vira seta', () {
      expect(digitando('IA -', '>'), 'IA →');
    });

    test('vale no começo da linha', () {
      expect(digitando('LLMs\n-', '>'), 'LLMs\n→');
      expect(digitando('-', '>'), '→');
    });

    test('o cursor fica logo depois dela', () {
      const antes = TextEditingValue(
        text: 'IA -',
        selection: TextSelection.collapsed(offset: 4),
      );
      const depois = TextEditingValue(
        text: 'IA ->',
        selection: TextSelection.collapsed(offset: 5),
      );

      final saiu = const SetaAoDigitar().formatEditUpdate(antes, depois);

      expect(saiu.text, 'IA →');
      expect(saiu.selection.baseOffset, 4);
    });

    test('duas teclas num pacote so continuam virando seta', () {
      // Digitando depressa, o Windows as vezes entrega `-` e `>` juntos. A
      // regra antiga exigia exatamente uma letra a mais, e a seta nao saia.
      const antes = TextEditingValue(
        text: 'IA ',
        selection: TextSelection.collapsed(offset: 3),
      );
      const depois = TextEditingValue(
        text: 'IA ->',
        selection: TextSelection.collapsed(offset: 5),
      );

      expect(
        const SetaAoDigitar().formatEditUpdate(antes, depois).text,
        'IA →',
      );
    });

    test('digitar no meio do texto tambem vale', () {
      const antes = TextEditingValue(
        text: 'a - b',
        selection: TextSelection.collapsed(offset: 3),
      );
      const depois = TextEditingValue(
        text: 'a -> b',
        selection: TextSelection.collapsed(offset: 4),
      );

      expect(
        const SetaAoDigitar().formatEditUpdate(antes, depois).text,
        'a → b',
      );
    });
  });

  group('o que nao vira seta', () {
    test('codigo grudado numa palavra: ptr->campo', () {
      expect(digitando('ptr-', '>'), 'ptr->');
    });

    test('a seta comprida que se quis escrever: -->', () {
      expect(digitando('a --', '>'), 'a -->');
    });

    test('dentro de um bloco de codigo', () {
      expect(digitando('```dart\nint f() -', '>'), '```dart\nint f() ->');
    });

    test('depois de o bloco de codigo fechar, volta a valer', () {
      expect(
        digitando('```dart\nvar a = 1;\n```\n\nEntao -', '>'),
        '```dart\nvar a = 1;\n```\n\nEntao →',
      );
    });

    test('entre crases, na mesma linha', () {
      expect(digitando('use `fn() -', '>'), 'use `fn() ->');
    });

    test('depois de a crase fechar, volta a valer', () {
      expect(digitando('use `fn()` -', '>'), 'use `fn()` →');
    });

    test('texto colado nao e texto digitado', () {
      const antes = TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      const depois = TextEditingValue(
        text: 'IA -> LLM',
        selection: TextSelection.collapsed(offset: 9),
      );

      expect(
        const SetaAoDigitar().formatEditUpdate(antes, depois).text,
        'IA -> LLM',
      );
    });

    test('apagar nao vira seta', () {
      const antes = TextEditingValue(
        text: 'IA ->x',
        selection: TextSelection.collapsed(offset: 6),
      );
      const depois = TextEditingValue(
        text: 'IA ->',
        selection: TextSelection.collapsed(offset: 5),
      );

      expect(
        const SetaAoDigitar().formatEditUpdate(antes, depois).text,
        'IA ->',
      );
    });

    test('o que ja estava escrito no arquivo fica como esta', () {
      // O formatador so ve o que se digita; abrir uma nota antiga nao reescreve
      // nenhum `->` que ja estivesse la.
      const texto = 'linha com -> antiga';
      const valor = TextEditingValue(text: texto);

      expect(const SetaAoDigitar().formatEditUpdate(valor, valor).text, texto);
    });
  });
}
