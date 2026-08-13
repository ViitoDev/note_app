import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/services/vault_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory vault;
  late VaultService service;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('notas_app_test_');
    service = VaultService();
  });

  tearDown(() async {
    if (await vault.exists()) await vault.delete(recursive: true);
  });

  test('cria nota na raiz sem sobrescrever outra com o mesmo titulo', () async {
    final first = await service.createNote(vault.path, 'Minha nota');
    final second = await service.createNote(vault.path, 'Minha nota');

    expect(p.basename(first), 'Minha nota.md');
    expect(p.basename(second), 'Minha nota 2.md');
    expect(await File(first).readAsString(), contains('# Minha nota'));
  });

  test('normaliza nome reservado e caracteres invalidos do Windows', () async {
    final reserved = await service.createNote(vault.path, 'CON');
    final invalid = await service.createNote(vault.path, 'a:b? ');

    expect(p.basename(reserved), '_CON.md');
    expect(p.basename(invalid), 'a-b-.md');
  });

  test('grava nota sem deixar arquivos temporarios ou backup', () async {
    final path = await service.createNote(vault.path, 'Editavel');

    await service.writeNote(path, '# Conteudo novo\n');

    expect(await File(path).readAsString(), '# Conteudo novo\n');
    final names = await vault
        .list()
        .map((entry) => p.basename(entry.path))
        .toList();
    expect(names, ['Editavel.md']);
  });

  test('varredura ignora pastas tecnicas e inclui apenas Markdown', () async {
    await Directory(p.join(vault.path, '.git')).create();
    await Directory(p.join(vault.path, 'Estudos')).create();
    await File(p.join(vault.path, '.git', 'oculta.md')).writeAsString('x');
    await File(p.join(vault.path, 'Estudos', 'nota.md')).writeAsString('x');
    await File(p.join(vault.path, 'texto.txt')).writeAsString('x');

    final tree = await service.scan(vault.path);

    expect(tree.noteCount, 1);
    expect(tree.children.single.name, 'Estudos');
  });
}
