import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/services/vault_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory vault;
  late VaultService service;

  setUp(() {
    vault = Directory.systemTemp.createTempSync('vault_pastas_');
    service = VaultService();
  });

  tearDown(() => vault.deleteSync(recursive: true));

  test('cria a pasta no disco', () async {
    final criada = await service.createFolder(vault.path, 'Receitas');

    expect(Directory(criada).existsSync(), isTrue);
    expect(p.basename(criada), 'Receitas');
  });

  test('cria subpasta dentro de outra', () async {
    final pai = await service.createFolder(vault.path, 'Estudos');
    final filha = await service.createFolder(pai, 'Flutter');

    expect(Directory(filha).existsSync(), isTrue);
    expect(p.basename(p.dirname(filha)), 'Estudos');
  });

  test('nome repetido ganha sufixo em vez de reaproveitar a pasta', () async {
    final primeira = await service.createFolder(vault.path, 'Ideias');
    final segunda = await service.createFolder(vault.path, 'Ideias');

    expect(primeira, isNot(segunda));
    expect(p.basename(segunda), 'Ideias 2');
    expect(Directory(primeira).existsSync(), isTrue);
    expect(Directory(segunda).existsSync(), isTrue);
  });

  test('caracteres proibidos no Windows sao trocados', () async {
    final criada = await service.createFolder(vault.path, 'a/b:c*d?e');
    expect(p.basename(criada), 'a-b-c-d-e');
    expect(Directory(criada).existsSync(), isTrue);
  });

  test('nome reservado do Windows recebe prefixo', () async {
    final criada = await service.createFolder(vault.path, 'CON');
    expect(p.basename(criada), '_CON');
    expect(Directory(criada).existsSync(), isTrue);
  });

  test('nome vazio vira um padrao em vez de falhar', () async {
    final criada = await service.createFolder(vault.path, '   ');
    expect(p.basename(criada), 'Nova pasta');
    expect(Directory(criada).existsSync(), isTrue);
  });

  test('ponto e espaco no fim sao removidos', () async {
    // O Windows nao aceita nome terminado em ponto ou espaco.
    final criada = await service.createFolder(vault.path, 'Notas. ');
    expect(p.basename(criada), 'Notas');
  });

  test('a pasta nova aparece na varredura do vault', () async {
    await service.createFolder(vault.path, 'Projetos');
    final arvore = await service.scan(vault.path);

    expect(arvore.children.map((c) => c.name), contains('Projetos'));
  });
}
