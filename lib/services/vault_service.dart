import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/atividade.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import '../models/vault_order.dart';
import '../repositories/vault_repository.dart';

/// Acesso ao vault: uma pasta comum de arquivos `.md` no disco.
///
/// Nao ha camada de sync aqui de proposito. O vault vive dentro da pasta do
/// Google Drive (`G:\My Drive\Notas`), entao gravar um arquivo ja e gravar na
/// nuvem — quem sobe e o cliente do Drive, nao o app. Para o app, o vault e
/// sempre so uma pasta local, e essa indiferenca e o que permite trocar a
/// estrategia de sync sem tocar em codigo.
class VaultService implements VaultRepository {
  static const _prefsKey = 'vault_path';

  /// Pastas que vivem dentro do vault mas nao sao conteudo do usuario.
  /// `.obsidian` aparece se o mesmo vault for aberto no Obsidian; as demais
  /// sao metadados de ferramentas de sync e versionamento.
  static const _ignoredDirs = <String>{
    '.stfolder',
    '.stversions',
    '.git',
    '.obsidian',
    '.trash',
  };

  @override
  Future<String?> loadSavedVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return null;
    // A pasta pode ter sido movida ou o cartao removido desde a ultima vez.
    return Directory(saved).existsSync() ? saved : null;
  }

  @override
  Future<void> saveVaultPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, path);
  }

  /// Pasta sugerida ao abrir o seletor. A unidade do Google Drive vem primeiro
  /// porque e onde o vault deve morar; a home do usuario e o fallback quando o
  /// cliente do Drive nao esta montado.
  @override
  String? get defaultStartPath {
    const driveRoot = r'G:\My Drive';
    if (Directory(driveRoot).existsSync()) return driveRoot;
    return Platform.environment['USERPROFILE'];
  }

  /// Le a arvore inteira do vault. Percorre recursivamente porque o vault
  /// pessoal e pequeno (centenas de arquivos, nao milhares).
  @override
  Future<VaultFolder> scan(String rootPath) =>
      _scanDirectory(Directory(rootPath));

  Future<VaultFolder> _scanDirectory(Directory dir) async {
    final folders = <VaultFolder>[];
    final files = <VaultFile>[];

    late final List<FileSystemEntity> entities;
    try {
      entities = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      // Uma subpasta ilegivel nao derruba a leitura do vault inteiro.
      return VaultFolder(
        id: dir.path,
        name: p.basename(dir.path),
        children: const [],
      );
    }

    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (name.startsWith('.') || _ignoredDirs.contains(name)) continue;

      if (entity is Directory) {
        folders.add(await _scanDirectory(entity));
      } else if (entity is File && p.extension(name).toLowerCase() == '.md') {
        files.add(VaultFile(id: entity.path, name: name));
      }
    }

    int byName(VaultEntry a, VaultEntry b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    folders.sort(byName);
    files.sort(byName);

    return VaultFolder(
      id: dir.path,
      name: p.basename(dir.path),
      children: [...folders, ...files],
    );
  }

  @override
  Future<Note> readNote(String noteId) async {
    final raw = await File(noteId).readAsString();
    return Note.parse(noteId, raw, name: p.basename(noteId));
  }

  @override
  Future<void> writeNote(String noteId, String content) async {
    final target = File(noteId);
    final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final temporary = File(
      p.join(target.parent.path, '.${p.basename(noteId)}.$suffix.tmp'),
    );
    final backup = File(
      p.join(target.parent.path, '.${p.basename(noteId)}.$suffix.bak'),
    );

    await temporary.writeAsString(content, flush: true);
    var movedOriginal = false;
    try {
      if (await target.exists()) {
        await target.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(target.path);
      if (movedOriginal && await backup.exists()) await backup.delete();
    } catch (_) {
      if (!await target.exists() && movedOriginal && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Cria uma subpasta e devolve o caminho dela.
  ///
  /// Como o vault vive dentro do Google Drive, a pasta nova sobe para a nuvem
  /// sozinha — nao ha nada a sincronizar aqui.
  @override
  Future<String> createFolder(String parentId, String name) async {
    var slug = _sanitizeName(name, fallback: 'Nova pasta');

    var target = p.join(parentId, slug);
    var counter = 2;
    while (Directory(target).existsSync() || File(target).existsSync()) {
      target = p.join(parentId, '$slug $counter');
      counter++;
    }

    await Directory(target).create(recursive: true);
    return target;
  }

  /// Cria uma nota vazia com frontmatter minimo e devolve o caminho dela.
  /// Se o nome ja existir, acrescenta um sufixo numerico em vez de sobrescrever.
  @override
  Future<String> createNote(String folderId, String title) async {
    final safeTitle = title.trim().isEmpty ? 'Sem titulo' : title.trim();
    final slug = _sanitizeName(safeTitle, fallback: 'Sem titulo');

    var target = p.join(folderId, '$slug.md');
    var counter = 2;
    while (File(target).existsSync()) {
      target = p.join(folderId, '$slug $counter.md');
      counter++;
    }

    final today = DateTime.now();
    final data = '${today.year}-${_two(today.month)}-${_two(today.day)}';
    final content =
        '---\n'
        'tipo: nota\n'
        'criado_em: $data\n'
        'tags: []\n'
        '---\n\n'
        '# $safeTitle\n\n';

    await File(target).writeAsString(content, flush: true);
    return target;
  }

  /// Apaga uma nota ou uma pasta inteira.
  ///
  /// Como o vault vive dentro do Google Drive, apagar aqui e apagar na nuvem —
  /// o cliente de desktop propaga a exclusao, e o que sai daqui vai parar na
  /// lixeira do Drive.
  ///
  /// Um caminho que ja nao existe nao e erro: o resultado pedido — o arquivo
  /// nao estar mais la — ja vale.
  @override
  Future<void> delete(String id) async {
    final pasta = Directory(id);
    if (pasta.existsSync()) {
      await pasta.delete(recursive: true);
      return;
    }

    final arquivo = File(id);
    if (arquivo.existsSync()) await arquivo.delete();
  }

  /// Move uma nota ou uma pasta para dentro de outra pasta.
  ///
  /// So renomeia o caminho: no disco, e a mesma operaçao que arrastar no
  /// Explorer, e o cliente do Drive reflete isso na nuvem.
  @override
  Future<String> move(String id, String newParentId) async {
    final nome = p.basename(id);
    final atual = p.dirname(id);
    if (p.equals(atual, newParentId)) return id;

    // Mover uma pasta para dentro dela mesma destroi a arvore: o `rename`
    // levaria o pai junto com o destino e o conteudo ficaria inalcançavel.
    if (p.equals(id, newParentId) || p.isWithin(id, newParentId)) {
      throw const FileSystemException(
        'Nao da para mover uma pasta para dentro dela mesma',
      );
    }

    final destino = _semColidir(p.join(newParentId, nome));

    final pasta = Directory(id);
    if (pasta.existsSync()) {
      await pasta.rename(destino);
    } else {
      await File(id).rename(destino);
    }
    return destino;
  }

  /// Troca o nome sem sair da pasta.
  ///
  /// A extensao nao e assunto de quem renomeia: uma nota continua `.md` mesmo
  /// que o nome digitado nao termine assim, e digitar ".md" no fim tambem nao
  /// produz `nome.md.md`.
  @override
  Future<String> rename(String id, String novoNome) async {
    final pasta = Directory(id);
    final ehPasta = pasta.existsSync();

    final limpo = _sanitizeName(
      novoNome,
      fallback: ehPasta ? 'Nova pasta' : 'Sem titulo',
    );
    // So `.md` e removido antes de recolocar. Cortar qualquer extensao faria
    // uma nota chamada "Aula 1.2" virar "Aula 1.md".
    final semExtensao = p.extension(limpo).toLowerCase() == '.md'
        ? p.withoutExtension(limpo)
        : limpo;
    final alvo = p.join(p.dirname(id), ehPasta ? limpo : '$semExtensao.md');

    // Renomear para o mesmo nome nao e erro nem operaçao: sem esta saida, o
    // `_semColidir` veria o proprio arquivo como colisao e criaria um "nome 2".
    if (p.equals(alvo, id)) return id;

    final destino = _semColidir(alvo);
    if (ehPasta) {
      await pasta.rename(destino);
    } else {
      await File(id).rename(destino);
    }
    return destino;
  }

  /// Devolve [alvo] ou, se ja existir algo ali, o mesmo nome com sufixo.
  static String _semColidir(String alvo) {
    if (!File(alvo).existsSync() && !Directory(alvo).existsSync()) return alvo;

    final pai = p.dirname(alvo);
    final ext = p.extension(alvo);
    final base = p.basenameWithoutExtension(alvo);

    var counter = 2;
    while (true) {
      final tentativa = p.join(pai, '$base $counter$ext');
      if (!File(tentativa).existsSync() && !Directory(tentativa).existsSync()) {
        return tentativa;
      }
      counter++;
    }
  }

  /// Nome do arquivo que guarda a ordem manual, dentro do proprio vault.
  ///
  /// Fica no vault, e nao nas preferencias do app, para a ordem viajar pelo
  /// Drive junto com as notas. O ponto no inicio faz a varredura pular ele,
  /// entao ele nunca aparece na arvore.
  static const _arquivoDeOrdem = '.notas-ordem.json';

  @override
  Future<VaultOrder> loadOrder(String rootPath) async {
    final arquivo = File(p.join(rootPath, _arquivoDeOrdem));
    if (!arquivo.existsSync()) return VaultOrder.vazia;
    try {
      return VaultOrder.decode(await arquivo.readAsString());
    } on FileSystemException {
      // Sem a ordem manual a arvore volta ao alfabetico, o que e util o
      // bastante para nao valer derrubar a abertura do vault.
      return VaultOrder.vazia;
    }
  }

  @override
  Future<void> saveOrder(String rootPath, VaultOrder order) async {
    final arquivo = File(p.join(rootPath, _arquivoDeOrdem));
    try {
      if (order.isEmpty) {
        if (arquivo.existsSync()) await arquivo.delete();
        return;
      }
      await arquivo.writeAsString(order.encode(), flush: true);
    } on FileSystemException {
      // Nao conseguir gravar a ordem nao pode desfazer o movimento que o
      // usuario acabou de fazer no disco.
    }
  }

  /// Historico de escrita, no vault pelo mesmo motivo da ordem: viaja pelo
  /// Drive e sobrevive a reinstalar o app. Fora daqui ele nao existiria em
  /// lugar nenhum — nenhum `.md` guarda quanto foi escrito ontem.
  static const _arquivoDeAtividade = '.notas-atividade.json';

  @override
  Future<Atividade> loadAtividade(String rootPath) async {
    final arquivo = File(p.join(rootPath, _arquivoDeAtividade));
    if (!arquivo.existsSync()) return Atividade.vazia;
    try {
      return Atividade.decode(await arquivo.readAsString());
    } on FileSystemException {
      // Perder o contador e chato; nao abrir o vault por causa dele seria pior.
      return Atividade.vazia;
    }
  }

  @override
  Future<void> saveAtividade(String rootPath, Atividade atividade) async {
    final arquivo = File(p.join(rootPath, _arquivoDeAtividade));
    try {
      await arquivo.writeAsString(atividade.encode(), flush: true);
    } on FileSystemException {
      // Nao conseguir anotar o que foi escrito nao pode desfazer a gravaçao da
      // nota, que e o que realmente importa.
    }
  }

  /// Transforma um titulo digitado num nome de arquivo ou pasta valido no
  /// Windows: sem caracteres proibidos, sem ponto ou espaco no fim, e fugindo
  /// dos nomes reservados do sistema (`CON`, `PRN`, `NUL`...).
  static String _sanitizeName(String input, {required String fallback}) {
    var slug = input
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (slug.isEmpty) return fallback;
    if (_windowsReservedName.hasMatch(slug)) slug = '_$slug';
    return slug;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static final RegExp _windowsReservedName = RegExp(
    r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
    caseSensitive: false,
  );
}
