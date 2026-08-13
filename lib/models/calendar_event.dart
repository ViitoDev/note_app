import 'note.dart';

/// De onde o evento foi extraido — determina como ele e exibido e editado.
enum EventSource {
  /// Nota inteira com `tipo: evento` no frontmatter.
  frontmatter,

  /// Marcacao `📅AAAA-MM-DD HH:MM` no meio do texto de qualquer nota.
  inlineTag,
}

/// Um compromisso que vive dentro de uma nota `.md`.
///
/// Nao existe banco de eventos: o calendario e uma leitura do vault. Apagar a
/// linha da nota apaga o evento, e e por isso que [noteId] sempre aponta de
/// volta para o arquivo de origem.
class CalendarEvent implements Comparable<CalendarEvent> {
  const CalendarEvent({
    required this.noteId,
    required this.title,
    required this.date,
    required this.source,
    this.time,
  });

  /// Identidade da nota de origem, para abrir ao clicar no evento.
  final String noteId;

  final String title;

  /// Dia do evento, sempre normalizado para meia-noite.
  final DateTime date;

  /// Horario, quando informado. Eventos sem hora sao "o dia todo".
  final Duration? time;

  final EventSource source;

  bool get isAllDay => time == null;

  /// Data e hora combinadas, util para ordenar dentro do mesmo dia.
  DateTime get start => date.add(time ?? Duration.zero);

  String get timeLabel {
    final t = time;
    if (t == null) return 'dia todo';
    final h = t.inHours.toString().padLeft(2, '0');
    final m = (t.inMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Eventos com hora vem antes dos de dia todo? Nao: o dia todo vem primeiro,
  /// como em qualquer agenda, e o resto segue a ordem do relogio.
  @override
  int compareTo(CalendarEvent other) {
    if (isAllDay != other.isAllDay) return isAllDay ? -1 : 1;
    final byStart = start.compareTo(other.start);
    return byStart != 0 ? byStart : title.compareTo(other.title);
  }

  @override
  String toString() => 'CalendarEvent($title, $date, $timeLabel, $source)';
}

/// Le eventos a partir das notas do vault.
///
/// Duas convencoes, ambas descritas na spec:
///   * nota com `tipo: evento` e campos `data:` e `hora:` no frontmatter;
///   * marcacao `📅AAAA-MM-DD HH:MM` em qualquer lugar do texto.
///
/// Uma mesma nota pode produzir os dois tipos ao mesmo tempo.
abstract final class EventParser {
  /// `📅` seguido da data, com a hora opcional. O titulo e o resto da linha,
  /// que pode estar vazio — dai o fallback para o nome da nota.
  static final RegExp _inlinePattern = RegExp(
    r'📅\s*(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{1,2}):(\d{2}))?[ \t]*([^\r\n]*)',
  );

  /// So a marcaçao, sem o texto que vem depois dela.
  ///
  /// [_inlinePattern] engole o resto da linha para virar titulo do evento;
  /// aqui a intençao e o contrario — separar a data do texto e devolver os
  /// dois.
  static final RegExp _soAMarca = RegExp(
    r'📅\s*(\d{4})-(\d{2})-(\d{2})(?:\s+\d{1,2}:\d{2})?',
  );

  static List<CalendarEvent> fromNote(Note note) {
    return [..._fromFrontmatter(note), ..._fromInlineTags(note)];
  }

  /// Separa a data de uma linha solta do texto — a de uma tarefa, por exemplo.
  ///
  /// Devolve o texto sem a marcaçao, para quem exibe poder mostrar o prazo do
  /// jeito dele em vez de repetir `📅2026-08-09` no meio da frase. Linha sem
  /// marcaçao volta intacta.
  static ({DateTime? data, String texto}) extrairData(String linha) {
    final m = _soAMarca.firstMatch(linha);
    if (m == null) return (data: null, texto: linha.trim());

    final data = _buildDate(m.group(1), m.group(2), m.group(3));
    if (data == null) return (data: null, texto: linha.trim());

    final sobrou = linha.replaceRange(m.start, m.end, ' ');
    return (data: data, texto: sobrou.replaceAll(RegExp(r'\s+'), ' ').trim());
  }

  /// Varre um vault inteiro e devolve tudo agrupado por dia, ja ordenado.
  static Map<DateTime, List<CalendarEvent>> groupByDay(
    Iterable<CalendarEvent> events,
  ) {
    final grouped = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      grouped.putIfAbsent(event.date, () => []).add(event);
    }
    for (final list in grouped.values) {
      list.sort();
    }
    return grouped;
  }

  static Iterable<CalendarEvent> _fromFrontmatter(Note note) sync* {
    if (note.frontmatter['tipo'] != 'evento') return;

    final date = _parseDate(note.frontmatter['data']);
    if (date == null) return;

    yield CalendarEvent(
      noteId: note.id,
      title: note.title,
      date: date,
      time: _parseTime(note.frontmatter['hora']),
      source: EventSource.frontmatter,
    );
  }

  static Iterable<CalendarEvent> _fromInlineTags(Note note) sync* {
    for (final match in _inlinePattern.allMatches(note.body)) {
      final date = _buildDate(match.group(1), match.group(2), match.group(3));
      if (date == null) continue;

      final hour = int.tryParse(match.group(4) ?? '');
      final minute = int.tryParse(match.group(5) ?? '');
      final time = (hour != null && minute != null && _validTime(hour, minute))
          ? Duration(hours: hour, minutes: minute)
          : null;

      final rest = (match.group(6) ?? '').trim();
      yield CalendarEvent(
        noteId: note.id,
        title: rest.isEmpty ? note.title : rest,
        date: date,
        time: time,
        source: EventSource.inlineTag,
      );
    }
  }

  /// O YAML entrega `data:` ora como String, ora ja como DateTime — depende de
  /// o valor estar entre aspas no arquivo.
  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }
    if (value is! String) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
    if (match == null) return null;
    return _buildDate(match.group(1), match.group(2), match.group(3));
  }

  static DateTime? _buildDate(String? y, String? m, String? d) {
    final year = int.tryParse(y ?? '');
    final month = int.tryParse(m ?? '');
    final day = int.tryParse(d ?? '');
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final date = DateTime(year, month, day);
    // Rejeita datas que o DateTime "conserta" sozinho, como 31 de fevereiro.
    if (date.month != month || date.day != day) return null;
    return date;
  }

  /// Aceita `14:00`, `9:30` e tambem o formato que o YAML converte em numero
  /// quando a hora nao esta entre aspas.
  static Duration? _parseTime(dynamic value) {
    if (value == null) return null;

    final text = value is String ? value.trim() : value.toString();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return null;

    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (!_validTime(hour, minute)) return null;
    return Duration(hours: hour, minutes: minute);
  }

  static bool _validTime(int hour, int minute) =>
      hour >= 0 && hour < 24 && minute >= 0 && minute < 60;
}
