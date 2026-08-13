import 'dart:convert';

import 'package:_discoveryapis_commons/_discoveryapis_commons.dart' as commons;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'drive_item.dart';

/// Operaçoes remotas de baixo nivel sobre a pasta do app no Google Drive.
///
/// O cliente HTTP ja deve chegar autenticado. Android e Windows poderao usar
/// fluxos OAuth diferentes sem mudar esta classe.
class GoogleDriveDataSource {
  GoogleDriveDataSource(http.Client authenticatedClient)
    : _api = drive.DriveApi(authenticatedClient);

  static const folderMimeType = 'application/vnd.google-apps.folder';
  static const markdownMimeType = 'text/markdown';
  static const defaultRootName = 'App Notas';
  static const _fields =
      'id,name,mimeType,parents,modifiedTime,version,md5Checksum';

  final drive.DriveApi _api;

  /// Encontra a pasta criada pelo app ou cria uma nova na raiz do Meu Drive.
  Future<DriveItem> findOrCreateRootFolder({
    String name = defaultRootName,
  }) async {
    final escapedName = _escapeQueryLiteral(name);
    final result = await _api.files.list(
      q:
          "name = '$escapedName' and "
          "mimeType = '$folderMimeType' and "
          "'root' in parents and trashed = false",
      spaces: 'drive',
      orderBy: 'createdTime',
      pageSize: 10,
      $fields: 'files($_fields)',
    );

    final existing = result.files;
    if (existing != null && existing.isNotEmpty) {
      return _toItem(existing.first);
    }

    final created = await _api.files.create(
      drive.File(
        name: name,
        mimeType: folderMimeType,
        parents: const ['root'],
        appProperties: const {'owner': 'notas_app'},
      ),
      $fields: _fields,
    );
    return _toItem(created);
  }

  /// Lista todos os filhos diretos, consumindo todas as paginas da API.
  Future<List<DriveItem>> listChildren(String parentId) async {
    final items = <DriveItem>[];
    String? pageToken;
    do {
      final result = await _api.files.list(
        q: "'${_escapeQueryLiteral(parentId)}' in parents and trashed = false",
        spaces: 'drive',
        orderBy: 'folder,name_natural',
        pageSize: 1000,
        pageToken: pageToken,
        $fields: 'nextPageToken,files($_fields)',
      );
      items.addAll((result.files ?? const []).map(_toItem));
      pageToken = result.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    return items;
  }

  Future<String> downloadText(String fileId) async {
    final response = await _api.files.get(
      fileId,
      downloadOptions: commons.DownloadOptions.fullMedia,
    );
    if (response is! commons.Media) {
      throw StateError('O Drive nao devolveu o conteudo do arquivo $fileId.');
    }

    final bytes = <int>[];
    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<DriveItem> createMarkdown({
    required String parentId,
    required String name,
    required String content,
  }) async {
    final bytes = utf8.encode(content);
    final created = await _api.files.create(
      drive.File(name: name, mimeType: markdownMimeType, parents: [parentId]),
      uploadMedia: commons.Media(Stream.value(bytes), bytes.length),
      uploadOptions: commons.UploadOptions.defaultOptions,
      $fields: _fields,
    );
    return _toItem(created);
  }

  Future<DriveItem> updateMarkdown({
    required String fileId,
    required String content,
  }) async {
    final bytes = utf8.encode(content);
    final updated = await _api.files.update(
      drive.File(),
      fileId,
      uploadMedia: commons.Media(Stream.value(bytes), bytes.length),
      uploadOptions: commons.UploadOptions.defaultOptions,
      $fields: _fields,
    );
    return _toItem(updated);
  }

  static DriveItem _toItem(drive.File file) {
    final id = file.id;
    final name = file.name;
    final mimeType = file.mimeType;
    if (id == null || name == null || mimeType == null) {
      throw const FormatException('Item do Drive sem metadados obrigatorios.');
    }
    return DriveItem(
      id: id,
      name: name,
      mimeType: mimeType,
      parentIds: List.unmodifiable(file.parents ?? const []),
      modifiedTime: file.modifiedTime,
      version: file.version,
      md5Checksum: file.md5Checksum,
    );
  }

  static String _escapeQueryLiteral(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}
