/// Como uma coluna e alinhada, conforme os `:` na linha de tracinhos.
enum AlinhamentoDaColuna {
  padrao,
  esquerda,
  centro,
  direita;

  /// O que vai escrito na linha de tracinhos para cada alinhamento.
  String get tracinhos => switch (this) {
    AlinhamentoDaColuna.padrao => '---',
    AlinhamentoDaColuna.esquerda => ':---',
    AlinhamentoDaColuna.centro => ':---:',
    AlinhamentoDaColuna.direita => '---:',
  };

  static AlinhamentoDaColuna dosTracinhos(String celula) {
    final texto = celula.trim();
    final comeca = texto.startsWith(':');
    final termina = texto.endsWith(':');
    if (comeca && termina) return AlinhamentoDaColuna.centro;
    if (comeca) return AlinhamentoDaColuna.esquerda;
    if (termina) return AlinhamentoDaColuna.direita;
    return AlinhamentoDaColuna.padrao;
  }
}

/// Uma tabela do corpo da nota, ja lida em celulas.
///
/// E so um valor: cada mexida devolve outra tabela, e quem chamou decide o que
/// fazer com ela. O editor usa isso para trocar o trecho de Markdown por um
/// novo — o arquivo continua sendo texto, e a grade na tela e uma leitura dele.
class TabelaDaNota {
  const TabelaDaNota({required this.celulas, required this.alinhamentos});

  /// As celulas por linha. A linha 0 e o cabeçalho, que o Markdown exige.
  final List<List<String>> celulas;

  final List<AlinhamentoDaColuna> alinhamentos;

  int get linhas => celulas.length;
  int get colunas => alinhamentos.length;

  /// Uma tabela vazia de [linhas] por [colunas], o cabeçalho incluso na conta.
  factory TabelaDaNota.vazia({required int linhas, required int colunas}) {
    return TabelaDaNota(
      celulas: [for (var i = 0; i < linhas; i++) List.filled(colunas, '')],
      alinhamentos: List.filled(colunas, AlinhamentoDaColuna.padrao),
    );
  }

  /// Le as linhas de uma tabela ja delimitada — cabeçalho, tracinhos e corpo.
  ///
  /// Devolve nulo se as linhas nao formarem uma tabela. Quem acha onde ela
  /// começa e termina no corpo da nota e [BlocosDaNota].
  static TabelaDaNota? ler(List<String> linhas) {
    if (linhas.length < 2) return null;

    final cabecalho = celulasDe(linhas[0]);
    final tracinhos = celulasDe(linhas[1]);
    if (cabecalho.isEmpty || tracinhos.length != cabecalho.length) return null;
    if (!tracinhos.every(eTracinho)) return null;

    final colunas = cabecalho.length;
    return TabelaDaNota(
      celulas: [
        for (final linha in [linhas[0], ...linhas.skip(2)])
          _naMedida(celulasDe(linha), colunas),
      ],
      alinhamentos: [
        for (final t in tracinhos) AlinhamentoDaColuna.dosTracinhos(t),
      ],
    );
  }

  /// A celula de tracinhos que separa o cabeçalho do corpo: `---`, `:---:`.
  static bool eTracinho(String celula) =>
      RegExp(r'^:?-+:?$').hasMatch(celula.trim());

  /// Quebra uma linha em celulas, do jeito que o Markdown quebra.
  ///
  /// As barras das pontas sao opcionais e nao contam como celula vazia. Uma
  /// barra escapada — `\|` — e conteudo, e nao divisao.
  static List<String> celulasDe(String linha) {
    var texto = linha.trim();
    if (texto.startsWith('|')) texto = texto.substring(1);
    if (texto.endsWith('|') && !texto.endsWith(r'\|')) {
      texto = texto.substring(0, texto.length - 1);
    }
    return [
      for (final celula in texto.split(RegExp(r'(?<!\\)\|')))
        celula.trim().replaceAll(r'\|', '|'),
    ];
  }

  /// Uma linha com celulas a menos que o cabeçalho ganha as que faltam; com
  /// celulas a mais perde as que sobram. E o que o Markdown desenha.
  static List<String> _naMedida(List<String> celulas, int colunas) => [
    for (var i = 0; i < colunas; i++) i < celulas.length ? celulas[i] : '',
  ];

  /// De volta para Markdown.
  String get markdown => [
    _linha(celulas.first),
    _linha([for (final a in alinhamentos) a.tracinhos]),
    for (final linha in celulas.skip(1)) _linha(linha),
  ].join('\n');

  /// A barra escrita dentro de uma celula sai escapada: crua, ela seria lida
  /// como divisao de coluna e partiria a celula em duas na proxima leitura.
  static String _linha(List<String> celulas) =>
      '| ${celulas.map((c) => c.replaceAll('|', r'\|')).join(' | ')} |';

  TabelaDaNota _com({
    List<List<String>>? celulas,
    List<AlinhamentoDaColuna>? alinhamentos,
  }) => TabelaDaNota(
    celulas: celulas ?? this.celulas,
    alinhamentos: alinhamentos ?? this.alinhamentos,
  );

  TabelaDaNota comCelula(int linha, int coluna, String texto) {
    // Quebra de linha dentro da celula acabaria com a tabela: no Markdown uma
    // linha e uma linha. O que vier colado de fora entra como espaço.
    final limpo = texto.replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return _com(
      celulas: [
        for (var i = 0; i < linhas; i++)
          [
            for (var j = 0; j < colunas; j++)
              i == linha && j == coluna ? limpo : celulas[i][j],
          ],
      ],
    );
  }

  TabelaDaNota comLinhaDepoisDe(int linha) =>
      _com(celulas: [...celulas]..insert(linha + 1, List.filled(colunas, '')));

  /// Tirar a ultima linha deixaria a tabela so com o cabeçalho, que ainda e
  /// uma tabela valida — mas tirar o proprio cabeçalho nao: a linha seguinte
  /// vira cabeçalho no lugar dele.
  TabelaDaNota semLinha(int linha) {
    if (linhas <= 1) return this;
    return _com(celulas: [...celulas]..removeAt(linha));
  }

  TabelaDaNota comColunaDepoisDe(int coluna) => _com(
    celulas: [
      for (final linha in celulas) [...linha]..insert(coluna + 1, ''),
    ],
    alinhamentos: [...alinhamentos]
      ..insert(coluna + 1, AlinhamentoDaColuna.padrao),
  );

  TabelaDaNota semColuna(int coluna) {
    if (colunas <= 1) return this;
    return _com(
      celulas: [
        for (final linha in celulas) [...linha]..removeAt(coluna),
      ],
      alinhamentos: [...alinhamentos]..removeAt(coluna),
    );
  }

  TabelaDaNota comAlinhamento(int coluna, AlinhamentoDaColuna alinhamento) =>
      _com(
        alinhamentos: [
          for (var i = 0; i < colunas; i++)
            i == coluna ? alinhamento : alinhamentos[i],
        ],
      );
}
