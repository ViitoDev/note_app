import 'package:flutter/material.dart';

import '../models/vault_entry.dart';
import 'app_theme.dart';

/// Onde uma linha arrastada deve parar.
///
/// `antesDe` nulo quer dizer "no fim da pasta". E a mesma forma usada para
/// acoplar paineis, e pelo mesmo motivo: descrever o destino por vizinho, e
/// nao por indice, dispensa acertar indices que mudam quando o item sai do
/// lugar de origem.
typedef MoverEntrada =
    void Function(
      VaultEntry arrastado,
      VaultFolder destino, {
      VaultEntry? antesDe,
    });

/// Tudo que a arvore precisa avisar para fora.
///
/// Existe para nao repassar seis callbacks a cada nivel da recursao.
@immutable
class _Acoes {
  const _Acoes({
    required this.selectedId,
    required this.onFileTap,
    required this.onNewNoteInFolder,
    required this.onNewFolderIn,
    required this.onDelete,
    required this.onRenomear,
    required this.onMover,
  });

  final String? selectedId;
  final ValueChanged<VaultFile> onFileTap;
  final ValueChanged<VaultFolder> onNewNoteInFolder;
  final ValueChanged<VaultFolder> onNewFolderIn;
  final ValueChanged<VaultEntry> onDelete;
  final ValueChanged<VaultEntry> onRenomear;
  final MoverEntrada onMover;
}

/// Arvore de pastas e notas do vault, no estilo da barra lateral do Obsidian.
class NoteTree extends StatelessWidget {
  const NoteTree({
    super.key,
    required this.root,
    required this.selectedId,
    required this.onFileTap,
    required this.onNewNoteInFolder,
    required this.onNewFolderIn,
    required this.onDelete,
    required this.onRenomear,
    required this.onMover,
  });

  final VaultFolder root;
  final String? selectedId;
  final ValueChanged<VaultFile> onFileTap;
  final ValueChanged<VaultFolder> onNewNoteInFolder;
  final ValueChanged<VaultFolder> onNewFolderIn;

  /// Pedido de exclusao vindo do menu do botao direito. A confirmaçao e a
  /// exclusao em si ficam com quem monta a arvore.
  final ValueChanged<VaultEntry> onDelete;

  /// Pedido de troca de nome, tambem vindo do menu do botao direito.
  final ValueChanged<VaultEntry> onRenomear;

  /// Uma linha foi arrastada para outro lugar — trocando de pasta, de posiçao,
  /// ou os dois.
  final MoverEntrada onMover;

  @override
  Widget build(BuildContext context) {
    final acoes = _Acoes(
      selectedId: selectedId,
      onFileTap: onFileTap,
      onNewNoteInFolder: onNewNoteInFolder,
      onNewFolderIn: onNewFolderIn,
      onDelete: onDelete,
      onRenomear: onRenomear,
      onMover: onMover,
    );

    return Column(
      children: [
        _RootTile(root: root, acoes: acoes),
        const Divider(height: 1),
        Expanded(
          // O vazio embaixo da ultima linha tambem recebe: e como se tira algo
          // de dentro de uma pasta sem ter outra linha da raiz para mirar.
          child: _SoltarNaRaiz(
            root: root,
            acoes: acoes,
            child: root.isEmpty
                ? const _EmptyVaultHint()
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final child in root.children)
                        _entryTile(child, root, acoes, 0),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

Widget _entryTile(VaultEntry entry, VaultFolder pai, _Acoes acoes, int depth) {
  final naTrilha = _naTrilha(entry, acoes.selectedId);
  return switch (entry) {
    VaultFolder() => _FolderTile(
      folder: entry,
      pai: pai,
      depth: depth,
      acoes: acoes,
      naTrilha: naTrilha,
    ),
    VaultFile() => _FileTile(
      file: entry,
      pai: pai,
      depth: depth,
      acoes: acoes,
      naTrilha: naTrilha,
    ),
  };
}

/// Esta linha esta no caminho ate a nota aberta?
///
/// E o que acende o trilho do galho ativo, de cima ate a nota. Numa arvore de
/// cinco niveis, saber de relance em que ramo se esta poupa refazer o caminho
/// com o olho a cada volta para a barra lateral.
bool _naTrilha(VaultEntry entry, String? selectedId) {
  if (selectedId == null) return false;
  if (entry.id == selectedId) return true;
  return entry is VaultFolder &&
      entry.children.any((filho) => _naTrilha(filho, selectedId));
}

/// Largura de um nivel de recuo, e onde o trilho dele e desenhado.
const _passo = 16.0;
const _margemDaArvore = AppTheme.gapSm;

/// Linhas verticais ligando cada linha aos pais dela.
///
/// Recuo sozinho nao basta passado o terceiro nivel: as linhas ficam parecidas
/// demais e a conta de "de quem esta nota e filha" passa a ser feita contando
/// pixels. O trilho responde isso sem contar nada.
class _Trilhos extends CustomPainter {
  const _Trilhos({
    required this.depth,
    required this.cor,
    required this.corAtiva,
    required this.naTrilha,
  });

  final int depth;
  final Color cor;
  final Color corAtiva;
  final bool naTrilha;

  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()..strokeWidth = 1;

    for (var nivel = 0; nivel < depth; nivel++) {
      // So o trilho mais fundo acende: emendado de linha em linha, ele desenha
      // o galho inteiro que leva ate a nota aberta.
      final aceso = naTrilha && nivel == depth - 1;
      tinta.color = aceso ? corAtiva : cor;

      final x = _margemDaArvore + nivel * _passo + 9;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tinta);
    }
  }

  @override
  bool shouldRepaint(covariant _Trilhos old) =>
      old.depth != depth || old.naTrilha != naTrilha || old.cor != cor;
}

/// Menu do botao direito, aberto na posiçao do cursor.
///
/// A raiz do vault nao tem menu de proposito: apagar o vault inteiro por um
/// clique errado nao e uma operaçao que valha oferecer.
Future<void> _menuDeContexto(
  BuildContext context,
  Offset posicao,
  VoidCallback onRenomear,
  VoidCallback onExcluir,
) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final scheme = Theme.of(context).colorScheme;

  final escolha = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      posicao & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      // Renomear em cima: e a açao do dia a dia, e deixar a destrutiva na
      // primeira posiçao convida ao clique errado.
      const PopupMenuItem(
        value: 'renomear',
        height: 38,
        child: Row(
          children: [
            Icon(Icons.drive_file_rename_outline, size: 16),
            SizedBox(width: AppTheme.gapMd),
            Text('Renomear'),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'excluir',
        height: 38,
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 16, color: scheme.error),
            const SizedBox(width: AppTheme.gapMd),
            const Text('Excluir'),
          ],
        ),
      ),
    ],
  );

  if (escolha == 'renomear') onRenomear();
  if (escolha == 'excluir') onExcluir();
}

class _RootTile extends StatelessWidget {
  const _RootTile({required this.root, required this.acoes});

  final VaultFolder root;
  final _Acoes acoes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DragTarget<VaultEntry>(
      onWillAcceptWithDetails: (d) => d.data.id != root.id,
      onAcceptWithDetails: (d) => acoes.onMover(d.data, root),
      builder: (context, candidatos, _) => DecoratedBox(
        decoration: BoxDecoration(
          color: candidatos.isEmpty ? null : scheme.primaryContainer,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.gapLg,
            AppTheme.gapMd,
            AppTheme.gapSm,
            AppTheme.gapMd,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'VAULT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _CountBadge(count: root.noteCount),
              const SizedBox(width: AppTheme.gapXs),
              IconButton(
                icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                tooltip: 'Nova pasta na raiz do vault',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => acoes.onNewFolderIn(root),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 17),
                tooltip: 'Nova nota na raiz do vault',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => acoes.onNewNoteInFolder(root),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A area livre da lista, que aceita soltar direto na raiz do vault.
class _SoltarNaRaiz extends StatelessWidget {
  const _SoltarNaRaiz({
    required this.root,
    required this.acoes,
    required this.child,
  });

  final VaultFolder root;
  final _Acoes acoes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DragTarget<VaultEntry>(
      onWillAcceptWithDetails: (d) => d.data.id != root.id,
      onAcceptWithDetails: (d) => acoes.onMover(d.data, root),
      builder: (context, candidatos, _) => Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          if (candidatos.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.primary),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Contador discreto de notas, usado na raiz e em cada pasta.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '$count',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _FolderTile extends StatefulWidget {
  const _FolderTile({
    required this.folder,
    required this.pai,
    required this.depth,
    required this.acoes,
    required this.naTrilha,
  });

  final VaultFolder folder;
  final VaultFolder pai;
  final int depth;
  final _Acoes acoes;

  /// Esta pasta esta no caminho ate a nota aberta.
  final bool naTrilha;

  @override
  State<_FolderTile> createState() => _FolderTileState();
}

class _FolderTileState extends State<_FolderTile> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Abre ja expandida a pasta que contem a nota selecionada, para a nota
    // aberta nunca ficar escondida atras de um colapso.
    _expanded = _containsSelected(widget.folder);
  }

  bool _containsSelected(VaultFolder folder) {
    final selected = widget.acoes.selectedId;
    if (selected == null) return false;
    for (final child in folder.children) {
      if (child.id == selected) return true;
      if (child is VaultFolder && _containsSelected(child)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Arrastavel(
          entry: widget.folder,
          pai: widget.pai,
          acoes: widget.acoes,
          aceitaDentro: widget.folder,
          child: _HoverRow(
            onTap: () => setState(() => _expanded = !_expanded),
            onSecondaryTap: (posicao) => _menuDeContexto(
              context,
              posicao,
              () => widget.acoes.onRenomear(widget.folder),
              () => widget.acoes.onDelete(widget.folder),
            ),
            depth: widget.depth,
            naTrilha: widget.naTrilha,
            builder: (hovered) => Row(
              children: [
                // Seta rotaciona em vez de trocar de icone: a transiçao guia o
                // olho para o conteudo que acabou de surgir.
                // Pasta vazia nao ganha seta: uma seta promete conteudo, e
                // clicar nela para nao ver nada acontecer nao ajuda ninguem. O
                // vao dela fica, para os nomes seguirem alinhados.
                SizedBox(
                  width: 15,
                  child: widget.folder.isEmpty
                      ? null
                      : AnimatedRotation(
                          turns: _expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: Icon(
                            Icons.chevron_right,
                            size: 15,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
                const SizedBox(width: 3),
                // Pasta aberta muda de icone: o desenho diz o mesmo que a
                // seta, e e o que da para ler de canto de olho.
                Icon(
                  _expanded ? Icons.folder_open_rounded : Icons.folder_rounded,
                  size: 14,
                  color: widget.naTrilha
                      ? theme.colorScheme.primary.withValues(alpha: 0.8)
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.gapSm),
                Expanded(
                  child: Tooltip(
                    message: widget.folder.name,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      widget.folder.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // O contador cede lugar aos botoes de criar no hover, evitando
                // que cada linha carregue icones permanentes.
                if (hovered) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 14,
                    ),
                    tooltip: 'Nova pasta em ${widget.folder.name}',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => widget.acoes.onNewFolderIn(widget.folder),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 15),
                    tooltip: 'Nova nota em ${widget.folder.name}',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        widget.acoes.onNewNoteInFolder(widget.folder),
                  ),
                ] else if (widget.folder.noteCount > 0)
                  // Pasta vazia nao mostra `0`: em um vault com muitas pastas
                  // de matéria ainda por preencher, era uma coluna inteira de
                  // zeros disputando atençao com os nomes.
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppTheme.gapSm,
                      right: AppTheme.gapSm,
                    ),
                    child: _CountBadge(count: widget.folder.noteCount),
                  ),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final child in widget.folder.children)
            _entryTile(child, widget.folder, widget.acoes, widget.depth + 1),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.pai,
    required this.depth,
    required this.acoes,
    required this.naTrilha,
  });

  final VaultFile file;
  final VaultFolder pai;
  final int depth;
  final _Acoes acoes;

  /// Esta e a nota aberta. Vem de fora junto com as pastas do caminho, pela
  /// mesma conta.
  final bool naTrilha;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = file.id == acoes.selectedId;

    return _Arrastavel(
      entry: file,
      pai: pai,
      acoes: acoes,
      child: _HoverRow(
        onTap: () => acoes.onFileTap(file),
        onSecondaryTap: (posicao) => _menuDeContexto(
          context,
          posicao,
          () => acoes.onRenomear(file),
          () => acoes.onDelete(file),
        ),
        selected: selected,
        depth: depth,
        naTrilha: naTrilha,
        builder: (hovered) => Row(
          children: [
            // O vao da seta que as pastas tem. Sem ele o nome da nota
            // começaria antes do nome das pastas irmas, e a coluna de nomes —
            // que e por onde o olho desce — sairia serrilhada.
            const SizedBox(width: 18),
            Icon(
              Icons.description_outlined,
              size: 14,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: Tooltip(
                message: file.title,
                waitDuration: const Duration(milliseconds: 600),
                child: Text(
                  file.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? scheme.primary
                        : hovered
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Onde uma linha em arrasto cairia se fosse solta agora.
enum _Zona { acima, dentro, abaixo }

/// Uma linha da arvore que pode ser arrastada e que aceita receber outra.
///
/// Numa pasta a linha vira tres alvos: as pontas reordenam entre irmaos, e o
/// meio move para dentro. Num arquivo sao dois, so as pontas — nao existe
/// "dentro" de um arquivo.
class _Arrastavel extends StatefulWidget {
  const _Arrastavel({
    required this.entry,
    required this.pai,
    required this.acoes,
    required this.child,
    this.aceitaDentro,
  });

  final VaultEntry entry;
  final VaultFolder pai;
  final _Acoes acoes;
  final Widget child;

  /// A propria pasta, quando esta linha e uma. Nulo num arquivo.
  final VaultFolder? aceitaDentro;

  @override
  State<_Arrastavel> createState() => _ArrastavelState();
}

class _ArrastavelState extends State<_Arrastavel> {
  _Zona? _zona;

  /// O irmao logo abaixo desta linha, ou nulo se ela for a ultima. Traduz
  /// "soltar embaixo desta" em "entrar antes da proxima".
  VaultEntry? get _proximoIrmao {
    final irmaos = widget.pai.children;
    final i = irmaos.indexWhere((e) => e.id == widget.entry.id);
    return i >= 0 && i + 1 < irmaos.length ? irmaos[i + 1] : null;
  }

  /// Recusa soltar uma pasta dentro dela mesma ou de uma filha dela: o
  /// resultado seria uma pasta inalcançavel.
  bool _aceita(VaultEntry arrastado) {
    if (arrastado.id == widget.entry.id) return false;
    if (arrastado is! VaultFolder) return true;
    return !_dentroDe(arrastado, widget.entry.id);
  }

  static bool _dentroDe(VaultFolder pasta, String id) {
    for (final filho in pasta.children) {
      if (filho.id == id) return true;
      if (filho is VaultFolder && _dentroDe(filho, id)) return true;
    }
    return false;
  }

  void _atualizar(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final y = box.globalToLocal(globalPosition).dy / box.size.height;
    // Numa pasta as pontas ficam estreitas para o meio — o alvo mais util —
    // ser o mais facil de acertar.
    final zona = widget.aceitaDentro == null
        ? (y < 0.5 ? _Zona.acima : _Zona.abaixo)
        : y < 0.28
        ? _Zona.acima
        : y > 0.72
        ? _Zona.abaixo
        : _Zona.dentro;

    if (zona != _zona) setState(() => _zona = zona);
  }

  void _soltar(VaultEntry arrastado) {
    final zona = _zona;
    setState(() => _zona = null);

    switch (zona) {
      case _Zona.dentro:
        widget.acoes.onMover(arrastado, widget.aceitaDentro!);
      case _Zona.acima:
        widget.acoes.onMover(arrastado, widget.pai, antesDe: widget.entry);
      case _Zona.abaixo || null:
        widget.acoes.onMover(arrastado, widget.pai, antesDe: _proximoIrmao);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Draggable<VaultEntry>(
      data: widget.entry,
      // Ancora no ponteiro: assim o `offset` que chega aqui e a posiçao do
      // cursor, e decidir a zona vira uma comparaçao direta.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _Fantasma(entry: widget.entry),
      childWhenDragging: Opacity(opacity: 0.35, child: widget.child),
      child: DragTarget<VaultEntry>(
        onWillAcceptWithDetails: (d) => _aceita(d.data),
        onMove: (d) {
          if (_aceita(d.data)) _atualizar(d.offset);
        },
        onLeave: (_) => setState(() => _zona = null),
        onAcceptWithDetails: (d) => _soltar(d.data),
        builder: (context, candidatos, _) => Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            if (_zona != null && candidatos.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: _zona == _Zona.dentro
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.gapSm,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.14),
                              border: Border.all(color: scheme.primary),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusSm,
                              ),
                            ),
                          ),
                        )
                      : Align(
                          alignment: _zona == _Zona.acima
                              ? Alignment.topCenter
                              : Alignment.bottomCenter,
                          child: Container(height: 2, color: scheme.primary),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// O que segue o cursor durante o arrasto de uma linha.
class _Fantasma extends StatelessWidget {
  const _Fantasma({required this.entry});

  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pasta = entry is VaultFolder;

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
            Icon(
              pasta ? Icons.folder_outlined : Icons.description_outlined,
              size: 14,
              color: scheme.primary,
            ),
            const SizedBox(width: AppTheme.gapSm),
            Text(switch (entry) {
              VaultFile(:final title) => title,
              VaultFolder(:final name) => name,
            }, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Linha da arvore com realce de hover e de seleçao.
///
/// Existe para que hover e seleçao tenham o mesmo tratamento em pastas e
/// arquivos — sem isso, cada tipo de linha acaba com um realce ligeiramente
/// diferente.
class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.builder,
    required this.onTap,
    required this.depth,
    this.onSecondaryTap,
    this.selected = false,
    this.naTrilha = false,
  });

  final Widget Function(bool hovered) builder;
  final VoidCallback onTap;

  /// Botao direito, com a posiçao global do clique para o menu abrir ali.
  final ValueChanged<Offset>? onSecondaryTap;

  final int depth;
  final bool selected;
  final bool naTrilha;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        // `onSecondaryTapUp` em vez de `onSecondaryTap`: o menu precisa saber
        // onde o cursor estava para abrir naquele ponto.
        onSecondaryTapUp: widget.onSecondaryTap == null
            ? null
            : (d) => widget.onSecondaryTap!(d.globalPosition),
        behavior: HitTestBehavior.opaque,
        // Os trilhos ficam por fora da margem da linha, e nao dentro dela:
        // assim eles emendam de uma linha para a seguinte em vez de sairem
        // picotados a cada dois pixels de folga.
        child: CustomPaint(
          painter: _Trilhos(
            depth: widget.depth,
            cor: scheme.outline,
            corAtiva: scheme.primary.withValues(alpha: 0.55),
            naTrilha: widget.naTrilha,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppTheme.gapXs,
              vertical: 1,
            ),
            padding: EdgeInsets.only(
              left: _margemDaArvore - AppTheme.gapXs + widget.depth * _passo,
              right: AppTheme.gapXs,
              top: 5,
              bottom: 5,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              color: widget.selected
                  ? scheme.primaryContainer
                  : _hovered
                  ? scheme.surfaceContainerHigh
                  : null,
            ),
            child: widget.builder(_hovered),
          ),
        ),
      ),
    );
  }
}

class _EmptyVaultHint extends StatelessWidget {
  const _EmptyVaultHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Nenhuma nota .md nesta pasta ainda.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
