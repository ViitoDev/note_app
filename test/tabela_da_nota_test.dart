import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/tabela_da_nota.dart';

void main() {
  group('lendo o Markdown', () {
    test('cabeçalho, tracinhos e corpo viram celulas', () {
      final t = TabelaDaNota.ler([
        '| Nome | Idade |',
        '| --- | --- |',
        '| Ana | 30 |',
      ])!;

      expect(t.linhas, 2);
      expect(t.colunas, 2);
      expect(t.celulas, [
        ['Nome', 'Idade'],
        ['Ana', '30'],
      ]);
    });

    test('os dois-pontos dizem o alinhamento', () {
      final t = TabelaDaNota.ler([
        '| a | b | c | d |',
        '| --- | :--- | :---: | ---: |',
      ])!;

      expect(t.alinhamentos, [
        AlinhamentoDaColuna.padrao,
        AlinhamentoDaColuna.esquerda,
        AlinhamentoDaColuna.centro,
        AlinhamentoDaColuna.direita,
      ]);
    });

    test('as barras das pontas sao opcionais', () {
      final t = TabelaDaNota.ler(['a | b', '--- | ---'])!;
      expect(t.celulas.first, ['a', 'b']);
    });

    test('linha curta ganha as celulas que faltam', () {
      // O Markdown desenha a linha assim; a grade tem que mostrar o mesmo.
      final t = TabelaDaNota.ler([
        '| a | b | c |',
        '| --- | --- | --- |',
        '| so uma |',
      ])!;

      expect(t.celulas[1], ['so uma', '', '']);
    });

    test('sem a linha de tracinhos nao e tabela', () {
      expect(TabelaDaNota.ler(['| a | b |', '| c | d |']), isNull);
      // Texto com um tracinho embaixo e titulo, e nao tabela.
      expect(TabelaDaNota.ler(['a | b', '---']), isNull);
    });
  });

  group('escrevendo de volta', () {
    test('o que foi lido sai igual', () {
      const markdown = '| Nome | Idade |\n| --- | --- |\n| Ana | 30 |';
      expect(TabelaDaNota.ler(markdown.split('\n'))!.markdown, markdown);
    });

    test('o alinhamento sobrevive a volta', () {
      const markdown = '| a | b |\n| :---: | ---: |\n|  |  |';
      expect(TabelaDaNota.ler(markdown.split('\n'))!.markdown, markdown);
    });

    test('a tabela vazia sai com as celulas em branco', () {
      expect(
        TabelaDaNota.vazia(linhas: 2, colunas: 2).markdown,
        '|  |  |\n| --- | --- |\n|  |  |',
      );
    });
  });

  group('mexendo na tabela', () {
    final base = TabelaDaNota.ler(['| a | b |', '| --- | --- |', '| c | d |'])!;

    test('escrever numa celula nao mexe nas outras', () {
      final nova = base.comCelula(1, 0, 'novo');
      expect(nova.celulas, [
        ['a', 'b'],
        ['novo', 'd'],
      ]);
    });

    test('barra digitada numa celula sobrevive a ida e volta', () {
      // Crua ela seria lida como divisao de coluna, e a celula viraria duas.
      final markdown = base.comCelula(1, 0, 'a | b').markdown;
      final devolta = TabelaDaNota.ler(markdown.split('\n'))!;

      expect(devolta.colunas, 2);
      expect(devolta.celulas[1][0], 'a | b');
    });

    test('quebra de linha colada numa celula vira espaço', () {
      // Uma quebra ali dentro desmancharia a tabela: no Markdown, uma linha
      // da tabela e uma linha do arquivo.
      final nova = base.comCelula(0, 0, 'dois\nvalores');
      expect(nova.celulas.first.first, 'dois valores');
    });

    test('linha nova entra vazia embaixo da escolhida', () {
      final nova = base.comLinhaDepoisDe(0);
      expect(nova.celulas, [
        ['a', 'b'],
        ['', ''],
        ['c', 'd'],
      ]);
    });

    test('coluna nova entra vazia e sem alinhamento', () {
      final nova = base.comColunaDepoisDe(0);
      expect(nova.celulas, [
        ['a', '', 'b'],
        ['c', '', 'd'],
      ]);
      expect(nova.alinhamentos.length, 3);
    });

    test('tirar linha e coluna', () {
      expect(base.semLinha(1).celulas, [
        ['a', 'b'],
      ]);
      expect(base.semColuna(0).celulas, [
        ['b'],
        ['d'],
      ]);
    });

    test('a ultima linha e a ultima coluna nao saem', () {
      // Sem cabeçalho nao ha tabela, e sem coluna nenhuma tambem nao.
      final so = TabelaDaNota.vazia(linhas: 1, colunas: 1);
      expect(so.semLinha(0).linhas, 1);
      expect(so.semColuna(0).colunas, 1);
    });
  });
}
