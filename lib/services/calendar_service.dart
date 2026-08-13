import '../models/calendar_event.dart';
import '../models/vault_entry.dart';
import '../repositories/vault_repository.dart';

/// Monta o calendario lendo o vault inteiro.
///
/// Nao existe indice persistido: a cada abertura o vault e relido. Para um
/// vault pessoal (centenas de notas) isso custa milissegundos, e evita o pior
/// problema de um cache — mostrar um evento que ja foi apagado do arquivo.
class CalendarService {
  const CalendarService(this._repository);

  final VaultRepository _repository;

  Future<List<CalendarEvent>> collect(VaultFolder root) async {
    final events = <CalendarEvent>[];
    for (final file in filesIn(root)) {
      try {
        final note = await _repository.readNote(file.id);
        events.addAll(EventParser.fromNote(note));
      } on Exception {
        // Uma nota ilegivel nao pode derrubar o calendario inteiro; ela
        // simplesmente nao contribui com eventos.
        continue;
      }
    }
    events.sort();
    return events;
  }

  /// Percorre a arvore em profundidade devolvendo so os arquivos.
  static Iterable<VaultFile> filesIn(VaultFolder folder) sync* {
    for (final child in folder.children) {
      switch (child) {
        case VaultFolder():
          yield* filesIn(child);
        case VaultFile():
          yield child;
      }
    }
  }
}
