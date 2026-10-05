import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/blocos_da_nota.dart';

/// Confere que cada bloco aponta para o pedaço certo do corpo — e disso que o
/// editor depende para trocar so o trecho mexido.
void _offsetsBatem(String corpo) {
  for (final bloco in BlocosDaNota.de(corpo)) {
    expect(bloco.inicio, lessThanOrEqualTo(bloco.fim), reason: corpo);
    if (bloco is BlocoDeTexto) {
      expect(corpo.substring(bloco.inicio, bloco.fim), bloco.texto);
    }
  }
}

void main() {
  test('nota sem tabela e um bloco de texto so', () {
    const corpo = '# Titulo\n\nUm paragrafo.\n';
    final blocos = BlocosDaNota.de(corpo);

    expect(blocos.length, 1);
    expect((blocos.single as BlocoDeTexto).texto, corpo);
  });

  test('nota vazia continua tendo onde escrever', () {
    final blocos = BlocosDaNota.de('');
    expect(blocos.single, isA<BlocoDeTexto>());
  });

  test('a tabela sai separada do texto de cima e do de baixo', () {
    const corpo =
        'Antes\n\n'
        '| a | b |\n'
        '| --- | --- |\n'
        '| c | d |\n'
        '\nDepois\n';

    final blocos = BlocosDaNota.de(corpo);

    expect(blocos.length, 3);
    // A linha em branco que separa a tabela do texto fica no arquivo, mas nao
    // vira uma linha vazia no campo.
    expect((blocos[0] as BlocoDeTexto).texto, 'Antes');
    expect((blocos[1] as BlocoDeTabela).tabela.celulas, [
      ['a', 'b'],
      ['c', 'd'],
    ]);
    expect((blocos[2] as BlocoDeTexto).texto, '\nDepois\n');
    _offsetsBatem(corpo);
  });

  test('o trecho da tabela e exatamente as linhas dela', () {
    const corpo = 'Antes\n| a |\n| --- |\n| c |\ndepois';
    final tabela = BlocosDaNota.de(corpo).whereType<BlocoDeTabela>().single;

    expect(corpo.substring(tabela.inicio, tabela.fim), '| a |\n| --- |\n| c |');
  });

  test('tabela dentro de bloco de codigo fica no codigo', () {
    // Ali ela esta sendo mostrada como exemplo; desenha-la apagaria o exemplo.
    const corpo = '```\n| a | b |\n| --- | --- |\n```\n';
    final blocos = BlocosDaNota.de(corpo);

    expect(blocos.whereType<BlocoDeTabela>(), isEmpty);
    expect(
      blocos.whereType<BlocoDeCodigo>().single.codigo,
      '| a | b |\n| --- | --- |',
    );
  });

  group('bloco de codigo', () {
    test('vira balao, com a linguagem e o codigo separados', () {
      const corpo = 'Antes\n\n``` Java\nint a;\nint b;\n```\n\nDepois';
      final blocos = BlocosDaNota.de(corpo);
      final codigo = blocos.whereType<BlocoDeCodigo>().single;

      expect(codigo.linguagem, 'Java');
      expect(codigo.codigo, 'int a;\nint b;');
      expect(
        corpo.substring(codigo.inicio, codigo.fim),
        '``` Java\nint a;\nint b;\n```',
      );
      expect(codigo.markdown, corpo.substring(codigo.inicio, codigo.fim));
      _offsetsBatem(corpo);
    });

    test('sem fechamento continua texto', () {
      // O resto da nota nao pode ser engolido por um bloco pela metade.
      const corpo = '```python\nprint(1)\ncontinua';
      expect(BlocosDaNota.de(corpo).whereType<BlocoDeCodigo>(), isEmpty);
    });

    test('quatro crases mostram tres dentro', () {
      const corpo = '````\n```py\nx\n```\n````\nfim';
      final codigo = BlocosDaNota.de(corpo).whereType<BlocoDeCodigo>().single;
      expect(codigo.codigo, '```py\nx\n```');
    });

    test('bloco vazio volta ao arquivo sem linha em branco', () {
      const corpo = '```py\n```';
      final codigo = BlocosDaNota.de(corpo).whereType<BlocoDeCodigo>().single;
      expect(codigo.codigo, '');
      expect(codigo.markdown, corpo);
    });

    test('trocar a linguagem mantem a cerca como foi escrita', () {
      const corpo = '~~~~ py\nx = 1\n~~~~';
      final codigo = BlocosDaNota.de(corpo).whereType<BlocoDeCodigo>().single;
      expect(codigo.comLinguagem('python').markdown, '~~~~python\nx = 1\n~~~~');
    });

    test('dois blocos seguidos saem separados', () {
      const corpo = '```a\n1\n```\n\n```b\n2\n```';
      final codigos = BlocosDaNota.de(
        corpo,
      ).whereType<BlocoDeCodigo>().toList();
      expect(codigos.map((c) => c.linguagem), ['a', 'b']);
      _offsetsBatem(corpo);
    });
  });

  test('tabela no fim da nota, sem quebra depois', () {
    const corpo = 'Antes\n\n| a |\n| --- |';
    final blocos = BlocosDaNota.de(corpo);

    expect(blocos.whereType<BlocoDeTabela>().length, 1);
    // O ultimo bloco de texto sai vazio, e e onde se clica para escrever
    // embaixo da tabela.
    expect((blocos.last as BlocoDeTexto).texto, isEmpty);
    _offsetsBatem(corpo);
  });

  test('tabela no começo da nota', () {
    const corpo = '| a |\n| --- |\n\nDepois';
    final blocos = BlocosDaNota.de(corpo);

    expect((blocos.first as BlocoDeTexto).texto, isEmpty);
    expect(blocos[1], isA<BlocoDeTabela>());
    _offsetsBatem(corpo);
  });

  test('duas tabelas, com texto no meio', () {
    const corpo = '| a |\n| --- |\n\nmeio\n\n| b |\n| --- |\n\nfim';
    final blocos = BlocosDaNota.de(corpo);

    expect(blocos.whereType<BlocoDeTabela>().length, 2);
    expect((blocos[2] as BlocoDeTexto).texto, 'meio');
    _offsetsBatem(corpo);
  });

  test('tabela colada no texto sai sem linha em branco em volta', () {
    const corpo = 'Operadores:\n| a |\n| --- |\n| c |\n## Exemplos\n';
    final blocos = BlocosDaNota.de(corpo);

    expect((blocos[0] as BlocoDeTexto).texto, 'Operadores:');
    expect((blocos[2] as BlocoDeTexto).texto, '## Exemplos\n');
    _offsetsBatem(corpo);
  });

  test('a quebra que e a unica entre dois desenhados continua no campo', () {
    // Tirada, o campo do meio ficaria vazio, e o que se escrevesse nele
    // grudaria na tabela ou na cerca do codigo.
    const corpo = '| a |\n| --- |\n```\nx\n```';
    final blocos = BlocosDaNota.de(corpo);

    expect(blocos[1], isA<BlocoDeTabela>());
    expect(blocos[3], isA<BlocoDeCodigo>());
    expect((blocos[2] as BlocoDeTexto).texto, '\n');
    _offsetsBatem(corpo);
  });

  test('linha em branco entre duas tabelas vira campo vazio entre elas', () {
    const corpo = '| a |\n| --- |\n\n| b |\n| --- |';
    final blocos = BlocosDaNota.de(corpo);

    expect(blocos.whereType<BlocoDeTabela>().length, 2);
    expect((blocos[2] as BlocoDeTexto).texto, '');
    // Escrever ali cai entre as duas quebras, em linha propria.
    expect(blocos[2].inicio, corpo.indexOf('\n\n') + 1);
    _offsetsBatem(corpo);
  });

  test('titulo escrito com tracinhos nao vira tabela', () {
    const corpo = 'Titulo | com barra\n---\n';
    expect(BlocosDaNota.de(corpo).whereType<BlocoDeTabela>(), isEmpty);
  });

  group('quadro', () {
    const bloco =
        '```quadro\n'
        '{"nos":[\n'
        '{"id":"n1","forma":"terminal","x":0,"y":0,'
        '"largura":120,"altura":48,"texto":"Inicio"}\n'
        '],"ligacoes":[\n'
        ']}\n'
        '```';

    test('o quadro sai separado do texto de cima e do de baixo', () {
      const corpo = 'Antes\n\n$bloco\n\nDepois\n';
      final blocos = BlocosDaNota.de(corpo);

      expect(blocos.length, 3);
      expect((blocos[0] as BlocoDeTexto).texto, 'Antes');
      expect((blocos[1] as BlocoDeQuadro).quadro.nos.single.texto, 'Inicio');
      expect((blocos[2] as BlocoDeTexto).texto, 'Depois\n');
      _offsetsBatem(corpo);
    });

    test('o trecho do quadro e o bloco inteiro, cercas inclusive', () {
      const corpo = 'Antes\n\n$bloco\n\nDepois\n';
      final quadro = BlocosDaNota.de(corpo).whereType<BlocoDeQuadro>().single;

      expect(corpo.substring(quadro.inicio, quadro.fim), bloco);
    });

    test('quadro vazio continua sendo quadro', () {
      const corpo = '```quadro\n```\n';
      final quadro = BlocosDaNota.de(corpo).whereType<BlocoDeQuadro>().single;

      expect(quadro.quadro.semNada, isTrue);
    });

    test('bloco estragado fica como texto, para poder ser consertado', () {
      const corpo = '```quadro\nnao sou json\n```\n';
      final blocos = BlocosDaNota.de(corpo);

      expect(blocos.whereType<BlocoDeQuadro>(), isEmpty);
      expect((blocos.single as BlocoDeTexto).texto, corpo);
    });

    test('cerca sem fechamento ainda nao e quadro', () {
      // Enquanto a cerca de baixo nao for escrita o bloco esta pela metade, e
      // o resto da nota nao pode ser engolido por ele.
      const corpo = '```quadro\n{"nos":[]}\ncontinua a nota\n';
      expect(BlocosDaNota.de(corpo).whereType<BlocoDeQuadro>(), isEmpty);
    });

    test('quadro dentro de bloco de codigo continua sendo texto', () {
      // Ali ele esta sendo mostrado como exemplo de sintaxe.
      const corpo = '````\n```quadro\n{"nos":[]}\n```\n````\n';
      expect(BlocosDaNota.de(corpo).whereType<BlocoDeQuadro>(), isEmpty);
    });

    test('quadro e tabela convivem na mesma nota', () {
      const corpo = '$bloco\n\n| a |\n| --- |\n\nfim';
      final blocos = BlocosDaNota.de(corpo);

      expect(blocos.whereType<BlocoDeQuadro>().length, 1);
      expect(blocos.whereType<BlocoDeTabela>().length, 1);
      _offsetsBatem(corpo);
    });

    test('dois quadros saem na ordem do texto', () {
      const corpo = '$bloco\n\nmeio\n\n```quadro\n```\n';
      final quadros = BlocosDaNota.de(
        corpo,
      ).whereType<BlocoDeQuadro>().toList();

      expect(quadros.length, 2);
      expect(quadros.first.quadro.nos.length, 1);
      expect(quadros.last.quadro.semNada, isTrue);
      _offsetsBatem(corpo);
    });
  });
}
