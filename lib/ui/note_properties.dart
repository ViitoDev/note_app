import 'package:flutter/material.dart';

import '../models/kanban_card.dart';
import 'app_theme.dart';

/// Ficha de propriedades da nota, no topo do preview.
///
/// Os campos aparecem todos, sempre, preenchidos ou nao — e a lista deles que
/// ensina o que uma nota pode virar neste app. Clicar num campo abre a escolha
/// certa para ele: os tipos de nota, um calendario, os horarios, as colunas do
/// quadro, o campo de tags.
///
/// Campo vazio nao conta: enquanto ninguem escolher nada, ele nao existe no
/// `.md`. E so no primeiro clique que a linha entra no frontmatter, e limpar o
/// campo a tira de volta. Assim a ficha pode ser completa sem encher os
/// arquivos de `data:` e `status:` vazios, que o calendario e o quadro teriam
/// de aprender a ignorar.
///
/// Os campos oferecidos sao exatamente os que o app le em algum lugar —
/// `tipo: evento` vira compromisso, `status:` vira card, `tags:` viram o grafo.
/// Nenhuma convençao nova nasce aqui.
class NoteProperties extends StatefulWidget {
  const NoteProperties({
    super.key,
    required this.frontmatter,
    required this.onCampo,
  });

  final Map<String, dynamic> frontmatter;

  /// Grava `campo: valor` no frontmatter da nota. Valor nulo apaga o campo.
  final void Function(String campo, String? valor) onCampo;

  @override
  State<NoteProperties> createState() => _NotePropertiesState();
}

class _NotePropertiesState extends State<NoteProperties> {
  /// Campos que a ficha desenha por conta propria. Qualquer outra chave do
  /// frontmatter e mostrada depois, como veio do arquivo.
  static const _proprios = {'tipo', 'data', 'hora', 'status', 'tags'};

  /// O campo de digitar tag so existe depois do `+`: uma caixa de texto aberta
  /// em toda nota poria um cursor piscando em cima da leitura.
  bool _adicionandoTag = false;
  final _novaTag = TextEditingController();

  @override
  void dispose() {
    _novaTag.dispose();
    super.dispose();
  }

  String? _texto(String campo) {
    final bruto = widget.frontmatter[campo];
    if (bruto == null) return null;
    final texto = bruto is DateTime ? _iso(bruto) : '$bruto'.trim();
    return texto.isEmpty ? null : texto;
  }

  /// As tags da nota, sempre numa lista que se pode mexer: quem chama aqui e
  /// para acrescentar ou tirar uma, e uma lista constante estouraria na hora.
  List<String> get _tags {
    final bruto = widget.frontmatter['tags'];
    if (bruto is List) {
      return [
        for (final t in bruto)
          if (t.toString().trim().isNotEmpty) t.toString().trim(),
      ];
    }
    if (bruto is String) {
      return [
        for (final t in bruto.split(RegExp(r'[,\s]+')))
          if (t.trim().isNotEmpty) t.trim(),
      ];
    }
    return [];
  }

  void _gravarTags(List<String> tags) =>
      widget.onCampo('tags', tags.isEmpty ? null : '[${tags.join(', ')}]');

  void _confirmarTag() {
    final digitado = _novaTag.text;
    _novaTag.clear();
    setState(() => _adicionandoTag = false);

    final tags = _tags;
    var mudou = false;
    // Aceita `estudos, ufms` de uma vez: quem esta marcando a nota pensa nas
    // tags juntas, nao uma abertura de campo por vez.
    for (final bruta in digitado.split(RegExp(r'[,\s]+'))) {
      final tag = bruta.trim().replaceFirst(RegExp('^#+'), '');
      if (tag.isEmpty) continue;
      if (tags.any((t) => t.toLowerCase() == tag.toLowerCase())) continue;
      tags.add(tag);
      mudou = true;
    }

    if (mudou) _gravarTags(tags);
  }

  Future<void> _escolherData() async {
    final escolhida = await showDialog<DateTime>(
      context: context,
      builder: (_) => _DialogoDeData(atual: _dataAtual),
    );
    if (escolhida != null) widget.onCampo('data', _iso(escolhida));
  }

  Future<void> _escolherHora() async {
    final escolhida = await showDialog<String>(
      context: context,
      builder: (_) => _DialogoDeHora(atual: _texto('hora')),
    );
    if (escolhida != null) widget.onCampo('hora', escolhida);
  }

  DateTime? get _dataAtual {
    final texto = _texto('data');
    if (texto == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(texto);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extras = widget.frontmatter.keys
        .where((k) => !_proprios.contains(k))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _linha(theme, 'tipo', _tipo(theme)),
        _linha(theme, 'data', _data(theme)),
        _linha(theme, 'hora', _hora(theme)),
        _linha(theme, 'status', _status(theme)),
        _linha(theme, 'tags', _etiquetas(theme)),
        // O que o usuario escreveu a mao continua a vista. A ficha nao e dona
        // do frontmatter: ela mostra os campos que sabe editar e nao esconde os
        // outros.
        for (final chave in extras)
          _linha(
            theme,
            chave,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                _porExtensoSePuder('${widget.frontmatter[chave]}'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        const SizedBox(height: AppTheme.gapLg),
        // Regua fina em vez de moldura: separa a ficha do texto sem fechar um
        // quadro em volta dela.
        Divider(height: 1, color: theme.colorScheme.outline),
      ],
    );
  }

  /// Uma linha da ficha: rotulo de largura fixa a esquerda, valor a direita.
  ///
  /// A largura fixa e o que alinha todos os valores numa coluna so — sem ela
  /// cada linha começaria num ponto diferente.
  Widget _linha(ThemeData theme, String chave, Widget valor) {
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 124,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, left: 6),
              child: Row(
                children: [
                  Icon(
                    _icone(chave),
                    size: 13,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: AppTheme.gapSm),
                  Expanded(
                    child: Text(
                      _titulo(chave),
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: valor),
        ],
      ),
    );
  }

  Widget _tipo(ThemeData theme) {
    final atual = _texto('tipo');
    return _Slot(
      onLimpar: atual == null ? null : () => widget.onCampo('tipo', null),
      child: _Menu(
        // So os tipos que mudam alguma coisa no app. Inventar uma lista maior
        // seria prometer comportamento que nao existe.
        opcoes: [
          for (final t in _tiposDeNota) (valor: t.$1, rotulo: t.$2),
          // Um tipo escrito a mao no arquivo aparece na lista para nao sumir da
          // vista de quem o escreveu.
          if (atual != null && !_tiposDeNota.any((t) => t.$1 == atual))
            (valor: atual, rotulo: atual),
        ],
        atual: atual,
        vazio: 'definir',
        rotulo: (v) => _tiposDeNota
            .firstWhere((t) => t.$1 == v, orElse: () => (v, v))
            .$2,
        onEscolher: (v) => widget.onCampo('tipo', v),
      ),
    );
  }

  Widget _status(ThemeData theme) {
    final atual = _texto('status');
    final coluna = KanbanColumn.porValor(atual);
    return _Slot(
      onLimpar: atual == null ? null : () => widget.onCampo('status', null),
      child: _Menu(
        // As colunas do quadro, na ordem em que estao la. Escolher aqui e o
        // mesmo que arrastar o card ali.
        opcoes: [
          for (final c in KanbanColumn.values) (valor: c.valor, rotulo: c.label),
          if (atual != null && coluna == null) (valor: atual, rotulo: atual),
        ],
        atual: coluna?.valor ?? atual,
        vazio: 'definir',
        rotulo: (v) => KanbanColumn.porValor(v)?.label ?? v,
        onEscolher: (v) => widget.onCampo('status', v),
      ),
    );
  }

  Widget _data(ThemeData theme) {
    final data = _dataAtual;
    final atual = _texto('data');
    return _Slot(
      onLimpar: atual == null ? null : () => widget.onCampo('data', null),
      child: _Alvo(
        onTap: _escolherData,
        texto: data != null ? _porExtenso(data) : atual,
        vazio: 'definir',
      ),
    );
  }

  Widget _hora(ThemeData theme) {
    final atual = _texto('hora');
    return _Slot(
      onLimpar: atual == null ? null : () => widget.onCampo('hora', null),
      child: _Alvo(onTap: _escolherHora, texto: atual, vazio: 'definir'),
    );
  }

  Widget _etiquetas(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 6, bottom: 4),
      child: Wrap(
        spacing: AppTheme.gapXs,
        runSpacing: AppTheme.gapXs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in _tags)
            _Etiqueta(
              tag: tag,
              onRemover: () => _gravarTags(_tags..remove(tag)),
            ),
          if (_adicionandoTag)
            _CampoDeTag(controller: _novaTag, onPronto: _confirmarTag)
          else
            _BotaoDeTag(onTap: () => setState(() => _adicionandoTag = true)),
        ],
      ),
    );
  }

  /// `criado_em` vira `Criado em`. O nome cru continua do outro lado da tela,
  /// no editor; aqui o que se quer e ler.
  static String _titulo(String chave) {
    final texto = chave.replaceAll('_', ' ').trim();
    if (texto.isEmpty) return chave;
    return texto[0].toUpperCase() + texto.substring(1);
  }

  static IconData _icone(String chave) => switch (chave) {
    'tipo' => Icons.category_outlined,
    'data' => Icons.event_outlined,
    'hora' => Icons.schedule,
    'status' => Icons.flag_outlined,
    'tags' => Icons.local_offer_outlined,
    'autor' => Icons.person_outline,
    'fonte' || 'link' || 'url' => Icons.link,
    _ when chave.startsWith('criado') => Icons.event_available_outlined,
    _ when chave.startsWith('atualizado') || chave.startsWith('modificado') =>
      Icons.update,
    _ => Icons.label_outline,
  };

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static final _dataIso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Data ISO vira data por extenso; qualquer outra coisa sai como esta.
  static String _porExtensoSePuder(String texto) {
    final m = _dataIso.firstMatch(texto.trim());
    if (m == null) return texto;
    return _porExtenso(
      DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      ),
    );
  }

  static String _porExtenso(DateTime d) =>
      '${d.day} de ${meses[d.month - 1]} de ${d.year}';
}

/// Os tipos que mudam o comportamento do app.
const _tiposDeNota = [
  ('nota', 'Nota'),
  ('evento', 'Evento — entra no calendario'),
];

const meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// A area de valor de uma linha: o que se clica, mais o `x` de limpar.
///
/// O `x` so aparece com o ponteiro em cima, e so quando ha o que limpar. Um
/// botao de apagar fixo em cada campo encheria a ficha de ruido justamente
/// onde se quer bater o olho e ler.
class _Slot extends StatefulWidget {
  const _Slot({required this.child, this.onLimpar});

  final Widget child;
  final VoidCallback? onLimpar;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _sobRato = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _sobRato = true),
      onExit: (_) => setState(() => _sobRato = false),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: widget.child),
            if (widget.onLimpar != null)
              AnimatedOpacity(
                opacity: _sobRato ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 13),
                  tooltip: 'Limpar',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 22,
                    height: 22,
                  ),
                  color: scheme.onSurfaceVariant,
                  onPressed: _sobRato ? widget.onLimpar : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// O valor clicavel de um campo.
///
/// Vazio, mostra o convite apagado; preenchido, mostra o valor. O realce ao
/// passar o mouse e o que diz que aquilo se clica — sem ele a ficha pareceria
/// so uma tabela impressa.
class _Alvo extends StatefulWidget {
  const _Alvo({required this.texto, required this.vazio, this.onTap});

  final String? texto;
  final String vazio;
  final VoidCallback? onTap;

  @override
  State<_Alvo> createState() => _AlvoState();
}

class _AlvoState extends State<_Alvo> {
  bool _sobRato = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preenchido = widget.texto != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _sobRato = true),
      onExit: (_) => setState(() => _sobRato = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: _sobRato ? scheme.surfaceContainerHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Text(
            widget.texto ?? widget.vazio,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: preenchido
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Campo de escolha unica, aberto num menu debaixo do valor.
class _Menu extends StatelessWidget {
  const _Menu({
    required this.opcoes,
    required this.atual,
    required this.vazio,
    required this.rotulo,
    required this.onEscolher,
  });

  final List<({String valor, String rotulo})> opcoes;
  final String? atual;
  final String vazio;
  final String Function(String) rotulo;
  final ValueChanged<String> onEscolher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      tooltip: '',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: onEscolher,
      itemBuilder: (context) => [
        for (final opcao in opcoes)
          PopupMenuItem(
            value: opcao.valor,
            height: 38,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 14,
                  color: opcao.valor == atual
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
                const SizedBox(width: AppTheme.gapSm),
                Expanded(
                  child: Text(opcao.rotulo, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
      child: _Alvo(
        texto: atual == null ? null : rotulo(atual!),
        vazio: vazio,
      ),
    );
  }
}

/// Uma tag da nota.
class _Etiqueta extends StatefulWidget {
  const _Etiqueta({required this.tag, required this.onRemover});

  final String tag;
  final VoidCallback onRemover;

  @override
  State<_Etiqueta> createState() => _EtiquetaState();
}

class _EtiquetaState extends State<_Etiqueta> {
  bool _sobRato = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _sobRato = true),
      onExit: (_) => setState(() => _sobRato = false),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppTheme.gapSm, 3, 5, 3),
        decoration: BoxDecoration(
          // O mesmo rosa dos nos de tag no grafo: reconhecer uma tag aqui
          // ensina a reconhece-la la.
          color: AppTheme.tag.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#${widget.tag}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppTheme.tag,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Some por opacidade, e nao por remoçao: a etiqueta teria dois
            // tamanhos e pularia debaixo do ponteiro.
            AnimatedOpacity(
              opacity: _sobRato ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onRemover,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.close, size: 12, color: AppTheme.tag),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convite discreto para marcar a nota, no fim da fila de etiquetas.
class _BotaoDeTag extends StatelessWidget {
  const _BotaoDeTag({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Marcar a nota com uma tag',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: scheme.outline),
            ),
            child: Icon(Icons.add, size: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Campo de digitar a tag nova, do tamanho de uma etiqueta.
class _CampoDeTag extends StatelessWidget {
  const _CampoDeTag({required this.controller, required this.onPronto});

  final TextEditingController controller;
  final VoidCallback onPronto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 156,
      child: TextField(
        controller: controller,
        autofocus: true,
        style: theme.textTheme.labelMedium,
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'estudos, ufms',
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        ),
        onSubmitted: (_) => onPronto(),
        // Clicar em qualquer outro lugar fecha o campo: quem saiu dele ja
        // terminou, e um campo aberto e esquecido fica pedindo atençao.
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          onPronto();
        },
      ),
    );
  }
}

/// Calendario compacto para escolher a data do campo `data:`.
///
/// Escrito aqui em vez de chamar o `showDatePicker`: o do Material vem em
/// ingles enquanto o app nao carrega pacote de localizaçao, e abre um dialogo
/// grande demais para um campo de uma linha.
class _DialogoDeData extends StatefulWidget {
  const _DialogoDeData({required this.atual});

  final DateTime? atual;

  @override
  State<_DialogoDeData> createState() => _DialogoDeDataState();
}

class _DialogoDeDataState extends State<_DialogoDeData> {
  static const _diasDaSemana = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

  late DateTime _mes;

  @override
  void initState() {
    super.initState();
    final base = widget.atual ?? DateTime.now();
    _mes = DateTime(base.year, base.month);
  }

  DateTime get _hoje {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month, agora.day);
  }

  void _andar(int meses) =>
      setState(() => _mes = DateTime(_mes.year, _mes.month + meses));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: SizedBox(
        width: 312,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    tooltip: 'Mes anterior',
                    onPressed: () => _andar(-1),
                  ),
                  Expanded(
                    child: Text(
                      '${meses[_mes.month - 1]} de ${_mes.year}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    tooltip: 'Proximo mes',
                    onPressed: () => _andar(1),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.gapSm),
              Row(
                children: [
                  for (final dia in _diasDaSemana)
                    Expanded(
                      child: Text(
                        dia,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppTheme.gapXs),
              ..._semanas(theme),
              const SizedBox(height: AppTheme.gapSm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, _hoje),
                  child: const Text('Hoje'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _semanas(ThemeData theme) {
    // Domingo na primeira coluna, como no calendario do app.
    final primeiro = DateTime(_mes.year, _mes.month);
    final vazias = primeiro.weekday % 7;
    final dias = DateTime(_mes.year, _mes.month + 1, 0).day;
    final celulas = vazias + dias;

    return [
      for (var linha = 0; linha * 7 < celulas; linha++)
        Row(
          children: [
            for (var coluna = 0; coluna < 7; coluna++)
              Expanded(child: _celula(theme, linha * 7 + coluna - vazias + 1)),
          ],
        ),
    ];
  }

  Widget _celula(ThemeData theme, int dia) {
    final dias = DateTime(_mes.year, _mes.month + 1, 0).day;
    if (dia < 1 || dia > dias) return const SizedBox(height: 34);

    final scheme = theme.colorScheme;
    final data = DateTime(_mes.year, _mes.month, dia);
    final escolhida = data == widget.atual;
    final hoje = data == _hoje;

    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: escolhida ? scheme.primaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            // O dia de hoje se marca por contorno, nao por preenchimento: o
            // preenchimento e da escolha, e os dois nao podem se confundir.
            side: hoje && !escolhida
                ? BorderSide(color: scheme.primary.withValues(alpha: 0.5))
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            onTap: () => Navigator.pop(context, data),
            child: Center(
              child: Text(
                '$dia',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: escolhida || hoje
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.85),
                  fontWeight: escolhida ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horarios de meia em meia hora, mais um campo para o que nao esta na lista.
class _DialogoDeHora extends StatefulWidget {
  const _DialogoDeHora({required this.atual});

  final String? atual;

  @override
  State<_DialogoDeHora> createState() => _DialogoDeHoraState();
}

class _DialogoDeHoraState extends State<_DialogoDeHora> {
  static const _alturaDoItem = 36.0;

  late final TextEditingController _digitado = TextEditingController(
    text: widget.atual ?? '',
  );

  late final ScrollController _rolagem = ScrollController(
    // Abre perto do horario da nota, ou perto da manha — comecar a lista a
    // meia-noite obrigaria a rolar toda vez.
    initialScrollOffset: _minutos(widget.atual ?? '08:00') / 30 * _alturaDoItem,
  );

  @override
  void dispose() {
    _digitado.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  /// Minutos desde a meia-noite, arredondados para baixo na meia hora.
  static int _minutos(String texto) {
    final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?').firstMatch(texto.trim());
    if (m == null) return 8 * 60;
    final h = int.parse(m.group(1)!).clamp(0, 23);
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    return h * 60 + (min >= 30 ? 30 : 0);
  }

  /// Aceita `14`, `14:5`, `1430` e devolve `14:30`. Vazio ou impossivel de ler
  /// devolve nulo, e o dialogo nao grava nada.
  static String? normalizar(String bruto) {
    final texto = bruto.trim();
    if (texto.isEmpty) return null;

    final m = RegExp(r'^(\d{1,2})[:h\s]?(\d{2})?$').firstMatch(texto);
    if (m == null) return null;

    final h = int.parse(m.group(1)!);
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (h > 23 || min > 59) return null;

    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  void _confirmarDigitado() {
    final hora = normalizar(_digitado.text);
    if (hora != null) Navigator.pop(context, hora);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atual = widget.atual == null ? null : normalizar(widget.atual!);

    return Dialog(
      child: SizedBox(
        width: 240,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _digitado,
                autofocus: true,
                style: theme.textTheme.bodyMedium,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '14:30',
                  prefixIcon: Icon(Icons.schedule, size: 16),
                ),
                onSubmitted: (_) => _confirmarDigitado(),
              ),
              const SizedBox(height: AppTheme.gapMd),
              SizedBox(
                height: 232,
                child: ListView.builder(
                  controller: _rolagem,
                  itemExtent: _alturaDoItem,
                  itemCount: 48,
                  itemBuilder: (context, i) {
                    final hora =
                        '${(i ~/ 2).toString().padLeft(2, '0')}:'
                        '${i.isEven ? '00' : '30'}';
                    final escolhida = hora == atual;

                    return Material(
                      color: escolhida
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        onTap: () => Navigator.pop(context, hora),
                        child: Center(
                          child: Text(
                            hora,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: escolhida
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
