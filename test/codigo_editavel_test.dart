import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/ui/codigo_editavel.dart';

void main() {
  const aspas = AspasDeCodigo();

  /// Digita [tecla] no fim de [antes], como o teclado entregaria.
  TextEditingValue digitar(String antes, String tecla) =>
      aspas.formatEditUpdate(
        TextEditingValue(
          text: antes,
          selection: TextSelection.collapsed(offset: antes.length),
        ),
        TextEditingValue(
          text: antes + tecla,
          selection: TextSelection.collapsed(
            offset: antes.length + tecla.length,
          ),
        ),
      );

  test('o trema da tecla morta vira aspa dupla', () {
    final feito = digitar('print(', '¨');
    expect(feito.text, 'print("');
    expect(feito.selection.baseOffset, 7);
  });

  test('aspa seguida de vogal volta a ser aspa e vogal', () {
    // `"` + `a` no US internacional da `ä`.
    final feito = digitar('print(', 'ä');
    expect(feito.text, 'print("a');
    expect(feito.selection.baseOffset, 8);
  });

  test('o acento agudo de verdade fica', () {
    // "número" dentro de um texto: o `ú` e letra, nao acidente.
    expect(digitar('"n', 'ú').text, '"nú');
  });

  test('duas aspas simples viram aspa simples', () {
    expect(digitar('x = ', '´').text, "x = '");
  });

  test('texto colado passa como veio', () {
    expect(digitar('', 'Müller über').text, 'Müller über');
  });

  test('no meio da linha, o cursor acompanha', () {
    final feito = aspas.formatEditUpdate(
      const TextEditingValue(
        text: 'a()',
        selection: TextSelection.collapsed(offset: 2),
      ),
      const TextEditingValue(
        text: 'a(ä)',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    expect(feito.text, 'a("a)');
    expect(feito.selection.baseOffset, 4);
  });

  test('enquanto o teclado compoe, nada e mexido', () {
    const compondo = TextEditingValue(
      text: 'print(¨',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 6, end: 7),
    );
    expect(
      aspas.formatEditUpdate(
        const TextEditingValue(
          text: 'print(',
          selection: TextSelection.collapsed(offset: 6),
        ),
        compondo,
      ),
      compondo,
    );
  });
}
