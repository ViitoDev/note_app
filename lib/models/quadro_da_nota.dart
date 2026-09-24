import 'dart:convert';

/// A moldura de um no do quadro, e o que ela quer dizer num fluxograma.
///
/// Sao os papeis que um fluxo tem: onde ele começa e acaba, o que se faz, o
/// que entra ou sai, o que se pergunta, por onde os caminhos se reencontram, o
/// que se anota ao lado sem fazer parte do fluxo, e o que agrupa um punhado
/// disso. Mais formas que estas seriam desenho, e nao significado — e para
/// desenho livre existe o traço, que nao finge ter papel nenhum.
enum FormaDoNo {
  /// Inicio e fim: capsula, os cantos totalmente arredondados.
  terminal,

  /// Uma açao do fluxo: retangulo.
  processo,

  /// Um dado que entra ou sai — ler, escrever, mostrar: paralelogramo.
  entrada,

  /// Uma pergunta, de onde saem dois caminhos: losango.
  decisao,

  /// O conector: por onde dois caminhos se reencontram, ou por onde o fluxo
  /// salta para outra parte do desenho. E tambem a terceira forma basica de
  /// quem so quer desenhar — retangulo, losango, elipse.
  elipse,

  /// Anotaçao solta, sem moldura nenhuma.
  texto,

  /// Um painel atras dos outros, com um nome no alto: o que agrupa um punhado
  /// de caixas numa parte so — a "UCP" que contem a unidade de controle e a
  /// logico-aritmetica.
  ///
  /// Nao e passo do fluxo, e cenario dele: fica atras de tudo, e arrasta-lo
  /// leva junto o que estiver em cima.
  fundo;

  static FormaDoNo doNome(Object? nome) => FormaDoNo.values.firstWhere(
    (f) => f.name == nome,
    orElse: () => FormaDoNo.processo,
  );

  /// Com que tamanho um no desta forma nasce.
  ///
  /// O losango e o maior: a pergunta e sempre mais comprida que a resposta, e
  /// as pontas do losango comem a largura util no meio.
  ({double largura, double altura}) get tamanhoInicial => switch (this) {
    FormaDoNo.terminal => (largura: 128, altura: 48),
    FormaDoNo.processo => (largura: 168, altura: 56),
    // Mais larga que o retangulo: a inclinaçao come as pontas, e o texto util
    // fica no miolo.
    FormaDoNo.entrada => (largura: 192, altura: 56),
    FormaDoNo.decisao => (largura: 208, altura: 104),
    // Pelo mesmo motivo do losango: a curva come os cantos, e o texto so cabe
    // na barriga.
    FormaDoNo.elipse => (largura: 168, altura: 96),
    // Pequena: a anotaçao solta nao tem moldura para preencher, e a area dela
    // cresce sozinha com o que for escrito. Nascer larga deixaria um retangulo
    // invisivel grande demais em volta de duas palavras.
    FormaDoNo.texto => (largura: 96, altura: 40),
    // Grande: ele nasce para caber caixas dentro.
    FormaDoNo.fundo => (largura: 320, altura: 240),
  };

  String get rotulo => switch (this) {
    FormaDoNo.terminal => 'Inicio/Fim',
    FormaDoNo.processo => 'Processo',
    FormaDoNo.entrada => 'Entrada/Saida',
    FormaDoNo.decisao => 'Decisao',
    FormaDoNo.elipse => 'Elipse',
    FormaDoNo.texto => 'Texto',
    FormaDoNo.fundo => 'Fundo',
  };

  /// Se esta forma e cenario, e nao passo do fluxo. Muda a ordem de desenho e
  /// a de quem o ponteiro pega primeiro.
  bool get eFundo => this == FormaDoNo.fundo;
}

/// A cor de um traço, pelo nome.
///
/// Nome, e nao `#rrggbb`: o bloco do quadro mora dentro da nota, e a nota
/// viaja — para outra maquina, para outro tema, para o editor de Markdown de
/// outra pessoa. Uma cor fixa em hexadecimal que fica boa neste fundo escuro
/// some num fundo claro. O nome diz a intençao, e quem desenha decide com que
/// tinta o tema de agora escreve aquilo.
enum CorDoTraco {
  /// A cor do texto: o traço que e so traço.
  tinta,

  /// A cor do app.
  indigo,

  /// A cor do que voce escreveu — a mesma dos rotulos e das tabelas.
  ceu,

  verde,
  ambar,
  rosa;

  static CorDoTraco doNome(Object? nome) => CorDoTraco.values.firstWhere(
    (c) => c.name == nome,
    orElse: () => CorDoTraco.tinta,
  );

  String get rotulo => switch (this) {
    CorDoTraco.tinta => 'Tinta',
    CorDoTraco.indigo => 'Indigo',
    CorDoTraco.ceu => 'Ceu',
    CorDoTraco.verde => 'Verde',
    CorDoTraco.ambar => 'Ambar',
    CorDoTraco.rosa => 'Rosa',
  };
}

/// De que jeito um traço foi feito.
///
/// Os tres sao o mesmo punhado de pontos, com o mesmo arquivo por tras; o que
/// muda e quantos pontos a mao deixa e o que se desenha no fim deles. Ter um
/// tipo so — e nao tres classes — e o que deixa a borracha, o arrasto e a
/// paleta valerem para os tres sem repetiçao.
enum TipoDoTraco {
  /// Ponto a ponto, por onde a caneta passou.
  livre,

  /// Dois pontos: a reta entre onde a mao apertou e onde soltou.
  reta,

  /// A mesma reta, com ponta no fim — a flecha solta, que aponta para o que
  /// quiser sem estar presa a caixa nenhuma. E o que a ligaçao nao faz:
  /// ligaçao gruda em duas caixas, e some quando uma delas some.
  seta;

  static TipoDoTraco doNome(Object? nome) => TipoDoTraco.values.firstWhere(
    (t) => t.name == nome,
    orElse: () => TipoDoTraco.livre,
  );

  /// Se este tipo guarda so as duas pontas, em vez do caminho inteiro da mao.
  bool get ePonta => this != TipoDoTraco.livre;

  String get rotulo => switch (this) {
    TipoDoTraco.livre => 'Caneta',
    TipoDoTraco.reta => 'Reta',
    TipoDoTraco.seta => 'Seta solta',
  };
}

/// Um traço solto do quadro: por onde a mao passou, com que tinta e com que
/// grossura.
///
/// Solto de proposito. A caixa e a flecha carregam significado — sao passo e
/// sequencia —, e ha desenho que nao tem significado nenhum: o circulo em
/// volta do que importa, a chave que junta tres linhas, o rabisco que so quem
/// desenhou entende. Esse desenho nao cabe numa caixa, e sem ele o quadro
/// obriga a escrever fluxograma quando a cabeça ainda esta rascunhando.
class TracoDoQuadro {
  const TracoDoQuadro({
    required this.id,
    required this.pontos,
    this.tipo = TipoDoTraco.livre,
    this.cor = CorDoTraco.tinta,
    this.grossura = grossuraPadrao,
  });

  /// Nome curto e estavel. Nada aponta para um traço — nao ha flecha que
  /// encoste nele —, mas e por ele que a borracha e o arrasto dizem em qual
  /// dos traços estao mexendo.
  final String id;

  final TipoDoTraco tipo;

  /// O caminho, em `x, y, x, y…`, nas coordenadas do quadro.
  ///
  /// Uma lista rasa, e nao uma lista de pares: um traço a mao tem dezenas de
  /// pontos, e `[12,40,18,44]` ocupa no arquivo menos da metade de
  /// `[{"x":12,"y":40},{"x":18,"y":44}]` — o traço inteiro continua cabendo
  /// numa linha, que e o que mantem o `diff` da nota legivel.
  final List<double> pontos;

  final CorDoTraco cor;
  final double grossura;

  static const grossuraPadrao = 2.0;

  /// As grossuras da barra. Quatro, e nao um controle continuo: escolher entre
  /// quatro e um clique, e a diferença entre 2,0 e 2,3 nao se ve.
  static const grossuras = [1.0, 2.0, 4.0, 8.0];

  static const grossuraMinima = 0.5;
  static const grossuraMaxima = 32.0;

  int get quantos => pontos.length ~/ 2;

  double x(int i) => pontos[i * 2];
  double y(int i) => pontos[i * 2 + 1];

  /// Um ponto so nao e traço: e um clique que nao virou nada.
  bool get valido => quantos >= 2;

  /// O retangulo que o traço ocupa, sem contar a grossura.
  ({double esquerda, double topo, double direita, double base}) get limites {
    var esquerda = x(0);
    var topo = y(0);
    var direita = x(0);
    var base = y(0);

    for (var i = 1; i < quantos; i++) {
      if (x(i) < esquerda) esquerda = x(i);
      if (x(i) > direita) direita = x(i);
      if (y(i) < topo) topo = y(i);
      if (y(i) > base) base = y(i);
    }

    return (esquerda: esquerda, topo: topo, direita: direita, base: base);
  }

  TracoDoQuadro com({
    TipoDoTraco? tipo,
    List<double>? pontos,
    CorDoTraco? cor,
    double? grossura,
  }) => TracoDoQuadro(
    id: id,
    tipo: tipo ?? this.tipo,
    pontos: pontos ?? this.pontos,
    cor: cor ?? this.cor,
    grossura: grossura ?? this.grossura,
  );

  /// O traço inteiro deslocado. E assim que ele e arrastado: ponto a ponto,
  /// porque nao ha "posiçao" de um traço separada do caminho dele.
  TracoDoQuadro movido(double dx, double dy) => com(
    pontos: [
      for (var i = 0; i < pontos.length; i++) pontos[i] + (i.isEven ? dx : dy),
    ],
  );

  Map<String, Object?> get json => {
    'id': id,
    if (tipo != TipoDoTraco.livre) 'tipo': tipo.name,
    if (cor != CorDoTraco.tinta) 'cor': cor.name,
    if (grossura != grossuraPadrao) 'grossura': _numero(grossura),
    'pontos': [for (final valor in pontos) _numero(valor)],
  };

  static TracoDoQuadro? doJson(Object? bruto) {
    if (bruto is! Map) return null;
    final id = bruto['id'];
    if (id is! String || id.isEmpty) return null;

    final crus = bruto['pontos'];
    if (crus is! List) return null;

    final pontos = <double>[];
    for (final valor in crus) {
      final numero = _real(valor);
      if (numero == null) return null;
      pontos.add(numero);
    }

    // Numero impar de coordenadas e um ponto pela metade: nao da para saber se
    // o que sobrou era um x sem y, ou lixo no fim da linha.
    if (pontos.length < 4 || pontos.length.isOdd) return null;

    final traco = TracoDoQuadro(
      id: id,
      tipo: TipoDoTraco.doNome(bruto['tipo']),
      pontos: pontos,
      cor: CorDoTraco.doNome(bruto['cor']),
      grossura: (_real(bruto['grossura']) ?? grossuraPadrao).clamp(
        grossuraMinima,
        grossuraMaxima,
      ),
    );

    // Reta e seta sao duas pontas: o que vier a mais foi engano de quem
    // escreveu o arquivo, e desenhar isso daria uma reta com cotovelo.
    if (!traco.tipo.ePonta || traco.quantos == 2) return traco;
    return traco.com(
      pontos: [
        traco.x(0),
        traco.y(0),
        traco.x(traco.quantos - 1),
        traco.y(traco.quantos - 1),
      ],
    );
  }

  /// Meio pixel e mais fino do que a tela mostra: guardar `18.437261` seria
  /// encher a nota de digitos que ninguem ve. Uma casa decimal basta, e o que
  /// for redondo sai inteiro.
  static Object _numero(double valor) {
    final arredondado = (valor * 10).round() / 10;
    return arredondado == arredondado.roundToDouble()
        ? arredondado.round()
        : arredondado;
  }

  static double? _real(Object? valor) => switch (valor) {
    final num n => n.toDouble(),
    _ => null,
  };
}

/// Uma caixa do quadro: onde ela esta, que tamanho tem e o que esta escrito
/// dentro dela.
///
/// So valor, como o resto do modelo: mexer devolve outro no, e quem chamou
/// decide o que fazer com ele.
class NoDoQuadro {
  const NoDoQuadro({
    required this.id,
    required this.forma,
    required this.x,
    required this.y,
    required this.largura,
    required this.altura,
    this.texto = '',
  });

  /// Nome curto e estavel, usado pelas ligaçoes para apontar para este no.
  final String id;

  final FormaDoNo forma;

  /// Canto superior esquerdo, em pixels do quadro — nao da tela. O que a tela
  /// mostra depende do zoom e do deslocamento, e nada disso e gravado.
  final double x;
  final double y;

  final double largura;
  final double altura;

  /// O que esta escrito dentro da caixa.
  ///
  /// Quando ele e *so* um `[[wikilink]]`, a caixa deixa de ser uma caixa com
  /// texto e passa a ser um atalho para aquela nota do vault — ver
  /// [Wikilink.sozinho]. Nao ha campo separado para isso de proposito: o `.md`
  /// ja tem um jeito de apontar para uma nota, e o grafo ja le aquele jeito.
  final String texto;

  /// Menor que isto a caixa deixa de caber o proprio texto.
  static const larguraMinima = 72.0;
  static const alturaMinima = 40.0;

  double get centroX => x + largura / 2;
  double get centroY => y + altura / 2;

  NoDoQuadro com({
    FormaDoNo? forma,
    double? x,
    double? y,
    double? largura,
    double? altura,
    String? texto,
  }) => NoDoQuadro(
    id: id,
    forma: forma ?? this.forma,
    x: x ?? this.x,
    y: y ?? this.y,
    largura: largura ?? this.largura,
    altura: altura ?? this.altura,
    texto: texto ?? this.texto,
  );

  Map<String, Object?> get json => {
    'id': id,
    'forma': forma.name,
    'x': _numero(x),
    'y': _numero(y),
    'largura': _numero(largura),
    'altura': _numero(altura),
    if (texto.isNotEmpty) 'texto': texto,
  };

  static NoDoQuadro? doJson(Object? bruto) {
    if (bruto is! Map) return null;
    final id = bruto['id'];
    if (id is! String || id.isEmpty) return null;

    final forma = FormaDoNo.doNome(bruto['forma']);
    final inicial = forma.tamanhoInicial;

    return NoDoQuadro(
      id: id,
      forma: forma,
      x: _real(bruto['x']) ?? 0,
      y: _real(bruto['y']) ?? 0,
      largura: _real(bruto['largura']) ?? inicial.largura,
      altura: _real(bruto['altura']) ?? inicial.altura,
      texto: bruto['texto'] is String ? bruto['texto'] as String : '',
    );
  }

  /// Coordenada inteira sai inteira do arquivo: `320` e mais facil de ler — e
  /// de comparar entre duas versoes da nota — do que `320.0`.
  static Object _numero(double valor) =>
      valor == valor.roundToDouble() ? valor.round() : valor;

  static double? _real(Object? valor) => switch (valor) {
    final num n => n.toDouble(),
    _ => null,
  };
}

/// Uma flecha de um no para outro, com o que estiver escrito em cima dela.
///
/// O rotulo existe por causa da decisao: e ele que diz qual das duas saidas do
/// losango e o "sim" e qual e o "nao".
class LigacaoDoQuadro {
  const LigacaoDoQuadro({
    required this.de,
    required this.para,
    this.rotulo = '',
  });

  final String de;
  final String para;
  final String rotulo;

  LigacaoDoQuadro com({String? rotulo}) =>
      LigacaoDoQuadro(de: de, para: para, rotulo: rotulo ?? this.rotulo);

  Map<String, Object?> get json => {
    'de': de,
    'para': para,
    if (rotulo.isNotEmpty) 'rotulo': rotulo,
  };

  static LigacaoDoQuadro? doJson(Object? bruto) {
    if (bruto is! Map) return null;
    final de = bruto['de'];
    final para = bruto['para'];
    if (de is! String || para is! String || de == para) return null;

    return LigacaoDoQuadro(
      de: de,
      para: para,
      rotulo: bruto['rotulo'] is String ? bruto['rotulo'] as String : '',
    );
  }
}

/// Um quadro do corpo da nota — caixas soltas numa area sem fim, ligadas por
/// flechas e rabiscadas por cima — ja lido do texto.
///
/// Mora no `.md` como um bloco de cerca, igual a um bloco de codigo, com a
/// palavra `quadro` na cerca e um JSON de uma entidade por linha dentro. Duas
/// razoes para ser assim, e nao um arquivo proprio ao lado da nota:
///
///   * a nota continua sendo *um* arquivo — copiar, sincronizar ou versionar a
///     nota leva o quadro junto, sem anexo para se perder no caminho;
///   * o que o app nao entende, o Markdown ainda entende: em qualquer outro
///     editor o bloco aparece como um trecho de codigo, e nao como sujeira.
///
/// Uma entidade por linha porque o arquivo e lido por gente e por `diff`:
/// mover uma caixa muda uma linha, e nao a nota inteira.
class QuadroDaNota {
  const QuadroDaNota({
    required this.nos,
    required this.ligacoes,
    this.tracos = const [],
    this.aMao = true,
  });

  final List<NoDoQuadro> nos;
  final List<LigacaoDoQuadro> ligacoes;

  /// O que foi desenhado a mao por cima. Depois das caixas nesta lista e
  /// depois delas na tela: rabisco e o que se poe *em cima* do que ja estava.
  final List<TracoDoQuadro> tracos;

  /// Se o quadro e desenhado com o traço torto de quem desenhou a mao, em vez
  /// da regua.
  ///
  /// Verdadeiro quando o arquivo nao diz nada, e nao falso. Um fluxograma
  /// perfeito parece decidido; o mesmo fluxograma torto parece um rascunho — e
  /// rascunho e o que um quadro dentro de uma nota quase sempre e. Quem quiser
  /// a regua desliga no interruptor da barra, e ai o `.md` guarda `"mao":false`
  /// para lembrar disso.
  final bool aMao;

  static const vazio = QuadroDaNota(nos: [], ligacoes: []);

  /// A palavra escrita na cerca que abre o bloco.
  static const marcador = 'quadro';

  bool get semNada => nos.isEmpty && tracos.isEmpty;

  NoDoQuadro? no(String id) {
    for (final no in nos) {
      if (no.id == id) return no;
    }
    return null;
  }

  TracoDoQuadro? traco(String id) {
    for (final traco in tracos) {
      if (traco.id == id) return traco;
    }
    return null;
  }

  /// Le o que estava dentro da cerca.
  ///
  /// Devolve nulo se aquilo nao for um quadro — e ai quem chamou deixa o bloco
  /// como texto, para poder ser consertado a mao. Vazio, no entanto, e um
  /// quadro legitimo: e assim que ele nasce, antes da primeira caixa.
  static QuadroDaNota? ler(String dentro) {
    if (dentro.trim().isEmpty) return vazio;

    final Object? bruto;
    try {
      bruto = jsonDecode(dentro);
    } on FormatException {
      return null;
    }
    if (bruto is! Map) return null;

    final nos = <NoDoQuadro>[];
    final vistos = <String>{};
    for (final item in _lista(bruto['nos'])) {
      final no = NoDoQuadro.doJson(item);
      // Id repetido e ambiguidade: as ligaçoes apontam por id, e duas caixas
      // com o mesmo nome deixariam a flecha sem saber em qual encostar.
      if (no != null && vistos.add(no.id)) nos.add(no);
    }

    final ligacoes = <LigacaoDoQuadro>[];
    for (final item in _lista(bruto['ligacoes'])) {
      final ligacao = LigacaoDoQuadro.doJson(item);
      // Flecha para caixa que nao existe nao tem onde encostar.
      if (ligacao != null &&
          vistos.contains(ligacao.de) &&
          vistos.contains(ligacao.para)) {
        ligacoes.add(ligacao);
      }
    }

    final tracos = <TracoDoQuadro>[];
    final tracosVistos = <String>{};
    for (final item in _lista(bruto['tracos'])) {
      final traco = TracoDoQuadro.doJson(item);
      if (traco != null && traco.valido && tracosVistos.add(traco.id)) {
        tracos.add(traco);
      }
    }

    return QuadroDaNota(
      nos: nos,
      ligacoes: ligacoes,
      tracos: tracos,
      aMao: bruto['mao'] is bool ? bruto['mao'] as bool : true,
    );
  }

  static List<Object?> _lista(Object? bruto) =>
      bruto is List ? bruto : const [];

  /// De volta para o Markdown, cercas inclusive — e o bloco inteiro que o
  /// editor troca no texto da nota.
  String get markdown {
    final linhas = <String>['```$marcador', '{"nos":['];
    _entidades(linhas, [for (final no in nos) no.json]);

    linhas.add('],"ligacoes":[');
    _entidades(linhas, [for (final ligacao in ligacoes) ligacao.json]);

    // A seçao dos traços so aparece quando ha traço. Sem isto, abrir e fechar
    // uma nota antiga acrescentaria duas linhas ao `.md` dela sem que nada
    // tivesse sido desenhado.
    if (tracos.isNotEmpty) {
      linhas.add('],"tracos":[');
      _entidades(linhas, [for (final traco in tracos) traco.json]);
    }

    // Pelo mesmo motivo: `"mao":true` e o que o arquivo ja diz calado.
    linhas
      ..add(aMao ? ']}' : '],"mao":false}')
      ..add('```');

    return linhas.join('\n');
  }

  static void _entidades(
    List<String> linhas,
    List<Map<String, Object?>> itens,
  ) {
    for (var i = 0; i < itens.length; i++) {
      linhas.add('${jsonEncode(itens[i])}${i == itens.length - 1 ? '' : ','}');
    }
  }

  /// O primeiro `n` livre. Sequencial, e nao sorteado, porque este texto vai
  /// ser lido: `n3` diz mais que um punhado de letras aleatorias.
  String get idLivre => _idLivre('n', {for (final no in nos) no.id});

  /// O mesmo para os traços, com a propria letra: `t1` e um traço e `n1` e uma
  /// caixa, e quem abre o `.md` ve isso sem precisar procurar.
  String get idLivreDoTraco =>
      _idLivre('t', {for (final traco in tracos) traco.id});

  static String _idLivre(String letra, Set<String> usados) {
    for (var i = 1; ; i++) {
      final id = '$letra$i';
      if (!usados.contains(id)) return id;
    }
  }

  QuadroDaNota _com({
    List<NoDoQuadro>? nos,
    List<LigacaoDoQuadro>? ligacoes,
    List<TracoDoQuadro>? tracos,
    bool? aMao,
  }) => QuadroDaNota(
    nos: nos ?? this.nos,
    ligacoes: ligacoes ?? this.ligacoes,
    tracos: tracos ?? this.tracos,
    aMao: aMao ?? this.aMao,
  );

  /// Acrescenta o no, ou troca o que ja tinha aquele id.
  QuadroDaNota comNo(NoDoQuadro no) {
    final indice = nos.indexWhere((n) => n.id == no.id);
    if (indice < 0) return _com(nos: [...nos, no]);
    return _com(nos: [...nos]..[indice] = no);
  }

  /// Tira o no e, com ele, as flechas que chegavam nele ou saiam dele —
  /// sozinhas elas apontariam para o vazio.
  QuadroDaNota semNo(String id) => _com(
    nos: [
      for (final no in nos)
        if (no.id != id) no,
    ],
    ligacoes: [
      for (final ligacao in ligacoes)
        if (ligacao.de != id && ligacao.para != id) ligacao,
    ],
  );

  /// Acrescenta o traço, ou troca o que ja tinha aquele id.
  ///
  /// Traço sem dois pontos nao entra: e o clique que nao virou desenho, e
  /// guardar isso encheria a nota de traços invisiveis.
  QuadroDaNota comTraco(TracoDoQuadro traco) {
    if (!traco.valido) return this;

    final indice = tracos.indexWhere((t) => t.id == traco.id);
    if (indice < 0) return _com(tracos: [...tracos, traco]);
    return _com(tracos: [...tracos]..[indice] = traco);
  }

  QuadroDaNota semTraco(String id) => _com(
    tracos: [
      for (final traco in tracos)
        if (traco.id != id) traco,
    ],
  );

  QuadroDaNota comMao(bool aMao) => _com(aMao: aMao);

  /// Traz tudo o que ha em [outro] para dentro deste quadro, deslocado de [dx]
  /// e [dy].
  ///
  /// Os nomes do que chega sao renumerados. Dois quadros feitos em separado tem
  /// ambos um `n1`, e juntar sem renumerar faria uma flecha do quadro de casa
  /// encostar numa caixa que veio de fora — ou, pior, a caixa de fora sumir
  /// dentro da de casa, porque [comNo] troca quem tem o mesmo id.
  ///
  /// O traço a mao continua sendo o deste quadro: e uma escolha de como este
  /// desenho se parece, e nao um pertence do que foi colado nele.
  QuadroDaNota juntar(QuadroDaNota outro, {double dx = 0, double dy = 0}) {
    final nomes = <String, String>{};
    final usados = {for (final no in nos) no.id};

    for (final no in outro.nos) {
      var i = usados.length + 1;
      while (usados.contains('n$i')) {
        i++;
      }
      nomes[no.id] = 'n$i';
      usados.add('n$i');
    }

    final usadosTraco = {for (final traco in tracos) traco.id};
    final nomesTraco = <String, String>{};

    for (final traco in outro.tracos) {
      var i = usadosTraco.length + 1;
      while (usadosTraco.contains('t$i')) {
        i++;
      }
      nomesTraco[traco.id] = 't$i';
      usadosTraco.add('t$i');
    }

    return _com(
      nos: [
        ...nos,
        for (final no in outro.nos)
          NoDoQuadro(
            id: nomes[no.id]!,
            forma: no.forma,
            x: no.x + dx,
            y: no.y + dy,
            largura: no.largura,
            altura: no.altura,
            texto: no.texto,
          ),
      ],
      ligacoes: [
        ...ligacoes,
        for (final ligacao in outro.ligacoes)
          LigacaoDoQuadro(
            de: nomes[ligacao.de]!,
            para: nomes[ligacao.para]!,
            rotulo: ligacao.rotulo,
          ),
      ],
      tracos: [
        ...tracos,
        for (final traco in outro.tracos)
          TracoDoQuadro(
            id: nomesTraco[traco.id]!,
            tipo: traco.tipo,
            pontos: traco.movido(dx, dy).pontos,
            cor: traco.cor,
            grossura: traco.grossura,
          ),
      ],
    );
  }

  /// Liga duas caixas. Ligaçao repetida — ou de uma caixa para ela mesma — nao
  /// entra: seriam duas flechas empilhadas no mesmo caminho.
  QuadroDaNota comLigacao(String de, String para) {
    if (de == para || no(de) == null || no(para) == null) return this;
    if (ligacoes.any((l) => l.de == de && l.para == para)) return this;

    return _com(
      ligacoes: [
        ...ligacoes,
        LigacaoDoQuadro(de: de, para: para),
      ],
    );
  }

  QuadroDaNota semLigacao(int indice) {
    if (indice < 0 || indice >= ligacoes.length) return this;
    return _com(ligacoes: [...ligacoes]..removeAt(indice));
  }

  QuadroDaNota comRotulo(int indice, String rotulo) {
    if (indice < 0 || indice >= ligacoes.length) return this;
    return _com(
      ligacoes: [...ligacoes]..[indice] = ligacoes[indice].com(rotulo: rotulo),
    );
  }
}
