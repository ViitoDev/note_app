import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tabela_da_nota.dart';
import 'app_theme.dart';

/// A tabela desenhada como grade dentro do editor, com cada celula editavel.
///
/// No arquivo ela continua sendo Markdown; aqui e so uma leitura dele. Cada
/// tecla devolve a tabela inteira por [onMudar], e quem recebe troca o trecho
/// correspondente no texto da nota — nao existe estado de tabela guardado
/// nesta tela que possa discordar do `.md`.
class TabelaEditavel extends StatefulWidget {
  const TabelaEditavel({
    super.key,
    required this.tabela,
    required this.onMudar,
    required this.onExcluir,
    this.autofocus = false,
  });

  final TabelaDaNota tabela;

  /// Poe o cursor na primeira celula assim que a grade aparece. Vale para a
  /// tabela que acabou de ser inserida pelo menu.
  final bool autofocus;
  final ValueChanged<TabelaDaNota> onMudar;

  /// Desenhada, a tabela nao pode mais ser apagada selecionando o texto dela.
  /// Sem esta saida ela ficaria na nota para sempre.
  final VoidCallback onExcluir;

  @override
  State<TabelaEditavel> createState() => _TabelaEditavelState();
}

class _TabelaEditavelState extends State<TabelaEditavel> {
  late List<List<TextEditingController>> _campos;
  late List<List<FocusNode>> _focos;

  /// Onde esta o cursor, para as açoes saberem em que linha e coluna mexer.
  /// Nulo quando ninguem esta editando.
  ({int linha, int coluna})? _celula;

  bool _mouseEmCima = false;

  @override
  void initState() {
    super.initState();
    _montarCampos();

    // Depois do quadro, e nao pelo `autofocus` do campo: ao fechar, o dialogo
    // devolve o foco a quem o abriu, e essa devoluçao chegaria por ultimo.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focos.first.first.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(TabelaEditavel old) {
    super.didUpdateWidget(old);

    final mudouDeTamanho =
        old.tabela.linhas != widget.tabela.linhas ||
        old.tabela.colunas != widget.tabela.colunas;

    if (mudouDeTamanho) {
      // Os antigos so sao soltos depois do quadro: neste ponto os campos deles
      // ainda estao montados, e soltar agora derrubaria o widget vivo.
      final campos = _campos;
      final focos = _focos;
      _montarCampos();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _soltar(campos, focos),
      );
      return;
    }

    // Mesmo tamanho: so acerta o texto de quem mudou. Reescrever todos jogaria
    // o cursor de quem esta digitando para o começo da celula.
    for (var i = 0; i < widget.tabela.linhas; i++) {
      for (var j = 0; j < widget.tabela.colunas; j++) {
        // A celula que esta sendo digitada nao se acerta por ninguem: e ela a
        // origem do texto. Sem esta saida, o espaço recem-digitado voltava
        // apagado — o Markdown apara as pontas de cada celula ao ser lido, e
        // "mais " virava "mais" antes da segunda palavra chegar.
        if (_focos[i][j].hasFocus) continue;

        final novo = widget.tabela.celulas[i][j];
        if (_campos[i][j].text != novo) _campos[i][j].text = novo;
      }
    }
  }

  void _montarCampos() {
    _campos = [
      for (final linha in widget.tabela.celulas)
        [for (final celula in linha) TextEditingController(text: celula)],
    ];
    _focos = [
      for (var i = 0; i < widget.tabela.linhas; i++)
        [
          for (var j = 0; j < widget.tabela.colunas; j++)
            FocusNode()..addListener(() => _focoMudou(i, j)),
        ],
    ];
  }

  static void _soltar(
    List<List<TextEditingController>> campos,
    List<List<FocusNode>> focos,
  ) {
    for (final linha in campos) {
      for (final campo in linha) {
        campo.dispose();
      }
    }
    for (final linha in focos) {
      for (final foco in linha) {
        foco.dispose();
      }
    }
  }

  void _focoMudou(int linha, int coluna) {
    if (!mounted) return;
    if (linha >= _focos.length || coluna >= _focos[linha].length) return;

    if (_focos[linha][coluna].hasFocus) {
      setState(() => _celula = (linha: linha, coluna: coluna));
    } else if (_celula == (linha: linha, coluna: coluna)) {
      setState(() => _celula = null);
    }
  }

  @override
  void dispose() {
    _soltar(_campos, _focos);
    super.dispose();
  }

  /// A linha e a coluna em que as açoes mexem: a do cursor, ou a ultima quando
  /// ninguem esta editando — que e onde a mao vai de qualquer jeito.
  int get _linhaAtual => _celula?.linha ?? widget.tabela.linhas - 1;
  int get _colunaAtual => _celula?.coluna ?? widget.tabela.colunas - 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mostrarAcoes = _mouseEmCima || _celula != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _mouseEmCima = true),
      onExit: (_) => setState(() => _mouseEmCima = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.gapSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              child: Table(
                border: TableBorder.all(color: scheme.outlineVariant),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (var i = 0; i < widget.tabela.linhas; i++)
                    TableRow(
                      // O cabeçalho ganha fundo proprio, como no preview: e o
                      // que diz, olhando, qual linha nomeia as colunas.
                      decoration: i == 0
                          ? BoxDecoration(color: scheme.surfaceContainerHigh)
                          : null,
                      children: [
                        for (var j = 0; j < widget.tabela.colunas; j++)
                          _celulaEditavel(theme, i, j),
                      ],
                    ),
                ],
              ),
            ),
            // As açoes ocupam lugar sempre, mesmo invisiveis: aparecendo do
            // nada elas empurrariam o texto de baixo a cada passada de mouse.
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

  Widget _celulaEditavel(ThemeData theme, int linha, int coluna) {
    final cabecalho = linha == 0;

    return TextField(
      controller: _campos[linha][coluna],
      focusNode: _focos[linha][coluna],
      // Cresce para baixo conforme o texto passa da largura da coluna. No
      // arquivo continua tudo numa linha — o que quebra e o desenho, e nao o
      // conteudo.
      maxLines: null,
      // A quebra que o desenho faz sozinho e uma coisa; a que se digita e
      // outra. No Markdown, uma linha da tabela e uma linha do arquivo, entao
      // o Enter e barrado na entrada, antes de virar texto.
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\n'))],
      cursorColor: theme.colorScheme.primary,
      cursorWidth: 1.6,
      textAlign: switch (widget.tabela.alinhamentos[coluna]) {
        AlinhamentoDaColuna.centro => TextAlign.center,
        AlinhamentoDaColuna.direita => TextAlign.right,
        _ => TextAlign.left,
      },
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: cabecalho ? FontWeight.w600 : FontWeight.w400,
        color: cabecalho
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withValues(alpha: 0.92),
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapMd,
          vertical: AppTheme.gapSm,
        ),
        hintText: cabecalho ? 'Coluna ${coluna + 1}' : null,
        hintStyle: TextStyle(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          fontWeight: FontWeight.w400,
        ),
      ),
      onChanged: (texto) =>
          widget.onMudar(widget.tabela.comCelula(linha, coluna, texto)),
    );
  }

  Widget _acoes(ThemeData theme) {
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.gapXs),
      // Uma fila so, sempre: empilhados os botoes ocupam meia tela e escondem
      // o texto de baixo. Num painel estreito demais a fila rola de lado, em
      // vez de quebrar ou transbordar a borda.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppTheme.gapXs,
          children: [
            _Acao(
              key: const ValueKey('tabela-mais-linha'),
              icone: Icons.add,
              rotulo: 'Linha',
              onTap: () =>
                  widget.onMudar(widget.tabela.comLinhaDepoisDe(_linhaAtual)),
            ),
            _Acao(
              key: const ValueKey('tabela-mais-coluna'),
              icone: Icons.add,
              rotulo: 'Coluna',
              onTap: () =>
                  widget.onMudar(widget.tabela.comColunaDepoisDe(_colunaAtual)),
            ),
            _Acao(
              key: const ValueKey('tabela-menos-linha'),
              icone: Icons.remove,
              rotulo: 'Linha',
              onTap: widget.tabela.linhas <= 1
                  ? null
                  : () => widget.onMudar(widget.tabela.semLinha(_linhaAtual)),
            ),
            _Acao(
              key: const ValueKey('tabela-menos-coluna'),
              icone: Icons.remove,
              rotulo: 'Coluna',
              onTap: widget.tabela.colunas <= 1
                  ? null
                  : () => widget.onMudar(widget.tabela.semColuna(_colunaAtual)),
            ),
            _Acao(
              key: const ValueKey('tabela-excluir'),
              icone: Icons.delete_outline,
              rotulo: 'Excluir',
              cor: scheme.error,
              onTap: widget.onExcluir,
            ),
          ],
        ),
      ),
    );
  }
}

/// Um botao pequeno da barra de açoes da tabela.
class _Acao extends StatelessWidget {
  const _Acao({
    super.key,
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
    final ativo = onTap != null;
    final cor = ativo
        ? (this.cor ?? scheme.onSurfaceVariant)
        : scheme.onSurfaceVariant.withValues(alpha: 0.35);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapSm,
          vertical: AppTheme.gapXs,
        ),
        // `min`, e nao o padrao: dentro do `Wrap` o botao recebe a largura
        // inteira como limite, e uma fila que se estica ocuparia a linha toda
        // — os cinco botoes sairiam empilhados, um por linha.
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
