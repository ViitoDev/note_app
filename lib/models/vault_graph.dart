import 'note.dart';

enum GraphNodeKind { nota, tag }

/// Um no do grafo: uma nota do vault ou uma tag usada por notas.
class GraphNode {
  GraphNode({
    required this.id,
    required this.label,
    required this.kind,
    this.noteId,
  });

  /// Identidade unica no grafo. Notas usam o proprio id; tags usam `#nome`.
  final String id;

  final String label;
  final GraphNodeKind kind;

  /// Para nos de nota, o id que abre o arquivo. Nulo em nos de tag.
  final String? noteId;

  /// Quantas arestas chegam neste no. Alimenta o tamanho do circulo — o que da
  /// ao grafo sua leitura imediata de "o que e central neste vault".
  int degree = 0;

  @override
  String toString() => 'GraphNode($id, $kind, grau $degree)';
}

/// Ligacao entre dois nos. Nao tem direcao: o grafo e lido como uma teia.
class GraphEdge {
  const GraphEdge(this.source, this.target);

  final String source;
  final String target;

  @override
  bool operator ==(Object other) =>
      other is GraphEdge &&
      ((other.source == source && other.target == target) ||
          (other.source == target && other.target == source));

  @override
  int get hashCode => Object.hashAllUnordered([source, target]);
}

/// O grafo inteiro do vault: notas, tags e o que as liga.
class VaultGraph {
  VaultGraph({required this.nodes, required this.edges});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  bool get isEmpty => nodes.isEmpty;

  Iterable<GraphNode> get notas =>
      nodes.where((n) => n.kind == GraphNodeKind.nota);
  Iterable<GraphNode> get tags =>
      nodes.where((n) => n.kind == GraphNodeKind.tag);

  int get maiorGrau =>
      nodes.fold(0, (maior, n) => n.degree > maior ? n.degree : maior);

  /// Constroi o grafo a partir das notas do vault.
  ///
  /// Tres tipos de ligacao entram:
  ///   * nota — tag, para cada tag do frontmatter ou `#tag` no corpo;
  ///   * nota — nota, para cada `[[link interno]]`;
  ///   * nada mais. Pastas nao viram no: elas organizam arquivos, nao ideias.
  factory VaultGraph.build(Iterable<Note> notes) {
    final nodes = <String, GraphNode>{};
    final edges = <GraphEdge>{};

    // Indice de titulo para id, usado para resolver `[[link]]`.
    final porTitulo = <String, String>{};
    for (final note in notes) {
      porTitulo[note.title.toLowerCase()] = note.id;
    }

    for (final note in notes) {
      nodes.putIfAbsent(
        note.id,
        () => GraphNode(
          id: note.id,
          label: note.title,
          kind: GraphNodeKind.nota,
          noteId: note.id,
        ),
      );

      for (final tag in TagParser.fromNote(note)) {
        final tagId = '#$tag';
        nodes.putIfAbsent(
          tagId,
          () => GraphNode(id: tagId, label: tag, kind: GraphNodeKind.tag),
        );
        edges.add(GraphEdge(note.id, tagId));
      }

      for (final alvo in TagParser.wikilinksFrom(note)) {
        final destino = porTitulo[alvo.toLowerCase()];
        // Link para nota inexistente e ignorado: um no fantasma poluiria o
        // grafo sem representar nada que exista no vault.
        if (destino == null || destino == note.id) continue;
        edges.add(GraphEdge(note.id, destino));
      }
    }

    for (final edge in edges) {
      nodes[edge.source]?.degree++;
      nodes[edge.target]?.degree++;
    }

    return VaultGraph(nodes: nodes.values.toList(), edges: edges.toList());
  }
}

/// Extrai tags e links internos do texto das notas.
abstract final class TagParser {
  /// `#tag` no corpo. Aceita letras acentuadas, numeros, `-`, `_` e `/` para
  /// tags hierarquicas (`#estudos/flutter`), mas exige comecar com letra para
  /// nao capturar `#1` de listas nem ancoras de cabecalho Markdown.
  static final RegExp _inlineTag = RegExp(
    r'(?<![\w#])#([\p{L}][\p{L}\p{N}_/-]*)',
    unicode: true,
  );

  /// Cabecalhos Markdown (`# Titulo`) nao sao tags.
  static final RegExp _heading = RegExp(r'^\s{0,3}#{1,6}\s', multiLine: true);

  static final RegExp _wikilink = RegExp(r'\[\[([^\]\|]+)(?:\|[^\]]*)?\]\]');

  /// Blocos de codigo e codigo inline, onde `#` costuma ser sintaxe da
  /// linguagem e nao marcacao do usuario.
  static final RegExp _code = RegExp(r'```.*?```|`[^`\n]*`', dotAll: true);

  /// Todas as tags de uma nota, vindas do frontmatter e do corpo, sem repetir
  /// e preservando a ordem em que aparecem.
  static Set<String> fromNote(Note note) {
    final tags = <String>{};

    final doFrontmatter = note.frontmatter['tags'];
    if (doFrontmatter is List) {
      for (final tag in doFrontmatter) {
        final limpa = _clean(tag.toString());
        if (limpa != null) tags.add(limpa);
      }
    } else if (doFrontmatter is String) {
      for (final tag in doFrontmatter.split(RegExp(r'[,\s]+'))) {
        final limpa = _clean(tag);
        if (limpa != null) tags.add(limpa);
      }
    }

    final corpo = _stripNoise(note.body);
    for (final match in _inlineTag.allMatches(corpo)) {
      final limpa = _clean(match.group(1)!);
      if (limpa != null) tags.add(limpa);
    }

    return tags;
  }

  static Set<String> wikilinksFrom(Note note) {
    final corpo = _stripNoise(note.body);
    return {
      for (final match in _wikilink.allMatches(corpo))
        if (match.group(1)!.trim().isNotEmpty) match.group(1)!.trim(),
    };
  }

  /// Remove codigo e cabecalhos antes de procurar tags, trocando por espacos
  /// para nao colar palavras vizinhas.
  static String _stripNoise(String body) {
    return body
        .replaceAllMapped(_code, (m) => ' ' * m.group(0)!.length)
        .replaceAllMapped(_heading, (m) => ' ' * m.group(0)!.length);
  }

  static String? _clean(String raw) {
    final tag = raw.trim().replaceFirst(RegExp('^#+'), '');
    if (tag.isEmpty) return null;
    return tag;
  }
}
