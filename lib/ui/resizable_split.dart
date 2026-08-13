import 'package:flutter/material.dart';

import 'ui_prefs.dart';

/// Dois paineis separados por um divisor que o usuario pode arrastar.
///
/// O tamanho escolhido persiste entre execucoes quando [storageKey] e passado.
class ResizableSplit extends StatefulWidget {
  const ResizableSplit({
    super.key,
    required this.first,
    required this.second,
    this.storageKey,
    this.axis = Axis.horizontal,
    this.minFirst = 180,
    this.minSecond = 260,
    this.initialFirst,
    this.initialSecond,
  });

  final Widget first;
  final Widget second;

  /// Chave de persistencia. Quando nula, o tamanho vale so para esta sessao.
  final String? storageKey;

  /// Horizontal divide em colunas; vertical, em linhas.
  final Axis axis;

  /// Limites em pixels, para nenhum dos lados sumir por completo.
  final double minFirst;
  final double minSecond;

  /// Tamanho inicial do primeiro painel. Se nulo, [initialSecond] dimensiona o
  /// segundo e o primeiro fica com o restante.
  final double? initialFirst;
  final double? initialSecond;

  @override
  State<ResizableSplit> createState() => _ResizableSplitState();
}

class _ResizableSplitState extends State<ResizableSplit> {
  static const _thickness = 9.0;

  double? _firstSize;
  bool _dragging = false;
  bool _hovering = false;

  bool get _horizontal => widget.axis == Axis.horizontal;

  @override
  void initState() {
    super.initState();
    final key = widget.storageKey;
    if (key != null) _firstSize = UiPrefs.readDouble('split.$key');
  }

  double _defaultFirst(double total) {
    if (widget.initialFirst != null) return widget.initialFirst!;
    if (widget.initialSecond != null) {
      return total - _thickness - widget.initialSecond!;
    }
    return (total - _thickness) / 2;
  }

  double _clamp(double value, double total) {
    final maxFirst = total - _thickness - widget.minSecond;
    // Espaco insuficiente para respeitar os dois minimos: divide ao meio em
    // vez de deixar um painel com tamanho negativo.
    if (maxFirst < widget.minFirst) {
      return ((total - _thickness) / 2).clamp(0.0, double.infinity);
    }
    return value.clamp(widget.minFirst, maxFirst);
  }

  void _store(double value) {
    final key = widget.storageKey;
    if (key != null) UiPrefs.writeDouble('split.$key', value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final total = _horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final size = _clamp(_firstSize ?? _defaultFirst(total), total);

        final children = <Widget>[
          SizedBox(
            width: _horizontal ? size : null,
            height: _horizontal ? null : size,
            child: widget.first,
          ),
          _divider(context, total, size),
          Expanded(child: widget.second),
        ];

        // `stretch` e o que faz cada lado ocupar a faixa inteira. Sem ele vale
        // o padrao do Row/Column, que e centralizar no eixo cruzado: um painel
        // que encolhe ate o conteudo — uma lista curta, um preview de nota
        // pequena — nasceria boiando no meio da faixa, em vez de encostado no
        // topo. Quem preenche sozinho, como o campo de texto do editor, nao
        // denuncia o problema, e por isso ele passou tanto tempo escondido.
        return _horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
      },
    );
  }

  Widget _divider(BuildContext context, double total, double size) {
    final scheme = Theme.of(context).colorScheme;
    final active = _dragging || _hovering;

    return MouseRegion(
      cursor: _horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _horizontal ? (_) => _startDrag() : null,
        onHorizontalDragUpdate: _horizontal
            ? (d) => _drag(d.delta.dx, total)
            : null,
        onHorizontalDragEnd: _horizontal ? (_) => _endDrag(size) : null,
        onVerticalDragStart: _horizontal ? null : (_) => _startDrag(),
        onVerticalDragUpdate: _horizontal
            ? null
            : (d) => _drag(d.delta.dy, total),
        onVerticalDragEnd: _horizontal ? null : (_) => _endDrag(size),
        // Duplo clique devolve o tamanho padrao — saida rapida de um arrasto
        // que deixou o painel inutilizavel.
        onDoubleTap: () {
          final restored = _defaultFirst(total);
          setState(() => _firstSize = restored);
          _store(restored);
        },
        child: SizedBox(
          width: _horizontal ? _thickness : null,
          height: _horizontal ? null : _thickness,
          // Alvo de 9px para o mouse, mas so 1px visivel: facil de agarrar sem
          // poluir a interface com uma barra grossa.
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: _horizontal ? (active ? 2 : 1) : double.infinity,
              height: _horizontal ? double.infinity : (active ? 2 : 1),
              color: active ? scheme.primary : scheme.outline,
            ),
          ),
        ),
      ),
    );
  }

  void _startDrag() => setState(() => _dragging = true);

  void _drag(double delta, double total) {
    setState(() {
      _firstSize = _clamp((_firstSize ?? _defaultFirst(total)) + delta, total);
    });
  }

  void _endDrag(double size) {
    setState(() => _dragging = false);
    _store(size);
  }
}
