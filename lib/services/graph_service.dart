import '../models/note.dart';
import '../models/vault_entry.dart';
import '../models/vault_graph.dart';
import '../repositories/vault_repository.dart';
import 'calendar_service.dart';

/// Monta o grafo lendo o vault inteiro.
///
/// Como no calendario, nao ha indice persistido: o vault e relido a cada
/// abertura. Assim uma tag apagada do arquivo desaparece do grafo em vez de
/// sobreviver num cache.
class GraphService {
  const GraphService(this._repository);

  final VaultRepository _repository;

  Future<VaultGraph> build(VaultFolder root) async {
    final notes = <Note>[];
    for (final file in CalendarService.filesIn(root)) {
      try {
        notes.add(await _repository.readNote(file.id));
      } on Exception {
        // Nota ilegivel nao derruba o grafo inteiro; ela so nao aparece.
        continue;
      }
    }
    return VaultGraph.build(notes);
  }
}
