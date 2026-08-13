import '../models/frontmatter_writer.dart';
import '../models/kanban_card.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import '../repositories/vault_repository.dart';
import 'calendar_service.dart';

/// Monta o quadro lendo o vault inteiro.
///
/// Como o calendario e o grafo, nao guarda indice: o vault e relido a cada
/// abertura. Um `status:` apagado do arquivo tira o card do quadro em vez de
/// ele sobreviver num cache.
class KanbanService {
  const KanbanService(this._repository);

  final VaultRepository _repository;

  Future<KanbanBoard> build(VaultFolder root) async {
    final notas = <Note>[];
    for (final file in CalendarService.filesIn(root)) {
      try {
        notas.add(await _repository.readNote(file.id));
      } on Exception {
        // Nota ilegivel nao derruba o quadro; ela so nao aparece.
        continue;
      }
    }
    return KanbanBoard.build(notas);
  }

  /// Move um card de coluna, gravando o `status:` na propria nota.
  ///
  /// A nota e relida antes de escrever: o quadro na tela pode estar velho, e
  /// gravar por cima de um texto desatualizado apagaria o que foi escrito no
  /// editor nesse meio-tempo.
  Future<void> mover(String noteId, KanbanColumn destino) async {
    final nota = await _repository.readNote(noteId);
    final novo = FrontmatterWriter.definir(nota.raw, 'status', destino.valor);
    if (novo == nota.raw) return;
    await _repository.writeNote(noteId, novo);
  }
}
