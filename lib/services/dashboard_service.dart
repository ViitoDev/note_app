import '../models/dashboard_data.dart';
import '../models/markdown_tasks.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import '../repositories/vault_repository.dart';
import 'calendar_service.dart';

/// Monta o painel lendo o vault inteiro.
///
/// Como o calendario, o grafo e o quadro, nao guarda indice: a cada abertura o
/// vault e relido. A diferença e que aqui a varredura vale por quatro — o
/// painel mostra evento, card, tarefa e tag de uma vez, e todos saem da mesma
/// passada pelas notas.
class DashboardService {
  const DashboardService(this._repository);

  final VaultRepository _repository;

  Future<DashboardData> build(VaultFolder root, {DateTime? agora}) async {
    final notas = <Note>[];
    for (final file in CalendarService.filesIn(root)) {
      try {
        notas.add(await _repository.readNote(file.id));
      } on Exception {
        // Nota ilegivel nao derruba o painel; ela so nao contribui com nada.
        continue;
      }
    }
    return DashboardData.build(notas, agora: agora ?? DateTime.now());
  }

  /// Marca ou desmarca uma tarefa direto do painel.
  ///
  /// A nota e relida antes de escrever: o painel na tela pode estar velho, e
  /// uma linha marcada por cima de um texto desatualizado apagaria o que foi
  /// escrito no editor nesse meio-tempo.
  ///
  /// Devolve o texto antes e depois — e com isso que o contador sabe que uma
  /// tarefa foi concluida. Nulo quando nada mudou.
  Future<({String antes, String depois})?> alternarTarefa(
    String noteId,
    int indice,
  ) async {
    final nota = await _repository.readNote(noteId);
    final novo = MarkdownTasks.alternarNoArquivo(nota.raw, nota.body, indice);
    if (novo == nota.raw) return null;

    await _repository.writeNote(noteId, novo);
    return (antes: nota.raw, depois: novo);
  }
}
