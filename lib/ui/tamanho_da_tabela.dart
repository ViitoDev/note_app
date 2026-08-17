import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/tabela_markdown.dart';
import 'app_theme.dart';

/// Pergunta o tamanho da tabela e devolve o que foi escolhido, ou nulo se a
/// escolha foi abandonada.
Future<({int linhas, int colunas})?> escolherTamanhoDaTabela(
  BuildContext context,
) {
  return showDialog<({int linhas, int colunas})>(
    context: context,
    builder: (_) => const _TamanhoDaTabelaDialog(),
  );
}

/// A grade de quadradinhos: o mouse passa por cima e a tabela vai sendo
/// desenhada, um clique escolhe.
///
/// O tamanho se pede assim, e nao em dois campos de numero, porque a pergunta
/// nao e aritmetica — e o formato da tabela, que se reconhece olhando. Quem
/// nao tem mouse chega ao mesmo lugar pelo clique direto no quadrado.
class _TamanhoDaTabelaDialog extends StatefulWidget {
  const _TamanhoDaTabelaDialog();

  @override
  State<_TamanhoDaTabelaDialog> createState() => _TamanhoDaTabelaDialogState();
}

class _TamanhoDaTabelaDialogState extends State<_TamanhoDaTabelaDialog> {
  static const _lado = 20.0;
  static const _folga = AppTheme.gapXs;

  /// A grade nasce pequena, do tamanho da tabela que quase sempre se quer, e
  /// cresce ao encostar na borda. Comecando no maximo, a tabela comum ficaria
  /// perdida num canto de uma grade enorme.
  static const _inicial = 5;

  int _linhasVisiveis = _inicial;
  int _colunasVisiveis = _inicial;

  /// O que esta apontado agora. Zero enquanto o mouse nao entrou na grade.
  int _linhas = 0;
  int _colunas = 0;

  void _apontar(int linha, int coluna) {
    setState(() {
      _linhas = linha + 1;
      _colunas = coluna + 1;
      if (_linhas == _linhasVisiveis) {
        _linhasVisiveis = math.min(
          _linhasVisiveis + 1,
          TabelaMarkdown.maxLinhas,
        );
      }
      if (_colunas == _colunasVisiveis) {
        _colunasVisiveis = math.min(
          _colunasVisiveis + 1,
          TabelaMarkdown.maxColunas,
        );
      }
    });
  }

  void _escolher(int linha, int coluna) {
    Navigator.of(context).pop((linhas: linha + 1, colunas: coluna + 1));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Inserir tabela'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _linhas == 0
                ? 'Passe o mouse para escolher o tamanho'
                : '$_linhas x $_colunas',
            style: theme.textTheme.titleSmall?.copyWith(
              color: _linhas == 0
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppTheme.gapMd),
          MouseRegion(
            // Sair da grade apaga a marcaçao: o numero em cima passa a valer
            // so enquanto ele esta sendo apontado.
            onExit: (_) => setState(() {
              _linhas = 0;
              _colunas = 0;
            }),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var linha = 0; linha < _linhasVisiveis; linha++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: _folga),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var coluna = 0;
                          coluna < _colunasVisiveis;
                          coluna++
                        )
                          _quadrado(theme, linha, coluna),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.gapSm),
          Text(
            'A primeira linha e o cabeçalho.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _quadrado(ThemeData theme, int linha, int coluna) {
    final scheme = theme.colorScheme;
    final marcado = linha < _linhas && coluna < _colunas;

    // O cabeçalho sai mais forte, do mesmo jeito que sairia na tabela pronta:
    // e o que mostra, antes de escolher, que a primeira linha nao e de dados.
    final cor = !marcado
        ? scheme.surfaceContainerHighest
        : linha == 0
        ? scheme.primary
        : scheme.primary.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.only(right: _folga),
      child: MouseRegion(
        onEnter: (_) => _apontar(linha, coluna),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _escolher(linha, coluna),
          child: Container(
            key: ValueKey('tabela-${linha + 1}x${coluna + 1}'),
            width: _lado,
            height: _lado,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(
                color: marcado ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
