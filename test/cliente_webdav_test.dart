import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notas_app/servidor/cliente_webdav.dart';

import 'servidor_falso.dart';

ClienteWebDav _cliente(
  ServidorFalso servidor, {
  String base = 'http://casa/',
}) => ClienteWebDav(
  base: Uri.parse(base),
  usuario: ServidorFalso.usuario,
  senha: ServidorFalso.senha,
  http: servidor.cliente,
);

/// Cliente ligado a um handler cru, para os casos que o servidor falso nao
/// sabe encenar — resposta fora do protocolo, XML quebrado, 500.
ClienteWebDav _comResposta(
  Future<http.Response> Function(http.Request) responder, {
  String base = 'http://casa/',
}) => ClienteWebDav(
  base: Uri.parse(base),
  usuario: 'u',
  senha: 's',
  http: MockClient(responder),
);

void main() {
  group('listagem', () {
    test('le arquivos e pastas do multistatus, sem a propria pasta', () async {
      final servidor = ServidorFalso()
        ..semear('nota.md', '# a')
        ..semear('estudo/aula.md', '# b');

      final itens = await _cliente(servidor).listar('');

      expect(
        itens.map((i) => i.caminho),
        unorderedEquals(['nota.md', 'estudo']),
      );
      expect(itens.firstWhere((i) => i.caminho == 'estudo').ehPasta, isTrue);
      expect(itens.firstWhere((i) => i.caminho == 'nota.md').ehPasta, isFalse);
    });

    test('desfaz o percent-encoding do href', () async {
      final servidor = ServidorFalso()..semear('Aula de calculo.md', '# a');

      final itens = await _cliente(servidor).listar('');

      expect(itens.single.caminho, 'Aula de calculo.md');
      expect(itens.single.nome, 'Aula de calculo.md');
    });

    test('le a data de gravacao no formato de data de HTTP', () async {
      final quando = DateTime.utc(2026, 2, 14, 9, 30, 5);
      final servidor = ServidorFalso()..semear('nota.md', '# a', em: quando);

      final itens = await _cliente(servidor).listar('');

      expect(itens.single.modificadoEm, quando);
    });

    test('percorre a arvore inteira em listarTudo', () async {
      final servidor = ServidorFalso()
        ..semear('raiz.md', '#')
        ..semear('a/b/fundo.md', '#');

      final itens = await _cliente(servidor).listarTudo();

      expect(
        itens.map((i) => i.caminho),
        unorderedEquals(['raiz.md', 'a', 'a/b', 'a/b/fundo.md']),
      );
    });

    test('listarTudo nao entra na pasta que o filtro recusou', () async {
      final servidor = ServidorFalso()
        ..semear('nota.md', '#')
        ..semear('.obsidian/workspace.json', '{}');

      final itens = await _cliente(
        servidor,
      ).listarTudo(ignorar: (item) => item.nome.startsWith('.'));

      expect(itens.map((i) => i.caminho), ['nota.md']);
      expect(
        servidor.pedidos,
        isNot(contains('PROPFIND /.obsidian')),
        reason: 'pasta recusada nao deve gerar ida a rede',
      );
    });

    test('entende multistatus sem prefixo de namespace', () async {
      final cliente = _comResposta(
        (_) async => http.Response(
          '<multistatus xmlns="DAV:"><response>'
          '<href>/nota.md</href>'
          '<propstat><prop><resourcetype/></prop></propstat>'
          '</response></multistatus>',
          207,
        ),
      );

      final itens = await cliente.listar('');

      expect(itens.single.caminho, 'nota.md');
      expect(itens.single.ehPasta, isFalse);
    });

    test('ignora href que cai fora da raiz configurada', () async {
      final cliente = _comResposta(
        base: 'http://casa/vault/',
        (_) async => http.Response(
          '<D:multistatus xmlns:D="DAV:">'
          '<D:response><D:href>/vault/dentro.md</D:href></D:response>'
          '<D:response><D:href>/outro/fora.md</D:href></D:response>'
          '</D:multistatus>',
          207,
        ),
      );

      final itens = await cliente.listar('');

      expect(itens.map((i) => i.caminho), ['dentro.md']);
    });
  });

  group('enderecos', () {
    test('respeita o prefixo de caminho da base', () async {
      late Uri pedida;
      final cliente = _comResposta(base: 'http://casa/vault/', (pedido) async {
        pedida = pedido.url;
        return http.Response('conteudo', 200);
      });

      await cliente.baixar('estudo/aula.md');

      expect(pedida.path, '/vault/estudo/aula.md');
    });

    test('poe barra no fim ao falar de pasta', () async {
      late Uri pedida;
      final cliente = _comResposta((pedido) async {
        pedida = pedido.url;
        return http.Response('', 201);
      });

      await cliente.criarPasta('estudo');

      expect(pedida.path, '/estudo/');
    });

    test('aceita caminho com a barra invertida do Windows', () async {
      late Uri pedida;
      final cliente = _comResposta((pedido) async {
        pedida = pedido.url;
        return http.Response('conteudo', 200);
      });

      await cliente.baixar(r'estudo\aula.md');

      expect(pedida.path, '/estudo/aula.md');
    });

    test('manda o usuario e a senha em Basic', () async {
      late String? enviado;
      final cliente = ClienteWebDav(
        base: Uri.parse('http://casa/'),
        usuario: 'joao',
        senha: 'abc 123',
        http: MockClient((pedido) async {
          enviado = pedido.headers['Authorization'];
          return http.Response('x', 200);
        }),
      );

      await cliente.baixar('nota.md');

      expect(enviado, 'Basic ${base64Encode(utf8.encode('joao:abc 123'))}');
    });
  });

  group('escrita', () {
    test('grava e le de volta o mesmo texto, com acentos', () async {
      final servidor = ServidorFalso();
      final cliente = _cliente(servidor);

      await cliente.enviar('nota.md', '# Sessão de estudo\n');

      expect(await cliente.baixar('nota.md'), '# Sessão de estudo\n');
    });

    test('criar pasta que ja existe nao e erro', () async {
      final servidor = ServidorFalso()..semear('estudo/a.md', '#');

      await expectLater(_cliente(servidor).criarPasta('estudo'), completes);
    });

    test('apagar o que ja sumiu nao e erro', () async {
      final servidor = ServidorFalso();

      await expectLater(_cliente(servidor).apagar('sumiu.md'), completes);
    });
  });

  group('falhas', () {
    test('senha errada vira falha de credencial', () async {
      final servidor = ServidorFalso();
      final cliente = ClienteWebDav(
        base: Uri.parse('http://casa/'),
        usuario: ServidorFalso.usuario,
        senha: 'errada',
        http: servidor.cliente,
      );

      await expectLater(
        cliente.testar(),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.falha,
            'falha',
            FalhaDoServidor.credencial,
          ),
        ),
      );
    });

    test('endereco que nao e WebDAV vira falha de protocolo', () async {
      final cliente = _comResposta(
        (_) async => http.Response('<html>Bem-vindo</html>', 200),
      );

      await expectLater(
        cliente.testar(),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.falha,
            'falha',
            FalhaDoServidor.protocolo,
          ),
        ),
      );
    });

    test('XML quebrado vira falha de protocolo, nao excecao solta', () async {
      final cliente = _comResposta(
        (_) async => http.Response('<D:multistatus', 207),
      );

      await expectLater(cliente.testar(), throwsA(isA<ServidorException>()));
    });

    test('servidor fora do ar vira falha de conexao', () async {
      final cliente = _comResposta(
        (_) async => throw const SocketExceptionFalsa(),
      );

      await expectLater(
        cliente.testar(),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.falha,
            'falha',
            FalhaDoServidor.conexao,
          ),
        ),
      );
    });

    test('arquivo que sumiu do servidor vira falha de inexistente', () async {
      final servidor = ServidorFalso();

      await expectLater(
        _cliente(servidor).baixar('sumiu.md'),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.falha,
            'falha',
            FalhaDoServidor.inexistente,
          ),
        ),
      );
    });
  });
}

/// Faz o papel de uma `SocketException` sem depender do formato dela.
class SocketExceptionFalsa implements Exception {
  const SocketExceptionFalsa();

  @override
  String toString() => 'sem rota para o host';
}
