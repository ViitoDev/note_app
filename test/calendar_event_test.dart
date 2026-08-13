import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/calendar_event.dart';
import 'package:notas_app/models/note.dart';

Note _note(String id, String raw) => Note.parse(id, raw);

void main() {
  group('frontmatter tipo: evento', () {
    test('extrai data e hora', () {
      final events = EventParser.fromNote(
        _note('/v/Consulta.md', '''
---
tipo: evento
data: 2026-08-10
hora: "14:00"
---

Levar exames.
'''),
      );

      expect(events, hasLength(1));
      final e = events.single;
      expect(e.title, 'Consulta');
      expect(e.date, DateTime(2026, 8, 10));
      expect(e.timeLabel, '14:00');
      expect(e.isAllDay, isFalse);
      expect(e.source, EventSource.frontmatter);
      expect(e.noteId, '/v/Consulta.md');
    });

    test('sem hora vira evento de dia todo', () {
      final events = EventParser.fromNote(
        _note('/v/Feriado.md', '---\ntipo: evento\ndata: 2026-09-07\n---\n'),
      );

      expect(events.single.isAllDay, isTrue);
      expect(events.single.timeLabel, 'dia todo');
    });

    test('aceita data que o YAML converteu em DateTime', () {
      // Sem aspas, o parser YAML entrega um DateTime em vez de String.
      final events = EventParser.fromNote(
        _note('/v/N.md', '---\ntipo: evento\ndata: 2026-08-10\n---\n'),
      );
      expect(events.single.date, DateTime(2026, 8, 10));
    });

    test('nota comum nao gera evento', () {
      final events = EventParser.fromNote(
        _note('/v/N.md', '---\ntipo: nota\ndata: 2026-08-10\n---\n'),
      );
      expect(events, isEmpty);
    });

    test('tipo evento sem data e ignorado em vez de quebrar', () {
      final events = EventParser.fromNote(
        _note('/v/N.md', '---\ntipo: evento\n---\n'),
      );
      expect(events, isEmpty);
    });

    test('data impossivel e rejeitada', () {
      final events = EventParser.fromNote(
        _note('/v/N.md', '---\ntipo: evento\ndata: "2026-02-31"\n---\n'),
      );
      expect(events, isEmpty);
    });

    test('hora invalida degrada para dia todo', () {
      final events = EventParser.fromNote(
        _note(
          '/v/N.md',
          '---\ntipo: evento\ndata: "2026-08-10"\nhora: "99:99"\n---\n',
        ),
      );
      expect(events.single.isAllDay, isTrue);
    });
  });

  group('tag inline', () {
    test('extrai data, hora e titulo do resto da linha', () {
      final events = EventParser.fromNote(
        _note(
          '/v/Projeto.md',
          'Reuniao com o time 📅2026-08-12 09:30 sobre o roadmap.',
        ),
      );

      expect(events, hasLength(1));
      final e = events.single;
      expect(e.date, DateTime(2026, 8, 12));
      expect(e.timeLabel, '09:30');
      expect(e.title, 'sobre o roadmap.');
      expect(e.source, EventSource.inlineTag);
    });

    test('sem texto depois da marcacao usa o nome da nota', () {
      final events = EventParser.fromNote(
        _note('/v/Dentista.md', 'Lembrete: 📅2026-08-12 09:30'),
      );
      expect(events.single.title, 'Dentista');
    });

    test('varias marcacoes na mesma nota viram varios eventos', () {
      final events = EventParser.fromNote(
        _note(
          '/v/N.md',
          '📅2026-08-12 09:30 primeira\n\n📅2026-08-13 10:00 segunda',
        ),
      );
      expect(events, hasLength(2));
      expect(events.map((e) => e.title), ['primeira', 'segunda']);
    });

    test('marcacao sem hora vale como dia todo', () {
      final events = EventParser.fromNote(
        _note('/v/N.md', '📅2026-08-12 entrega'),
      );
      expect(events.single.isAllDay, isTrue);
      expect(events.single.title, 'entrega');
    });

    test('marcacao no frontmatter nao conta, so no corpo', () {
      final events = EventParser.fromNote(
        _note(
          '/v/N.md',
          '---\nnota: "📅2026-08-12 nao conta"\n---\n\nCorpo limpo.',
        ),
      );
      expect(events, isEmpty);
    });
  });

  test('nota pode ter frontmatter e tag inline ao mesmo tempo', () {
    final events = EventParser.fromNote(
      _note(
        '/v/N.md',
        '---\ntipo: evento\ndata: "2026-08-10"\n---\n\nE tambem 📅2026-08-11 outra coisa',
      ),
    );

    expect(events, hasLength(2));
    expect(events.map((e) => e.source), [
      EventSource.frontmatter,
      EventSource.inlineTag,
    ]);
  });

  group('agrupamento por dia', () {
    test('agrupa e ordena com dia todo primeiro', () {
      final dia = DateTime(2026, 8, 10);
      final eventos = [
        CalendarEvent(
          noteId: 'a',
          title: 'tarde',
          date: dia,
          time: const Duration(hours: 15),
          source: EventSource.inlineTag,
        ),
        CalendarEvent(
          noteId: 'b',
          title: 'manha',
          date: dia,
          time: const Duration(hours: 9),
          source: EventSource.inlineTag,
        ),
        CalendarEvent(
          noteId: 'c',
          title: 'dia todo',
          date: dia,
          source: EventSource.frontmatter,
        ),
      ];

      final grupos = EventParser.groupByDay(eventos);
      expect(grupos.keys, [dia]);
      expect(grupos[dia]!.map((e) => e.title), ['dia todo', 'manha', 'tarde']);
    });

    test('dias diferentes ficam em chaves diferentes', () {
      final grupos = EventParser.groupByDay([
        CalendarEvent(
          noteId: 'a',
          title: 'x',
          date: DateTime(2026, 8, 10),
          source: EventSource.frontmatter,
        ),
        CalendarEvent(
          noteId: 'b',
          title: 'y',
          date: DateTime(2026, 8, 11),
          source: EventSource.frontmatter,
        ),
      ]);
      expect(grupos, hasLength(2));
    });
  });
}
