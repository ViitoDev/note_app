import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import 'app_theme.dart';
import 'resizable_split.dart';

/// Visao mensal do calendario, alimentada pelos eventos que vivem nas notas.
///
/// A tela nao le arquivos: recebe os eventos ja extraidos. Isso mantem a
/// leitura do vault num lugar so ([CalendarService]) e deixa a tela testavel
/// sem tocar em disco.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.events,
    required this.onOpenNote,
    required this.onRefresh,
    this.today,
  });

  final List<CalendarEvent> events;

  /// Abre a nota de origem de um evento.
  final ValueChanged<String> onOpenNote;

  final VoidCallback onRefresh;

  /// Injetavel para o teste nao depender do relogio real.
  final DateTime? today;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const _weekdayLabels = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
  static const _monthNames = [
    'janeiro',
    'fevereiro',
    'março',
    'abril',
    'maio',
    'junho',
    'julho',
    'agosto',
    'setembro',
    'outubro',
    'novembro',
    'dezembro',
  ];

  late DateTime _visibleMonth;
  DateTime? _selectedDay;

  DateTime get _today {
    final t = widget.today ?? DateTime.now();
    return DateTime(t.year, t.month, t.day);
  }

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(_today.year, _today.month);
    _selectedDay = _today;
  }

  Map<DateTime, List<CalendarEvent>> get _byDay =>
      EventParser.groupByDay(widget.events);

  void _shiftMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _goToToday() {
    setState(() {
      _visibleMonth = DateTime(_today.year, _today.month);
      _selectedDay = _today;
    });
  }

  /// Dias exibidos na grade: o mes inteiro mais o preenchimento das semanas
  /// nas pontas, sempre começando no domingo.
  List<DateTime> get _gridDays {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    // DateTime.weekday: segunda = 1 ... domingo = 7. A grade começa no domingo.
    final leading = first.weekday % 7;
    final start = first.subtract(Duration(days: leading));

    final lastDay = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final total = ((leading + lastDay) / 7).ceil() * 7;

    return List.generate(
      total,
      (i) => DateTime(start.year, start.month, start.day + i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDay = _byDay;

    // O corte e pela largura do proprio painel, e nao pela da janela: o mesmo
    // calendario ocupa a tela inteira numa aba e uma barra de 300px acoplado.
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = constraints.maxWidth;
        final compacto = largura < 560;
        final margem = compacto ? AppTheme.gapMd : AppTheme.gapXl;

        final calendar = Column(
          children: [
            _header(theme, compacto: compacto, margem: margem),
            _weekdayRow(theme, margem: margem),
            Expanded(
              child: _grid(theme, byDay, margem: margem, compacto: compacto),
            ),
          ],
        );

        // Sem largura para duas colunas, o painel do dia desce para baixo da
        // grade em vez de espremer as duas.
        if (largura < 900) {
          return ResizableSplit(
            axis: Axis.vertical,
            storageKey: 'calendario_v',
            initialSecond: 220,
            minFirst: 200,
            minSecond: 120,
            first: calendar,
            second: _dayPanel(theme, byDay, margem: margem),
          );
        }

        return ResizableSplit(
          storageKey: 'calendario',
          initialSecond: 320,
          minFirst: 380,
          minSecond: 240,
          first: calendar,
          second: _dayPanel(theme, byDay, margem: margem),
        );
      },
    );
  }

  Widget _header(
    ThemeData theme, {
    required bool compacto,
    required double margem,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        margem,
        compacto ? AppTheme.gapMd : AppTheme.gapLg,
        AppTheme.gapSm,
        AppTheme.gapMd,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              '${_monthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
              style: compacto
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: compacto ? AppTheme.gapXs : AppTheme.gapLg),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            tooltip: 'Mes anterior',
            visualDensity: VisualDensity.compact,
            onPressed: () => _shiftMonth(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            tooltip: 'Proximo mes',
            visualDensity: VisualDensity.compact,
            onPressed: () => _shiftMonth(1),
          ),
          // Num painel estreito sobram poucos pixels: fica so o essencial de
          // navegar o mes e recarregar.
          if (!compacto) ...[
            const SizedBox(width: AppTheme.gapXs),
            TextButton(onPressed: _goToToday, child: const Text('Hoje')),
            const Spacer(),
            Text(
              '${widget.events.length} evento(s) no vault',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(width: AppTheme.gapSm),
          ] else
            const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 17),
            tooltip: 'Reler o vault',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onRefresh,
          ),
        ],
      ),
    );
  }

  Widget _weekdayRow(ThemeData theme, {required double margem}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(margem, 0, margem, AppTheme.gapSm),
      child: Row(
        children: [
          for (final label in _weekdayLabels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(
    ThemeData theme,
    Map<DateTime, List<CalendarEvent>> byDay, {
    required double margem,
    required bool compacto,
  }) {
    final days = _gridDays;
    // Sempre multiplo de sete: a grade preenche as pontas das semanas.
    final linhas = days.length ~/ 7;
    const espaco = AppTheme.gapXs;

    return Padding(
      padding: EdgeInsets.fromLTRB(margem, 0, margem, margem),
      child: LayoutBuilder(
        builder: (context, c) {
          final larguraCelula = (c.maxWidth - espaco * 6) / 7;

          // O mes inteiro tem que caber sem rolar: um calendario em que se
          // rola para ver o fim do mes perde a coisa que ele faz de melhor,
          // que e mostrar o mes de uma vez. Entao a altura da celula sai do
          // espaço disponivel dividido pelas semanas — e nao da largura dela,
          // que nao sabe nada sobre a altura da tela.
          final porLinha = c.maxHeight.isFinite
              ? (c.maxHeight - espaco * (linhas - 1)) / linhas
              : double.infinity;

          // Abaixo deste ponto a celula fica ilegivel, e ai rolar e melhor do
          // que espremer. Numa barra estreita o piso e menor: la a celula ja e
          // so o numero do dia com um ponto.
          final minima = compacto ? 30.0 : 40.0;
          final cabe = porLinha.isFinite && porLinha >= minima;
          final alturaCelula = cabe ? porLinha : minima;

          return GridView.builder(
            // Sem rolagem quando cabe: uma grade que rola um pixel a toa
            // parece que tem mais mes escondido embaixo.
            physics: cabe ? const NeverScrollableScrollPhysics() : null,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: larguraCelula / alturaCelula,
              mainAxisSpacing: espaco,
              crossAxisSpacing: espaco,
            ),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              return _DayCell(
                day: day,
                events: byDay[day] ?? const [],
                isToday: day == _today,
                isSelected: day == _selectedDay,
                inMonth: day.month == _visibleMonth.month,
                onTap: () => setState(() => _selectedDay = day),
              );
            },
          );
        },
      ),
    );
  }

  Widget _dayPanel(
    ThemeData theme,
    Map<DateTime, List<CalendarEvent>> byDay, {
    required double margem,
  }) {
    final day = _selectedDay;
    if (day == null) {
      return const Center(child: Text('Escolha um dia'));
    }

    final scheme = theme.colorScheme;
    final events = byDay[day] ?? const <CalendarEvent>[];

    // Material, e nao Container: o ListTile pinta fundo e tinta de toque na
    // Material mais proxima, e um ColoredBox no meio esconderia os dois.
    return Material(
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              margem,
              AppTheme.gapLg,
              AppTheme.gapLg,
              AppTheme.gapMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${day.day} de ${_monthNames[day.month - 1]} de ${day.year}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  events.isEmpty
                      ? 'sem compromissos'
                      : '${events.length} compromisso(s)',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: events.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.gapXl),
                      child: Text(
                        'Nenhum evento neste dia.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.gapMd,
                      vertical: AppTheme.gapMd,
                    ),
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppTheme.gapSm),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.gapMd,
                            vertical: AppTheme.gapXs,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            side: BorderSide(color: scheme.outline),
                          ),
                          tileColor: scheme.surfaceContainerLow,
                          hoverColor: scheme.surfaceContainerHigh,
                          leading: Icon(
                            e.source == EventSource.frontmatter
                                ? Icons.event_note
                                : Icons.tag,
                            size: 17,
                            color: scheme.primary,
                          ),
                          title: Text(
                            e.title,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            e.timeLabel,
                            style: theme.textTheme.labelSmall,
                          ),
                          trailing: Icon(
                            Icons.north_east,
                            size: 14,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          onTap: () => widget.onOpenNote(e.noteId),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.events,
    required this.isToday,
    required this.isSelected,
    required this.inMonth,
    required this.onTap,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final bool isToday;
  final bool isSelected;
  final bool inMonth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Acoplado numa barra estreita a celula fica pequena demais para a lista
    // de eventos. Em vez de estourar, ela vira so o numero do dia com um ponto
    // avisando que ha algo marcado.
    return LayoutBuilder(
      builder: (context, c) {
        final apertada = c.maxHeight < 56;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              color: isSelected
                  ? scheme.primaryContainer
                  : inMonth
                  ? scheme.surfaceContainerLow
                  : null,
              border: Border.all(
                color: isSelected
                    ? scheme.primary.withValues(alpha: 0.6)
                    : scheme.outline.withValues(alpha: inMonth ? 1 : 0.4),
              ),
            ),
            padding: EdgeInsets.all(apertada ? 2 : AppTheme.gapSm),
            child: apertada
                ? _apertada(theme, scheme)
                : _completa(theme, scheme),
          ),
        );
      },
    );
  }

  /// Numero do dia e, se houver evento, um ponto embaixo.
  ///
  /// O [FittedBox] garante que nada estoure: por menor que a celula fique, o
  /// conteudo encolhe junto em vez de transbordar.
  Widget _apertada(ThemeData theme, ColorScheme scheme) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _disco(theme, scheme),
            if (events.isNotEmpty)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Hoje ganha um disco preenchido em vez de borda na celula: marca o dia sem
  /// competir com a borda da seleçao.
  Widget _disco(ThemeData theme, ColorScheme scheme) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isToday ? scheme.primary : Colors.transparent,
      ),
      child: Text(
        '${day.day}',
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 11.5,
          fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isToday
              ? scheme.onPrimary
              : isSelected
              ? scheme.onSurface
              : inMonth
              ? scheme.onSurfaceVariant
              : scheme.onSurfaceVariant.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  Widget _completa(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _disco(theme, scheme),
        const SizedBox(height: AppTheme.gapXs),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final e in events.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 3,
                        height: 3,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary.withValues(
                            alpha: e.isAllDay ? 0.5 : 1,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.isAllDay ? e.title : '${e.timeLabel} ${e.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10.5,
                            color: scheme.onSurface.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (events.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '+${events.length - 3}',
                    style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
