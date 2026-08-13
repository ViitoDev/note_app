import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/vault_graph.dart';

/// Posicao viva de um no durante a simulacao.
class NodePosition {
  NodePosition({required this.node, required this.x, required this.y});

  final GraphNode node;
  double x;
  double y;
  double vx = 0;
  double vy = 0;

  /// Fixado pelo arrasto do usuario: a simulacao para de mover este no.
  bool pinned = false;
}

/// Layout dirigido por forcas, no espirito do Fruchterman-Reingold.
///
/// Tres forcas convivem:
///   * repulsao entre todos os pares, que espalha o grafo;
///   * atracao ao longo das arestas, que aproxima o que esta ligado;
///   * gravidade fraca para o centro, que impede componentes isolados de
///     escaparem para o infinito — sem ela, notas sem tag somem da tela.
///
/// Nao usa pacote externo de proposito: a simulacao cabe em poucas dezenas de
/// linhas e evita mais uma dependencia para manter.
class GraphLayout {
  GraphLayout({required VaultGraph graph, int seed = 42}) : _graph = graph {
    final random = math.Random(seed);
    // Disco inicial pequeno: partir de posicoes proximas faz a simulacao
    // "abrir" o grafo, o que revela a estrutura melhor do que partir do caos.
    for (final node in graph.nodes) {
      final angle = random.nextDouble() * 2 * math.pi;
      final radius = 40 + random.nextDouble() * 120;
      positions[node.id] = NodePosition(
        node: node,
        x: math.cos(angle) * radius,
        y: math.sin(angle) * radius,
      );
    }
  }

  final VaultGraph _graph;
  final Map<String, NodePosition> positions = {};

  /// Cai a cada passo para o grafo assentar em vez de vibrar para sempre.
  double _temperature = 1.0;

  static const _repulsion = 9000.0;
  static const _springLength = 90.0;
  static const _springStrength = 0.035;
  static const _gravity = 0.012;
  static const _damping = 0.86;

  bool get settled => _temperature < 0.02;

  Iterable<NodePosition> get all => positions.values;

  /// Avanca um passo da simulacao. Chamado a cada frame pela tela.
  void step() {
    if (settled) return;

    final nodes = positions.values.toList(growable: false);

    for (final a in nodes) {
      var fx = 0.0;
      var fy = 0.0;

      for (final b in nodes) {
        if (identical(a, b)) continue;
        var dx = a.x - b.x;
        var dy = a.y - b.y;
        var distSq = dx * dx + dy * dy;
        // Nos exatamente sobrepostos gerariam divisao por zero; um empurrao
        // minimo e deterministico resolve.
        if (distSq < 0.01) {
          dx = (a.hashCode % 7 - 3) * 0.1;
          dy = (b.hashCode % 7 - 3) * 0.1;
          distSq = dx * dx + dy * dy + 0.01;
        }
        final force = _repulsion / distSq;
        final dist = math.sqrt(distSq);
        fx += dx / dist * force;
        fy += dy / dist * force;
      }

      // Gravidade proporcional a distancia: quase nula perto do centro.
      fx -= a.x * _gravity;
      fy -= a.y * _gravity;

      a.vx = (a.vx + fx) * _damping;
      a.vy = (a.vy + fy) * _damping;
    }

    for (final edge in _graph.edges) {
      final a = positions[edge.source];
      final b = positions[edge.target];
      if (a == null || b == null) continue;

      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dist = math.sqrt(dx * dx + dy * dy) + 0.01;
      final force = (dist - _springLength) * _springStrength;
      final fx = dx / dist * force;
      final fy = dy / dist * force;

      a.vx += fx;
      a.vy += fy;
      b.vx -= fx;
      b.vy -= fy;
    }

    for (final node in nodes) {
      if (node.pinned) {
        node.vx = 0;
        node.vy = 0;
        continue;
      }
      node.x += node.vx * _temperature;
      node.y += node.vy * _temperature;
    }

    _temperature *= 0.985;
  }

  /// Reaquece a simulacao — usado ao soltar um no arrastado, para o grafo
  /// reacomodar em volta da nova posicao.
  void reheat([double to = 0.55]) {
    _temperature = math.max(_temperature, to);
  }

  /// Retangulo que contem todos os nos, para a tela enquadrar o grafo.
  GraphBounds bounds() {
    if (positions.isEmpty) return GraphBounds.zero;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final p in positions.values) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
    }
    return GraphBounds(minX, minY, maxX, maxY);
  }

  /// No mais proximo de um ponto, dentro de [tolerance].
  NodePosition? nodeAt(double x, double y, double tolerance) {
    NodePosition? melhor;
    var menorDist = double.infinity;
    for (final p in positions.values) {
      final dx = p.x - x;
      final dy = p.y - y;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < tolerance && dist < menorDist) {
        menorDist = dist;
        melhor = p;
      }
    }
    return melhor;
  }
}

/// Retangulo simples, para o layout nao depender de `dart:ui`.
///
/// Nome proprio em vez de `Rect` para nao colidir com o do Flutter na tela,
/// que importa este arquivo junto com o `material.dart`.
@immutable
class GraphBounds {
  const GraphBounds(this.left, this.top, this.right, this.bottom);

  static const zero = GraphBounds(0, 0, 0, 0);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}
