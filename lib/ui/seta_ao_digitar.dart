import 'package:flutter/services.dart';

/// Troca `->` por `→` enquanto se escreve.
///
/// A troca acontece no texto, e nao so no preview: a seta e o que se quis
/// escrever, e ela e um caractere comum — continua sendo seta em qualquer
/// outro editor de Markdown, hoje e depois deste app.
///
/// So no que esta sendo digitado agora. Um `->` que ja estava no arquivo fica
/// como esta, e texto colado tambem: o formatador roda a cada tecla, e uma
/// tecla so muda uma letra. Isso evita que abrir uma nota antiga reescreva
/// sozinho o que ela dizia.
class SetaAoDigitar extends TextInputFormatter {
  const SetaAoDigitar();

  static const seta = '→';
  static const _digitado = '->';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue antes,
    TextEditingValue depois,
  ) {
    final cursor = depois.selection.baseOffset;

    if (!depois.selection.isCollapsed || cursor < 2) return depois;
    if (depois.text.substring(cursor - 2, cursor) != _digitado) return depois;
    if (!_acabaramDeEntrar(antes, depois, cursor)) return depois;

    final inicio = cursor - 2;
    if (!_soltoNoTexto(depois.text, inicio)) return depois;
    if (_emCodigo(depois.text, inicio)) return depois;

    return TextEditingValue(
      text: depois.text.replaceRange(inicio, cursor, seta),
      selection: TextSelection.collapsed(offset: inicio + seta.length),
    );
  }

  /// Se o que mudou foi um punhado de teclas entrando bem no cursor.
  ///
  /// Aqui nao basta contar uma letra a mais: o Windows as vezes entrega duas
  /// teclas rapidas num pacote so, e exigir exatamente uma fazia a seta nao
  /// acontecer justamente para quem digita depressa. O que importa e que o
  /// texto so *cresceu*, e cresceu no lugar do cursor — o que sobra dos dois
  /// lados tem que ser igual ao que ja estava la.
  ///
  /// O teto de duas letras e o que separa digitar de colar: `->` colado no
  /// meio de um paragrafo inteiro continua sendo o que foi colado.
  static bool _acabaramDeEntrar(
    TextEditingValue antes,
    TextEditingValue depois,
    int cursor,
  ) {
    final cresceu = depois.text.length - antes.text.length;
    if (cresceu < 1 || cresceu > _digitado.length) return false;

    final inicio = cursor - cresceu;
    if (inicio < 0 || inicio > antes.text.length) return false;

    return depois.text.substring(0, inicio) ==
            antes.text.substring(0, inicio) &&
        depois.text.substring(cursor) == antes.text.substring(inicio);
  }

  /// Se o `->` esta solto no texto, e nao grudado numa palavra.
  ///
  /// `A -> B` e uma frase; `ptr->campo` e codigo — e codigo aparece no meio de
  /// uma nota de programaçao mesmo sem crase em volta. O espaço antes e o que
  /// separa um caso do outro.
  static bool _soltoNoTexto(String texto, int inicio) {
    if (inicio == 0) return true;
    final antes = texto[inicio - 1];
    return antes == ' ' || antes == '\t' || antes == '\n';
  }

  /// Se aquele ponto do texto esta dentro de codigo — bloco de cerca ou crase
  /// na mesma linha. Ali a seta apagaria justamente o que se queria mostrar.
  static bool _emCodigo(String texto, int ate) {
    final antes = texto.substring(0, ate);

    // Cerca em numero impar: a ultima abriu um bloco que ainda nao fechou.
    if (_cerca.allMatches(antes).length.isOdd) return true;

    final comecoDaLinha = antes.lastIndexOf('\n') + 1;
    return '`'.allMatches(antes.substring(comecoDaLinha)).length.isOdd;
  }

  static final _cerca = RegExp(r'^[ \t]*(```|~~~)', multiLine: true);
}
