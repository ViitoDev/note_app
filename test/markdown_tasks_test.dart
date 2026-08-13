import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/markdown_tasks.dart';

void main() {
  group('contar', () {
    test('conta as caixas de tarefa', () {
      expect(MarkdownTasks.contar('- [ ] Um\n- [x] Dois\n- [ ] Tres'), 3);
    });

    test('aceita os tres marcadores de lista e os numerados', () {
      expect(
        MarkdownTasks.contar('- [ ] a\n* [ ] b\n+ [ ] c\n1. [ ] d\n2) [ ] e'),
        5,
      );
    });

    test('lista comum nao e tarefa', () {
      expect(MarkdownTasks.contar('- Um\n- Dois'), 0);
    });

    test('colchete sem espaço depois nao e tarefa', () {
      // E o mesmo criterio do parser do preview: sem o espaço ele desenha
      // texto, nao caixa — e contar aqui desalinharia os indices.
      expect(MarkdownTasks.contar('- [x]colado'), 0);
    });

    test('ignora o que esta dentro de bloco de codigo', () {
      const texto = '- [ ] Real\n\n```\n- [ ] Exemplo\n```\n\n- [x] Outra';

      // O preview nao desenha caixa dentro de codigo; contar a do exemplo
      // faria todo clique depois dela mexer na linha errada.
      expect(MarkdownTasks.contar(texto), 2);
    });
  });

  group('alternar', () {
    test('marca uma tarefa vazia', () {
      expect(MarkdownTasks.alternar('- [ ] Um', 0), '- [x] Um');
    });

    test('desmarca uma tarefa feita', () {
      expect(MarkdownTasks.alternar('- [x] Um', 0), '- [ ] Um');
      expect(MarkdownTasks.alternar('- [X] Um', 0), '- [ ] Um');
    });

    test('mexe so na tarefa do indice pedido', () {
      const texto = '- [ ] Um\n- [ ] Dois\n- [ ] Tres';

      expect(
        MarkdownTasks.alternar(texto, 1),
        '- [ ] Um\n- [x] Dois\n- [ ] Tres',
      );
    });

    test('preserva indentaçao e marcador da linha', () {
      expect(
        MarkdownTasks.alternar('    2) [ ] Aninhada', 0),
        '    2) [ ] Aninhada'.replaceFirst('[ ]', '[x]'),
      );
    });

    test('indice fora da conta devolve o texto intacto', () {
      // Acontece se o arquivo mudar por fora entre o desenho e o clique;
      // reescrever a linha errada seria pior do que nao fazer nada.
      const texto = '- [ ] Um';
      expect(MarkdownTasks.alternar(texto, 5), texto);
      expect(MarkdownTasks.alternar(texto, -1), texto);
    });

    test('o indice pula o bloco de codigo, como a contagem', () {
      const texto = '- [ ] Real\n\n```\n- [ ] Exemplo\n```\n\n- [ ] Outra';

      expect(
        MarkdownTasks.alternar(texto, 1),
        '- [ ] Real\n\n```\n- [ ] Exemplo\n```\n\n- [x] Outra',
      );
    });

    test('nao mexe no resto do texto', () {
      const texto = '# Titulo\n\nParagrafo com [link](x).\n\n- [ ] Tarefa\n';

      expect(
        MarkdownTasks.alternar(texto, 0),
        '# Titulo\n\nParagrafo com [link](x).\n\n- [x] Tarefa\n',
      );
    });

    test('o tamanho do texto nao muda', () {
      // E o que deixa a posiçao do cursor no editor continuar valendo.
      const texto = '- [ ] Um\n- [x] Dois';
      expect(MarkdownTasks.alternar(texto, 0).length, texto.length);
      expect(MarkdownTasks.alternar(texto, 1).length, texto.length);
    });
  });
}
