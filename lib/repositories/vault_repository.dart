import '../models/atividade.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import '../models/vault_order.dart';

/// Contrato de acesso ao vault usado pela interface.
///
/// A implementacao e local: o vault e uma pasta dentro do Google Drive, e a
/// sincronizacao com a nuvem fica por conta do cliente do Drive. Manter este
/// contrato permite trocar a origem dos dados sem acoplar a UI.
abstract interface class VaultRepository {
  Future<String?> loadSavedVaultPath();

  Future<void> saveVaultPath(String path);

  String? get defaultStartPath;

  Future<VaultFolder> scan(String rootId);

  Future<Note> readNote(String noteId);

  Future<void> writeNote(String noteId, String content);

  Future<String> createNote(String folderId, String title);

  Future<String> createFolder(String parentId, String name);

  /// Apaga a nota ou a pasta, com tudo que estiver dentro dela.
  Future<void> delete(String id);

  /// Move a nota ou a pasta para dentro de [newParentId] e devolve o caminho
  /// novo, que pode diferir do pedido se ja houvesse algo com aquele nome.
  Future<String> move(String id, String newParentId);

  /// Troca o nome da nota ou da pasta, sem tirar ela da pasta onde esta.
  ///
  /// [novoNome] vem sem extensao: quem renomeia digita "Aula de calculo", nao
  /// "Aula de calculo.md". Devolve o caminho novo, que pode diferir do pedido
  /// se o nome precisou ser ajustado ou ja estivesse em uso.
  Future<String> rename(String id, String novoNome);

  /// A ordem manual escolhida pelo usuario, guardada junto do vault.
  Future<VaultOrder> loadOrder(String rootPath);

  Future<void> saveOrder(String rootPath, VaultOrder order);

  /// O historico de escrita, guardado junto do vault.
  ///
  /// E o unico dado do app que nao da para deduzir dos `.md`: o arquivo diz
  /// como a nota esta hoje, nunca quanto dela foi escrito ontem.
  Future<Atividade> loadAtividade(String rootPath);

  Future<void> saveAtividade(String rootPath, Atividade atividade);
}
