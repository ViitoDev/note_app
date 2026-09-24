import 'package:flutter/material.dart';

import '../models/quadro_da_nota.dart';
import 'app_theme.dart';
import 'desenho_do_quadro.dart';

/// O quadro do jeito que ele aparece no meio da nota: um cartao do tamanho de
/// um paragrafo, com o desenho inteiro reduzido para caber.
///
/// Nao se desenha aqui de proposito. Uma area de arrastar caixas dentro de uma
/// nota que rola briga com a rolagem — a roda do mouse teria dois significados
/// no mesmo lugar. O cartao serve para *ver* o fluxo enquanto se le a nota; um
/// clique abre a tela cheia, e la se mexe com espaço.
class QuadroNoTexto extends StatefulWidget {
  const QuadroNoTexto({
    super.key,
    required this.quadro,
    required this.onAbrir,
    this.onExcluir,
  });

  final QuadroDaNota quadro;

  final VoidCallback onAbrir;

  /// Desenhado, o quadro nao pode mais ser apagado selecionando o texto dele.
  /// Sem esta saida ele ficaria na nota para sempre. Nulo no preview, onde
  /// nada se apaga.
  final VoidCallback? onExcluir;

  @override
  State<QuadroNoTexto> createState() => _QuadroNoTextoState();
}

class _QuadroNoTextoState extends State<QuadroNoTexto> {
  bool _mouseEmCima = false;

  /// Altura do cartao. Menor num quadro vazio: nada a mostrar nao precisa de
  /// meia tela.
  double get _altura => widget.quadro.semNada ? 132 : 260;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mostrarAcoes = _mouseEmCima && widget.onExcluir != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _mouseEmCima = true),
      onExit: (_) => setState(() => _mouseEmCima = false),
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.gapSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: widget.onAbrir,
              child: Container(
                height: _altura,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(
                    color: _mouseEmCima
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Stack(
                    children: [
                      Positioned.fill(child: _desenho(theme)),
                      if (widget.quadro.semNada) _vazio(theme),
                      Positioned(
                        left: AppTheme.gapSm,
                        top: AppTheme.gapSm,
                        child: _etiqueta(theme),
                      ),
                      if (_mouseEmCima)
                        Positioned(
                          right: AppTheme.gapSm,
                          top: AppTheme.gapSm,
                          child: _abrir(theme),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            // As açoes ocupam lugar sempre, mesmo invisiveis: aparecendo do
            // nada elas empurrariam o texto de baixo a cada passada de mouse.
            if (widget.onExcluir != null)
              AnimatedOpacity(
                opacity: mostrarAcoes ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IgnorePointer(
                  ignoring: !mostrarAcoes,
                  child: _acoes(theme),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _desenho(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        // O desenho vem reduzido para caber, nunca ampliado: um quadro de duas
        // caixas esticado até a largura da nota ficaria com letra de cartaz.
        final visao = DesenhoDoQuadro.enquadrar(
          DesenhoDoQuadro.limitesDe(widget.quadro, folga: 24),
          area,
        );

        return CustomPaint(
          painter: QuadroPintado(
            quadro: widget.quadro,
            cores: theme.colorScheme,
            pan: visao.pan,
            escala: visao.escala,
          ),
        );
      },
    );
  }

  Widget _etiqueta(ThemeData theme) {
    final quantas = widget.quadro.nos.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_tree_outlined,
            size: 13,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppTheme.gapXs),
          Text(
            quantas == 0
                ? 'Quadro'
                : 'Quadro · $quantas ${quantas == 1 ? 'caixa' : 'caixas'}',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  Widget _abrir(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.open_in_full, size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: AppTheme.gapXs),
          Text(
            'Abrir',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _vazio(ThemeData theme) {
    return Center(
      child: IgnorePointer(
        child: Text(
          'Quadro vazio — clique para desenhar',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _acoes(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.gapXs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Acao(
            icone: Icons.open_in_full,
            rotulo: 'Abrir',
            onTap: widget.onAbrir,
          ),
          _Acao(
            icone: Icons.delete_outline,
            rotulo: 'Excluir',
            cor: theme.colorScheme.error,
            onTap: widget.onExcluir,
          ),
        ],
      ),
    );
  }
}

/// Um botao pequeno da barra de açoes do quadro. Gemeo do da tabela: as duas
/// barras aparecem no mesmo lugar, do mesmo jeito, e devem se parecer.
class _Acao extends StatelessWidget {
  const _Acao({
    required this.icone,
    required this.rotulo,
    required this.onTap,
    this.cor,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback? onTap;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cor = onTap == null
        ? scheme.onSurfaceVariant.withValues(alpha: 0.35)
        : (this.cor ?? scheme.onSurfaceVariant);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapSm,
          vertical: AppTheme.gapXs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 14, color: cor),
            const SizedBox(width: AppTheme.gapXs),
            Text(
              rotulo,
              style: theme.textTheme.bodySmall?.copyWith(color: cor),
            ),
          ],
        ),
      ),
    );
  }
}
