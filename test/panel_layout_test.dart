import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/ui/panel_layout.dart';

void main() {
  group('arranjo padrao', () {
    test('nasce com a arvore a esquerda e o resto fechado', () {
      expect(PanelLayout.padrao.esquerda, [PanelKind.arquivos]);
      expect(PanelLayout.padrao.direita, isEmpty);
      expect(PanelLayout.padrao.contains(PanelKind.grafo), isFalse);
    });
  });

  group('mover', () {
    test('acopla um painel fechado na barra escolhida', () {
      final l = PanelLayout.padrao.mover(PanelKind.grafo, DockSide.direita);

      expect(l.direita, [PanelKind.grafo]);
      expect(l.sideOf(PanelKind.grafo), DockSide.direita);
    });

    test('empilha na ordem de chegada quando nao ha referencia', () {
      final l = PanelLayout.padrao
          .mover(PanelKind.calendario, DockSide.direita)
          .mover(PanelKind.grafo, DockSide.direita);

      expect(l.direita, [PanelKind.calendario, PanelKind.grafo]);
    });

    test('soltar acima de outro painel entra na frente dele', () {
      final l = PanelLayout.padrao
          .mover(PanelKind.calendario, DockSide.direita)
          .mover(
            PanelKind.grafo,
            DockSide.direita,
            antesDe: PanelKind.calendario,
          );

      expect(l.direita, [PanelKind.grafo, PanelKind.calendario]);
    });

    test('trocar de barra tira o painel da anterior', () {
      final l = PanelLayout.padrao.mover(PanelKind.arquivos, DockSide.direita);

      expect(l.esquerda, isEmpty);
      expect(l.direita, [PanelKind.arquivos]);
    });

    test('reordenar dentro da mesma barra nao duplica o painel', () {
      final antes = PanelLayout.padrao
          .mover(PanelKind.calendario, DockSide.direita)
          .mover(PanelKind.grafo, DockSide.direita);

      final depois = antes.mover(
        PanelKind.grafo,
        DockSide.direita,
        antesDe: PanelKind.calendario,
      );

      expect(depois.direita, [PanelKind.grafo, PanelKind.calendario]);
    });

    test('mover para junto de si mesmo deixa o painel no fim, sem sumir', () {
      final l = PanelLayout.padrao.mover(
        PanelKind.arquivos,
        DockSide.esquerda,
        antesDe: PanelKind.arquivos,
      );

      expect(l.esquerda, [PanelKind.arquivos]);
    });

    test('referencia que nao esta na barra manda o painel para o fim', () {
      final l = PanelLayout.padrao.mover(
        PanelKind.grafo,
        DockSide.direita,
        antesDe: PanelKind.arquivos,
      );

      expect(l.direita, [PanelKind.grafo]);
    });
  });

  test('ocultar tira o painel das duas barras', () {
    final l = PanelLayout.padrao.ocultar(PanelKind.arquivos);

    expect(l.vazio, isTrue);
    expect(l.contains(PanelKind.arquivos), isFalse);
  });

  group('persistencia', () {
    test('o arranjo sobrevive a ida e volta do texto guardado', () {
      final original = PanelLayout.padrao
          .mover(PanelKind.calendario, DockSide.direita)
          .mover(PanelKind.grafo, DockSide.direita);

      expect(PanelLayout.decode(original.encode()), original);
    });

    test('sem preferencia guardada vale o padrao', () {
      expect(PanelLayout.decode(null), PanelLayout.padrao);
    });

    test('texto sem o separador das barras cai no padrao', () {
      expect(PanelLayout.decode('arquivos'), PanelLayout.padrao);
    });

    test('nome desconhecido e ignorado sem derrubar o resto', () {
      expect(
        PanelLayout.decode('arquivos,timeline|grafo'),
        const PanelLayout(
          esquerda: [PanelKind.arquivos],
          direita: [PanelKind.grafo],
        ),
      );
    });

    test('painel repetido nas duas barras fica so na primeira', () {
      final l = PanelLayout.decode('grafo|grafo');

      expect(l.esquerda, [PanelKind.grafo]);
      expect(l.direita, isEmpty);
    });

    test('barra vazia dos dois lados le como tudo fechado', () {
      expect(PanelLayout.decode('|').vazio, isTrue);
    });
  });
}
