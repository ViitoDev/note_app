import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Um WebDAV de mentira, inteiro em memoria.
///
/// Os testes do sincronizador precisam dos dois lados, e montar o lado de la
/// com um servidor de verdade tornaria a suite dependente de rede e de Docker.
/// Aqui as respostas sao as mesmas que um `dufs` devolveria — inclusive o
/// `<D:multistatus>` com prefixo de namespace e os href com percent-encoding.
class ServidorFalso {
  ServidorFalso({DateTime? relogio})
    : _relogio = relogio ?? DateTime.utc(2026, 3, 1, 10);

  /// Conteudo de cada arquivo, por caminho relativo (`pasta/nota.md`).
  final arquivos = <String, String>{};

  /// Data de gravacao de cada arquivo, como o servidor a carimbaria.
  final datas = <String, DateTime>{};

  final pastas = <String>{};

  /// Todo pedido que chegou, na ordem. E como os testes conferem que uma nota
  /// intocada nao virou trafego.
  final pedidos = <String>[];

  DateTime _relogio;

  /// Cada gravacao no servidor avanca o relogio dele um segundo — o
  /// `getlastmodified` do WebDAV so tem precisao de segundo, e duas gravacoes
  /// no mesmo instante fariam a sincronizacao achar que nada mudou.
  DateTime _carimbar() => _relogio = _relogio.add(const Duration(seconds: 1));

  /// Poe um arquivo no servidor sem passar por HTTP, para montar o cenario.
  void semear(String caminho, String conteudo, {DateTime? em}) {
    arquivos[caminho] = conteudo;
    datas[caminho] = em ?? _carimbar();
    final partes = caminho.split('/');
    for (var i = 1; i < partes.length; i++) {
      pastas.add(partes.take(i).join('/'));
    }
  }

  /// O cliente HTTP a injetar no `ClienteWebDav`.
  http.Client get cliente => MockClient(_responder);

  Future<http.Response> _responder(http.Request pedido) async {
    final caminho = pedido.url.pathSegments
        .where((s) => s.isNotEmpty)
        .join('/');
    pedidos.add('${pedido.method} /$caminho');

    if (pedido.headers['authorization'] != _autorizacaoEsperada) {
      return http.Response('', 401);
    }

    return switch (pedido.method) {
      'PROPFIND' => _propfind(caminho),
      'GET' => _get(caminho),
      'PUT' => _put(caminho, pedido.body),
      'MKCOL' => _mkcol(caminho),
      'DELETE' => _delete(caminho),
      _ => http.Response('', 405),
    };
  }

  /// O `ClienteWebDav` dos testes sempre usa este par.
  static const usuario = 'notas';
  static const senha = 'segredo';
  static final _autorizacaoEsperada =
      'Basic ${base64Encode(utf8.encode('$usuario:$senha'))}';

  http.Response _propfind(String pasta) {
    if (pasta.isNotEmpty && !pastas.contains(pasta)) {
      return http.Response('', 404);
    }

    final linhas = <String>[_resposta(pasta, pasta: true)];

    bool filhoDireto(String caminho) {
      if (pasta.isEmpty) return !caminho.contains('/');
      if (!caminho.startsWith('$pasta/')) return false;
      return !caminho.substring(pasta.length + 1).contains('/');
    }

    for (final sub in pastas.where(filhoDireto)) {
      linhas.add(_resposta(sub, pasta: true));
    }
    for (final arquivo in arquivos.keys.where(filhoDireto)) {
      linhas.add(_resposta(arquivo, pasta: false));
    }

    return http.Response(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<D:multistatus xmlns:D="DAV:">${linhas.join()}</D:multistatus>',
      207,
      headers: {'content-type': 'application/xml; charset=utf-8'},
    );
  }

  String _resposta(String caminho, {required bool pasta}) {
    // Percent-encoding por segmento, como qualquer servidor faz: e o que
    // garante que "Aula de calculo.md" volte com o espaco no lugar.
    final href =
        '/${caminho.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/')}'
        '${pasta ? '/' : ''}';

    final tipo = pasta ? '<D:collection/>' : '';
    final data = pasta ? _relogio : (datas[caminho] ?? _relogio);
    final tamanho = pasta ? '' : '${utf8.encode(arquivos[caminho]!).length}';

    return '<D:response><D:href>$href</D:href><D:propstat>'
        '<D:prop>'
        '<D:resourcetype>$tipo</D:resourcetype>'
        '<D:getlastmodified>${HttpDate.format(data)}</D:getlastmodified>'
        '${pasta ? '' : '<D:getcontentlength>$tamanho</D:getcontentlength>'}'
        '</D:prop><D:status>HTTP/1.1 200 OK</D:status>'
        '</D:propstat></D:response>';
  }

  http.Response _get(String caminho) {
    final conteudo = arquivos[caminho];
    if (conteudo == null) return http.Response('', 404);
    return http.Response.bytes(utf8.encode(conteudo), 200);
  }

  http.Response _put(String caminho, String corpo) {
    final pai = caminho.contains('/')
        ? caminho.substring(0, caminho.lastIndexOf('/'))
        : '';
    // Um WebDAV recusa gravar dentro de pasta que nao existe; sem isso o teste
    // nao pegaria a ordem errada entre criar a pasta e subir a nota.
    if (pai.isNotEmpty && !pastas.contains(pai)) return http.Response('', 409);

    arquivos[caminho] = corpo;
    datas[caminho] = _carimbar();
    return http.Response('', 201);
  }

  http.Response _mkcol(String caminho) {
    if (pastas.contains(caminho)) return http.Response('', 405);
    pastas.add(caminho);
    return http.Response('', 201);
  }

  http.Response _delete(String caminho) {
    if (arquivos.remove(caminho) != null) {
      datas.remove(caminho);
      return http.Response('', 204);
    }
    if (pastas.remove(caminho)) return http.Response('', 204);
    return http.Response('', 404);
  }
}
