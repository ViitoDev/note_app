import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'panel_layout.dart';

/// Faz de [child] a alca de arrasto de um painel.
///
/// A ancora do arrasto e o proprio ponteiro ([pointerDragAnchorStrategy]).
/// Com isso o `offset` que chega nos alvos e a posicao do cursor, e decidir se
/// o painel entra acima ou abaixo do painel de baixo do cursor vira uma
/// comparacao direta — sem descontar o tamanho do fantasma.
class PanelDraggable extends StatelessWidget {
  const PanelDraggable({
    super.key,
    required this.painel,
    required this.onDragChanged,
    required this.child,
  });

  final PanelKind painel;

  /// Recebe o painel enquanto ele esta no ar, e nulo quando o arrasto acaba.
  final ValueChanged<PanelKind?> onDragChanged;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Draggable<PanelKind>(
      data: painel,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => onDragChanged(painel),
      onDragEnd: (_) => onDragChanged(null),
      feedback: _Fantasma(painel: painel),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: child),
    );
  }
}

/// O que segue o cursor durante o arrasto.
class _Fantasma extends StatelessWidget {
  const _Fantasma({required this.painel});

  final PanelKind painel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // O feedback vive num Overlay, fora de qualquer Material da tela: sem este
    // Material o texto sairia com o sublinhado amarelo de "sem tema".
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapMd,
          vertical: AppTheme.gapSm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: scheme.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(painel.icon, size: 15, color: scheme.primary),
            const SizedBox(width: AppTheme.gapSm),
            Text(painel.label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Cabecalho de um painel acoplado: identifica, arrasta e oculta.
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.painel,
    required this.onDragChanged,
    required this.onOcultar,
    this.acoes = const [],
  });

  final PanelKind painel;
  final ValueChanged<PanelKind?> onDragChanged;
  final VoidCallback onOcultar;

  /// Botoes extras do painel, antes do de ocultar.
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PanelDraggable(
      painel: painel,
      onDragChanged: onDragChanged,
      child: Tooltip(
        message: 'Arraste para mover o painel de lugar',
        waitDuration: const Duration(milliseconds: 700),
        // Material, e nao Container colorido: o botao de fechar usa tinta, e
        // uma cor pintada por cima esconderia o realce do toque.
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: Container(
            height: 32,
            padding: const EdgeInsets.only(
              left: AppTheme.gapMd,
              right: AppTheme.gapXs,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
                const SizedBox(width: AppTheme.gapXs),
                Expanded(
                  child: Text(
                    painel.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...acoes,
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  tooltip: 'Fechar o painel ${painel.label}',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 26,
                    height: 26,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: onOcultar,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Um painel ja acoplado, que tambem aceita receber outro painel.
///
/// Soltar na metade de cima insere acima; na de baixo, abaixo. E assim que
/// arrastar o grafo para cima do calendario parte a barra ao meio.
class PanelDropSlot extends StatefulWidget {
  const PanelDropSlot({super.key, required this.child, required this.onSoltar});

  final Widget child;

  /// [antes] indica se o painel largado deve ficar acima deste.
  final void Function(PanelKind painel, {required bool antes}) onSoltar;

  @override
  State<PanelDropSlot> createState() => _PanelDropSlotState();
}

class _PanelDropSlotState extends State<PanelDropSlot> {
  bool _ativo = false;
  bool _antes = true;

  void _atualizar(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final antes = box.globalToLocal(globalPosition).dy < box.size.height / 2;
    if (antes != _antes || !_ativo) {
      setState(() {
        _antes = antes;
        _ativo = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DragTarget<PanelKind>(
      onMove: (d) => _atualizar(d.offset),
      onLeave: (_) => setState(() => _ativo = false),
      onAcceptWithDetails: (d) {
        final antes = _antes;
        setState(() => _ativo = false);
        widget.onSoltar(d.data, antes: antes);
      },
      builder: (context, candidatos, _) => Stack(
        // Passthrough para o painel continuar sendo dimensionado pelas
        // restricoes da barra: um Stack comum encolheria a fatia.
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_ativo && candidatos.isNotEmpty)
            Positioned(
              top: _antes ? 0 : null,
              bottom: _antes ? null : 0,
              left: 0,
              right: 0,
              child: Container(height: 3, color: scheme.primary),
            ),
        ],
      ),
    );
  }
}

/// Faixa estreita que aparece durante o arrasto na borda de uma barra vazia
/// ou recolhida, para dar onde soltar quando nao ha painel nenhum ali.
class EmptyDockTarget extends StatelessWidget {
  const EmptyDockTarget({
    super.key,
    required this.side,
    required this.onSoltar,
  });

  final DockSide side;
  final ValueChanged<PanelKind> onSoltar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DragTarget<PanelKind>(
      onAcceptWithDetails: (d) => onSoltar(d.data),
      builder: (context, candidatos, _) {
        final sobre = candidatos.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: sobre ? 132 : 76,
          decoration: BoxDecoration(
            color: sobre
                ? scheme.primaryContainer
                : scheme.surfaceContainerLowest,
            border: Border.all(color: sobre ? scheme.primary : scheme.outline),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.gapSm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    side == DockSide.esquerda
                        ? Icons.first_page
                        : Icons.last_page,
                    size: 18,
                    color: sobre ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppTheme.gapSm),
                  Text(
                    'Soltar\n${side.label}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
