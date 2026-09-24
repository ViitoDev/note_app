import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'item_remoto.dart';

/// Por que a conversa com o servidor falhou.
///
/// A interface precisa distinguir isso: "senha errada" manda o usuario de
/// volta ao formulario, "fora do ar" manda esperar, e tratar os dois com a
/// mesma frase faz o usuario trocar uma senha que estava certa.
enum FalhaDoServidor {
  /// Nao chegou a falar com ninguem: IP errado, servidor desligado, sem rede.
  conexao,

  /// Falou, e ouviu 401 ou 403: usuario ou senha.
  credencial,

  /// Falou, e o caminho nao existe no servidor.
  inexistente,

  /// Respondeu algo que nao da para usar.
  protocolo,
}

class ServidorException implements Exception {
  const ServidorException(this.falha, this.mensagem, {this.status});

  final FalhaDoServidor falha;
  final String mensagem;
  final int? status;

  @override
  String toString() => mensagem;
}

/// Conversa com o servidor WebDAV que guarda o vault.
///
/// Fala os verbos crus — PROPFIND, GET, PUT, MKCOL, DELETE — e nada mais. Quem
/// decide o que subir e o que baixar e o `Sincronizador`; aqui nao ha nocao de
/// "mudou" nem de conflito, so de pedir e receber.
class ClienteWebDav {
  ClienteWebDav({
    required Uri base,
    required String usuario,
    required String senha,
    http.Client? http,
    // ignore: prefer_initializing_formals
  }) : _base = base,
       _autorizacao = 'Basic ${base64Encode(utf8.encode('$usuario:$senha'))}',
       _http = http ?? _clientePadrao();

  final Uri _base;
  final String _autorizacao;
  final http.Client _http;

  /// Timeout curto de proposito: o app sincroniza em segundo plano enquanto o
  /// usuario escreve, e uma chamada pendurada por minutos deixaria o indicador
  /// girando sem fim numa rede local que, quando responde, responde rapido.
  static const _timeout = Duration(seconds: 20);

  static http.Client _clientePadrao() => http.Client();

  void fechar() => _http.close();

  // -------------------------------------------------------------- listagem

  /// Lista os filhos diretos de [caminho] — nao ele mesmo.
  Future<List<ItemRemoto>> listar(String caminho) async {
    final resposta = await _enviar(
      'PROPFIND',
      caminho,
      pasta: true,
      cabecalhos: const {
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      },
      corpo: utf8.encode(_pedidoDePropfind),
    );

    if (resposta.statusCode != 207) {
      throw ServidorException(
        FalhaDoServidor.protocolo,
        'O servidor respondeu ${resposta.statusCode} a um PROPFIND; '
        'esperava 207. O endereco aponta mesmo para um WebDAV?',
        status: resposta.statusCode,
      );
    }

    final proprio = normalizar(caminho);
    return _lerMultistatus(resposta.bodyBytes)
        // O PROPFIND com Depth 1 devolve a propria pasta junto dos filhos.
        .where((item) => item.caminho != proprio)
        .toList();
  }

  /// Percorre a arvore inteira do servidor, de pasta em pasta.
  ///
  /// Sao varias idas e voltas em vez de um unico `Depth: infinity` porque nem
  /// todo servidor WebDAV aceita esse cabecalho — o Apache, por exemplo, o
  /// recusa por padrao. Para um vault pessoal, dezenas de pastas custam pouco,
  /// e funcionar em qualquer servidor vale mais do que a ida a menos.
  Future<List<ItemRemoto>> listarTudo({
    bool Function(ItemRemoto item)? ignorar,
  }) async {
    final encontrados = <ItemRemoto>[];
    final fila = <String>[''];

    while (fila.isNotEmpty) {
      final pasta = fila.removeLast();
      for (final item in await listar(pasta)) {
        if (ignorar != null && ignorar(item)) continue;
        encontrados.add(item);
        if (item.ehPasta) fila.add(item.caminho);
      }
    }
    return encontrados;
  }

  // -------------------------------------------------------------- conteudo

  Future<String> baixar(String caminho) async {
    final resposta = await _enviar('GET', caminho);
    if (resposta.statusCode == 404) {
      throw ServidorException(
        FalhaDoServidor.inexistente,
        'O arquivo $caminho nao existe mais no servidor.',
        status: 404,
      );
    }
    _exigirSucesso(resposta.statusCode, 'baixar $caminho');
    // `allowMalformed`: uma nota com um byte estranho deve chegar com um
    // caractere torto, nao derrubar a sincronizacao inteira.
    return utf8.decode(resposta.bodyBytes, allowMalformed: true);
  }

  Future<void> enviar(String caminho, String conteudo) async {
    final resposta = await _enviar(
      'PUT',
      caminho,
      cabecalhos: const {'Content-Type': 'text/markdown; charset=utf-8'},
      corpo: utf8.encode(conteudo),
    );
    _exigirSucesso(resposta.statusCode, 'gravar $caminho');
  }

  Future<void> criarPasta(String caminho) async {
    final resposta = await _enviar('MKCOL', caminho, pasta: true);
    // 405 e "ja existe", que e exatamente o que se queria.
    if (resposta.statusCode == 405) return;
    _exigirSucesso(resposta.statusCode, 'criar a pasta $caminho');
  }

  Future<void> apagar(String caminho, {bool pasta = false}) async {
    final resposta = await _enviar('DELETE', caminho, pasta: pasta);
    // Apagar o que ja sumiu e o desfecho desejado, nao um erro.
    if (resposta.statusCode == 404) return;
    _exigirSucesso(resposta.statusCode, 'apagar $caminho');
  }

  /// Bate na raiz so para ver se responde. E o que o botao "Testar" chama
  /// antes de salvar uma configuracao que talvez nunca fosse funcionar.
  Future<void> testar() => listar('');

  // --------------------------------------------------------------- detalhes

  static const _pedidoDePropfind =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<D:propfind xmlns:D="DAV:"><D:prop>'
      '<D:resourcetype/><D:getlastmodified/>'
      '<D:getcontentlength/><D:getetag/>'
      '</D:prop></D:propfind>';

  Future<http.Response> _enviar(
    String metodo,
    String caminho, {
    bool pasta = false,
    Map<String, String> cabecalhos = const {},
    List<int>? corpo,
  }) async {
    final pedido = http.Request(metodo, _url(caminho, pasta: pasta))
      ..headers['Authorization'] = _autorizacao
      ..headers.addAll(cabecalhos);
    if (corpo != null) pedido.bodyBytes = corpo;

    final http.Response resposta;
    try {
      resposta = await http.Response.fromStream(
        await _http.send(pedido).timeout(_timeout),
      );
    } on Exception catch (e) {
      // SocketException, TimeoutException, HandshakeException: do ponto de
      // vista de quem usa o app sao todos "nao alcancei o servidor".
      throw ServidorException(
        FalhaDoServidor.conexao,
        'Nao consegui falar com ${_base.host}:${_base.port}. '
        'O servidor esta ligado e voce esta na mesma rede? ($e)',
      );
    }

    if (resposta.statusCode == 401 || resposta.statusCode == 403) {
      throw ServidorException(
        FalhaDoServidor.credencial,
        'O servidor recusou o usuario ou a senha.',
        status: resposta.statusCode,
      );
    }
    return resposta;
  }

  Uri _url(String caminho, {bool pasta = false}) {
    final segmentos = <String>[
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      ...normalizar(caminho).split('/').where((s) => s.isNotEmpty),
    ];
    // O WebDAV quer a barra no fim para colecoes: sem ela alguns servidores
    // respondem 301 no PROPFIND, e o redirecionamento perde o corpo do pedido.
    return _base.replace(pathSegments: pasta ? [...segmentos, ''] : segmentos);
  }

  /// Caminho no formato que a sincronizacao usa: separador `/`, sem barra
  /// solta nas pontas. O app roda no Windows, entao caminho com `\` chega aqui
  /// com frequencia.
  static String normalizar(String caminho) => caminho
      .replaceAll(r'\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .join('/');

  static void _exigirSucesso(int status, String oQue) {
    if (status >= 200 && status < 300) return;
    throw ServidorException(
      FalhaDoServidor.protocolo,
      'O servidor respondeu $status ao tentar $oQue.',
      status: status,
    );
  }

  /// Le o `<D:multistatus>` devolvido pelo PROPFIND.
  ///
  /// O prefixo do namespace varia por servidor (`D:`, `d:`, ou nenhum), entao
  /// a busca e sempre por nome local em qualquer namespace.
  List<ItemRemoto> _lerMultistatus(List<int> bytes) {
    final XmlDocument documento;
    try {
      documento = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } on XmlException catch (e) {
      throw ServidorException(
        FalhaDoServidor.protocolo,
        'A resposta do servidor nao e um XML de WebDAV valido. ($e)',
      );
    }

    final itens = <ItemRemoto>[];
    for (final resposta in documento.findAllElements(
      'response',
      namespace: '*',
    )) {
      final href = _texto(resposta, 'href');
      if (href == null) continue;

      final caminho = _relativo(href);
      // Um href fora da raiz configurada nao e nosso; ignorar e mais seguro do
      // que adivinhar onde ele cairia dentro do vault.
      if (caminho == null) continue;

      final ehPasta =
          resposta
              .findAllElements('resourcetype', namespace: '*')
              .expand((e) => e.findElements('collection', namespace: '*'))
              .isNotEmpty ||
          href.endsWith('/');

      itens.add(
        ItemRemoto(
          caminho: caminho,
          ehPasta: ehPasta,
          modificadoEm: _data(_texto(resposta, 'getlastmodified')),
          tamanho: int.tryParse(_texto(resposta, 'getcontentlength') ?? ''),
          etag: _texto(resposta, 'getetag'),
        ),
      );
    }
    return itens;
  }

  static String? _texto(XmlElement dentro, String nome) {
    final achados = dentro.findAllElements(nome, namespace: '*');
    if (achados.isEmpty) return null;
    final texto = achados.first.innerText.trim();
    return texto.isEmpty ? null : texto;
  }

  static DateTime? _data(String? bruta) {
    if (bruta == null) return null;
    try {
      // `getlastmodified` vem no formato de data de HTTP (RFC 1123).
      return HttpDate.parse(bruta).toUtc();
    } on HttpException {
      return DateTime.tryParse(bruta)?.toUtc();
    } on FormatException {
      return DateTime.tryParse(bruta)?.toUtc();
    }
  }

  /// Transforma o href devolvido pelo servidor num caminho relativo a raiz do
  /// vault, ou nulo se ele cair fora dela.
  String? _relativo(String href) {
    final Uri uri;
    try {
      uri = Uri.parse(href);
    } on FormatException {
      return null;
    }

    // `pathSegments` ja desfaz o percent-encoding, entao "Aula%20de%20calculo"
    // volta a ser "Aula de calculo" — que e como o arquivo se chama no disco.
    final dele = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final nossos = _base.pathSegments.where((s) => s.isNotEmpty).toList();
    if (dele.length < nossos.length) return null;
    for (var i = 0; i < nossos.length; i++) {
      if (dele[i] != nossos[i]) return null;
    }
    return dele.sublist(nossos.length).join('/');
  }
}
