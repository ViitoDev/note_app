import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/servidor/cliente_webdav.dart';
import 'package:notas_app/servidor/sincronizador.dart';
import 'package:path/path.dart' as p;

import 'servidor_falso.dart';

void main() {
  late Directory vault;
  late ServidorFalso servidor;

  setUp(() async {
    vault = await Directory.systemTemp.createTemp('notas_sync_test_');
    servidor = ServidorFalso();
  });

  tearDown(() async {
    if (await vault.exists()) await vault.delete(recursive: true);
  });

  Sincronizador sincronizador() => Sincronizador(
    cliente: ClienteWebDav(
      base: Uri.parse('http://casa/'),
      usuario: ServidorFalso.usuario,
      senha: ServidorFalso.senha,
      http: servidor.cliente,
    ),
    raiz: vault.path,
    agora: () => DateTime(2026, 3, 1, 14, 5),
  );

  /// Cria um arquivo no vault local. [em] carimba a data de gravacao, que e o
  /// que a sincronizacao compara.
  Future<File> escrever(String caminho, String texto, {DateTime? em}) async {
    final arquivo = File(p.join(vault.path, p.joinAll(caminho.split('/'))));
    await arquivo.parent.create(recursive: true);
    await arquivo.writeAsString(texto, flush: true);
    if (em != null) await arquivo.setLastModified(em);
    return arquivo;
  }

  String? ler(String caminho) {
    final arquivo = File(p.join(vault.path, p.joinAll(caminho.split('/'))));
    return arquivo.existsSync() ? arquivo.readAsStringSync() : null;
  }

  List<String> naLixeira() {
    final lixeira = Directory(p.join(vault.path, Sincronizador.pastaDaLixeira));
    if (!lixeira.existsSync()) return const [];
    return lixeira.listSync().map((e) => p.basename(e.path)).toList()..sort();
  }

  group('primeira rodada', () {
    test('sobe a nota que so existe aqui', () async {
      await escrever('nota.md', '# Minha nota\n');

      final r = await sincronizador().sincronizar();

      expect(r.enviados, ['nota.md']);
      expect(servidor.arquivos['nota.md'], '# Minha nota\n');
    });

    test('baixa a nota que so existe no servidor', () async {
      servidor.semear('de-la.md', '# Veio do servidor\n');

      final r = await sincronizador().sincronizar();

      expect(r.baixados, ['de-la.md']);
      expect(ler('de-la.md'), '# Veio do servidor\n');
    });

    test(
      'cria no servidor a pasta que so existe aqui, antes da nota',
      () async {
        await escrever('estudo/calculo/aula.md', '# Aula\n');

        await sincronizador().sincronizar();

        expect(servidor.pastas, containsAll(['estudo', 'estudo/calculo']));
        expect(servidor.arquivos['estudo/calculo/aula.md'], '# Aula\n');
        expect(
          servidor.pedidos.indexOf('MKCOL /estudo'),
          lessThan(servidor.pedidos.indexOf('MKCOL /estudo/calculo')),
          reason: 'a pasta de cima precisa nascer antes da de baixo',
        );
      },
    );

    test('cria aqui a pasta que so existe no servidor', () async {
      servidor.semear('estudo/aula.md', '# Aula\n');

      await sincronizador().sincronizar();

      expect(ler('estudo/aula.md'), '# Aula\n');
    });

    test(
      'vault ja identico dos dois lados nao gera copia de conflito',
      () async {
        await escrever('nota.md', '# Igual\n');
        servidor.semear('nota.md', '# Igual\n');

        final r = await sincronizador().sincronizar();

        expect(r.conflitos, isEmpty);
        expect(r.enviados, isEmpty);
        expect(r.baixados, isEmpty);
        expect(vault.listSync().map((e) => p.basename(e.path)), [
          Sincronizador.arquivoDeEstado,
          'nota.md',
        ]);
      },
    );
  });

  group('rodadas seguintes', () {
    test('nada muda na segunda rodada seguida', () async {
      await escrever('nota.md', '# a\n');
      servidor.semear('outra.md', '# b\n');
      await sincronizador().sincronizar();

      final r = await sincronizador().sincronizar();

      expect(r.semMudanca, isTrue);
      expect(r.resumo, 'Tudo em dia com o servidor.');
    });

    test('sobe so a nota que mudou aqui', () async {
      await escrever('a.md', '# a\n');
      await escrever('b.md', '# b\n');
      await sincronizador().sincronizar();

      await escrever('a.md', '# a editada\n', em: DateTime(2026, 5, 1));
      final r = await sincronizador().sincronizar();

      expect(r.enviados, ['a.md']);
      expect(servidor.arquivos['a.md'], '# a editada\n');
      expect(servidor.arquivos['b.md'], '# b\n');
    });

    test('desce so a nota que mudou la', () async {
      await escrever('a.md', '# a\n');
      servidor.semear('b.md', '# b\n');
      await sincronizador().sincronizar();

      servidor.semear('b.md', '# b, escrita no notebook\n');
      final r = await sincronizador().sincronizar();

      expect(r.baixados, ['b.md']);
      expect(ler('b.md'), '# b, escrita no notebook\n');
      expect(ler('a.md'), '# a\n');
    });
  });

  group('exclusoes', () {
    test('nota apagada aqui e apagada no servidor', () async {
      await escrever('sai.md', '# sai\n');
      await sincronizador().sincronizar();

      await File(p.join(vault.path, 'sai.md')).delete();
      final r = await sincronizador().sincronizar();

      expect(r.apagadosLa, ['sai.md']);
      expect(servidor.arquivos, isNot(contains('sai.md')));
    });

    test(
      'nota apagada no servidor vai para a lixeira, nao para o nada',
      () async {
        servidor.semear('sai.md', '# texto que importa\n');
        await sincronizador().sincronizar();

        servidor.arquivos.remove('sai.md');
        final r = await sincronizador().sincronizar();

        expect(r.apagadosAqui, ['sai.md']);
        expect(ler('sai.md'), isNull);
        expect(naLixeira(), ['sai.md']);
        expect(
          ler('${Sincronizador.pastaDaLixeira}/sai.md'),
          '# texto que importa\n',
        );
      },
    );

    test('a lixeira guarda a pasta de origem no nome', () async {
      servidor.semear('estudo/aula.md', '# a\n');
      await sincronizador().sincronizar();

      servidor.arquivos.remove('estudo/aula.md');
      await sincronizador().sincronizar();

      expect(naLixeira(), ['estudo - aula.md']);
    });

    test('a nota apagada nao volta a descer na rodada seguinte', () async {
      await escrever('sai.md', '# sai\n');
      await sincronizador().sincronizar();
      await File(p.join(vault.path, 'sai.md')).delete();
      await sincronizador().sincronizar();

      final r = await sincronizador().sincronizar();

      expect(r.semMudanca, isTrue);
      expect(ler('sai.md'), isNull);
    });
  });

  group('conflito', () {
    test('mudou nos dois: guarda a versao de la e sobe a daqui', () async {
      await escrever('nota.md', '# original\n');
      await sincronizador().sincronizar();

      await escrever('nota.md', '# escrita aqui\n', em: DateTime(2026, 5, 1));
      servidor.semear('nota.md', '# escrita la\n');

      final r = await sincronizador().sincronizar();

      expect(r.conflitos, ['nota (do servidor 2026-03-01 14h05).md']);
      // A nota continua sendo a nota: quem estava digitando nela nao perde o
      // arquivo que tinha aberto.
      expect(ler('nota.md'), '# escrita aqui\n');
      expect(ler('nota (do servidor 2026-03-01 14h05).md'), '# escrita la\n');
      expect(servidor.arquivos['nota.md'], '# escrita aqui\n');
    });

    test('mudou nos dois com o mesmo texto nao e conflito', () async {
      await escrever('nota.md', '# original\n');
      await sincronizador().sincronizar();

      await escrever('nota.md', '# igual dos dois\n', em: DateTime(2026, 5, 1));
      servidor.semear('nota.md', '# igual dos dois\n');

      final r = await sincronizador().sincronizar();

      expect(r.conflitos, isEmpty);
      expect(r.semMudanca, isTrue);
    });

    test('a copia do conflito sobe na rodada seguinte', () async {
      await escrever('nota.md', '# original\n');
      await sincronizador().sincronizar();
      await escrever('nota.md', '# aqui\n', em: DateTime(2026, 5, 1));
      servidor.semear('nota.md', '# la\n');
      await sincronizador().sincronizar();

      final r = await sincronizador().sincronizar();

      expect(r.enviados, ['nota (do servidor 2026-03-01 14h05).md']);
      expect(
        servidor.arquivos['nota (do servidor 2026-03-01 14h05).md'],
        '# la\n',
      );
    });
  });

  group('subir uma nota so', () {
    test('sobe a nota sem varrer o vault inteiro', () async {
      await escrever('a.md', '# a\n');
      await escrever('b.md', '# b\n');
      await escrever('estudo/c.md', '# c\n');
      await sincronizador().sincronizar();
      servidor.pedidos.clear();

      await escrever('a.md', '# a editada\n', em: DateTime(2026, 5, 1));
      final subiu = await sincronizador().subirNota('a.md');

      expect(subiu, isTrue);
      expect(servidor.arquivos['a.md'], '# a editada\n');
      // O ponto de existir este caminho: uma pausa de digitacao nao pode
      // custar uma varredura dos dois lados.
      expect(
        servidor.pedidos.where((pedido) => pedido.startsWith('PROPFIND')),
        hasLength(2),
        reason: 'so a pasta da nota, antes e depois de gravar',
      );
      expect(servidor.pedidos, isNot(contains('PROPFIND /estudo')));
    });

    test('aceita o caminho com a barra invertida do Windows', () async {
      await escrever('estudo/aula.md', '# a\n');
      await sincronizador().sincronizar();

      await escrever('estudo/aula.md', '# b\n', em: DateTime(2026, 5, 1));
      final subiu = await sincronizador().subirNota(r'estudo\aula.md');

      expect(subiu, isTrue);
      expect(servidor.arquivos['estudo/aula.md'], '# b\n');
    });

    test('recusa quando o servidor mexeu na nota', () async {
      await escrever('nota.md', '# original\n');
      await sincronizador().sincronizar();

      // Outra maquina gravou por cima enquanto esta escrevia.
      servidor.semear('nota.md', '# escrita no notebook\n');
      await escrever('nota.md', '# escrita aqui\n', em: DateTime(2026, 5, 1));

      final subiu = await sincronizador().subirNota('nota.md');

      // Falso significa "nao sei resolver isto": quem decide entre duas
      // versoes e a rodada completa, que guarda a copia de conflito.
      expect(subiu, isFalse);
      expect(
        servidor.arquivos['nota.md'],
        '# escrita no notebook\n',
        reason: 'o texto do servidor nao pode ser apagado pelo caminho rapido',
      );
    });

    test('recusa nota que nunca foi sincronizada', () async {
      await escrever('nova.md', '# nova\n');

      expect(await sincronizador().subirNota('nova.md'), isFalse);
      expect(servidor.arquivos, isEmpty);
    });

    test('recusa nota que sumiu do disco', () async {
      expect(await sincronizador().subirNota('fantasma.md'), isFalse);
    });

    test('ignora arquivo que nao entra na sincronizacao', () async {
      await escrever('anexo.png', 'bytes');

      expect(await sincronizador().subirNota('anexo.png'), isTrue);
      expect(servidor.arquivos, isEmpty);
    });

    test('deixa o estado em dia, sem reenviar na rodada seguinte', () async {
      await escrever('nota.md', '# a\n');
      await sincronizador().sincronizar();

      await escrever('nota.md', '# b\n', em: DateTime(2026, 5, 1));
      await sincronizador().subirNota('nota.md');

      final r = await sincronizador().sincronizar();

      expect(
        r.semMudanca,
        isTrue,
        reason: 'a subida rapida ja anotou as datas',
      );
      expect(servidor.arquivos['nota.md'], '# b\n');
    });
  });

  group('o que fica de fora', () {
    test('sobe os .md e os dois .json do app, e mais nada', () async {
      await escrever('nota.md', '# a\n');
      await escrever('.notas-ordem.json', '{}');
      await escrever('.notas-atividade.json', '{}');
      await escrever('anexo.png', 'nao e texto');
      await escrever('leiame.txt', 'tambem nao');

      await sincronizador().sincronizar();

      expect(
        servidor.arquivos.keys,
        unorderedEquals([
          'nota.md',
          '.notas-ordem.json',
          '.notas-atividade.json',
        ]),
      );
    });

    test('nao sobe .git, .obsidian nem a lixeira', () async {
      await escrever('nota.md', '# a\n');
      await escrever('.git/config', 'x');
      await escrever('.obsidian/workspace.json', '{}');
      await escrever('${Sincronizador.pastaDaLixeira}/velha.md', '# velha\n');

      await sincronizador().sincronizar();

      expect(servidor.arquivos.keys, ['nota.md']);
      expect(servidor.pastas, isEmpty);
    });

    test('nao sobe o proprio arquivo de estado', () async {
      await escrever('nota.md', '# a\n');

      await sincronizador().sincronizar();
      await sincronizador().sincronizar();

      expect(servidor.arquivos, isNot(contains(Sincronizador.arquivoDeEstado)));
    });

    test('nao sobe o temporario de uma gravacao em andamento', () async {
      await escrever('nota.md', '# a\n');
      await escrever('.nota.md.1234.tmp', '# pela metade');

      await sincronizador().sincronizar();

      expect(servidor.arquivos.keys, ['nota.md']);
    });
  });

  group('resistencia', () {
    test('estado corrompido nao apaga nem duplica nada', () async {
      await escrever('nota.md', '# a\n');
      servidor.semear('nota.md', '# a\n');
      await escrever(Sincronizador.arquivoDeEstado, 'isto nao e json');

      final r = await sincronizador().sincronizar();

      expect(r.conflitos, isEmpty);
      expect(ler('nota.md'), '# a\n');
      expect(servidor.arquivos['nota.md'], '# a\n');
    });

    test('nome com acento e espaco sobrevive a ida e volta', () async {
      await escrever('Sessão de estudo.md', '# Cálculo\n');

      await sincronizador().sincronizar();
      await File(p.join(vault.path, 'Sessão de estudo.md')).delete();
      await File(p.join(vault.path, Sincronizador.arquivoDeEstado)).delete();
      await sincronizador().sincronizar();

      expect(ler('Sessão de estudo.md'), '# Cálculo\n');
    });

    test('pasta que ficou vazia dos dois lados sai do caminho', () async {
      await escrever('estudo/aula.md', '# a\n');
      await sincronizador().sincronizar();

      await Directory(p.join(vault.path, 'estudo')).delete(recursive: true);
      await sincronizador().sincronizar();

      expect(servidor.pastas, isEmpty);
      expect(servidor.arquivos, isEmpty);
    });
  });
}
