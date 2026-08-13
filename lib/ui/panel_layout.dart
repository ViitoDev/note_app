import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Os paineis que o usuario pode acoplar nas barras laterais.
///
/// O editor de nota nao esta aqui de proposito: ele e o centro fixo da tela,
/// nao um painel que se move.
enum PanelKind {
  arquivos('Arquivos', Icons.folder_outlined),
  dashboard('Painel', Icons.dashboard_outlined),
  calendario('Calendario', Icons.calendar_month_outlined),
  grafo('Grafo', Icons.hub_outlined),
  kanban('Quadro', Icons.view_kanban_outlined),
  email('E-mail', Icons.mail_outline);

  const PanelKind(this.label, this.icon);

  final String label;
  final IconData icon;

  static PanelKind? porNome(String nome) {
    for (final p in values) {
      if (p.name == nome) return p;
    }
    return null;
  }
}

/// As duas barras que recebem paineis.
enum DockSide {
  esquerda('esquerda'),
  direita('direita');

  const DockSide(this.label);

  final String label;

  DockSide get oposto =>
      this == DockSide.esquerda ? DockSide.direita : DockSide.esquerda;
}

/// Onde cada painel esta acoplado.
///
/// Um painel ausente das duas listas esta oculto. A ordem dentro da lista e a
/// ordem de cima para baixo na barra, e e ela que decide como a barra se
/// divide: dois paineis viram meio a meio, tres viram tres faixas.
@immutable
class PanelLayout {
  const PanelLayout({this.esquerda = const [], this.direita = const []});

  final List<PanelKind> esquerda;
  final List<PanelKind> direita;

  /// A arvore do vault a esquerda e o resto oculto — o mesmo arranjo que o app
  /// tinha antes dos paineis serem moveis.
  static const padrao = PanelLayout(esquerda: [PanelKind.arquivos]);

  List<PanelKind> of(DockSide side) =>
      side == DockSide.esquerda ? esquerda : direita;

  DockSide? sideOf(PanelKind painel) {
    if (esquerda.contains(painel)) return DockSide.esquerda;
    if (direita.contains(painel)) return DockSide.direita;
    return null;
  }

  bool contains(PanelKind painel) => sideOf(painel) != null;

  bool get vazio => esquerda.isEmpty && direita.isEmpty;

  /// Move [painel] para [side], logo acima de [antesDe]. Sem [antesDe], entra
  /// no fim da barra.
  ///
  /// O painel sai das duas listas antes de ser inserido: e isso que permite
  /// reordenar dentro da propria barra sem acabar com o painel duplicado.
  PanelLayout mover(PanelKind painel, DockSide side, {PanelKind? antesDe}) {
    final destino = [...of(side)]..remove(painel);
    final outra = [...of(side.oposto)]..remove(painel);

    final alvo = antesDe == null ? -1 : destino.indexOf(antesDe);
    if (alvo < 0) {
      destino.add(painel);
    } else {
      destino.insert(alvo, painel);
    }

    return side == DockSide.esquerda
        ? PanelLayout(esquerda: destino, direita: outra)
        : PanelLayout(esquerda: outra, direita: destino);
  }

  PanelLayout ocultar(PanelKind painel) => PanelLayout(
    esquerda: [...esquerda]..remove(painel),
    direita: [...direita]..remove(painel),
  );

  /// Formato `esquerda|direita`, cada lado com os nomes separados por virgula.
  String encode() =>
      '${esquerda.map((p) => p.name).join(',')}'
      '|${direita.map((p) => p.name).join(',')}';

  /// Le o formato de [encode]. Entrada estranha cai no padrao em vez de
  /// derrubar a tela — uma preferencia corrompida nao vale um app que nao abre.
  static PanelLayout decode(String? raw) {
    if (raw == null) return padrao;
    final partes = raw.split('|');
    if (partes.length != 2) return padrao;

    // O mesmo painel nao pode aparecer duas vezes, nem na mesma barra nem em
    // barras diferentes: a primeira ocorrencia ganha.
    final vistos = <PanelKind>{};
    List<PanelKind> lado(String texto) {
      final saida = <PanelKind>[];
      for (final nome in texto.split(',')) {
        final painel = PanelKind.porNome(nome);
        if (painel != null && vistos.add(painel)) saida.add(painel);
      }
      return saida;
    }

    return PanelLayout(esquerda: lado(partes[0]), direita: lado(partes[1]));
  }

  @override
  bool operator ==(Object other) =>
      other is PanelLayout &&
      listEquals(esquerda, other.esquerda) &&
      listEquals(direita, other.direita);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(esquerda), Object.hashAll(direita));

  @override
  String toString() => 'PanelLayout(${encode()})';
}
