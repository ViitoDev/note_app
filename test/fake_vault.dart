import 'package:notas_app/models/atividade.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/models/vault_order.dart';
import 'package:notas_app/repositories/vault_repository.dart';
import 'package:path/path.dart' as p;

/// Vault falso em memoria, para as telas rodarem sem tocar em disco.
///
/// Traz o contrato inteiro com o comportamento mais inofensivo possivel, e
/// cada teste sobrescreve so o que lhe interessa. Sem esta base, cada arquivo
/// de teste carregaria a sua copia do contrato e todos quebrariam junto a cada
/// metodo novo no repositorio.
class FakeVault implements VaultRepository {
  FakeVault({this.rootPath = r'C:\vault'});

  final String rootPath;

  /// Registro do que a tela pediu, para os testes conferirem.
  final excluidos = <String>[];
  final movidos = <({String id, String destino})>[];
  final renomeados = <({String id, String nome})>[];

  VaultOrder ordem = VaultOrder.vazia;
  Atividade atividade = Atividade.vazia;

  @override
  Future<String?> loadSavedVaultPath() async => rootPath;

  @override
  Future<void> saveVaultPath(String path) async {}

  @override
  String? get defaultStartPath => r'C:\';

  @override
  Future<VaultFolder> scan(String rootId) async =>
      VaultFolder(id: rootPath, name: 'vault', children: const []);

  @override
  Future<Note> readNote(String noteId) async => Note.parse(
    noteId,
    '# ${p.basenameWithoutExtension(noteId)}',
    name: p.basename(noteId),
  );

  @override
  Future<void> writeNote(String noteId, String content) async {}

  @override
  Future<String> createNote(String folderId, String title) async =>
      p.join(folderId, '$title.md');

  @override
  Future<String> createFolder(String parentId, String name) async =>
      p.join(parentId, name);

  @override
  Future<void> delete(String id) async => excluidos.add(id);

  @override
  Future<String> move(String id, String newParentId) async {
    movidos.add((id: id, destino: newParentId));
    return p.join(newParentId, p.basename(id));
  }

  @override
  Future<String> rename(String id, String novoNome) async {
    final alvo = p.join(
      p.dirname(id),
      p.extension(id) == '.md' ? '$novoNome.md' : novoNome,
    );
    renomeados.add((id: id, nome: novoNome));
    return alvo;
  }

  @override
  Future<VaultOrder> loadOrder(String rootPath) async => ordem;

  @override
  Future<void> saveOrder(String rootPath, VaultOrder order) async {
    ordem = order;
  }

  @override
  Future<Atividade> loadAtividade(String rootPath) async => atividade;

  @override
  Future<void> saveAtividade(String rootPath, Atividade nova) async {
    atividade = nova;
  }
}
