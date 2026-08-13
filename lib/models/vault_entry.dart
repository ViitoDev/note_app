import 'package:path/path.dart' as p;

/// Um item da arvore do vault: pasta ou arquivo `.md`.
sealed class VaultEntry {
  const VaultEntry({required this.id, required this.name});

  /// Identidade estavel no armazenamento. Na implementacao local ainda e o
  /// caminho; no Google Drive sera o `fileId`.
  final String id;

  /// Nome atual do item, independente de sua identidade.
  final String name;
}

class VaultFolder extends VaultEntry {
  const VaultFolder({
    required super.id,
    required super.name,
    required this.children,
  });

  /// Subpastas primeiro, depois arquivos — cada grupo em ordem alfabetica.
  final List<VaultEntry> children;

  bool get isEmpty => children.isEmpty;

  /// Total de notas na pasta e em tudo abaixo dela.
  int get noteCount => children.fold(
    0,
    (total, child) => total + (child is VaultFolder ? child.noteCount : 1),
  );
}

class VaultFile extends VaultEntry {
  const VaultFile({required super.id, required super.name});

  /// Nome exibido na arvore: sem a extensao `.md`.
  String get title => p.basenameWithoutExtension(name);
}
