import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notas_app/drive/google_drive_data_source.dart';

void main() {
  test('encontra pasta raiz existente pelo nome', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/drive/v3/files');
      expect(request.url.queryParameters['q'], contains("name = 'App Notas'"));
      return _jsonResponse({
        'files': [
          {
            'id': 'folder-1',
            'name': 'App Notas',
            'mimeType': GoogleDriveDataSource.folderMimeType,
            'parents': ['root'],
            'version': '3',
          },
        ],
      });
    });

    final folder = await GoogleDriveDataSource(client).findOrCreateRootFolder();

    expect(folder.id, 'folder-1');
    expect(folder.name, 'App Notas');
    expect(folder.isFolder, isTrue);
    expect(folder.version, '3');
  });

  test('cria pasta raiz quando ela ainda nao existe', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (request.method == 'GET') return _jsonResponse({'files': []});

      expect(request.method, 'POST');
      expect(request.url.path, '/drive/v3/files');
      expect(request.body, contains('App Notas'));
      return _jsonResponse({
        'id': 'folder-new',
        'name': 'App Notas',
        'mimeType': GoogleDriveDataSource.folderMimeType,
        'parents': ['root'],
      });
    });

    final folder = await GoogleDriveDataSource(client).findOrCreateRootFolder();

    expect(calls, 2);
    expect(folder.id, 'folder-new');
  });

  test('lista todas as paginas de filhos', () async {
    final client = MockClient((request) async {
      final pageToken = request.url.queryParameters['pageToken'];
      if (pageToken == null) {
        return _jsonResponse({
          'nextPageToken': 'pagina-2',
          'files': [
            {
              'id': 'a',
              'name': 'A.md',
              'mimeType': GoogleDriveDataSource.markdownMimeType,
              'parents': ['folder'],
            },
          ],
        });
      }
      expect(pageToken, 'pagina-2');
      return _jsonResponse({
        'files': [
          {
            'id': 'b',
            'name': 'B.md',
            'mimeType': GoogleDriveDataSource.markdownMimeType,
            'parents': ['folder'],
          },
        ],
      });
    });

    final files = await GoogleDriveDataSource(client).listChildren('folder');

    expect(files.map((item) => item.id), ['a', 'b']);
  });

  test('baixa Markdown como UTF-8', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/drive/v3/files/note-1');
      expect(request.url.queryParameters['alt'], 'media');
      return http.Response.bytes(
        utf8.encode('# Olá\n'),
        200,
        headers: {'content-type': 'text/markdown; charset=utf-8'},
      );
    });

    final content = await GoogleDriveDataSource(client).downloadText('note-1');

    expect(content, '# Olá\n');
  });

  test('cria e atualiza Markdown por upload multipart', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'www.googleapis.com');
      expect(request.url.queryParameters['uploadType'], 'multipart');
      final expectedContent = calls == 1
          ? '# Conteudo'
          : '# Conteudo atualizado';
      expect(
        request.body,
        contains(base64Encode(utf8.encode(expectedContent))),
      );

      if (calls == 1) {
        expect(request.method, 'POST');
        expect(request.url.path, '/upload/drive/v3/files');
      } else {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/upload/drive/v3/files/note-1');
      }
      return _jsonResponse({
        'id': 'note-1',
        'name': 'Nota.md',
        'mimeType': GoogleDriveDataSource.markdownMimeType,
        'parents': ['folder'],
      });
    });
    final source = GoogleDriveDataSource(client);

    final created = await source.createMarkdown(
      parentId: 'folder',
      name: 'Nota.md',
      content: '# Conteudo',
    );
    final updated = await source.updateMarkdown(
      fileId: created.id,
      content: '# Conteudo atualizado',
    );

    expect(updated.id, 'note-1');
    expect(calls, 2);
  });
}

http.Response _jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
