import 'package:flutter/material.dart';

import 'realce_de_codigo.dart';

/// O campo de texto que ja desenha o Markdown enquanto se escreve.
///
/// Nao ha mais um preview ao lado: o proprio campo mostra titulo grande,
/// negrito, italico, codigo e link, como o `.md` vai ser lido. O texto do
/// controlador continua sendo o Markdown cru — e isso que vai para o arquivo —,
/// so o desenho muda.
///
/// Os marcadores (`#`, `**`, `[[`, a crase) somem das linhas onde o cursor nao
/// esta e voltam, apagados, na linha em que se escreve. Escondidos por inteiro
/// eles nao teriam como ser apagados nem corrigidos; a mostra o tempo todo,
/// a nota voltaria a ser lida como codigo.
class MarkdownAoVivo extends TextEditingController {
  MarkdownAoVivo({super.text});

  /// Se o campo esta com o foco. Sem foco nao ha linha sendo escrita, e a nota
  /// inteira sai desenhada.
  bool Function() comFoco = _nunca;

  static bool _nunca() => false;

  /// O começo das linhas que sairam com os marcadores a mostra no ultimo
  /// desenho. E o que diz, num clique, se o usuario viu um link ou o texto dele.
  Set<int> _ativasDesenhadas = const {};

  /// Se a linha que contem [offset] estava desenhada — sem marcadores — da
  /// ultima vez que o campo foi pintado.
  bool estavaDesenhada(int offset) =>
      !_ativasDesenhadas.contains(_inicioDaLinha(text, offset));

  static int _inicioDaLinha(String texto, int offset) {
    if (offset <= 0) return 0;
    return texto.lastIndexOf('\n', offset - 1) + 1;
  }

  // ------------------------------------------------------------ o que ha ali

  /// A caixa `[ ]` ou `[x]` de uma linha de tarefa que contem [offset], se o
  /// offset cair em cima dela. Devolve onde fica o caractere de dentro.
  int? caixaEm(int offset) {
    final inicio = _inicioDaLinha(text, offset);
    final fim = _fimDaLinha(text, inicio);
    final m = _item.firstMatch(text.substring(inicio, fim));
    if (m == null || m.group(4) == null) return null;

    final recuo = inicio + m.group(1)!.length;
    final inicioDaCaixa = recuo + m.group(2)!.length + m.group(3)!.length;
    // Desde o marcador, e nao so a caixa: fora da linha que se escreve o `- `
    // esta escondido, e um clique na borda esquerda da caixa cai nele.
    if (offset < recuo || offset > inicioDaCaixa + 3) return null;
    return inicioDaCaixa + 1;
  }

  /// O titulo do `[[link]]` em que [offset] caiu, se houver.
  String? linkEm(int offset) {
    final inicio = _inicioDaLinha(text, offset);
    final linha = text.substring(inicio, _fimDaLinha(text, inicio));
    for (final m in _wikilink.allMatches(linha)) {
      if (offset >= inicio + m.start && offset <= inicio + m.end) {
        return m.group(1)!.trim();
      }
    }
    return null;
  }

  static int _fimDaLinha(String texto, int inicio) {
    final quebra = texto.indexOf('\n', inicio);
    return quebra < 0 ? texto.length : quebra;
  }

  // -------------------------------------------------------------- o desenho

  static final _titulo = RegExp(r'^(#{1,6})([ \t]+)');
  static final _citacao = RegExp(r'^(>[ \t]?)');
  static final _regua = RegExp(r'^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$');

  /// Cerca de bloco de codigo, com a linguagem que vier depois dela — com ou
  /// sem espaço no meio: ```` ```Java ```` e ```` ``` Java ```` sao a mesma.
  static final _cerca = RegExp(r'^\s*(```|~~~)[ \t]*([^\s`]*)');

  /// Recuo, marcador, o espaço depois dele e, se houver, a caixa de tarefa.
  static final _item = RegExp(
    r'^(\s*)([-*+]|\d+[.)])([ \t]+)(\[[ xX]\][ \t])?',
  );

  static final _recuoDaLinha = RegExp(r'^[ \t]*');

  static final _wikilink = RegExp(r'\[\[([^\]\|\n]+)(?:\|([^\]\n]*))?\]\]');

  /// Os destaques dentro da linha. Codigo primeiro: dentro de crase, `**` e
  /// `[[` sao exemplo escrito de proposito, e nao formataçao.
  static final _destaque = RegExp(
    r'(`+)([^`]+?)\1' // 1, 2: codigo
    r'|\[\[([^\]\|\n]+)(?:\|([^\]\n]*))?\]\]' // 3, 4: wikilink
    r'|\[([^\]\n]+)\]\(([^)\n]*)\)' // 5, 6: link comum
    r'|(\*\*|__)(?=\S)(.+?)(?<=\S)\7' // 7, 8: negrito
    r'|~~(?=\S)(.+?)(?<=\S)~~' // 9: riscado
    r'|(\*|_)(?=\S)(.+?)(?<=\S)\10', // 10, 11: italico
  );

  /// As mesmas matizes de titulo que o preview usava: cada nivel tem a sua,
  /// para dois titulos proximos nao se confundirem a olho.
  static const _toneDeTitulo = [
    Color(0xFF4FA8E0), // h1 — azul
    Color(0xFF63C29A), // h2 — verde-agua
    Color(0xFFD8A657), // h3 — dourado
    Color(0xFFCE7DE0), // h4 — lilas
    Color(0xFFE0836F), // h5 — terracota
    Color(0xFF8FB4E0), // h6 — azul acinzentado
  ];
  static const _tamanhoDeTitulo = [26.0, 19.0, 16.0, 14.5, 13.5, 12.5];

  /// Rosa: fora da paleta dos titulos, para o negrito nunca passar por um h3.
  static const _negrito = Color(0xFFE8659B);

  static const _mono = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Cascadia Mono', 'DejaVu Sans Mono', 'monospace'],
    fontSize: 12.5,
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final scheme = Theme.of(context).colorScheme;
    final pintura = _Pintura(base: base, scheme: scheme);

    final ativas = _linhasAtivas();
    final desenhadas = <int>{};
    final filhos = <InlineSpan>[];
    var emCodigo = false;
    String? linguagem;
    // O bloco e juntado inteiro antes de ser pintado: o realce precisa ver o
    // codigo todo — um comentario ou texto entre aspas atravessa linhas.
    final codigo = StringBuffer();
    final blocos = _blocosDeCodigo(text);
    var cercaEscondida = false;
    var inicio = 0;

    void fecharCodigo() {
      if (codigo.isEmpty) return;
      final texto = codigo.toString();
      codigo.clear();
      final pedacos = realcarCodigo(texto, linguagem);
      filhos.add(
        pedacos == null
            ? TextSpan(text: texto, style: pintura.codigoEmBloco)
            : TextSpan(style: pintura.codigoEmBloco, children: pedacos),
      );
    }

    while (inicio <= text.length) {
      final fim = _fimDaLinha(text, inicio);
      final linha = text.substring(inicio, fim);
      final ativa = ativas.any((a) => a.$1 <= fim && a.$2 >= inicio);
      if (ativa) desenhadas.add(inicio);

      final cerca = _cerca.firstMatch(linha);
      if (cerca != null) {
        fecharCodigo();
        emCodigo = !emCodigo;
        linguagem = emCodigo ? cerca.group(2) : null;
        // Como no Obsidian: fora do bloco, as crases e o nome da linguagem
        // somem — a linha inteira, quebra inclusive — e sobra so o codigo.
        // Com o cursor em qualquer ponto do bloco elas voltam, para se poder
        // trocar a linguagem ou fechar o bloco.
        final bloco = blocos.firstWhere(
          (b) => b.$1 <= inicio && inicio <= b.$2,
          orElse: () => (inicio, fim),
        );
        cercaEscondida = !ativas.any(
          (a) => a.$1 <= bloco.$2 && a.$2 >= bloco.$1,
        );
        filhos.add(
          TextSpan(
            text: linha,
            style: cercaEscondida ? pintura.escondido : pintura.cerca,
          ),
        );
      } else if (emCodigo) {
        // A quebra vai junto do codigo, e nao solta: e parte do que o realce
        // tem que ler.
        codigo.write(fim >= text.length ? linha : '$linha\n');
        if (fim >= text.length) break;
        inicio = fim + 1;
        continue;
      } else {
        _linha(linha, ativa, pintura, filhos);
      }

      if (fim >= text.length) break;
      filhos.add(
        TextSpan(
          text: '\n',
          style: cerca != null && cercaEscondida ? pintura.escondido : null,
        ),
      );
      inicio = fim + 1;
    }
    // Bloco aberto e ainda nao fechado — o que se esta escrevendo agora.
    fecharCodigo();

    _ativasDesenhadas = desenhadas;
    return TextSpan(style: base, children: filhos);
  }

  /// Onde cada bloco de codigo começa e termina: da cerca de abertura ao fim
  /// da de fechamento. Bloco ainda sem fechamento vai ate o fim do texto.
  static List<(int, int)> _blocosDeCodigo(String texto) {
    final blocos = <(int, int)>[];
    int? aberto;
    var inicio = 0;
    while (inicio <= texto.length) {
      final fim = _fimDaLinha(texto, inicio);
      if (_cerca.hasMatch(texto.substring(inicio, fim))) {
        if (aberto == null) {
          aberto = inicio;
        } else {
          blocos.add((aberto, fim));
          aberto = null;
        }
      }
      if (fim >= texto.length) break;
      inicio = fim + 1;
    }
    if (aberto != null) blocos.add((aberto, texto.length));
    return blocos;
  }

  /// Os trechos (inicio, fim) onde ha cursor ou seleçao agora.
  List<(int, int)> _linhasAtivas() {
    if (!comFoco() || !selection.isValid) return const [];
    return [(selection.start, selection.end)];
  }

  void _linha(
    String linha,
    bool ativa,
    _Pintura pintura,
    List<InlineSpan> saida,
  ) {
    final marca = ativa ? pintura.marcador : pintura.escondido;

    final titulo = _titulo.firstMatch(linha);
    if (titulo != null) {
      final nivel = titulo.group(1)!.length - 1;
      final estilo = pintura.base.copyWith(
        fontSize: _tamanhoDeTitulo[nivel],
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: _toneDeTitulo[nivel],
      );
      saida.add(TextSpan(text: titulo.group(0), style: marca));
      _destaques(linha.substring(titulo.end), ativa, pintura, estilo, saida);
      return;
    }

    if (_regua.hasMatch(linha)) {
      saida.add(TextSpan(text: linha, style: pintura.regua));
      return;
    }

    final citacao = _citacao.firstMatch(linha);
    if (citacao != null) {
      saida.add(
        TextSpan(text: citacao.group(0), style: pintura.barraDaCitacao),
      );
      _destaques(
        linha.substring(citacao.end),
        ativa,
        pintura,
        pintura.citacao,
        saida,
      );
      return;
    }

    final item = _item.firstMatch(linha);
    if (item != null) {
      final caixa = item.group(4);
      final feita = caixa != null && caixa[1] != ' ';

      saida.add(TextSpan(text: item.group(1), style: pintura.recuo));
      // Numa tarefa a caixa ja diz que e item de lista; o traço ao lado dela
      // so repetiria a informaçao.
      final semTraco = caixa != null && !ativa;
      saida
        ..add(
          TextSpan(
            text: item.group(2),
            style: semTraco ? pintura.escondido : pintura.marcaDeLista,
          ),
        )
        ..add(
          TextSpan(
            text: item.group(3),
            style: semTraco ? pintura.escondido : pintura.depoisDaMarca,
          ),
        );
      if (caixa != null) {
        saida.add(TextSpan(text: caixa, style: pintura.caixa(feita)));
      }
      _destaques(
        linha.substring(item.end),
        ativa,
        pintura,
        feita ? pintura.tarefaFeita : pintura.base,
        saida,
      );
      return;
    }

    // Paragrafo recuado a mao ganha o mesmo recuo largo dos itens de lista.
    final recuo = _recuoDaLinha.firstMatch(linha)!.end;
    if (recuo > 0) {
      saida.add(
        TextSpan(text: linha.substring(0, recuo), style: pintura.recuo),
      );
    }
    _destaques(linha.substring(recuo), ativa, pintura, pintura.base, saida);
  }

  /// Negrito, italico, codigo e links dentro de um pedaço de linha.
  void _destaques(
    String texto,
    bool ativa,
    _Pintura pintura,
    TextStyle estilo,
    List<InlineSpan> saida,
  ) {
    final marca = ativa ? pintura.marcador : pintura.escondido;
    var ultimo = 0;

    for (final m in _destaque.allMatches(texto)) {
      if (m.start > ultimo) {
        saida.add(
          TextSpan(text: texto.substring(ultimo, m.start), style: estilo),
        );
      }

      if (m.group(1) != null) {
        final crase = m.group(1)!;
        saida
          ..add(TextSpan(text: crase, style: marca))
          ..add(TextSpan(text: m.group(2), style: pintura.codigo))
          ..add(TextSpan(text: crase, style: marca));
      } else if (m.group(3) != null) {
        final alvo = m.group(3)!;
        final apelido = m.group(4);
        final link = estilo.merge(pintura.link);
        saida.add(TextSpan(text: '[[', style: marca));
        if (apelido == null) {
          saida.add(TextSpan(text: alvo, style: link));
        } else {
          saida
            ..add(TextSpan(text: '$alvo|', style: marca))
            ..add(TextSpan(text: apelido, style: link));
        }
        saida.add(TextSpan(text: ']]', style: marca));
      } else if (m.group(5) != null) {
        saida
          ..add(TextSpan(text: '[', style: marca))
          ..add(TextSpan(text: m.group(5), style: estilo.merge(pintura.link)))
          ..add(TextSpan(text: '](${m.group(6)})', style: marca));
      } else if (m.group(7) != null) {
        final par = m.group(7)!;
        saida
          ..add(TextSpan(text: par, style: marca))
          ..add(
            TextSpan(
              text: m.group(8),
              style: estilo.copyWith(
                fontWeight: FontWeight.w700,
                color: _negrito,
              ),
            ),
          )
          ..add(TextSpan(text: par, style: marca));
      } else if (m.group(9) != null) {
        saida
          ..add(TextSpan(text: '~~', style: marca))
          ..add(
            TextSpan(
              text: m.group(9),
              style: estilo.copyWith(decoration: TextDecoration.lineThrough),
            ),
          )
          ..add(TextSpan(text: '~~', style: marca));
      } else {
        final par = m.group(10)!;
        saida
          ..add(TextSpan(text: par, style: marca))
          ..add(
            TextSpan(
              text: m.group(11),
              style: estilo.copyWith(
                fontStyle: FontStyle.italic,
                color: estilo == pintura.base
                    ? pintura.scheme.onSurfaceVariant
                    : null,
              ),
            ),
          )
          ..add(TextSpan(text: par, style: marca));
      }
      ultimo = m.end;
    }

    if (ultimo < texto.length) {
      saida.add(TextSpan(text: texto.substring(ultimo), style: estilo));
    }
  }
}

/// Os estilos de um desenho, montados uma vez por pintura a partir do estilo
/// do campo e das cores do tema.
class _Pintura {
  _Pintura({required this.base, required this.scheme});

  final TextStyle base;
  final ColorScheme scheme;

  /// Marcador fora da linha que se escreve: continua no texto, mas nao ocupa
  /// lugar nem aparece. Tamanho quase zero, e nao zero, porque fonte zero e
  /// tratada como "sem tamanho" e herdaria o do pai.
  late final escondido = const TextStyle(
    color: Colors.transparent,
    fontSize: 0.01,
    letterSpacing: 0,
  );

  /// Marcador na linha que se escreve: a mostra para ser editado, apagado
  /// para nao disputar com o texto.
  late final marcador = TextStyle(
    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.normal,
    decoration: TextDecoration.none,
  );

  /// O recuo no começo da linha, alargado so no desenho.
  ///
  /// O arquivo recua com dois espaços por nivel — o minimo que o Markdown
  /// pede para aninhar, e o que qualquer outro editor entende. Na letra de
  /// leitura dois espaços dao uns 8 pixels, e o item aninhado parecia colado
  /// no de cima. Com o espaçamento, cada nivel anda uns 24 pixels, e o
  /// arquivo continua com os mesmos dois espaços.
  late final recuo = const TextStyle(letterSpacing: 8);

  /// O espaço entre o marcador e o texto do item, um pouco mais largo.
  late final depoisDaMarca = const TextStyle(letterSpacing: 3);

  late final marcaDeLista = TextStyle(
    color: scheme.primary,
    fontWeight: FontWeight.w700,
  );

  TextStyle caixa(bool feita) => MarkdownAoVivo._mono.copyWith(
    fontSize: base.fontSize,
    color: feita ? scheme.primary : scheme.onSurfaceVariant,
    fontWeight: FontWeight.w700,
  );

  late final tarefaFeita = base.copyWith(
    color: scheme.onSurfaceVariant,
    decoration: TextDecoration.lineThrough,
    decorationColor: scheme.onSurfaceVariant.withValues(alpha: 0.6),
  );

  late final link = TextStyle(
    color: scheme.primary,
    decoration: TextDecoration.underline,
    decorationColor: scheme.primary.withValues(alpha: 0.35),
  );

  late final codigo = MarkdownAoVivo._mono.copyWith(
    color: scheme.primary,
    backgroundColor: scheme.surfaceContainerHigh,
  );

  /// As cores do IntelliJ, as mesmas que o preview usava: quem escreve olhando
  /// a IDE do lado ve o mesmo codigo com as mesmas cores.
  late final codigoEmBloco = MarkdownAoVivo._mono.copyWith(
    color: Darcula.texto,
    backgroundColor: scheme.surfaceContainerLowest,
  );

  late final cerca = MarkdownAoVivo._mono.copyWith(
    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
  );

  late final citacao = base.copyWith(
    color: scheme.onSurfaceVariant,
    fontStyle: FontStyle.italic,
  );

  late final barraDaCitacao = TextStyle(
    color: scheme.primary.withValues(alpha: 0.6),
    fontWeight: FontWeight.w700,
  );

  late final regua = TextStyle(color: scheme.outline, letterSpacing: 2);
}
