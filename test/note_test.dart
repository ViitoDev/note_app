import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/note.dart';

void main() {
  group('Note.parse', () {
    test('separa frontmatter do corpo', () {
      final note = Note.parse('/vault/consulta.md', '''
---
tipo: evento
data: 2026-08-10
hora: "14:00"
tags: [saude, medico]
---

# Consulta medica

Levar exames.
''');

      expect(note.tipo, 'evento');
      expect(note.frontmatter['data'], '2026-08-10');
      expect(note.frontmatter['hora'], '14:00');
      expect(note.frontmatter['tags'], ['saude', 'medico']);
      expect(note.body.trim(), startsWith('# Consulta medica'));
      expect(note.body, isNot(contains('tipo: evento')));
    });

    test('nota sem frontmatter mantem o texto inteiro no corpo', () {
      const raw = '# So um titulo\n\nCorpo da nota.';
      final note = Note.parse('/vault/simples.md', raw);

      expect(note.frontmatter, isEmpty);
      expect(note.body, raw);
    });

    test('aceita quebra de linha CRLF vinda do Windows', () {
      final note = Note.parse(
        '/vault/win.md',
        '---\r\ntipo: nota\r\n---\r\n\r\nCorpo.',
      );

      expect(note.tipo, 'nota');
      expect(note.body.trim(), 'Corpo.');
    });

    test('frontmatter malformado nao impede a nota de abrir', () {
      final note = Note.parse(
        '/vault/quebrado.md',
        '---\ntipo: [nao fechado\n---\n\nO texto tem que sobreviver.',
      );

      expect(note.frontmatter, isEmpty);
      expect(note.body, contains('O texto tem que sobreviver.'));
    });

    test(
      'tres tracos no meio do texto nao sao confundidos com frontmatter',
      () {
        const raw = 'Primeira linha.\n\n---\n\nDepois da linha horizontal.';
        final note = Note.parse('/vault/hr.md', raw);

        expect(note.frontmatter, isEmpty);
        expect(note.body, raw);
      },
    );

    test('title vem do nome do arquivo, sem a extensao', () {
      final note = Note.parse('/vault/Diario/2026-08-05.md', 'texto');
      expect(note.title, '2026-08-05');
    });
  });
}
