import 'package:flutter/material.dart';

import '../models/kanban_card.dart';
import 'app_theme.dart';
import 'resizable_split.dart';

/// Quadro kanban alimentado pelo `status:` do frontmatter das notas.
///
/// Arrastar um card entre colunas reescreve esse campo no arquivo — nao ha
/// estado de quadro em lugar nenhum alem das proprias notas.
class KanbanScreen extends StatelessWidget {
  const KanbanScreen({
    super.key,
    required this.board,
    required this.onMover,
    required this.onOpenNote,
    required this.onRefresh,
    required this.onNovoCard,
  });

  final KanbanBoard board;

  /// Pedido de troca de coluna. A gravaçao fica com quem monta a tela.
  final void Function(KanbanCard card, KanbanColumn destino) onMover;

  final ValueChanged<String> onOpenNote;
  final VoidCallback onRefresh;

  /// Pedido de card novo naquela coluna. Quem monta a tela cria a nota.
  final ValueChanged<KanbanColumn> onNovoCard;

  @override
  Widget build(BuildContext context) {
    if (board.isEmpty) {
      return _Vazio(onRefresh: onRefresh, onNovoCard: onNovoCard);
    }

    return Column(
      children: [
        _barra(context),
        const Divider(height: 1),
        Expanded(
          // Quadro em cima, resumo embaixo, com divisor: as duas partes
          // competem pela altura e quem decide a divisao e o usuario.
          child: ResizableSplit(
            storageKey: 'kanban_resumo',
            axis: Axis.vertical,
            minFirst: 200,
            minSecond: 120,
            initialSecond: 220,
            first: _colunas(context),
            second: _Resumao(board: board, onOpenNote: onOpenNote),
          ),
        ),
      ],
    );
  }

  Widget _barra(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapLg,
        AppTheme.gapSm,
        AppTheme.gapSm,
        AppTheme.gapSm,
      ),
      child: Row(
        children: [
          Text('QUADRO', style: theme.textTheme.labelSmall),
          const SizedBox(width: AppTheme.gapMd),
          Text(
            '${board.total} ${board.total == 1 ? 'card' : 'cards'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Reler o vault',
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }

  Widget _colunas(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Quatro colunas espremidas viram ilegiveis; abaixo da largura minima
        // elas mantem o tamanho e o quadro rola de lado.
        const minima = 190.0;
        final cabe =
            constraints.maxWidth >= minima * KanbanColumn.values.length;

        final colunas = [
          for (final coluna in KanbanColumn.values)
            _Coluna(
              coluna: coluna,
              cards: board.of(coluna),
              onMover: onMover,
              onOpenNote: onOpenNote,
              onNovoCard: onNovoCard,
            ),
        ];

        if (cabe) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final c in colunas) Expanded(child: c)],
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in colunas) SizedBox(width: minima, child: c),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Coluna extends StatefulWidget {
  const _Coluna({
    required this.coluna,
    required this.cards,
    required this.onMover,
    required this.onOpenNote,
    required this.onNovoCard,
  });

  final KanbanColumn coluna;
  final List<KanbanCard> cards;
  final void Function(KanbanCard, KanbanColumn) onMover;
  final ValueChanged<String> onOpenNote;
  final ValueChanged<KanbanColumn> onNovoCard;

  @override
  State<_Coluna> createState() => _ColunaState();
}

class _ColunaState extends State<_Coluna> {
  bool _recebendo = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DragTarget<KanbanCard>(
      // Soltar na coluna de origem nao e movimento nenhum.
      onWillAcceptWithDetails: (d) => d.data.coluna != widget.coluna,
      onMove: (_) {
        if (!_recebendo) setState(() => _recebendo = true);
      },
      onLeave: (_) => setState(() => _recebendo = false),
      onAcceptWithDetails: (d) {
        setState(() => _recebendo = false);
        widget.onMover(d.data, widget.coluna);
      },
      builder: (context, candidatos, _) => Container(
        margin: const EdgeInsets.all(AppTheme.gapSm),
        decoration: BoxDecoration(
          color: _recebendo
              ? scheme.primaryContainer.withValues(alpha: 0.5)
              : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: _recebendo ? scheme.primary : scheme.outline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.gapMd,
                AppTheme.gapMd,
                AppTheme.gapMd,
                AppTheme.gapSm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.coluna.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${widget.cards.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  // Criar o card na propria coluna: sem isto, entrar no quadro
                  // exigia sair dele, criar a nota e escrever o `status:` a
                  // mao — e um quadro em que nao se adiciona cartao e meio
                  // quadro.
                  IconButton(
                    icon: const Icon(Icons.add, size: 16),
                    tooltip: 'Novo card em ${widget.coluna.label}',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    onPressed: () => widget.onNovoCard(widget.coluna),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.cards.isEmpty
                  ? Center(
                      child: Text(
                        'vazia',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.gapSm,
                        0,
                        AppTheme.gapSm,
                        AppTheme.gapSm,
                      ),
                      children: [
                        for (final card in widget.cards)
                          _Card(card: card, onAbrir: widget.onOpenNote),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card, required this.onAbrir});

  final KanbanCard card;
  final ValueChanged<String> onAbrir;

  @override
  Widget build(BuildContext context) {
    final corpo = _corpo(context);

    return Draggable<KanbanCard>(
      data: card,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _Fantasma(card: card),
      childWhenDragging: Opacity(opacity: 0.3, child: corpo),
      child: corpo,
    );
  }

  Widget _corpo(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapSm),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: InkWell(
          onTap: () => onAbrir(card.noteId),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.gapMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.titulo,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (card.resumo.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    card.resumo,
                    style: theme.textTheme.labelSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (card.tags.isNotEmpty || card.prazo != null) ...[
                  const SizedBox(height: AppTheme.gapSm),
                  Wrap(
                    spacing: AppTheme.gapXs,
                    runSpacing: AppTheme.gapXs,
                    children: [
                      if (card.prazo != null)
                        _Etiqueta(texto: _data(card.prazo!), forte: true),
                      for (final tag in card.tags) _Etiqueta(texto: '#$tag'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto, this.forte = false});

  final String texto;
  final bool forte;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: forte ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        texto,
        style: theme.textTheme.labelSmall?.copyWith(
          color: forte ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// O que segue o cursor enquanto o card e arrastado.
class _Fantasma extends StatelessWidget {
  const _Fantasma({required this.card});

  final KanbanCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // O feedback vive num Overlay, fora de qualquer Material da tela.
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapMd,
          vertical: AppTheme.gapSm,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: scheme.primary),
        ),
        child: Text(
          card.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// A lista embaixo do quadro, com todos os cards de uma vez.
///
/// O quadro mostra a distribuiçao; este resumo mostra o conteudo. Sao leituras
/// diferentes da mesma coisa, e por isso ele nao repete o recorte por coluna.
class _Resumao extends StatelessWidget {
  const _Resumao({required this.board, required this.onOpenNote});

  final KanbanBoard board;
  final ValueChanged<String> onOpenNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todos = board.todos;

    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.gapLg,
              AppTheme.gapMd,
              AppTheme.gapLg,
              AppTheme.gapSm,
            ),
            child: Row(
              children: [
                Text('RESUMO', style: theme.textTheme.labelSmall),
                const SizedBox(width: AppTheme.gapMd),
                Expanded(
                  child: Text(
                    _distribuicao(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.gapXs),
              itemCount: todos.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
              itemBuilder: (context, i) => _LinhaResumo(
                card: todos[i],
                onAbrir: () => onOpenNote(todos[i].noteId),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _distribuicao() => [
    for (final coluna in KanbanColumn.values)
      '${board.of(coluna).length} ${coluna.label.toLowerCase()}',
  ].join('  ·  ');
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({required this.card, required this.onAbrir});

  final KanbanCard card;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onAbrir,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapLg,
          vertical: AppTheme.gapSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A coluna vira etiqueta: sem ela o resumo seria uma lista solta,
            // sem dizer em que pe cada card esta.
            SizedBox(width: 116, child: _Etiqueta(texto: card.coluna.label)),
            const SizedBox(width: AppTheme.gapMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.titulo,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (card.resumo.isNotEmpty)
                    Text(
                      card.resumo,
                      style: theme.textTheme.labelSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (card.tags.isNotEmpty) ...[
              const SizedBox(width: AppTheme.gapMd),
              Text(
                card.tags.map((t) => '#$t').join(' '),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _data(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

class _Vazio extends StatelessWidget {
  const _Vazio({required this.onRefresh, required this.onNovoCard});

  final VoidCallback onRefresh;
  final ValueChanged<KanbanColumn> onNovoCard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.view_kanban_outlined,
              size: 34,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.gapMd),
            Text('Nenhum card ainda', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.gapSm),
            Text(
              'Um card e uma nota com `status:` no topo. O botao abaixo cria '
              'a nota ja com o campo preenchido — e escrever `status: '
              'a-fazer` a mao em qualquer nota faz o mesmo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.gapLg),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Criar o primeiro card'),
                  onPressed: () => onNovoCard(KanbanColumn.aFazer),
                ),
                const SizedBox(width: AppTheme.gapMd),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 15),
                  label: const Text('Reler o vault'),
                  onPressed: onRefresh,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
