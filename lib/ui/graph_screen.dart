import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/vault_graph.dart';
import 'app_theme.dart';
import 'graph_layout.dart';

/// Visao em grafo do vault: notas e tags como nos, ligacoes como arestas.
///
/// A tela nao le arquivos — recebe o grafo pronto. Ela cuida so da simulacao,
/// do desenho e da interacao.
class GraphScreen extends StatefulWidget {
  const GraphScreen({
    super.key,
    required this.graph,
    required this.onOpenNote,
    required this.onRefresh,
    this.animate = true,
  });

  final VaultGraph graph;
  final ValueChanged<String> onOpenNote;
  final VoidCallback onRefresh;

  /// Desligado no teste: sem ticker, o layout roda de uma vez so.
  final bool animate;

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen>
    with SingleTickerProviderStateMixin {
  late GraphLayout _layout;
  Ticker? _ticker;

  double _scale = 1;
  Offset _pan = Offset.zero;
  bool _enquadrou = false;

  /// Ultimo tamanho medido da area de desenho. Mudou de tamanho, o
  /// enquadramento anterior nao vale mais.
  Size? _ultimoTamanho;

  /// O usuario ja deu zoom ou arrastou o grafo. A partir daí a tela para de
  /// reenquadrar sozinha: refazer o enquadramento por baixo da mao dele seria
  /// pior do que deixar como ele deixou.
  bool _mexeuNaMao = false;

  NodePosition? _arrastando;
  NodePosition? _sobRato;

  /// Filtro de texto: destaca o que combina e apaga o resto.
  String _busca = '';

  /// Vizinhos diretos do no sob o rato, para o realce de contexto.
  Set<String> _vizinhos = const {};

  /// Escapatoria para quem quer ler o vault inteiro de uma vez.
  ///
  /// Desligado, o grafo nomeia so os nos mais ligados — ver
  /// [_GraphPainter._cotaDeNotas]. Ligado, tenta nomear todos, e ainda assim
  /// nenhum rotulo cai por cima do outro: o que nao couber continua a um passe
  /// de mouse de distancia.
  bool _todosOsNomes = false;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(GraphScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.graph, widget.graph)) {
      // Grafo novo, enquadramento novo — inclusive por cima de um zoom antigo,
      // que se referia a um desenho que nao existe mais.
      _enquadrou = false;
      _mexeuNaMao = false;
      _rebuild();
    }
  }

  void _rebuild() {
    _layout = GraphLayout(graph: widget.graph);
    _ticker?.dispose();

    if (!widget.animate) {
      // Sem animacao, roda a simulacao inteira de uma vez.
      for (var i = 0; i < 300 && !_layout.settled; i++) {
        _layout.step();
      }
      return;
    }

    // O ticker para quando o grafo assenta. Deixar ele rodando pediria um
    // quadro novo a cada 16ms para sempre, so para nao desenhar nada.
    _ticker = createTicker((_) {
      if (_layout.settled) {
        _ticker?.stop();
        return;
      }
      setState(_layout.step);
    })..start();
  }

  /// Sacode a simulaçao e religa o ticker se ele ja tiver parado.
  void _reaquecer() {
    _layout.reheat();
    final ticker = _ticker;
    if (ticker != null && !ticker.isActive) ticker.start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// Reenquadra na primeira medida e sempre que o painel muda de tamanho.
  ///
  /// Roda durante o layout, entao o ajuste em si fica para depois do quadro —
  /// mexer no estado no meio de um `build` derruba o framework.
  void _talvezEnquadrar(Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (_enquadrou && size == _ultimoTamanho) return;

    _ultimoTamanho = size;
    if (_enquadrou && _mexeuNaMao) return;

    _enquadrou = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _enquadrar(size));
    });
  }

  /// Ajusta zoom e deslocamento para o grafo caber na area disponivel.
  void _enquadrar(Size size) {
    final b = _layout.bounds();
    if (b.width <= 0 && b.height <= 0) return;

    const margem = 80.0;
    final escalaX = (size.width - margem) / math.max(b.width, 1);
    final escalaY = (size.height - margem) / math.max(b.height, 1);
    _scale = math.min(math.min(escalaX, escalaY), 1.6).clamp(0.15, 1.6);
    _pan = Offset(
      size.width / 2 - b.centerX * _scale,
      size.height / 2 - b.centerY * _scale,
    );
  }

  Offset _paraGrafo(Offset local) =>
      Offset((local.dx - _pan.dx) / _scale, (local.dy - _pan.dy) / _scale);

  void _atualizarVizinhos(NodePosition? node) {
    if (node == null) {
      if (_vizinhos.isNotEmpty) setState(() => _vizinhos = const {});
      return;
    }
    final vizinhos = <String>{node.node.id};
    for (final e in widget.graph.edges) {
      if (e.source == node.node.id) vizinhos.add(e.target);
      if (e.target == node.node.id) vizinhos.add(e.source);
    }
    setState(() => _vizinhos = vizinhos);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.graph.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hub_outlined,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppTheme.gapLg),
              Text('Nada para exibir', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppTheme.gapSm),
              Text(
                'O grafo se monta a partir das tags e dos links internos das '
                'notas. Marque uma nota com #tag ou aponte para outra com '
                '[[nome da nota]].',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // A barra se mede pelo espaço do painel, nao pelo da janela: o grafo
        // tanto ocupa a tela toda quanto vive acoplado numa lateral estreita.
        LayoutBuilder(
          builder: (context, c) => _barra(theme, compacta: c.maxWidth < 620),
        ),
        const Divider(height: 1),
        Expanded(
          // O CustomPaint nao recorta nada por conta propria: sem este
          // ClipRect os nos que caem fora da area do painel sao desenhados por
          // cima do resto da tela.
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                _talvezEnquadrar(size);
                return _tela(theme, size);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _barra(ThemeData theme, {required bool compacta}) {
    final busca = TextField(
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(Icons.search, size: 16),
        hintText: 'Filtrar notas e tags',
      ),
      style: theme.textTheme.bodyMedium,
      onChanged: (v) => setState(() => _busca = v.trim().toLowerCase()),
    );

    // Wrap, e nao Row: num painel estreito as contagens quebram para a linha
    // de baixo em vez de estourar a largura.
    final contagens = Wrap(
      spacing: AppTheme.gapMd,
      runSpacing: AppTheme.gapXs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _Legenda(
          cor: theme.colorScheme.primary,
          texto: '${widget.graph.notas.length} notas',
        ),
        _Legenda(
          cor: _corTag(theme),
          texto: '${widget.graph.tags.length} tags',
        ),
        Text(
          '${widget.graph.edges.length} ligaçoes',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );

    // Num painel estreito nao cabem o campo e as contagens lado a lado: eles
    // passam a ocupar duas linhas em vez de o campo encolher ate a inutilidade.
    if (compacta) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.gapMd,
          AppTheme.gapSm,
          AppTheme.gapXs,
          AppTheme.gapSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: busca),
                _acoes(),
              ],
            ),
            const SizedBox(height: AppTheme.gapSm),
            contagens,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapXl,
        AppTheme.gapMd,
        AppTheme.gapMd,
        AppTheme.gapMd,
      ),
      child: Row(
        children: [
          SizedBox(width: 260, child: busca),
          const SizedBox(width: AppTheme.gapLg),
          Flexible(child: contagens),
          const Spacer(),
          _acoes(),
        ],
      ),
    );
  }

  Widget _acoes() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _todosOsNomes
                ? Icons.label_outline
                : Icons.label_off_outlined,
            size: 17,
          ),
          tooltip: _todosOsNomes
              ? 'Mostrando todos os nomes'
              : 'Mostrando so os nomes principais',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() => _todosOsNomes = !_todosOsNomes),
        ),
        IconButton(
          icon: const Icon(Icons.center_focus_strong_outlined, size: 17),
          tooltip: 'Enquadrar o grafo',
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() {
            _enquadrou = false;
            _mexeuNaMao = false;
          }),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 17),
          tooltip: 'Reler o vault',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onRefresh,
        ),
      ],
    );
  }

  Widget _tela(ThemeData theme, Size size) {
    return MouseRegion(
      cursor: _sobRato != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onHover: (e) {
        final p = _paraGrafo(e.localPosition);
        final node = _layout.nodeAt(p.dx, p.dy, 18 / _scale);
        if (node != _sobRato) {
          setState(() => _sobRato = node);
          _atualizarVizinhos(node);
        }
      },
      onExit: (_) {
        setState(() => _sobRato = null);
        _atualizarVizinhos(null);
      },
      child: Listener(
        // Roda do mouse dá zoom em torno do ponteiro, como em qualquer mapa.
        onPointerSignal: (signal) {
          if (signal is! PointerScrollEvent) return;
          final antes = _paraGrafo(signal.localPosition);
          final novo = (_scale * (signal.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(
            0.1,
            4.0,
          );
          setState(() {
            _mexeuNaMao = true;
            _scale = novo;
            final depois = _paraGrafo(signal.localPosition);
            _pan += Offset(
              (depois.dx - antes.dx) * _scale,
              (depois.dy - antes.dy) * _scale,
            );
          });
        },
        child: GestureDetector(
          onTapUp: (d) {
            final p = _paraGrafo(d.localPosition);
            final node = _layout.nodeAt(p.dx, p.dy, 18 / _scale);
            final noteId = node?.node.noteId;
            if (noteId != null) widget.onOpenNote(noteId);
          },
          onPanStart: (d) {
            final p = _paraGrafo(d.localPosition);
            _arrastando = _layout.nodeAt(p.dx, p.dy, 18 / _scale);
            _arrastando?.pinned = true;
          },
          onPanUpdate: (d) {
            setState(() {
              final node = _arrastando;
              if (node == null) {
                // Sem no sob o cursor, o arrasto move o grafo inteiro.
                _mexeuNaMao = true;
                _pan += d.delta;
              } else {
                node.x += d.delta.dx / _scale;
                node.y += d.delta.dy / _scale;
              }
            });
          },
          onPanEnd: (_) {
            _arrastando?.pinned = false;
            _arrastando = null;
            // Reaquece para o grafo reacomodar em volta do no solto.
            _reaquecer();
          },
          child: CustomPaint(
            size: size,
            painter: _GraphPainter(
              layout: _layout,
              graph: widget.graph,
              scale: _scale,
              pan: _pan,
              busca: _busca,
              destacados: _vizinhos,
              foco: _sobRato?.node.id,
              todosOsNomes: _todosOsNomes,
              corNota: theme.colorScheme.primary,
              corTag: _corTag(theme),
              corAresta: theme.colorScheme.outline,
              corTexto: theme.colorScheme.onSurface,
              corTextoFraco: theme.colorScheme.onSurfaceVariant,
              corFundo: theme.colorScheme.surfaceContainerLowest,
              maiorGrau: widget.graph.maiorGrau,
            ),
          ),
        ),
      ),
    );
  }

  /// Tags recebem cor propria para o olho separar os dois tipos de no sem
  /// precisar ler os rotulos.
  static Color _corTag(ThemeData theme) => AppTheme.tag;
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.cor, required this.texto});

  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(texto, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.layout,
    required this.graph,
    required this.scale,
    required this.pan,
    required this.busca,
    required this.destacados,
    required this.foco,
    required this.todosOsNomes,
    required this.corNota,
    required this.corTag,
    required this.corAresta,
    required this.corTexto,
    required this.corTextoFraco,
    required this.corFundo,
    required this.maiorGrau,
  });

  final GraphLayout layout;
  final VaultGraph graph;
  final double scale;
  final Offset pan;
  final String busca;
  final Set<String> destacados;

  /// No sob o rato, se houver. Ele nunca perde o rotulo.
  final String? foco;

  final bool todosOsNomes;
  final Color corNota;
  final Color corTag;
  final Color corAresta;
  final Color corTexto;
  final Color corTextoFraco;
  final Color corFundo;
  final int maiorGrau;

  /// Piso de peso a partir do qual o rotulo e considerado pedido pelo usuario
  /// — passar o mouse, ou digitar na busca — e escapa de qualquer cota.
  static const _pedido = 400.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(scale);
    _arestas(canvas);
    _nos(canvas);
    canvas.restore();

    // Os nomes sao desenhados fora da transformaçao, em pixels de tela. E o
    // que permite medir a caixa de cada um e descartar quem cairia por cima de
    // outro — a fonte de quase toda a poluiçao que o grafo tinha.
    _nomes(canvas, size);
  }

  void _arestas(Canvas canvas) {
    final paint = Paint()
      ..strokeWidth = 1 / scale
      ..style = PaintingStyle.stroke;

    for (final edge in graph.edges) {
      final a = layout.positions[edge.source];
      final b = layout.positions[edge.target];
      if (a == null || b == null) continue;

      final relevante =
          destacados.isEmpty ||
          (destacados.contains(edge.source) &&
              destacados.contains(edge.target));
      paint.color = corAresta.withValues(alpha: relevante ? 0.55 : 0.12);
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }
  }

  void _nos(Canvas canvas) {
    for (final p in layout.all) {
      final base = p.node.kind == GraphNodeKind.tag ? corTag : corNota;
      final raio = _raio(p);
      final opacidade = _opacidade(p);

      // Anel em volta do no sob o rato: diz qual circulo esta sendo lido sem
      // depender de procurar o rotulo correspondente.
      if (p.node.id == foco) {
        canvas.drawCircle(
          Offset(p.x, p.y),
          raio + 5 / scale,
          Paint()
            ..color = base.withValues(alpha: 0.5)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4 / scale,
        );
      }

      canvas.drawCircle(
        Offset(p.x, p.y),
        raio,
        Paint()..color = base.withValues(alpha: opacidade),
      );
    }
  }

  /// Desenha os nomes na ordem em que o grafo precisa deles, e para quando o
  /// espaço acaba.
  ///
  /// Quem chega primeiro fica com o lugar; quem chegaria por cima e descartado.
  /// Trocar "desenha todos" por "desenha os que cabem" e o que separa um mapa
  /// de uma mancha de texto.
  void _nomes(Canvas canvas, Size size) {
    final candidatos = layout.all.toList()
      ..sort((a, b) => _peso(b).compareTo(_peso(a)));

    // Uma folga alem da borda: um no logo fora da area ainda pode ter o nome
    // entrando nela.
    final area = Offset.zero & size;
    final cota = _cotaDeNotas();
    final ocupados = <Rect>[];
    var extras = 0;

    for (final p in candidatos) {
      final pedido = _peso(p) >= _pedido;

      // Circulo ja apagado pela busca ou pelo realce de vizinhança: o nome
      // seria ruido em cima justamente do que interessa.
      if (_opacidade(p) < 0.3) continue;

      if (!pedido) {
        // Tags sao poucas e dizem do que o vault trata; notas sao muitas e e
        // delas que vem o amontoado.
        if (p.node.kind == GraphNodeKind.tag) {
          if (scale < 0.4) continue;
        } else {
          if (extras >= cota) continue;
        }
      }

      final centro = Offset(p.x * scale + pan.dx, p.y * scale + pan.dy);
      if (!area.inflate(80).contains(centro)) continue;

      final texto = _texto(p, destaque: p.node.id == foco);
      final caixa = Rect.fromLTWH(
        centro.dx - texto.width / 2,
        centro.dy + _raio(p) * scale + 4,
        texto.width,
        texto.height,
      );

      // Margem em volta da caixa: nomes que so se encostam ainda leem como um
      // borrao unico.
      if (ocupados.any((r) => r.overlaps(caixa.inflate(3)))) continue;

      ocupados.add(caixa);
      texto.paint(canvas, caixa.topLeft);
      if (!pedido && p.node.kind == GraphNodeKind.nota) extras++;
    }
  }

  /// Quantos nomes de nota o grafo mostra por conta propria.
  ///
  /// De longe, so os nos mais ligados se nomeiam: sao eles que dao a forma do
  /// vault, e os outros virariam textura. Conforme o zoom entra, o desenho
  /// abre e cabe mais; passado certo ponto o usuario claramente esta lendo uma
  /// regiao, e ai todos os nomes que couberem aparecem.
  int _cotaDeNotas() {
    if (todosOsNomes || scale >= 1.15) return 1 << 20;
    return ((scale - 0.45) * 12).clamp(0, 24).round();
  }

  /// Raio cresce com o grau, mas pela raiz: sem isso um no muito conectado
  /// domina a tela e esconde o resto.
  double _raio(NodePosition p) {
    final proporcao = maiorGrau == 0 ? 0.0 : p.node.degree / maiorGrau;
    return 4.0 + math.sqrt(proporcao) * 11.0;
  }

  double _opacidade(NodePosition p) {
    final combina = busca.isEmpty || _combina(p);
    final emFoco = destacados.isEmpty || destacados.contains(p.node.id);
    return (combina ? 1.0 : 0.15) * (emFoco ? 1.0 : 0.25);
  }

  bool _combina(NodePosition p) => p.node.label.toLowerCase().contains(busca);

  /// Ordem de importancia do nome. O que o usuario apontou vem primeiro, o
  /// resto se ordena pelo quanto o no esta ligado ao vault.
  double _peso(NodePosition p) {
    if (p.node.id == foco) return 1000;
    if (destacados.contains(p.node.id)) return 600;
    if (busca.isNotEmpty && _combina(p)) return _pedido;
    return maiorGrau == 0 ? 0 : p.node.degree * 100 / maiorGrau;
  }

  TextPainter _texto(NodePosition p, {required bool destaque}) {
    final isTag = p.node.kind == GraphNodeKind.tag;
    final cor = destacados.contains(p.node.id) ? corTexto : corTextoFraco;

    return TextPainter(
      text: TextSpan(
        // `#` na frente da tag: o rosa ja separa os dois tipos de no, e o
        // simbolo termina de dizer que aquilo nao e um arquivo.
        text: isTag ? '#${p.node.label}' : p.node.label,
        style: TextStyle(
          color: cor.withValues(alpha: _opacidade(p)),
          // Tamanho em pixels de tela, nao em unidades do grafo: o nome tem o
          // mesmo corpo em qualquer zoom.
          fontSize: 11,
          height: 1.25,
          fontWeight: isTag ? FontWeight.w600 : FontWeight.w400,
          // Um halo da cor do fundo mantem o nome legivel quando ele cai sobre
          // uma aresta ou outro circulo.
          shadows: [Shadow(color: corFundo, blurRadius: 3)],
        ),
      ),
      textAlign: TextAlign.center,
      // Titulo comprido vira uma linha cortada. O nome inteiro esta a um passe
      // de mouse de distancia, e tres linhas empilhadas escondem o grafo que
      // elas deveriam explicar.
      maxLines: destaque ? 2 : 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: destaque ? 190 : 120);
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
