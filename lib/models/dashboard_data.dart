import 'package:flutter/foundation.dart';

import 'calendar_event.dart';
import 'kanban_card.dart';
import 'markdown_tasks.dart';
import 'note.dart';
import 'vault_graph.dart';

/// Uma caixa `- [ ]` ainda nao marcada, com a nota de onde ela saiu.
///
/// O indice e o mesmo que [MarkdownTasks.alternar] usa, e e o que permite
/// marcar a tarefa daqui sem abrir a nota: o painel reescreve a linha no
/// arquivo, como o preview faz.
@immutable
class TarefaAberta {
  const TarefaAberta({
    required this.noteId,
    required this.nota,
    required this.indice,
    required this.texto,
    this.prazo,
  });

  final String noteId;

  /// Titulo da nota, para a tarefa nao aparecer solta na lista.
  final String nota;

  final int indice;
  final String texto;

  /// Data da marcaçao `📅` na propria linha, quando houver. E o que faz uma
  /// tarefa ter dia certo em vez de so estar aberta.
  final DateTime? prazo;
}

/// Tudo que o painel mostra, apurado de uma varredura so do vault.
///
/// O painel junta o que as outras abas mostram separado, entao ler o vault uma
/// vez por elemento seria ler o vault quatro vezes. Aqui as notas passam uma
/// unica vez e cada leitura tira dali o que lhe interessa.
///
/// Nada disso e guardado: como no calendario e no quadro, o `.md` continua
/// sendo a unica fonte da verdade e o painel e so uma leitura dele.
@immutable
class DashboardData {
  const DashboardData({
    required this.hoje,
    required this.eventos,
    required this.board,
    required this.grafo,
    required this.tarefas,
    required this.tags,
    required this.totalNotas,
    required this.tarefasFeitas,
  });

  /// Estado inicial, antes da primeira leitura do vault.
  ///
  /// Nasce com a data de hoje, e nao com uma data qualquer: o cabeçalho do
  /// painel mostra o dia por extenso, e um placeholder apareceria na tela como
  /// "1 de janeiro de 2000" no instante entre montar e ler.
  factory DashboardData.vazia() =>
      DashboardData.build(const [], agora: DateTime.now());

  /// Meia-noite do dia em que o painel foi montado.
  final DateTime hoje;

  /// Todos os eventos do vault, ja ordenados.
  final List<CalendarEvent> eventos;

  final KanbanBoard board;

  /// O mesmo grafo da aba de grafo. Sai desta varredura em vez de uma segunda
  /// leitura do vault — as notas ja estao na mao aqui.
  final VaultGraph grafo;

  /// So as tarefas abertas: as feitas viram numero em [tarefasFeitas].
  final List<TarefaAberta> tarefas;

  /// Quantas notas usam cada tag, da mais usada para a menos.
  final Map<String, int> tags;

  final int totalNotas;
  final int tarefasFeitas;

  // ------------------------------------------------------------------- o dia

  List<CalendarEvent> get eventosDeHoje => [
    for (final e in eventos)
      if (e.date == hoje) e,
  ];

  /// Os proximos sete dias, sem contar hoje — o "vem por ai" da semana.
  List<CalendarEvent> get eventosDaSemana {
    final limite = hoje.add(const Duration(days: 7));
    return [
      for (final e in eventos)
        if (e.date.isAfter(hoje) && !e.date.isAfter(limite)) e,
    ];
  }

  List<TarefaAberta> get tarefasDeHoje => [
    for (final t in tarefas)
      if (t.prazo == hoje) t,
  ];

  List<TarefaAberta> get tarefasAtrasadas => [
    for (final t in tarefas)
      if (t.prazo != null && t.prazo!.isBefore(hoje)) t,
  ];

  /// Tarefa sem `📅` nao tem dia: ela e pendencia, nao compromisso.
  List<TarefaAberta> get tarefasSemPrazo => [
    for (final t in tarefas)
      if (t.prazo == null) t,
  ];

  /// Card com prazo hoje que ainda nao foi entregue.
  List<KanbanCard> get cardsDeHoje => [
    for (final c in _cardsPendentes)
      if (c.prazo == hoje) c,
  ];

  List<KanbanCard> get cardsAtrasados => [
    for (final c in _cardsPendentes)
      if (c.prazo != null && c.prazo!.isBefore(hoje)) c,
  ];

  List<KanbanCard> get emAndamento => board.of(KanbanColumn.fazendo);

  /// Um card pronto nao esta atrasado: ele foi entregue, mesmo que tarde.
  Iterable<KanbanCard> get _cardsPendentes =>
      board.todos.where((c) => c.coluna != KanbanColumn.pronto);

  int get totalDeHoje =>
      eventosDeHoje.length + tarefasDeHoje.length + cardsDeHoje.length;

  int get totalAtrasado => tarefasAtrasadas.length + cardsAtrasados.length;

  /// Nada marcado para hoje e nada vencido.
  bool get diaLimpo => totalDeHoje == 0 && totalAtrasado == 0;

  /// Sem vault lido ainda, ou com um vault que nao tem nada dentro.
  bool get semNada => totalNotas == 0;

  int get totalTarefas => tarefas.length + tarefasFeitas;

  // ---------------------------------------------------------------- montagem

  /// Apura tudo a partir das notas do vault.
  ///
  /// [agora] entra por parametro para o teste poder fixar o dia — um painel de
  /// "hoje" que le o relogio la dentro so daria para testar por algumas horas.
  factory DashboardData.build(Iterable<Note> notas, {required DateTime agora}) {
    final hoje = DateTime(agora.year, agora.month, agora.day);

    final crus = <CalendarEvent>[];
    final tarefas = <TarefaAberta>[];
    final tags = <String, int>{};

    // Linhas que ja entraram como tarefa. Uma linha `- [ ] 📅2026-08-09 Ler` e
    // as duas coisas para o parser: tarefa pela caixa, evento pela data. No
    // calendario isso e o certo — ela tem dia marcado. Aqui nao: o painel
    // mostraria o mesmo texto na agenda e na lista de tarefas, e so uma das
    // duas copias teria caixa para marcar.
    final jaSaoTarefa = <String>{};

    var total = 0;
    var feitas = 0;

    for (final nota in notas) {
      total++;
      crus.addAll(EventParser.fromNote(nota));

      for (final tag in TagParser.fromNote(nota)) {
        tags[tag] = (tags[tag] ?? 0) + 1;
      }

      for (final t in MarkdownTasks.listar(nota.body)) {
        final linha = EventParser.extrairData(t.texto);
        if (linha.data != null) {
          jaSaoTarefa.add(_chave(nota.id, linha.data!, linha.texto));
        }
        if (t.feita) {
          feitas++;
          continue;
        }
        tarefas.add(
          TarefaAberta(
            noteId: nota.id,
            nota: nota.title,
            indice: t.indice,
            // Caixa sem texto nenhum ainda e uma tarefa; sem o rotulo da nota
            // ela viraria uma linha em branco na lista.
            texto: linha.texto.isEmpty ? nota.title : linha.texto,
            prazo: linha.data,
          ),
        );
      }
    }

    final eventos = [
      for (final e in crus)
        if (e.source != EventSource.inlineTag ||
            !jaSaoTarefa.contains(_chave(e.noteId, e.date, e.title)))
          e,
    ]..sort();
    tarefas.sort(_porPrazo);

    return DashboardData(
      hoje: hoje,
      eventos: eventos,
      board: KanbanBoard.build(notas),
      grafo: VaultGraph.build(notas),
      tarefas: tarefas,
      tags: Map.fromEntries(
        tags.entries.toList()..sort((a, b) {
          final porUso = b.value.compareTo(a.value);
          return porUso != 0 ? porUso : a.key.compareTo(b.key);
        }),
      ),
      totalNotas: total,
      tarefasFeitas: feitas,
    );
  }

  /// Identifica uma linha datada: mesma nota, mesmo dia, mesmo texto.
  static String _chave(String noteId, DateTime dia, String texto) =>
      '$noteId|${dia.toIso8601String()}|$texto';

  /// Quem tem dia marcado vem antes, do mais antigo ao mais distante; o resto
  /// segue por nota e pela ordem em que aparece no arquivo.
  static int _porPrazo(TarefaAberta a, TarefaAberta b) {
    if ((a.prazo == null) != (b.prazo == null)) return a.prazo == null ? 1 : -1;
    if (a.prazo != null) {
      final porData = a.prazo!.compareTo(b.prazo!);
      if (porData != 0) return porData;
    }
    final porNota = a.nota.toLowerCase().compareTo(b.nota.toLowerCase());
    return porNota != 0 ? porNota : a.indice.compareTo(b.indice);
  }
}
