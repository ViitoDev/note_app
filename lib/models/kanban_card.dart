import 'package:flutter/foundation.dart';

import 'note.dart';

/// As quatro colunas do quadro.
///
/// A ordem da enum e a ordem na tela, da esquerda para a direita.
enum KanbanColumn {
  aFazer('Pronto para fazer', 'a-fazer', {
    'a-fazer',
    'afazer',
    'para-fazer',
    'pronto-para-fazer',
    'todo',
    'backlog',
    'aberto',
  }),
  fazendo('Fazendo', 'fazendo', {
    'fazendo',
    'doing',
    'em-andamento',
    'andamento',
    'em-progresso',
    'wip',
  }),
  revisao('Revisao', 'revisao', {
    'revisao',
    'em-revisao',
    'revisar',
    'review',
    'in-review',
  }),
  pronto('Pronto', 'pronto', {
    'pronto',
    'done',
    'feito',
    'concluido',
    'finalizado',
    'entregue',
  });

  const KanbanColumn(this.label, this.valor, this.apelidos);

  /// Titulo da coluna na tela.
  final String label;

  /// O que e gravado no `status:` quando o card cai nesta coluna.
  final String valor;

  /// Outras escritas aceitas na leitura.
  ///
  /// A lista existe porque o `.md` e escrito a mao: quem digita `status: done`
  /// ou `status: Em andamento` espera ver o card no lugar certo, e nao sumido.
  final Set<String> apelidos;

  /// A coluna de um `status:` escrito de qualquer jeito, ou nulo se o valor
  /// nao corresponder a nenhuma — nota sem status nao e card.
  static KanbanColumn? porValor(Object? bruto) {
    if (bruto is! String) return null;
    final chave = normalizar(bruto);
    if (chave.isEmpty) return null;

    for (final coluna in values) {
      if (coluna.apelidos.contains(chave)) return coluna;
    }
    return null;
  }

  /// Reduz o texto a uma forma comparavel: minusculas, sem acento, e com
  /// espaço e sublinhado virando hifen.
  static String normalizar(String bruto) {
    final buffer = StringBuffer();
    for (final rune in bruto.trim().toLowerCase().runes) {
      final c = String.fromCharCode(rune);
      buffer.write(_semAcento[c] ?? (c == ' ' || c == '_' ? '-' : c));
    }
    return buffer.toString();
  }

  static const _semAcento = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'ê': 'e',
    'è': 'e',
    'ë': 'e',
    'í': 'i',
    'î': 'i',
    'ì': 'i',
    'ï': 'i',
    'ó': 'o',
    'õ': 'o',
    'ô': 'o',
    'ò': 'o',
    'ö': 'o',
    'ú': 'u',
    'û': 'u',
    'ù': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
}

/// Uma nota que virou card do quadro.
@immutable
class KanbanCard {
  const KanbanCard({
    required this.noteId,
    required this.titulo,
    required this.coluna,
    this.tags = const [],
    this.resumo = '',
    this.prazo,
  });

  final String noteId;
  final String titulo;
  final KanbanColumn coluna;
  final List<String> tags;

  /// Primeira linha util do corpo, para o card e o resumo nao serem so um
  /// titulo solto.
  final String resumo;

  /// `data:` do frontmatter, quando o card tambem tem prazo.
  final DateTime? prazo;

  @override
  bool operator ==(Object other) =>
      other is KanbanCard && other.noteId == noteId;

  @override
  int get hashCode => noteId.hashCode;
}

/// O quadro inteiro, ja separado por coluna.
@immutable
class KanbanBoard {
  const KanbanBoard(this._porColuna);

  final Map<KanbanColumn, List<KanbanCard>> _porColuna;

  static const vazio = KanbanBoard({});

  List<KanbanCard> of(KanbanColumn coluna) => _porColuna[coluna] ?? const [];

  /// Todos os cards, na ordem das colunas — e a ordem do resumo embaixo do
  /// quadro.
  List<KanbanCard> get todos => [
    for (final coluna in KanbanColumn.values) ...of(coluna),
  ];

  int get total => todos.length;

  bool get isEmpty => total == 0;

  /// Monta o quadro a partir das notas do vault.
  ///
  /// So entra quem tem `status:` reconhecido. Uma nota comum nao vira card por
  /// acidente — o quadro e opt-in, escrito no proprio arquivo.
  factory KanbanBoard.build(Iterable<Note> notas) {
    final porColuna = <KanbanColumn, List<KanbanCard>>{};

    for (final nota in notas) {
      final coluna = KanbanColumn.porValor(nota.frontmatter['status']);
      if (coluna == null) continue;

      porColuna
          .putIfAbsent(coluna, () => [])
          .add(
            KanbanCard(
              noteId: nota.id,
              titulo: nota.title,
              coluna: coluna,
              tags: _tags(nota),
              resumo: _resumo(nota.body),
              prazo: _prazo(nota.frontmatter['data']),
            ),
          );
    }

    // Dentro da coluna, alfabetica: sem uma ordem definida a lista mudaria de
    // arranjo a cada varredura, porque o disco nao promete ordem.
    for (final lista in porColuna.values) {
      lista.sort(
        (a, b) => a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase()),
      );
    }

    return KanbanBoard(porColuna);
  }

  static List<String> _tags(Note nota) {
    final bruto = nota.frontmatter['tags'];
    if (bruto is List) {
      return [
        for (final t in bruto)
          if (t != null) '$t',
      ];
    }
    if (bruto is String && bruto.trim().isNotEmpty) {
      return bruto
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    }
    return const [];
  }

  static String _resumo(String corpo) {
    for (final linha in corpo.split('\n')) {
      final limpa = linha.trim();
      // Titulo, marcador de frontmatter e cerca de codigo nao resumem nada.
      if (limpa.isEmpty ||
          limpa.startsWith('#') ||
          limpa.startsWith('---') ||
          limpa.startsWith('```')) {
        continue;
      }
      return limpa.length > 160 ? '${limpa.substring(0, 160)}...' : limpa;
    }
    return '';
  }

  static DateTime? _prazo(Object? bruto) {
    if (bruto is DateTime) return DateTime(bruto.year, bruto.month, bruto.day);
    if (bruto is! String) return null;
    return DateTime.tryParse(bruto.trim());
  }
}
