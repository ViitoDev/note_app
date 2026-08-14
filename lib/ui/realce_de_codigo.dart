import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight_core.dart' show highlight, Node;
import 'package:highlight/languages/bash.dart';
import 'package:highlight/languages/cpp.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/kotlin.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/sql.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';

/// Cores do Darcula, o tema escuro que vem no IntelliJ.
///
/// Os valores sao os do proprio tema, e nao uma aproximaçao: quem escreve a
/// nota olhando para a IDE do lado ve o mesmo codigo com as mesmas cores, e
/// nao precisa reaprender o que cada uma quer dizer.
abstract final class Darcula {
  /// Texto sem classificaçao — pontuaçao, identificadores comuns.
  static const texto = Color(0xFFA9B7C6);

  static const palavraChave = Color(0xFFCC7832);
  static const literal = Color(0xFF6A8759);
  static const numero = Color(0xFF6897BB);
  static const comentario = Color(0xFF808080);
  static const nome = Color(0xFFFFC66D);
  static const anotacao = Color(0xFFBBB529);
  static const campo = Color(0xFF9876AA);
  static const tag = Color(0xFFE8BF6A);

  /// Estilo de cada classe que o tokenizador atribui.
  ///
  /// O que nao estiver aqui sai na cor do texto comum — e melhor um trecho sem
  /// realce do que um realce inventado.
  static const porClasse = <String, TextStyle>{
    'keyword': TextStyle(color: palavraChave, fontWeight: FontWeight.w600),
    'built_in': TextStyle(color: palavraChave),
    'literal': TextStyle(color: palavraChave),
    'type': TextStyle(color: texto),

    'string': TextStyle(color: literal),
    'regexp': TextStyle(color: literal),
    'attribute': TextStyle(color: campo),
    'variable': TextStyle(color: campo),
    'symbol': TextStyle(color: campo),

    'number': TextStyle(color: numero),
    'link': TextStyle(color: numero),

    'comment': TextStyle(color: comentario, fontStyle: FontStyle.italic),
    'quote': TextStyle(color: comentario, fontStyle: FontStyle.italic),
    'doctag': TextStyle(color: comentario, fontWeight: FontWeight.w600),

    'title': TextStyle(color: nome),
    'section': TextStyle(color: nome),
    'function': TextStyle(color: nome),

    'meta': TextStyle(color: anotacao),
    'meta-keyword': TextStyle(color: anotacao),

    'name': TextStyle(color: tag),
    'tag': TextStyle(color: tag),
    'attr': TextStyle(color: campo),
  };
}

/// As linguagens que o app sabe realçar.
///
/// Cada uma custa uma gramatica carregada no binario, entao a lista e das que
/// aparecem numa nota de estudo de computaçao, e nao das quase duzentas que o
/// pacote traz. Acrescentar outra e uma linha aqui e uma no topo do arquivo.
final _linguagens = {
  'java': java,
  'python': python,
  'dart': dart,
  'javascript': javascript,
  'kotlin': kotlin,
  'cpp': cpp,
  'cs': cs,
  'sql': sql,
  'bash': bash,
  'json': json,
  'xml': xml,
  'yaml': yaml,
};

/// Como cada linguagem costuma ser escrita na cerca do bloco.
///
/// Ninguem escreve ```` ```cs ````; escreve ```` ```c# ````. O nome que o
/// tokenizador espera e um so, mas o que se digita varia.
const _apelidos = {
  'py': 'python',
  'js': 'javascript',
  'ts': 'javascript',
  'node': 'javascript',
  'kt': 'kotlin',
  'c++': 'cpp',
  'cc': 'cpp',
  'c': 'cpp',
  'c#': 'cs',
  'csharp': 'cs',
  'sh': 'bash',
  'shell': 'bash',
  'zsh': 'bash',
  'html': 'xml',
  'yml': 'yaml',
  'postgres': 'sql',
  'mysql': 'sql',
};

bool _registradas = false;

void _registrar() {
  if (_registradas) return;
  highlight.registerLanguages(_linguagens);
  _registradas = true;
}

/// Pinta os blocos de codigo do preview com as cores do IntelliJ.
///
/// O renderizador de Markdown entrega so o texto do bloco, sem dizer de que
/// linguagem ele e — dai [porTrecho], montado antes a partir do proprio corpo
/// da nota. Trecho sem linguagem declarada sai sem realce: adivinhar a
/// linguagem erra em codigo curto, e um `for` pintado de Python num trecho de
/// Java confunde mais do que ajuda.
class RealceDeCodigo implements SyntaxHighlighter {
  RealceDeCodigo({required this.porTrecho, required this.base}) {
    _registrar();
  }

  /// Do texto do bloco para a linguagem declarada na cerca dele.
  final Map<String, String> porTrecho;

  /// Fonte e tamanho do bloco. A cor vem do realce.
  final TextStyle base;

  @override
  TextSpan format(String source) {
    final semRealce = TextSpan(
      text: source,
      style: base.copyWith(color: Darcula.texto),
    );

    final declarada = porTrecho[source.trimRight()];
    final linguagem = _apelidos[declarada] ?? declarada;
    if (linguagem == null || !_linguagens.containsKey(linguagem)) {
      return semRealce;
    }

    final nos = highlight.parse(source, language: linguagem).nodes;
    if (nos == null || nos.isEmpty) return semRealce;

    return TextSpan(
      style: base.copyWith(color: Darcula.texto),
      children: _spans(nos),
    );
  }

  List<TextSpan> _spans(List<Node> nos) {
    return [
      for (final no in nos)
        TextSpan(
          text: no.value,
          style: Darcula.porClasse[no.className],
          children: no.children == null ? null : _spans(no.children!),
        ),
    ];
  }
}
