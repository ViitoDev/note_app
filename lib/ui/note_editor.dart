import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../models/frontmatter_writer.dart';
import '../models/markdown_tasks.dart';
import '../models/note.dart';
import '../models/wikilink.dart';
import 'app_theme.dart';
import 'note_properties.dart';
import 'resizable_split.dart';
import 'wikilink_suggestions.dart';

enum EditorMode { editar, visualizar, dividido }

/// Caixa de tarefa clicavel do preview.
class _CaixaDeTarefa extends StatelessWidget {
  const _CaixaDeTarefa({required this.marcada, required this.onTap});

  final bool marcada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Area de toque maior que o icone: 17px de alvo e pouco para o
          // ponteiro, e a folga cabe entre a caixa e o texto.
          padding: const EdgeInsets.only(right: 6, top: 1, bottom: 1, left: 1),
          child: Icon(
            marcada
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 17,
            color: marcada ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Editor de uma nota: Markdown cru de um lado, preview renderizado do outro.
///
/// O texto editado e o arquivo inteiro, frontmatter incluso — nada e escondido
/// do usuario, coerente com "o `.md` e a fonte da verdade".
class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.note,
    required this.onSave,
    required this.onDirtyChanged,
    this.notasDoVault = const [],
    this.onAbrirLink,
  });

  final Note note;
  final Future<void> Function(String) onSave;
  final ValueChanged<bool> onDirtyChanged;

  /// Chamado ao clicar num `[[link]]` do preview, com o titulo da nota alvo.
  ///
  /// Quem resolve o titulo e quem tem o vault na mao; o editor so avisa que o
  /// link foi tocado. Sem isto o link continua aparecendo, mas nao leva a
  /// lugar nenhum.
  final ValueChanged<String>? onAbrirLink;

  /// Titulos das outras notas do vault, para o autocompletar de `[[`.
  ///
  /// Vem de fora porque o editor nao le o vault: ele conhece uma nota so. Sem
  /// a lista o autocompletar simplesmente nao aparece, e digitar `[[` continua
  /// funcionando na mao.
  final List<String> notasDoVault;

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor> {
  /// O corpo da nota — o texto sem o bloco de frontmatter.
  ///
  /// O editor mostra so isto. O `---` no topo deixou de ser algo que se digita
  /// desde que existe a ficha de propriedades, e mante-lo a vista era pedir que
  /// o usuario editasse o mesmo dado de dois jeitos, um deles a mao e sujeito a
  /// erro de sintaxe.
  late TextEditingController _controller;

  /// O bloco de frontmatter, `---` inclusive, tal como esta no arquivo.
  ///
  /// Fica fora da vista mas nao fora do arquivo: e a ficha que mexe nele, e
  /// tudo que ela nao entende — comentarios, campos proprios, a ordem das
  /// linhas — atravessa daqui de volta para o disco sem uma virgula trocada.
  String _cabecalho = '';

  /// Ultimo conteudo gravado, ja como o arquivo inteiro.
  late String _savedText;

  /// Os dois lados rolam por conta propria, mas voltam juntos ao topo quando a
  /// nota muda — este widget e reaproveitado entre notas, e sem os
  /// controladores a rolagem da nota anterior ficaria valendo para a nova.
  final _editorScroll = ScrollController();
  final _previewScroll = ScrollController();

  /// O foco do campo de texto e proprio para que as setas e o Enter cheguem
  /// aqui antes de virarem movimento de cursor e quebra de linha — sem isso
  /// nao ha como dirigir a lista de sugestoes pelo teclado.
  late final FocusNode _focoDoTexto = FocusNode(onKeyEvent: _teclasDoEditor);

  /// O `[[` que esta sendo escrito agora, se houver.
  WikilinkAberto? _link;
  List<String> _sugestoes = const [];
  int _sugestaoMarcada = 0;

  EditorMode _mode = EditorMode.dividido;
  bool _dirty = false;
  bool _saving = false;

  /// Quanto tempo de silencio o editor espera antes de gravar sozinho.
  ///
  /// Um segundo e a pausa que separa "parei de escrever" de "estou pensando no
  /// meio da frase". Menos que isso grava no meio de cada palavra; mais que
  /// isso deixa texto no ar tempo demais.
  static const _pausa = Duration(seconds: 1);

  /// A gravaçao agendada, ou nulo quando nao ha nada pendente.
  Timer? _agendada;

  @override
  void initState() {
    super.initState();
    _savedText = widget.note.raw;
    _controller = TextEditingController(text: _separar(widget.note.raw))
      ..addListener(_onTextChanged);
    // Os dois lados mostram a mesma nota: rolar um sem o outro obriga a
    // procurar de novo, do outro lado, o trecho que se estava lendo.
    _editorScroll.addListener(_editorRolou);
    _previewScroll.addListener(_previewRolou);
  }

  void _editorRolou() => _acompanhar(_editorScroll, _previewScroll);
  void _previewRolou() => _acompanhar(_previewScroll, _editorScroll);

  /// Verdadeiro enquanto um lado esta sendo movido pelo outro.
  ///
  /// Sem esta trava os dois se empurrariam em circulo, porque mexer num deles
  /// dispara o aviso que move o outro.
  bool _acompanhando = false;

  /// Leva [destino] a mesma altura relativa de [origem].
  ///
  /// A conta e por proporçao, e nao por linha: os dois lados desenham a mesma
  /// nota com alturas diferentes — um titulo ocupa tres vezes mais espaço
  /// renderizado do que em texto cru — e casar linha a linha exigiria medir
  /// cada bloco dos dois lados. A proporçao acerta o trecho; o olho faz o
  /// resto.
  void _acompanhar(ScrollController origem, ScrollController destino) {
    if (_acompanhando) return;
    if (!origem.hasClients || !destino.hasClients) return;

    final limiteDaOrigem = origem.position.maxScrollExtent;
    final limiteDoDestino = destino.position.maxScrollExtent;
    if (limiteDaOrigem <= 0 || limiteDoDestino <= 0) return;

    final alvo =
        (origem.offset / limiteDaOrigem * limiteDoDestino).clamp(
          0.0,
          limiteDoDestino,
        );
    // Um pixel de folga: sem ela, o arredondamento de um lado devolveria o
    // movimento para o outro sem parar.
    if ((destino.offset - alvo).abs() < 1) return;

    _acompanhando = true;
    destino.jumpTo(alvo);
    _acompanhando = false;
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Troca de nota: recarrega o conteudo mantendo o modo de visualizaçao.
    if (oldWidget.note.id != widget.note.id) {
      // A gravaçao agendada era da nota anterior; quem troca de nota ja
      // descarregou o que havia pendente antes de chegar aqui.
      _agendada?.cancel();
      _savedText = widget.note.raw;
      _controller.text = _separar(widget.note.raw);
      _setDirty(false);
      _voltarAoTopo();
    }
  }

  /// Guarda o cabeçalho em [_cabecalho] e devolve o corpo, que e o que se edita.
  ///
  /// O cabeçalho so sai da vista quando o app conseguiu ler o que ha nele.
  /// Frontmatter quebrado — `---` no lugar mas YAML invalido — continua no
  /// editor: escondido, nao haveria por onde conserta-lo, e a ficha nao teria o
  /// que mostrar. Ficaria um pedaço do arquivo sem dono.
  String _separar(String arquivo) {
    final nota = Note.parse(widget.note.id, arquivo, name: widget.note.name);
    if (nota.frontmatter.isEmpty) {
      _cabecalho = '';
      return arquivo;
    }

    _cabecalho = arquivo.substring(0, arquivo.length - nota.body.length);
    return nota.body;
  }

  /// O arquivo inteiro: o que fica no disco e o que o preview le.
  String get _arquivo => _cabecalho + _controller.text;

  /// Leva os dois paines de volta ao inicio da nota.
  ///
  /// Depois do quadro: o conteudo novo acabou de entrar, e um `jumpTo` antes
  /// de ele ser medido cairia num limite de rolagem que ainda e o da nota
  /// anterior.
  void _voltarAoTopo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final scroll in [_editorScroll, _previewScroll]) {
        if (scroll.hasClients) scroll.jumpTo(0);
      }
    });
  }

  @override
  void dispose() {
    _agendada?.cancel();
    _controller
      ..removeListener(_onTextChanged)
      ..dispose();
    _focoDoTexto.dispose();
    _editorScroll
      ..removeListener(_editorRolou)
      ..dispose();
    _previewScroll
      ..removeListener(_previewRolou)
      ..dispose();
    super.dispose();
  }

  /// Marca ou desmarca a tarefa que foi clicada no preview e grava.
  ///
  /// O preview nao guarda estado de tarefa: ele reescreve o `- [ ]` no texto e
  /// passa a mostrar o que o texto diz. Sem isso haveria duas verdades sobre a
  /// mesma caixa — a do arquivo e a da tela.
  void _alternarTarefa(int indice) {
    // A contagem e sempre do corpo, que e justamente o que o editor segura: o
    // frontmatter nao vira caixa no preview, e uma linha dele na conta
    // desalinharia todos os indices.
    final texto = _controller.text;
    final novo = MarkdownTasks.alternar(texto, indice);
    if (novo == texto) return;

    // `[ ]` e `[x]` tem o mesmo tamanho, entao a posiçao do cursor no editor
    // continua valendo; trocar o texto inteiro jogaria o cursor para o começo.
    _controller.value = _controller.value.copyWith(text: novo);
    unawaited(save());
  }

  /// Grava um campo da ficha no frontmatter da nota. Valor nulo apaga o campo.
  ///
  /// A ficha edita o mesmo arquivo que o editor cru — nao ha cadastro nenhum
  /// por tras dela. So a linha do campo e reescrita: o resto do frontmatter
  /// (ordem, comentarios, aspas) fica exatamente como o usuario deixou.
  void _definirCampo(String campo, String? valor) {
    final texto = _arquivo;
    final novo = valor == null
        ? FrontmatterWriter.remover(texto, campo)
        : FrontmatterWriter.definir(texto, campo, valor);
    if (novo == texto) return;

    final corpo = _separar(novo);
    // Mexer num campo nao mexe no corpo, entao o texto do editor costuma sair
    // igual — e reescreve-lo jogaria o cursor de quem estava digitando para o
    // começo da nota. So se toca no controlador quando o corpo mudou de fato.
    if (corpo != _controller.text) _controller.text = corpo;

    setState(() {});
    _onTextChanged();
    unawaited(save());
  }

  void _onTextChanged() {
    _setDirty(_arquivo != _savedText);
    _agendar();
    _atualizarSugestoes();
  }

  /// Reavalia a lista de notas sugeridas a cada tecla e a cada mexida no
  /// cursor — o controlador avisa das duas coisas, e as duas mudam a resposta.
  void _atualizarSugestoes() {
    final selecao = _controller.selection;
    final link = selecao.isValid && selecao.isCollapsed
        ? WikilinkAberto.em(_controller.text, selecao.baseOffset)
        : null;

    final sugestoes = link == null
        ? const <String>[]
        : sugestoesDeNotas(widget.notasDoVault, link.consulta);

    if (link == _link && sugestoes.length == _sugestoes.length) {
      // Mesma consulta e mesma quantidade: nada que valha um quadro novo. Sem
      // esta saida o editor se reconstruiria a cada seta apertada no texto.
      if (link == null || sugestoes.join() == _sugestoes.join()) return;
    }

    setState(() {
      _link = link;
      _sugestoes = sugestoes;
      // A marca volta para o primeiro: depois de digitar mais uma letra, a
      // lista e outra, e manter o indice antigo apontaria para outra nota.
      _sugestaoMarcada = 0;
    });
  }

  void _fecharSugestoes() {
    if (_sugestoes.isEmpty) return;
    setState(() {
      _link = null;
      _sugestoes = const [];
    });
  }

  /// Setas, Enter, Tab e Esc enquanto a lista esta aberta.
  ///
  /// Vem do `FocusNode` do campo, e nao de um `Shortcuts` por cima: assim as
  /// teclas sao vistas antes de o campo de texto mexer o cursor ou quebrar a
  /// linha com elas. Com a lista fechada, tudo passa direto.
  KeyEventResult _teclasDoEditor(FocusNode node, KeyEvent evento) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final tecla = evento.logicalKey;

    if (_sugestoes.isEmpty) {
      // Fora da lista de sugestoes, as duas teclas que a lista de itens usa.
      if (tecla == LogicalKeyboardKey.enter ||
          tecla == LogicalKeyboardKey.numpadEnter) {
        return _continuarLista();
      }
      if (tecla == LogicalKeyboardKey.backspace) return _apagarMarcador();
      return KeyEventResult.ignored;
    }

    final total = _sugestoes.length;

    if (tecla == LogicalKeyboardKey.arrowDown) {
      setState(() => _sugestaoMarcada = (_sugestaoMarcada + 1) % total);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowUp) {
      setState(() => _sugestaoMarcada = (_sugestaoMarcada - 1 + total) % total);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.enter ||
        tecla == LogicalKeyboardKey.tab ||
        tecla == LogicalKeyboardKey.numpadEnter) {
      _inserirLink(_sugestoes[_sugestaoMarcada]);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.escape) {
      _fecharSugestoes();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// O começo de um item de lista: recuo, marcador e, se houver, a caixa de
  /// tarefa. Serve tanto para `- `, `* ` e `+ ` quanto para `1. ` e `1) `.
  static final _marcador = RegExp(
    r'^(\s*)(?:([-*+])|(\d+)([.)]))[ \t]+(\[[ xX]\][ \t]+)?',
  );

  /// A linha que esta sendo escrita, do começo dela ate o cursor.
  ///
  /// Devolve nulo quando nao ha cursor unico — com texto selecionado, as
  /// teclas de lista nao tem o que fazer.
  ({int inicio, String texto})? _linhaAteOCursor() {
    final selecao = _controller.selection;
    if (!selecao.isValid || !selecao.isCollapsed) return null;

    final cursor = selecao.baseOffset;
    if (cursor <= 0) return null;

    final inicio = _controller.text.lastIndexOf('\n', cursor - 1) + 1;
    return (inicio: inicio, texto: _controller.text.substring(inicio, cursor));
  }

  /// Enter dentro de uma lista abre a linha seguinte com o mesmo marcador.
  ///
  /// Num item vazio faz o contrario: apaga o marcador e encerra a lista. Sem
  /// isso, sair de uma lista custaria um backspace a cada vez, e a unica saida
  /// seria apagar o que o Enter acabou de escrever.
  KeyEventResult _continuarLista() {
    final linha = _linhaAteOCursor();
    if (linha == null) return KeyEventResult.ignored;

    final marcador = _marcador.firstMatch(linha.texto);
    if (marcador == null) return KeyEventResult.ignored;

    final cursor = _controller.selection.baseOffset;
    final texto = _controller.text;

    if (linha.texto.substring(marcador.end).trim().isEmpty) {
      _controller.value = TextEditingValue(
        text: texto.replaceRange(linha.inicio, cursor, ''),
        selection: TextSelection.collapsed(offset: linha.inicio),
      );
      return KeyEventResult.handled;
    }

    final recuo = marcador.group(1)!;
    // Lista numerada segue a contagem; a caixa de tarefa volta desmarcada,
    // que e o unico estado em que uma tarefa nova pode nascer.
    final proximo =
        marcador.group(2) ??
        '${int.parse(marcador.group(3)!) + 1}${marcador.group(4)}';
    final tarefa = marcador.group(5) == null ? '' : '[ ] ';

    final novo = '\n$recuo$proximo $tarefa';
    _controller.value = TextEditingValue(
      text: texto.replaceRange(cursor, cursor, novo),
      selection: TextSelection.collapsed(offset: cursor + novo.length),
    );
    return KeyEventResult.handled;
  }

  /// Um backspace logo depois do marcador tira o marcador inteiro.
  ///
  /// So nesse ponto exato — com qualquer coisa ja escrita no item, backspace
  /// volta a ser backspace e apaga uma letra.
  KeyEventResult _apagarMarcador() {
    final linha = _linhaAteOCursor();
    if (linha == null) return KeyEventResult.ignored;

    final marcador = _marcador.firstMatch(linha.texto);
    if (marcador == null || marcador.end != linha.texto.length) {
      return KeyEventResult.ignored;
    }

    // O recuo fica: quem estava num item aninhado continua na altura dele.
    final ate = linha.inicio + marcador.group(1)!.length;
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(
        ate,
        _controller.selection.baseOffset,
        '',
      ),
      selection: TextSelection.collapsed(offset: ate),
    );
    return KeyEventResult.handled;
  }

  /// Troca o `[[` pela metade pelo link inteiro e poe o cursor depois dele.
  void _inserirLink(String titulo) {
    final link = _link;
    final cursor = _controller.selection.baseOffset;
    if (link == null || cursor < 0) return;

    final texto = _controller.text;
    // Um `]]` que ja esteja depois do cursor e reaproveitado, senao completar
    // um link que ja existia deixaria um par de colchetes sobrando.
    final fim = texto.startsWith(']]', cursor) ? cursor + 2 : cursor;

    _controller.value = TextEditingValue(
      text: texto.replaceRange(link.inicio, fim, '[[$titulo]]'),
      selection: TextSelection.collapsed(
        offset: link.inicio + titulo.length + 4,
      ),
    );
  }

  /// Marca a gravaçao para daqui a [_pausa], adiando a que ja estava marcada.
  ///
  /// Adiar e o ponto: cada tecla empurra o prazo para frente, entao a gravaçao
  /// so acontece quando voce para de escrever — e nao a cada letra.
  void _agendar() {
    _agendada?.cancel();
    if (!_dirty) return;
    _agendada = Timer(_pausa, () => unawaited(save()));
  }

  /// Sai do foco: quem clicou em outra coisa terminou de escrever, e esperar a
  /// pausa correr seria segurar o texto sem motivo.
  void _foco(bool temFoco) {
    if (!temFoco && _dirty) unawaited(save());
  }

  void _setDirty(bool value) {
    if (_dirty == value) return;
    setState(() => _dirty = value);
    widget.onDirtyChanged(value);
  }

  bool get isDirty => _dirty;

  /// Grava agora, sem esperar a pausa.
  ///
  /// Continua publico porque `Ctrl+S` existe e porque quem troca de nota
  /// precisa descarregar o que estava pendente antes da troca.
  Future<bool> save() async {
    _agendada?.cancel();
    if (!_dirty) return true;
    if (_saving) {
      // Ja ha uma gravaçao no ar. Reagenda em vez de desistir: o que foi
      // digitado durante ela ficaria sem gravar ate a tecla seguinte.
      _agendar();
      return false;
    }

    final text = _arquivo;
    setState(() => _saving = true);
    try {
      await widget.onSave(text);
      if (!mounted) return true;
      _savedText = text;
      // Digitar durante a gravaçao nao pode ser perdido: o que foi salvo e
      // `text`, e o que estiver no campo alem disso continua pendente.
      _setDirty(_arquivo != text);
      _agendar();
      return true;
    } catch (_) {
      // O chamador apresenta o erro. O editor mantem o conteudo como pendente
      // e nao reagenda: insistir de um em um segundo num disco que esta
      // falhando so repetiria o mesmo aviso. A tecla seguinte tenta de novo.
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final mode = (!wide && _mode == EditorMode.dividido)
        ? EditorMode.editar
        : _mode;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): save,
      },
      child: Focus(
        autofocus: true,
        onFocusChange: _foco,
        child: Column(
          children: [
            _toolbar(theme, wide),
            const Divider(height: 1),
            Expanded(
              // A ficha encabeça os dois paines. Duas copias do mesmo campo na
              // tela nao se desencontram: nenhuma delas guarda estado — ambas
              // leem o frontmatter do arquivo e escrevem por [_definirCampo],
              // entao mexer numa aparece na outra no mesmo quadro.
              child: switch (mode) {
                EditorMode.editar => _comFicha(
                  theme,
                  (altura) => _rawEditor(theme, altura),
                ),
                EditorMode.visualizar => _preview(theme),
                EditorMode.dividido => ResizableSplit(
                  storageKey: 'editor',
                  minFirst: 240,
                  minSecond: 240,
                  first: _comFicha(
                    theme,
                    (altura) => _rawEditor(theme, altura),
                  ),
                  second: _preview(theme),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(ThemeData theme, bool wide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapXl,
        AppTheme.gapMd,
        AppTheme.gapMd,
        AppTheme.gapMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.note.title,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppTheme.gapMd),
                _Estado(salvando: _saving, pendente: _dirty),
              ],
            ),
          ),
          SegmentedButton<EditorMode>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: EditorMode.editar,
                icon: Icon(Icons.edit_outlined, size: 17),
                tooltip: 'Editar',
              ),
              const ButtonSegment(
                value: EditorMode.visualizar,
                icon: Icon(Icons.visibility_outlined, size: 17),
                tooltip: 'Visualizar',
              ),
              if (wide)
                const ButtonSegment(
                  value: EditorMode.dividido,
                  icon: Icon(Icons.vertical_split_outlined, size: 17),
                  tooltip: 'Dividido',
                ),
            ],
            selected: {
              (!wide && _mode == EditorMode.dividido)
                  ? EditorMode.editar
                  : _mode,
            },
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ],
      ),
    );
  }

  /// Recuo do texto dentro do campo. A lista de sugestoes precisa dele para
  /// converter a posiçao do cursor no texto em posiçao na tela.
  static const _recuo = EdgeInsets.fromLTRB(
    AppTheme.gapXl,
    AppTheme.gapLg,
    AppTheme.gapXl,
    AppTheme.gapXl,
  );

  TextStyle _estiloDoTexto(ThemeData theme) => TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: const ['Cascadia Mono', 'monospace'],
    fontSize: 13.5,
    height: 1.7,
    color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
  );

  /// O painel de escrita: a ficha e o texto dentro de uma rolagem so.
  ///
  /// A rolagem e do painel, e nao do campo de texto, para a ficha subir junto
  /// com a nota — parada no topo ela roubaria altura de leitura em toda nota
  /// longa. E o mesmo arranjo do preview, do outro lado.
  Widget _comFicha(ThemeData theme, Widget Function(double) texto) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        controller: _editorScroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_ficha(theme), texto(constraints.maxHeight)],
        ),
      ),
    );
  }

  /// [alturaMinima] mantem o campo ocupando o painel inteiro numa nota curta:
  /// sem isso o clique abaixo da ultima linha cairia no vazio, em vez de por o
  /// cursor no texto.
  Widget _rawEditor(ThemeData theme, double alturaMinima) {
    final campo = TextField(
      controller: _controller,
      focusNode: _focoDoTexto,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      cursorColor: theme.colorScheme.primary,
      cursorWidth: 1.6,
      style: _estiloDoTexto(theme),
      decoration: InputDecoration(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: _recuo,
        hintText: 'Escreva em Markdown...',
        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        // A lista de sugestoes pode passar da borda do campo numa nota curta.
        clipBehavior: Clip.none,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: alturaMinima),
            child: campo,
          ),
          if (_sugestoes.isNotEmpty)
            _sugestoesNoCursor(theme, constraints.maxWidth, alturaMinima),
        ],
      ),
    );
  }

  /// A lista de notas, colada embaixo do cursor.
  ///
  /// Fica dentro da rolagem, junto do texto: presa ao ponto do documento onde
  /// se escreve, ela acompanha a rolagem sem precisar descontar deslocamento
  /// nenhum.
  Widget _sugestoesNoCursor(
    ThemeData theme,
    double largura,
    double alturaMinima,
  ) {
    const larguraDaLista = 300.0;
    final altura = WikilinkSuggestions.alturaPara(_sugestoes.length);

    // Mede o texto do mesmo jeito que o campo mede, para achar onde o cursor
    // caiu. Refazer a conta e mais simples — e mais estavel entre versoes do
    // Flutter — do que ir buscar o `RenderEditable` por dentro.
    final medida = TextPainter(
      text: TextSpan(text: _controller.text, style: _estiloDoTexto(theme)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: largura - _recuo.horizontal);

    final cursor = medida.getOffsetForCaret(
      TextPosition(offset: _controller.selection.baseOffset),
      Rect.zero,
    );

    final topoDaLinha = _recuo.top + cursor.dy;
    final fundo = math.max(alturaMinima, medida.height + _recuo.vertical);

    // Embaixo da linha, e acima dela quando nao cabe: escrevendo no fim de uma
    // nota longa, a lista embaixo cairia fora do que da para rolar.
    var y = topoDaLinha + medida.preferredLineHeight + 2;
    if (y + altura > fundo) y = topoDaLinha - altura - 2;

    return Positioned(
      left: (_recuo.left + cursor.dx).clamp(
        0.0,
        math.max(0.0, largura - larguraDaLista),
      ),
      top: math.max(0.0, y),
      width: larguraDaLista,
      child: WikilinkSuggestions(
        titulos: _sugestoes,
        selecionado: _sugestaoMarcada,
        onEscolher: _inserirLink,
      ),
    );
  }

  /// A ficha de propriedades, com o recuo do texto que ela encabeça.
  Widget _ficha(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapXl,
        AppTheme.gapLg,
        AppTheme.gapXl,
        0,
      ),
      child: NoteProperties(
        // Le do arquivo inteiro, nao do que esta no editor: o frontmatter e
        // justamente a parte que saiu de la.
        frontmatter: Note.parse(
          widget.note.id,
          _arquivo,
          name: widget.note.name,
        ).frontmatter,
        onCampo: _definirCampo,
      ),
    );
  }

  Widget _preview(ThemeData theme) {
    // Reparseia a cada build para o preview acompanhar a digitaçao, em vez de
    // mostrar o estado do arquivo em disco.
    final parsed = Note.parse(
      widget.note.id,
      _arquivo,
      name: widget.note.name,
    );

    // O contador anda na ordem em que o parser desenha as caixas, que e a
    // ordem delas no texto.
    final total = MarkdownTasks.contar(parsed.body);
    var proxima = 0;

    return SingleChildScrollView(
      controller: _previewScroll,
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapXl,
        AppTheme.gapLg,
        AppTheme.gapXl,
        48,
      ),
      // `topCenter`, e nao `Center`: a centralizaçao que interessa aqui e so a
      // horizontal, por causa da medida de linha limitada. Deixar explicito
      // que o texto começa no topo evita que a leitura volte a escorregar para
      // o meio se a faixa ao redor mudar de restriçao.
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // Medida de linha limitada: texto corrido muito largo cansa a
          // leitura, e o vault e feito para ser lido.
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NoteProperties(
                frontmatter: parsed.frontmatter,
                onCampo: _definirCampo,
              ),
              const SizedBox(height: AppTheme.gapLg),
              MarkdownBody(
                // `[[nota]]` vira link comum so na hora de desenhar: no
                // arquivo, e no editor ao lado, os colchetes continuam la.
                data: Wikilink.paraMarkdown(parsed.body),
                selectable: true,
                onTapLink: (_, href, _) {
                  final titulo = href == null ? null : Wikilink.tituloDe(href);
                  if (titulo != null) widget.onAbrirLink?.call(titulo);
                },
                // `gitHubWeb` traz o TaskListSyntax; sem ele as listas de
                // tarefa (`- [ ]` / `- [x]`) viram texto solto.
                extensionSet: md.ExtensionSet.gitHubWeb,
                checkboxBuilder: (checked) {
                  // O MarkdownBody pode se reconstruir sem passar por
                  // `_preview` de novo, e ai o contador continuaria de onde
                  // parou. O resto da divisao realinha ele a cada passada.
                  final indice = total == 0 ? 0 : proxima++ % total;
                  return _CaixaDeTarefa(
                    marcada: checked,
                    onTap: () => _alternarTarefa(indice),
                  );
                },
                styleSheet: _markdownStyle(theme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Estilo do Markdown renderizado: hierarquia clara, blocos delimitados por
  /// borda em vez de preenchimento forte, citaçao marcada por barra lateral.
  MarkdownStyleSheet _markdownStyle(ThemeData theme) {
    final scheme = theme.colorScheme;
    const mono = TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: ['Cascadia Mono', 'monospace'],
      fontSize: 12.5,
      height: 1.6,
    );

    // Titulos e negrito num azul proprio, que nao e o dos links.
    //
    // E o que separa a estrutura do texto corrido numa olhada: os titulos dao
    // o esqueleto da nota, e o negrito marca o que voce mesmo destacou. Usar
    // aqui o indigo do app fazia titulo passar por link — e link e clicavel,
    // titulo nao. Cada azul tem um dono: o indigo e do app, este e do texto.
    const destaque = AppTheme.realce;

    TextStyle? titulo(TextStyle? base, double tamanho) =>
        base?.copyWith(fontSize: tamanho, height: 1.4, color: destaque);

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: titulo(theme.textTheme.titleLarge, 26)?.copyWith(height: 1.3),
      h2: titulo(theme.textTheme.titleLarge, 19),
      h3: titulo(theme.textTheme.titleMedium, 16),
      h4: titulo(theme.textTheme.titleMedium, 14.5),
      h5: titulo(theme.textTheme.titleSmall, 13.5),
      h6: titulo(theme.textTheme.titleSmall, 12.5),
      // `strong` so troca a cor e reforça o peso; o resto da linha continua
      // herdando o estilo de onde o negrito estiver — paragrafo, item de
      // lista, celula de tabela.
      strong: TextStyle(fontWeight: FontWeight.w700, color: destaque),
      h1Padding: const EdgeInsets.only(top: AppTheme.gapSm, bottom: 2),
      h2Padding: const EdgeInsets.only(top: AppTheme.gapXl, bottom: 2),
      h3Padding: const EdgeInsets.only(top: AppTheme.gapLg, bottom: 2),
      h4Padding: const EdgeInsets.only(top: AppTheme.gapLg, bottom: 2),
      h5Padding: const EdgeInsets.only(top: AppTheme.gapMd, bottom: 2),
      h6Padding: const EdgeInsets.only(top: AppTheme.gapMd, bottom: 2),
      p: theme.textTheme.bodyLarge?.copyWith(fontSize: 14.5, height: 1.7),
      pPadding: const EdgeInsets.only(bottom: AppTheme.gapMd),
      listBullet: theme.textTheme.bodyLarge?.copyWith(fontSize: 14.5),
      listBulletPadding: const EdgeInsets.only(right: AppTheme.gapSm),
      a: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary.withValues(alpha: 0.35),
      ),
      code: mono.copyWith(
        color: scheme.primary,
        backgroundColor: scheme.surfaceContainerHigh,
      ),
      codeblockPadding: const EdgeInsets.all(AppTheme.gapLg),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: scheme.outline),
      ),
      blockquote: theme.textTheme.bodyLarge?.copyWith(
        fontSize: 14.5,
        color: scheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(AppTheme.gapLg, 4, 0, 4),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: scheme.primary.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      tableBorder: TableBorder.all(color: scheme.outline, width: 1),
      tableHead: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gapMd,
        vertical: AppTheme.gapSm,
      ),
    );
  }
}

/// Diz em que pe esta a gravaçao, no lugar do antigo botao "Salvar".
///
/// O botao saiu porque nao ha mais nada para clicar: o texto e gravado sozinho
/// quando voce para de escrever. O que restou e a pergunta que o botao
/// respondia sem querer — "ja foi para o disco?" — e e ela que este rotulo
/// responde, sem pedir nada em troca.
class _Estado extends StatelessWidget {
  const _Estado({required this.salvando, required this.pendente});

  final bool salvando;
  final bool pendente;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (String texto, String dica) = salvando
        ? ('Salvando', 'Gravando no arquivo')
        : pendente
        ? ('Nao salvo', 'Grava sozinho quando voce parar de escrever')
        : ('Salvo', 'O arquivo esta em dia — e o Drive sobe sozinho');

    return Tooltip(
      message: dica,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 12,
            child: salvando
                ? const CircularProgressIndicator(strokeWidth: 1.6)
                : Icon(
                    pendente ? Icons.circle : Icons.cloud_done_outlined,
                    size: pendente ? 7 : 12,
                    color: pendente ? scheme.primary : scheme.onSurfaceVariant,
                  ),
          ),
          const SizedBox(width: AppTheme.gapSm),
          Text(texto, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
