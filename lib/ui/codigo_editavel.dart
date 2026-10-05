import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/blocos_da_nota.dart';
import 'app_theme.dart';
import 'realce_de_codigo.dart';

/// O bloco de codigo desenhado como balao: a linguagem no alto, o codigo
/// colorido embaixo, os dois editaveis.
///
/// Como a grade da tabela, e so uma leitura do `.md`: cada tecla devolve o
/// bloco inteiro por [onMudar], e quem recebe troca o trecho no texto da nota.
/// As cercas continuam no arquivo; aqui elas viram a moldura do balao.
class CodigoEditavel extends StatefulWidget {
  const CodigoEditavel({
    super.key,
    required this.bloco,
    required this.onMudar,
    required this.onExcluir,
    this.autofocus = false,
  });

  final BlocoDeCodigo bloco;
  final ValueChanged<BlocoDeCodigo> onMudar;

  /// Desenhado, o bloco nao pode mais ser apagado selecionando as cercas dele.
  /// Sem esta saida ele ficaria na nota para sempre.
  final VoidCallback onExcluir;

  /// Poe o cursor no codigo assim que o balao aparece — vale para o que
  /// acabou de ser aberto com ```` ``` ```` e Enter, ou pelo menu.
  final bool autofocus;

  /// A letra do codigo, a mesma do realce que a nota usava no preview.
  static const fonte = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Cascadia Mono', 'DejaVu Sans Mono', 'monospace'],
    fontSize: 13,
    height: 1.6,
    color: Darcula.texto,
  );

  /// Os nomes que fazem do balao uma janela de terminal.
  ///
  /// Nao e linguagem para colorir: e a saida de um programa, copiada a mao.
  /// `bash` e `sh` ficam de fora de proposito — ali e o comando que se escreve,
  /// e ele continua colorido como codigo.
  static const nomesDeTerminal = {
    'terminal',
    'cmd',
    'console',
    'prompt',
    'saida',
    'saída',
    'output',
  };

  static bool eTerminal(String linguagem) =>
      nomesDeTerminal.contains(linguagem.trim().toLowerCase());

  @override
  State<CodigoEditavel> createState() => _CodigoEditavelState();
}

/// As cores da janela de terminal: preto de console, letra cinza-clara, e os
/// tres botoes de janela na barra — o que faz a saida se ler como saida, e
/// nao como mais um trecho de codigo da nota.
abstract final class _Terminal {
  static const fundo = Color(0xFF0C0C0C);
  static const barra = Color(0xFF1C1C1C);
  static const borda = Color(0xFF2E2E2E);
  static const texto = Color(0xFFD4D4D4);
  static const apagado = Color(0xFF8A8A8A);
  static const botoes = [
    Color(0xFFFF5F57),
    Color(0xFFFEBC2E),
    Color(0xFF28C840),
  ];
}

class _CodigoEditavelState extends State<CodigoEditavel> {
  late final _codigo = _CodigoRealcado(
    text: widget.bloco.codigo,
    linguagem: widget.bloco.linguagem,
  );
  late final _linguagem = TextEditingController(text: widget.bloco.linguagem);
  late final _focoDoCodigo = FocusNode(onKeyEvent: _teclas);

  bool _mouseEmCima = false;
  bool _copiado = false;
  Timer? _desfazerCopiado;

  @override
  void initState() {
    super.initState();
    _codigo.addListener(_codigoMudou);
    _linguagem.addListener(_linguagemMudou);

    // Depois do quadro, e nao pelo `autofocus` do campo: o balao nasce no
    // meio de uma reconstruçao do editor, e o foco pedido antes dela se perde.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focoDoCodigo.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(CodigoEditavel old) {
    super.didUpdateWidget(old);
    // O arquivo mudou por outro caminho — desfazer, sincronizaçao. So se toca
    // no campo quando o texto dele saiu do lugar: reescrever o que esta sendo
    // digitado jogaria o cursor para o começo a cada tecla.
    _codigo.linguagem = widget.bloco.linguagem;
    _acertar(_codigo, widget.bloco.codigo);
    _acertar(_linguagem, widget.bloco.linguagem);
  }

  static void _acertar(TextEditingController campo, String texto) {
    if (campo.text == texto) return;
    final cursor = campo.selection.baseOffset.clamp(0, texto.length);
    campo.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  @override
  void dispose() {
    _desfazerCopiado?.cancel();
    _codigo.dispose();
    _linguagem.dispose();
    _focoDoCodigo.dispose();
    super.dispose();
  }

  void _codigoMudou() {
    if (_codigo.text == widget.bloco.codigo) return;
    widget.onMudar(widget.bloco.comCodigo(_codigo.text));
  }

  void _linguagemMudou() {
    if (_linguagem.text.trim() == widget.bloco.linguagem) return;
    widget.onMudar(widget.bloco.comLinguagem(_linguagem.text));
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _codigo.text));
    if (!mounted) return;
    setState(() => _copiado = true);
    _desfazerCopiado?.cancel();
    _desfazerCopiado = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  // ------------------------------------------------------------- teclado

  /// Um nivel de recuo no codigo. Quatro espaços, e nao os dois das listas da
  /// nota: e o que o Python pede, e o que as IDEs escrevem por padrao.
  static const _recuo = '    ';

  /// Tab recua e Enter mantem o recuo da linha, como numa IDE. Fora daqui
  /// Tab passaria o foco adiante, e Enter voltaria para a margem — num bloco
  /// de Python, cada linha nova teria que ser recuada na mao.
  KeyEventResult _teclas(FocusNode no, KeyEvent evento) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final tecla = evento.logicalKey;
    final selecao = _codigo.selection;
    if (!selecao.isValid) return KeyEventResult.ignored;

    // A aspa dupla e escrita aqui, antes de chegar ao sistema de acentos. No
    // teclado "US internacional" ela e tecla morta: fica esperando a tecla
    // seguinte, e duas seguidas viram um `¨` so — a segunda parecia apagar a
    // primeira. So a dupla: em portugues ela nao faz acento nenhum, enquanto a
    // simples, o til e o circunflexo fazem o "número", o "não" e o "você" que
    // vao dentro dos textos entre aspas.
    final teclado = HardwareKeyboard.instance;
    if (evento.physicalKey == PhysicalKeyboardKey.quote &&
        teclado.isShiftPressed &&
        !teclado.isControlPressed &&
        !teclado.isAltPressed &&
        !teclado.isMetaPressed) {
      _escrever('"');
      return KeyEventResult.handled;
    }

    if (tecla == LogicalKeyboardKey.tab) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _desrecuar();
      } else {
        _escrever(_recuo);
      }
      return KeyEventResult.handled;
    }

    if (tecla == LogicalKeyboardKey.enter ||
        tecla == LogicalKeyboardKey.numpadEnter) {
      final texto = _codigo.text;
      final inicio = texto.lastIndexOf('\n', selecao.start - 1) + 1;
      final linha = texto.substring(inicio, selecao.start);
      var recuo = RegExp(r'^[ \t]*').firstMatch(linha)!.group(0)!;
      // Depois de `:` ou `{` a linha seguinte e o corpo do que se abriu.
      final fimDaLinha = linha.trimRight();
      if (fimDaLinha.endsWith(':') || fimDaLinha.endsWith('{')) {
        recuo += _recuo;
      }
      _escrever('\n$recuo');
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _escrever(String texto) {
    final selecao = _codigo.selection;
    _codigo.value = TextEditingValue(
      text: _codigo.text.replaceRange(selecao.start, selecao.end, texto),
      selection: TextSelection.collapsed(offset: selecao.start + texto.length),
    );
  }

  void _desrecuar() {
    final texto = _codigo.text;
    final cursor = _codigo.selection.start;
    final inicio = texto.lastIndexOf('\n', cursor - 1) + 1;
    final sobra = RegExp(r'^( {1,4}|\t)').firstMatch(texto.substring(inicio));
    if (sobra == null) return;
    _codigo.value = TextEditingValue(
      text: texto.replaceRange(inicio, inicio + sobra.end, ''),
      selection: TextSelection.collapsed(
        offset: (cursor - sobra.end).clamp(inicio, texto.length),
      ),
    );
  }

  // --------------------------------------------------------------- desenho

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final terminal = CodigoEditavel.eTerminal(widget.bloco.linguagem);
    final borda = terminal ? _Terminal.borda : scheme.outlineVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _mouseEmCima = true),
      onExit: (_) => setState(() => _mouseEmCima = false),
      child: Padding(
        // A quebra que separa o bloco do texto ja existe no Markdown e nao
        // deve aparecer como uma linha vazia extra acima do cartao.
        padding: const EdgeInsets.only(bottom: AppTheme.gapSm),
        child: Container(
          key: ValueKey(terminal ? 'codigo-terminal' : 'codigo-balao'),
          decoration: BoxDecoration(
            color: terminal ? _Terminal.fundo : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: borda),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cabecalho(scheme, terminal),
              Divider(height: 1, color: borda),
              _corpo(scheme, terminal),
            ],
          ),
        ),
      ),
    );
  }

  /// A faixa de cima: a linguagem, que se edita ali mesmo, e as açoes.
  Widget _cabecalho(ColorScheme scheme, bool terminal) {
    final rotulo = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: terminal ? _Terminal.apagado : scheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );

    return Container(
      color: terminal ? _Terminal.barra : scheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapMd,
        AppTheme.gapXs,
        AppTheme.gapXs,
        AppTheme.gapXs,
      ),
      child: Row(
        children: [
          if (terminal)
            for (final cor in _Terminal.botoes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                  child: const SizedBox.square(dimension: 10),
                ),
              )
          else
            Icon(Icons.code_rounded, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppTheme.gapSm),
          SizedBox(
            width: 180,
            child: TextField(
              key: const ValueKey('codigo-linguagem'),
              controller: _linguagem,
              style: rotulo,
              cursorColor: scheme.primary,
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                hintText: 'linguagem',
                hintStyle: rotulo?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const Spacer(),
          _acao(
            chave: 'codigo-copiar',
            icone: _copiado ? Icons.check_rounded : Icons.copy_rounded,
            dica: _copiado ? 'Copiado' : 'Copiar codigo',
            onPressed: () => unawaited(_copiar()),
          ),
          // Excluir so aparece com o ponteiro em cima, mas ocupa o lugar
          // sempre: surgindo do nada, empurraria o copiar para o lado.
          AnimatedOpacity(
            opacity: _mouseEmCima ? 1 : 0,
            duration: const Duration(milliseconds: 120),
            child: _acao(
              chave: 'codigo-excluir',
              icone: Icons.delete_outline_rounded,
              dica: 'Excluir bloco',
              onPressed: widget.onExcluir,
            ),
          ),
        ],
      ),
    );
  }

  Widget _acao({
    required String chave,
    required IconData icone,
    required String dica,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: ValueKey(chave),
      onPressed: onPressed,
      tooltip: dica,
      iconSize: 15,
      visualDensity: VisualDensity.compact,
      icon: Icon(icone),
    );
  }

  Widget _corpo(ColorScheme scheme, bool terminal) {
    final fonte = terminal
        ? CodigoEditavel.fonte.copyWith(color: _Terminal.texto)
        : CodigoEditavel.fonte;

    return TextField(
      controller: _codigo,
      focusNode: _focoDoCodigo,
      inputFormatters: const [AspasDeCodigo()],
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: fonte,
      cursorColor: terminal ? _Terminal.texto : scheme.primary,
      cursorWidth: 1.6,
      decoration: InputDecoration(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(
          AppTheme.gapLg,
          AppTheme.gapMd,
          AppTheme.gapLg,
          AppTheme.gapMd,
        ),
        hintText: terminal
            ? 'Cole ou digite a saida...'
            : 'Escreva o codigo...',
        hintStyle: fonte.copyWith(
          color: terminal
              ? _Terminal.apagado
              : scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// O campo do codigo, pintado com as cores da linguagem do balao.
class _CodigoRealcado extends TextEditingController {
  _CodigoRealcado({super.text, required String linguagem})
    : _linguagem = linguagem;

  String _linguagem;
  String? _textoRealcado;
  String? _linguagemRealcada;
  List<TextSpan>? _pedacosRealcados;
  bool _realceCalculado = false;

  String get linguagem => _linguagem;

  set linguagem(String value) {
    if (_linguagem == value) return;
    _linguagem = value;
    _invalidarRealce();
  }

  @override
  set value(TextEditingValue novo) {
    if (value.text != novo.text) _invalidarRealce();
    super.value = novo;
  }

  void _invalidarRealce() {
    _textoRealcado = null;
    _linguagemRealcada = null;
    _pedacosRealcados = null;
    _realceCalculado = false;
  }

  List<TextSpan>? _pedacos() {
    if (_realceCalculado &&
        _textoRealcado == text &&
        _linguagemRealcada == linguagem) {
      return _pedacosRealcados;
    }

    _textoRealcado = text;
    _linguagemRealcada = linguagem;
    _pedacosRealcados = realcarCodigo(text, linguagem);
    _realceCalculado = true;
    return _pedacosRealcados;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final pedacos = CodigoEditavel.eTerminal(linguagem)
        ? null
        : _pedacos();
    return pedacos == null
        ? TextSpan(text: text, style: style)
        : TextSpan(style: style, children: pedacos);
  }
}

/// Aspas de codigo sempre retas, mesmo num teclado com teclas mortas.
///
/// No layout "US internacional" a aspa espera a tecla seguinte para virar
/// acento: `"` e `a` dao `ä`, e `"` duas vezes da `¨`. Num texto em portugues
/// isso e o que se quer; dentro de codigo nunca e — nenhuma linguagem aceita
/// `¨` no lugar de `"`, e `print(äbc")` so aparece por acidente. O `á` do `'`
/// fica: ele e letra de verdade em "número", dentro de um texto entre aspas.
///
/// So no que acabou de ser digitado. Texto colado passa como veio: quem colou
/// um `ü` de proposito nao pode ve-lo trocado.
class AspasDeCodigo extends TextInputFormatter {
  const AspasDeCodigo();

  static const _trocas = {
    '¨': '"',
    '´': "'",
    'ä': '"a',
    'ë': '"e',
    'ï': '"i',
    'ö': '"o',
    'ü': '"u',
    'Ä': '"A',
    'Ë': '"E',
    'Ï': '"I',
    'Ö': '"O',
    'Ü': '"U',
  };

  /// Uma tecla escreve no maximo dois caracteres — a tecla morta pendente e a
  /// seguinte. Mais que isso e colagem.
  static const _digitado = 2;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue antes,
    TextEditingValue depois,
  ) {
    // Enquanto a tecla morta esta pendente o sistema ainda esta compondo; mexer
    // agora desencontraria o texto do que o teclado acha que escreveu.
    if (depois.composing.isValid && !depois.composing.isCollapsed) {
      return depois;
    }

    final velho = antes.text;
    final novo = depois.text;
    if (novo.length <= velho.length) return depois;

    var inicio = 0;
    final limite = velho.length;
    while (inicio < limite && velho[inicio] == novo[inicio]) {
      inicio++;
    }
    var fimNoNovo = novo.length;
    var fimNoVelho = velho.length;
    while (fimNoVelho > inicio &&
        fimNoNovo > inicio &&
        velho[fimNoVelho - 1] == novo[fimNoNovo - 1]) {
      fimNoVelho--;
      fimNoNovo--;
    }

    final entrou = novo.substring(inicio, fimNoNovo);
    if (entrou.isEmpty || entrou.length > _digitado) return depois;

    final trocado = entrou.split('').map((c) => _trocas[c] ?? c).join();
    if (trocado == entrou) return depois;

    final delta = trocado.length - entrou.length;
    int andar(int offset) => offset >= fimNoNovo ? offset + delta : offset;

    return TextEditingValue(
      text: novo.replaceRange(inicio, fimNoNovo, trocado),
      selection: depois.selection.copyWith(
        baseOffset: andar(depois.selection.baseOffset),
        extentOffset: andar(depois.selection.extentOffset),
      ),
    );
  }
}
