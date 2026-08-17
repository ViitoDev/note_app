import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Uma linha do menu do botao direito.
class ItemDoMenu {
  const ItemDoMenu({
    required this.rotulo,
    required this.icone,
    required this.onPressed,
    this.separado = false,
  });

  final String rotulo;
  final IconData icone;
  final VoidCallback onPressed;

  /// Abre um risco acima desta linha, separando o que o app acrescentou do
  /// que o campo de texto ja fazia sozinho.
  final bool separado;
}

/// O menu do botao direito do editor, desenhado como o resto do app.
///
/// O menu que vem pronto do Flutter e um cartao claro com os nomes em ingles,
/// que so aparecia certo em tema claro e em outro idioma. Aqui as mesmas açoes
/// sao redesenhadas com as cores do tema e os nomes em portugues — as açoes em
/// si continuam sendo as do campo, que sabe quando cada uma vale.
class MenuDoTexto extends StatelessWidget {
  const MenuDoTexto({super.key, required this.anchor, required this.itens});

  /// Onde o menu foi pedido, em coordenadas da tela.
  final Offset anchor;

  final List<ItemDoMenu> itens;

  /// Distancia minima entre o menu e a borda da janela.
  static const _folgaDaTela = 8.0;

  /// Traduz as açoes que o proprio campo de texto oferece.
  ///
  /// A lista vem dele e muda com o estado — sem texto selecionado nao ha o que
  /// copiar, sem nada na area de transferencia nao ha o que colar. O que se
  /// faz aqui e so trocar o nome e dar um icone a cada uma.
  static List<ItemDoMenu> doCampo(EditableTextState campo) {
    return [
      for (final item in campo.contextMenuButtonItems)
        if (_acoes[item.type] case final acao?)
          if (item.onPressed case final aperta?)
            ItemDoMenu(rotulo: acao.$1, icone: acao.$2, onPressed: aperta),
    ];
  }

  static const _acoes = <ContextMenuButtonType, (String, IconData)>{
    ContextMenuButtonType.cut: ('Recortar', Icons.content_cut),
    ContextMenuButtonType.copy: ('Copiar', Icons.content_copy),
    ContextMenuButtonType.paste: ('Colar', Icons.content_paste),
    ContextMenuButtonType.selectAll: ('Selecionar tudo', Icons.select_all),
    ContextMenuButtonType.delete: ('Excluir', Icons.backspace_outlined),
    ContextMenuButtonType.lookUp: ('Procurar', Icons.search),
    ContextMenuButtonType.searchWeb: ('Pesquisar na web', Icons.travel_explore),
    ContextMenuButtonType.share: ('Compartilhar', Icons.ios_share),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final acima = MediaQuery.of(context).padding.top + _folgaDaTela;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _folgaDaTela,
        acima,
        _folgaDaTela,
        _folgaDaTela,
      ),
      child: CustomSingleChildLayout(
        // A mesma conta do menu de desktop do Flutter: o menu nasce no ponto
        // clicado e se vira sozinho quando nao cabe para baixo ou para a
        // direita.
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor: anchor - Offset(_folgaDaTela, acima),
        ),
        child: Material(
          color: scheme.surfaceContainerHighest,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.gapXs),
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in itens) ...[
                    if (item.separado)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTheme.gapXs,
                        ),
                        child: Divider(height: 1, color: scheme.outlineVariant),
                      ),
                    _Linha(item: item),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({required this.item});

  final ItemDoMenu item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: item.onPressed,
      hoverColor: scheme.primary.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapMd,
          vertical: AppTheme.gapSm,
        ),
        child: Row(
          children: [
            Icon(item.icone, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppTheme.gapMd),
            Text(
              item.rotulo,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
            // Uma folga a direita para o nome nao encostar na borda do cartao
            // quando ele se ajusta ao texto mais longo.
            const SizedBox(width: AppTheme.gapXl),
          ],
        ),
      ),
    );
  }
}
