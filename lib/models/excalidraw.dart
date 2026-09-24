import 'dart:convert';

import 'quadro_da_nota.dart';

/// A ponte entre o quadro daqui e o Excalidraw.
///
/// Duas coisas diferentes falam este formato, e as duas entram por aqui:
///
///   * o arquivo `.excalidraw` — um JSON com `"type":"excalidraw"` e uma lista
///     de elementos — que pode estar no vault vindo de qualquer lugar;
///   * o que o Excalidraw poe na area de transferencia quando se copia uma
///     seleçao, que e o mesmo JSON com `"type":"excalidraw/clipboard"`.
///
/// O que se ganha com isso e simples de dizer: um desenho feito no
/// excalidraw.com entra numa nota com Ctrl+V, e um quadro feito aqui volta para
/// la do mesmo jeito. Nenhum dos dois lados precisa ser o dono do desenho.
///
/// O que *nao* atravessa a ponte, e por que:
///
///   * a rotaçao (`angle`). O quadro daqui nao gira caixa nenhuma, e fingir que
///     gira desenharia o retangulo no lugar errado. O que vem girado entra em
///     pe, na area que ele ocupava.
///   * as imagens. Elas moram fora do `.excalidraw`, num porao de arquivos que
///     o formato guarda a parte; trazer a referencia sem o arquivo encheria a
///     nota de caixas vazias.
///   * o estilo fino — o tracejado, o preenchimento riscado, a transparencia.
///     O quadro daqui tem seis cores com nome e quatro grossuras, de proposito:
///     e uma nota, e nao um editor de vetor.
///
/// O que atravessa e o desenho: onde cada coisa esta, que forma tem, o que esta
/// escrito nela, quem aponta para quem, e por onde a mao passou.
abstract final class Excalidraw {
  /// O que vem escrito em `type` num arquivo, e o que vem na area de
  /// transferencia.
  static const tipoDoArquivo = 'excalidraw';
  static const tipoColado = 'excalidraw/clipboard';

  /// A extensao dos arquivos do formato, com o ponto.
  static const extensao = '.excalidraw';

  /// Se [texto] tem cara de ser um destes dois. Uma pergunta barata, para nao
  /// gastar um `jsonDecode` inteiro em cada coisa que alguem copiou.
  static bool pareceExcalidraw(String texto) {
    final limpo = texto.trimLeft();
    if (!limpo.startsWith('{')) return false;
    return limpo.contains('"excalidraw') && limpo.contains('"elements"');
  }

  /// Le um desenho do Excalidraw. Nulo quando aquilo nao e um.
  ///
  /// Um desenho *vazio* e legitimo, como no quadro daqui: e um arquivo novo,
  /// ainda sem nada dentro.
  static QuadroDaNota? ler(String texto) {
    final Object? bruto;
    try {
      bruto = jsonDecode(texto);
    } on FormatException {
      return null;
    }
    if (bruto is! Map) return null;

    final tipo = bruto['type'];
    if (tipo != tipoDoArquivo && tipo != tipoColado) return null;

    final elementos = bruto['elements'];
    if (elementos is! List) return null;

    return _Leitura(elementos).quadro;
  }

  /// O mesmo quadro no formato do Excalidraw.
  ///
  /// [paraColar] escolhe entre o arquivo — para gravar um `.excalidraw` — e o
  /// pacote da area de transferencia, que e o que o excalidraw.com aceita
  /// quando se aperta Ctrl+V na tela dele.
  static String escrever(QuadroDaNota quadro, {bool paraColar = false}) {
    final elementos = <Map<String, Object?>>[];

    for (final no in quadro.nos) {
      // O painel de fundo vira um retangulo comum, e nao um `frame`: o frame do
      // Excalidraw recorta o que passa da borda dele, e uma caixa que hoje
      // encosta para fora do painel sumiria pela metade do outro lado.
      elementos.add(_caixa(no, quadro));
      if (no.texto.isNotEmpty) elementos.add(_textoDaCaixa(no));
    }

    for (var i = 0; i < quadro.ligacoes.length; i++) {
      elementos.addAll(_flecha(quadro, quadro.ligacoes[i], i));
    }

    for (final traco in quadro.tracos) {
      elementos.add(_traco(traco));
    }

    return const JsonEncoder.withIndent('  ').convert({
      'type': paraColar ? tipoColado : tipoDoArquivo,
      'version': 2,
      'source': 'notas_app',
      'elements': elementos,
      if (!paraColar)
        'appState': {'gridSize': null, 'viewBackgroundColor': '#ffffff'},
      if (!paraColar) 'files': <String, Object?>{},
    });
  }

  // ------------------------------------------------------------- escrevendo

  /// Os campos que todo elemento do Excalidraw tem.
  ///
  /// Escritos por extenso, e nao deixados de fora para o outro lado completar:
  /// o `.excalidraw` tambem e lido por outras ferramentas alem do proprio
  /// Excalidraw, e nem todas sao generosas com o que falta.
  static Map<String, Object?> _comum(
    String id,
    String tipo, {
    required double x,
    required double y,
    required double largura,
    required double altura,
    String contorno = _preto,
    String fundo = 'transparent',
    double grossura = 2,
    List<Map<String, Object?>>? presos,
  }) => {
    'id': id,
    'type': tipo,
    'x': x,
    'y': y,
    'width': largura,
    'height': altura,
    'angle': 0,
    'strokeColor': contorno,
    'backgroundColor': fundo,
    'fillStyle': 'solid',
    'strokeWidth': grossura,
    'strokeStyle': 'solid',
    // O `roughness` do Excalidraw e o nosso traço a mao: 1 e o desenho torto,
    // 0 e a regua.
    'roughness': 1,
    'opacity': 100,
    'groupIds': <String>[],
    'frameId': null,
    'roundness': null,
    'seed': id.hashCode & 0x7FFFFFFF,
    'version': 1,
    'versionNonce': id.hashCode & 0x7FFFFFFF,
    'isDeleted': false,
    'boundElements': presos,
    'updated': 1,
    'link': null,
    'locked': false,
  };

  static Map<String, Object?> _caixa(NoDoQuadro no, QuadroDaNota quadro) {
    final elemento = _comum(
      no.id,
      switch (no.forma) {
        FormaDoNo.decisao => 'diamond',
        FormaDoNo.elipse => 'ellipse',
        _ => 'rectangle',
      },
      x: no.x,
      y: no.y,
      largura: no.largura,
      altura: no.altura,
      presos: [
        if (no.texto.isNotEmpty) {'id': 'texto-${no.id}', 'type': 'text'},
        for (var i = 0; i < quadro.ligacoes.length; i++)
          if (quadro.ligacoes[i].de == no.id ||
              quadro.ligacoes[i].para == no.id)
            {'id': 'flecha-$i', 'type': 'arrow'},
      ],
    );

    // A anotaçao solta nao tem moldura aqui, e nao pode ganhar uma la: e so o
    // texto, e o retangulo em volta seria uma caixa que ninguem desenhou.
    if (no.forma == FormaDoNo.texto) {
      elemento['strokeColor'] = 'transparent';
    }
    // A capsula do inicio e do fim e um retangulo de cantos bem redondos, que e
    // o mais perto que o Excalidraw tem dela.
    if (no.forma == FormaDoNo.terminal) {
      elemento['roundness'] = {'type': 3};
    }

    return elemento;
  }

  static Map<String, Object?> _textoDaCaixa(NoDoQuadro no) => {
    ..._comum(
      'texto-${no.id}',
      'text',
      x: no.x + 8,
      y: no.y + 8,
      largura: no.largura - 16,
      altura: no.altura - 16,
    ),
    'text': no.texto,
    'originalText': no.texto,
    'fontSize': 16,
    // 1 e a "Virgil", a letra manuscrita do Excalidraw — a mesma intençao da
    // letra a mao daqui.
    'fontFamily': 1,
    'textAlign': 'center',
    'verticalAlign': 'middle',
    'containerId': no.id,
    'lineHeight': 1.25,
    'autoResize': true,
  };

  static List<Map<String, Object?>> _flecha(
    QuadroDaNota quadro,
    LigacaoDoQuadro ligacao,
    int indice,
  ) {
    final de = quadro.no(ligacao.de);
    final para = quadro.no(ligacao.para);
    if (de == null || para == null) return const [];

    final id = 'flecha-$indice';
    final inicio = (x: de.centroX, y: de.centroY);
    final fim = (x: para.centroX, y: para.centroY);

    // A flecha do Excalidraw guarda os pontos *relativos* ao proprio canto, e
    // nao em coordenadas da tela.
    final flecha = {
      ..._comum(
        id,
        'arrow',
        x: inicio.x,
        y: inicio.y,
        largura: (fim.x - inicio.x).abs(),
        altura: (fim.y - inicio.y).abs(),
        presos: ligacao.rotulo.isEmpty
            ? null
            : [
                {'id': 'rotulo-$indice', 'type': 'text'},
              ],
      ),
      'points': [
        [0, 0],
        [fim.x - inicio.x, fim.y - inicio.y],
      ],
      'lastCommittedPoint': null,
      // Quem esta preso nas pontas: e isto que faz a flecha continuar grudada
      // na caixa quando ela e arrastada la do outro lado.
      'startBinding': {'elementId': de.id, 'focus': 0, 'gap': 4},
      'endBinding': {'elementId': para.id, 'focus': 0, 'gap': 4},
      'startArrowhead': null,
      'endArrowhead': 'arrow',
      'elbowed': false,
    };

    if (ligacao.rotulo.isEmpty) return [flecha];

    return [
      flecha,
      {
        ..._comum(
          'rotulo-$indice',
          'text',
          x: (inicio.x + fim.x) / 2,
          y: (inicio.y + fim.y) / 2,
          largura: 80,
          altura: 20,
        ),
        'text': ligacao.rotulo,
        'originalText': ligacao.rotulo,
        'fontSize': 16,
        'fontFamily': 1,
        'textAlign': 'center',
        'verticalAlign': 'middle',
        'containerId': id,
        'lineHeight': 1.25,
        'autoResize': true,
      },
    ];
  }

  static Map<String, Object?> _traco(TracoDoQuadro traco) {
    final limites = traco.limites;
    final tipo = switch (traco.tipo) {
      TipoDoTraco.livre => 'freedraw',
      TipoDoTraco.reta => 'line',
      TipoDoTraco.seta => 'arrow',
    };

    return {
      ..._comum(
        traco.id,
        tipo,
        x: traco.x(0),
        y: traco.y(0),
        largura: limites.direita - limites.esquerda,
        altura: limites.base - limites.topo,
        contorno: _hexDe(traco.cor),
        grossura: traco.grossura,
      ),
      'points': [
        for (var i = 0; i < traco.quantos; i++)
          [traco.x(i) - traco.x(0), traco.y(i) - traco.y(0)],
      ],
      'lastCommittedPoint': null,
      if (traco.tipo == TipoDoTraco.livre) ...{
        'pressures': <double>[],
        'simulatePressure': true,
      },
      if (traco.tipo != TipoDoTraco.livre) ...{
        'startBinding': null,
        'endBinding': null,
        'startArrowhead': null,
        'endArrowhead': traco.tipo == TipoDoTraco.seta ? 'arrow' : null,
        'elbowed': false,
      },
    };
  }

  // ------------------------------------------------------------------ cores

  static const _preto = '#1e1e1e';

  /// A cor com que cada tinta nossa sai para o Excalidraw. Sao as cores da
  /// paleta de fabrica dele: um desenho exportado daqui abre la com as cores
  /// que os botoes de la mostram, e nao com um tom parecido fora da paleta.
  static String _hexDe(CorDoTraco cor) => switch (cor) {
    CorDoTraco.tinta => _preto,
    CorDoTraco.indigo => '#6741d9',
    CorDoTraco.ceu => '#1971c2',
    CorDoTraco.verde => '#2f9e44',
    CorDoTraco.ambar => '#f08c00',
    CorDoTraco.rosa => '#e03131',
  };

  /// A tinta mais parecida com [hex], pela distancia entre as duas cores.
  ///
  /// Pela distancia, e nao por uma tabela de nomes: o Excalidraw deixa escolher
  /// qualquer cor, e uma tabela so acertaria as seis de fabrica — todo o resto
  /// cairia em preto.
  static CorDoTraco corDe(Object? hex) {
    final alvo = _rgbDe(hex);
    if (alvo == null) return CorDoTraco.tinta;

    var achada = CorDoTraco.tinta;
    var menor = double.infinity;

    for (final cor in CorDoTraco.values) {
      final dela = _rgbDe(_hexDe(cor))!;
      final distancia =
          ((alvo.r - dela.r) * (alvo.r - dela.r) +
                  (alvo.g - dela.g) * (alvo.g - dela.g) +
                  (alvo.b - dela.b) * (alvo.b - dela.b))
              .toDouble();

      if (distancia < menor) {
        menor = distancia;
        achada = cor;
      }
    }

    return achada;
  }

  static ({int r, int g, int b})? _rgbDe(Object? hex) {
    if (hex is! String) return null;

    var limpo = hex.trim().replaceFirst('#', '');
    // `#abc` e a forma curta de `#aabbcc`.
    if (limpo.length == 3) {
      limpo = limpo.split('').map((c) => '$c$c').join();
    }
    if (limpo.length == 8) limpo = limpo.substring(0, 6);
    if (limpo.length != 6) return null;

    final valor = int.tryParse(limpo, radix: 16);
    if (valor == null) return null;

    return (r: (valor >> 16) & 0xFF, g: (valor >> 8) & 0xFF, b: valor & 0xFF);
  }
}

/// Uma passada pelos elementos de um desenho do Excalidraw.
///
/// Uma classe, e nao uma funçao com meia duzia de mapas soltos: a leitura tem
/// tres voltas — primeiro as caixas, depois os textos que moram dentro delas,
/// depois as flechas que as ligam — e cada volta precisa do que a anterior
/// descobriu.
class _Leitura {
  _Leitura(this._elementos) {
    _caixas();
    _textos();
    _flechasETracos();
  }

  final List<Object?> _elementos;

  final _nos = <NoDoQuadro>[];
  final _ligacoes = <LigacaoDoQuadro>[];
  final _tracos = <TracoDoQuadro>[];

  /// O id de la para o nome daqui. E o que renumera `a1b2c3d4` para `n1`, que
  /// e o que mantem o `.md` legivel.
  final _nomes = <String, String>{};

  QuadroDaNota get quadro =>
      QuadroDaNota(nos: _nos, ligacoes: _ligacoes, tracos: _tracos);

  Iterable<Map<Object?, Object?>> get _vivos sync* {
    for (final bruto in _elementos) {
      // `isDeleted` e o apagado que o Excalidraw guarda para poder desfazer.
      // Ele nao esta no desenho, e nao pode entrar no nosso.
      if (bruto is Map && bruto['isDeleted'] != true) yield bruto;
    }
  }

  void _caixas() {
    for (final elemento in _vivos) {
      final forma = switch (elemento['type']) {
        'rectangle' => FormaDoNo.processo,
        'diamond' => FormaDoNo.decisao,
        'ellipse' => FormaDoNo.elipse,
        'frame' || 'magicframe' => FormaDoNo.fundo,
        // Um texto solto — sem caixa em volta — e a anotaçao solta daqui. O
        // texto que mora dentro de uma caixa e assunto de [_textos].
        'text' when elemento['containerId'] == null => FormaDoNo.texto,
        _ => null,
      };
      if (forma == null) continue;

      final id = elemento['id'];
      if (id is! String || id.isEmpty) continue;

      final largura = _real(elemento['width']) ?? 0;
      final altura = _real(elemento['height']) ?? 0;
      // Elemento sem tamanho nenhum e um resto de um gesto que nao terminou.
      if (largura <= 0 || altura <= 0) continue;

      final nome = 'n${_nos.length + 1}';
      _nomes[id] = nome;

      _nos.add(
        NoDoQuadro(
          id: nome,
          forma: forma,
          x: _real(elemento['x']) ?? 0,
          y: _real(elemento['y']) ?? 0,
          largura: largura.clamp(NoDoQuadro.larguraMinima, 4000),
          altura: altura.clamp(NoDoQuadro.alturaMinima, 4000),
          texto: switch (elemento['type']) {
            'text' => _texto(elemento),
            // O nome do frame e o titulo do painel, e mora noutro campo.
            'frame' || 'magicframe' => _palavra(elemento['name']),
            _ => '',
          },
        ),
      );
    }
  }

  /// O texto que mora dentro de uma caixa vai para a caixa.
  ///
  /// No Excalidraw ele e um elemento a parte, preso ao container por
  /// `containerId`; aqui o texto e um campo da propria caixa. Sem esta volta, o
  /// que estava escrito dentro de cada retangulo chegaria como uma anotaçao
  /// solta jogada por cima dele.
  void _textos() {
    for (final elemento in _vivos) {
      if (elemento['type'] != 'text') continue;

      final dono = elemento['containerId'];
      if (dono is! String) continue;

      final nome = _nomes[dono];
      if (nome == null) continue;

      final indice = _nos.indexWhere((no) => no.id == nome);
      if (indice < 0) continue;

      final texto = _texto(elemento);
      if (texto.isEmpty) continue;

      // Dois textos no mesmo container nao acontece no Excalidraw, mas um
      // arquivo remendado a mao pode ter; o segundo entra embaixo do primeiro,
      // em vez de apagar o que ja estava.
      final atual = _nos[indice].texto;
      _nos[indice] = _nos[indice].com(
        texto: atual.isEmpty ? texto : '$atual\n$texto',
      );
    }
  }

  void _flechasETracos() {
    for (final elemento in _vivos) {
      final tipo = elemento['type'];
      if (tipo != 'arrow' && tipo != 'line' && tipo != 'freedraw') continue;

      // Uma flecha presa nas duas pontas e uma ligaçao daqui: ela segue as
      // caixas quando elas se mexem, que e o que ela quer dizer.
      if (tipo == 'arrow') {
        final de = _nomes[_presoEm(elemento['startBinding'])];
        final para = _nomes[_presoEm(elemento['endBinding'])];

        if (de != null && para != null && de != para) {
          _ligacoes.add(
            LigacaoDoQuadro(de: de, para: para, rotulo: _rotuloDe(elemento)),
          );
          continue;
        }
      }

      // Solta, ela e um traço: guarda o caminho que tem, e nao duas caixas que
      // nao existem.
      final traco = _tracoDe(elemento);
      if (traco != null) _tracos.add(traco);
    }
  }

  TracoDoQuadro? _tracoDe(Map<Object?, Object?> elemento) {
    final crus = elemento['points'];
    if (crus is! List || crus.length < 2) return null;

    final x = _real(elemento['x']) ?? 0;
    final y = _real(elemento['y']) ?? 0;

    final pontos = <double>[];
    for (final par in crus) {
      if (par is! List || par.length < 2) continue;
      final dx = _real(par[0]);
      final dy = _real(par[1]);
      if (dx == null || dy == null) continue;
      // Os pontos de la sao relativos ao canto do proprio elemento.
      pontos
        ..add(x + dx)
        ..add(y + dy);
    }
    if (pontos.length < 4) return null;

    return TracoDoQuadro(
      id: 't${_tracos.length + 1}',
      tipo: switch (elemento['type']) {
        'freedraw' => TipoDoTraco.livre,
        // A flecha solta so continua sendo flecha se ela tinha ponta; a linha
        // com ponta nos dois lados perde uma, que e o que cabe aqui.
        'arrow' when elemento['endArrowhead'] != null => TipoDoTraco.seta,
        'arrow' => TipoDoTraco.reta,
        _ => TipoDoTraco.reta,
      },
      pontos: pontos,
      cor: Excalidraw.corDe(elemento['strokeColor']),
      grossura: (_real(elemento['strokeWidth']) ?? TracoDoQuadro.grossuraPadrao)
          .clamp(TracoDoQuadro.grossuraMinima, TracoDoQuadro.grossuraMaxima),
    );
  }

  /// O que uma flecha do Excalidraw tiver escrito em cima dela.
  String _rotuloDe(Map<Object?, Object?> flecha) {
    final id = flecha['id'];
    if (id is! String) return '';

    for (final elemento in _vivos) {
      if (elemento['type'] == 'text' && elemento['containerId'] == id) {
        return _texto(elemento);
      }
    }
    return '';
  }

  static String? _presoEm(Object? ligadura) =>
      ligadura is Map && ligadura['elementId'] is String
      ? ligadura['elementId'] as String
      : null;

  /// O texto de um elemento de texto. `originalText` e o que foi digitado;
  /// `text` e o mesmo ja quebrado em linhas pela largura da caixa — e essas
  /// quebras sao da largura de la, nao das palavras.
  static String _texto(Map<Object?, Object?> elemento) =>
      _palavra(elemento['originalText']).isNotEmpty
      ? _palavra(elemento['originalText'])
      : _palavra(elemento['text']);

  static String _palavra(Object? valor) => valor is String ? valor.trim() : '';

  static double? _real(Object? valor) => switch (valor) {
    final num n => n.toDouble(),
    _ => null,
  };
}
