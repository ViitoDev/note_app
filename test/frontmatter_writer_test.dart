import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/frontmatter_writer.dart';

void main() {
  group('definir', () {
    test('troca so a linha do campo', () {
      expect(
        FrontmatterWriter.definir(
          '---\ntipo: nota\nstatus: a-fazer\n---\n\nCorpo\n',
          'status',
          'fazendo',
        ),
        '---\ntipo: nota\nstatus: fazendo\n---\n\nCorpo\n',
      );
    });

    test('campo novo entra antes do fechamento', () {
      expect(
        FrontmatterWriter.definir(
          '---\ntipo: nota\n---\n\nCorpo\n',
          'hora',
          '9:30',
        ),
        '---\ntipo: nota\nhora: 9:30\n---\n\nCorpo\n',
      );
    });

    test('nota sem frontmatter ganha o bloco', () {
      expect(
        FrontmatterWriter.definir('Corpo\n', 'tipo', 'evento'),
        '---\ntipo: evento\n---\n\nCorpo\n',
      );
    });
  });

  group('remover', () {
    test('tira a linha e deixa o resto como estava', () {
      expect(
        FrontmatterWriter.remover(
          '---\ntipo: nota\n# um comentario\ndata: 2026-08-10\n---\n\nCorpo\n',
          'data',
        ),
        '---\ntipo: nota\n# um comentario\n---\n\nCorpo\n',
      );
    });

    test('campo que nao existe nao mexe no texto', () {
      const texto = '---\ntipo: nota\n---\n\nCorpo\n';
      expect(FrontmatterWriter.remover(texto, 'status'), texto);
    });

    test('nota sem frontmatter volta intacta', () {
      expect(FrontmatterWriter.remover('Corpo\n', 'status'), 'Corpo\n');
    });

    test('bloco que ficaria vazio sai inteiro', () {
      // `---` seguido de `---` nao e metadado nenhum, e a linha em branco que
      // separava o bloco do texto vai junto.
      expect(
        FrontmatterWriter.remover(
          '---\nstatus: pronto\n---\n\nCorpo\n',
          'status',
        ),
        'Corpo\n',
      );
    });

    test('preserva CRLF', () {
      expect(
        FrontmatterWriter.remover(
          '---\r\ntipo: nota\r\nhora: 9:30\r\n---\r\n\r\nCorpo\r\n',
          'hora',
        ),
        '---\r\ntipo: nota\r\n---\r\n\r\nCorpo\r\n',
      );
    });

    test('campo de nome parecido nao e levado junto', () {
      expect(
        FrontmatterWriter.remover(
          '---\ndata: 2026-08-10\ndata_final: 2026-08-20\n---\n\nCorpo\n',
          'data',
        ),
        '---\ndata_final: 2026-08-20\n---\n\nCorpo\n',
      );
    });
  });
}
