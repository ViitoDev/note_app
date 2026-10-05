import 'quadro_da_nota.dart';
import 'tabela_da_nota.dart';

/// Um pedaço do corpo da nota, com o lugar exato que ele ocupa no texto.
///
/// [inicio] e [fim] sao indices no corpo: `corpo.substring(inicio, fim)` e o
/// trecho que este bloco representa. E por eles que o editor troca so o pedaço
/// mexido, sem reescrever a nota inteira.
sealed class BlocoDaNota {
  const BlocoDaNota({required this.inicio, required this.fim});

  final int inicio;
  final int fim;
}

/// Markdown cru, escrito num campo de texto comum.
class BlocoDeTexto extends BlocoDaNota {
  const BlocoDeTexto({
    required super.inicio,
    required super.fim,
    required this.texto,
  });

  final String texto;
}

/// Uma tabela, desenhada como grade.
class BlocoDeTabela extends BlocoDaNota {
  const BlocoDeTabela({
    required super.inicio,
    required super.fim,
    required this.tabela,
  });

  final TabelaDaNota tabela;
}

/// Um quadro, desenhado como area de caixas e flechas.
class BlocoDeQuadro extends BlocoDaNota {
  const BlocoDeQuadro({
    required super.inicio,
    required super.fim,
    required this.quadro,
  });

  final QuadroDaNota quadro;
}

/// Um bloco de codigo, desenhado como balao: a linguagem em cima, o codigo
/// embaixo.
///
/// As duas cercas sao guardadas como estavam no arquivo — recuo, crases ou
/// tis, quantas forem —, e so o que foi mexido e reescrito. Trocar uma letra
/// do codigo nao pode mudar a cerca que o usuario escreveu.
class BlocoDeCodigo extends BlocoDaNota {
  const BlocoDeCodigo({
    required super.inicio,
    required super.fim,
    required this.abertura,
    required this.codigo,
    required this.fechamento,
  });

  /// A linha de cima, ```` ```python ```` por exemplo.
  final String abertura;

  /// O que esta entre as cercas, sem a quebra da ultima linha.
  final String codigo;

  /// A linha de baixo, que so fecha.
  final String fechamento;

  static final _partesDaAbertura = RegExp(r'^(\s*(?:`{3,}|~{3,}))[ \t]*(.*)$');

  /// O nome escrito depois da cerca, como foi escrito: `Java`, `py`, `c#`.
  String get linguagem =>
      _partesDaAbertura.firstMatch(abertura)?.group(2)?.trim() ?? '';

  /// O bloco como ele fica no arquivo.
  ///
  /// Codigo vazio nao ganha linha em branco entre as cercas: e assim que o
  /// balao novo nasce, e abrir e fechar um balao sem escrever nada nao pode
  /// deixar a nota diferente.
  String get markdown => codigo.isEmpty
      ? '$abertura\n$fechamento'
      : '$abertura\n$codigo\n$fechamento';

  BlocoDeCodigo comCodigo(String novo) => BlocoDeCodigo(
    inicio: inicio,
    fim: fim,
    abertura: abertura,
    codigo: novo,
    fechamento: fechamento,
  );

  /// Troca so o nome da linguagem; a cerca e o recuo ficam.
  BlocoDeCodigo comLinguagem(String nova) {
    final cerca = _partesDaAbertura.firstMatch(abertura)?.group(1) ?? '```';
    return BlocoDeCodigo(
      inicio: inicio,
      fim: fim,
      abertura: '$cerca${nova.trim()}',
      codigo: codigo,
      fechamento: fechamento,
    );
  }
}

/// Separa o corpo da nota em texto, tabelas e quadros.
///
/// O editor desenha o texto no proprio campo, com tres exceçoes que viram
/// widget: tabela — contar barras para saber em que coluna se esta e trabalho
/// de maquina —, quadro, que em texto e um punhado de coordenadas, e bloco de
/// codigo, que ganha um balao com a linguagem em cima.
abstract final class BlocosDaNota {
  static List<BlocoDaNota> de(String corpo) {
    final linhas = _linhasDe(corpo);
    final blocos = <BlocoDaNota>[];

    var inicioDoTexto = 0;
    var depoisDeDesenho = false;
    var emCodigo = false;
    var i = 0;

    /// O texto entre [de] e [ate], sem as quebras que so separam o texto de um
    /// bloco desenhado vizinho.
    ///
    /// Essas quebras continuam no arquivo — sem elas a tabela grudaria na
    /// linha de cima —, mas no campo virariam linhas em branco que ninguem
    /// escreveu, abrindo um buraco em volta de toda tabela. Some a quebra da
    /// linha e mais uma linha em branco, a que o Markdown pede entre blocos; a
    /// partir da segunda, a linha em branco foi o usuario que deu, e aparece.
    BlocoDeTexto texto(int de, int ate, {required bool antesDeDesenho}) {
      var quebras = 0;
      while (de + quebras < ate && corpo[de + quebras] == '\n') {
        quebras++;
      }
      final soQuebras = de + quebras == ate;

      if (depoisDeDesenho) {
        // So quebras entre dois desenhados: pelo menos uma fica de cada lado
        // do campo, senao o que se escrevesse nele grudaria num dos dois. Com
        // uma quebra so, nao ha como, e ela continua no campo.
        final limite = soQuebras && antesDeDesenho && quebras > 0
            ? quebras - 1
            : quebras;
        de += limite < 2 ? limite : 2;
      }
      if (antesDeDesenho && !(soQuebras && depoisDeDesenho && quebras == 1)) {
        for (var n = 0; n < 2 && de < ate && corpo[ate - 1] == '\n'; n++) {
          ate--;
        }
      }
      return BlocoDeTexto(
        inicio: de,
        fim: ate,
        texto: corpo.substring(de, ate),
      );
    }

    /// Fecha o texto acumulado ate [ate] e entrega o bloco desenhado que
    /// começa ali, do jeito que os dois casos abaixo precisam.
    void desenhado(int ate, int fim, BlocoDaNota Function() bloco) {
      blocos.add(texto(inicioDoTexto, ate, antesDeDesenho: true));
      blocos.add(bloco());
      inicioDoTexto = fim;
      depoisDeDesenho = true;
    }

    while (i < linhas.length) {
      final linha = linhas[i];

      // O quadro tambem mora numa cerca, e a dele e reconhecida antes de a
      // cerca virar bloco de codigo — senao o proprio quadro seria o exemplo
      // que nao se desenha.
      final fimDoQuadro = emCodigo ? -1 : _ateOndeVaiOQuadro(linhas, i);
      if (fimDoQuadro >= 0) {
        final quadro = QuadroDaNota.ler(
          [
            // So o que esta entre as cercas: a de cima diz a linguagem, e a de
            // baixo apenas fecha.
            for (var j = i + 1; j < fimDoQuadro - 1; j++) linhas[j].texto,
          ].join('\n'),
        );

        if (quadro != null) {
          final fim = linhas[fimDoQuadro - 1].fim;
          desenhado(
            linha.inicio,
            fim,
            () => BlocoDeQuadro(inicio: linha.inicio, fim: fim, quadro: quadro),
          );
          i = fimDoQuadro;
          continue;
        }
      }

      // Bloco de codigo fechado vira balao. Tem prioridade sobre a tabela:
      // uma tabela ali dentro esta sendo mostrada como exemplo, e desenha-la
      // seria apagar o exemplo.
      final fimDoCodigo = emCodigo ? -1 : _ateOndeVaiOCodigo(linhas, i);
      if (fimDoCodigo >= 0) {
        final fim = linhas[fimDoCodigo - 1].fim;
        desenhado(
          linha.inicio,
          fim,
          () => BlocoDeCodigo(
            inicio: linha.inicio,
            fim: fim,
            abertura: linha.texto,
            codigo: [
              for (var j = i + 1; j < fimDoCodigo - 1; j++) linhas[j].texto,
            ].join('\n'),
            fechamento: linhas[fimDoCodigo - 1].texto,
          ),
        );
        i = fimDoCodigo;
        continue;
      }

      // Cerca sem fechamento: o resto da nota e codigo sendo escrito, e fica
      // como texto ate a cerca de baixo aparecer.
      if (_cerca.hasMatch(linha.texto)) {
        emCodigo = !emCodigo;
        i++;
        continue;
      }

      final fimDaTabela = emCodigo ? -1 : _ateOndeVaiATabela(linhas, i);
      if (fimDaTabela < 0) {
        i++;
        continue;
      }

      final tabela = TabelaDaNota.ler([
        for (var j = i; j < fimDaTabela; j++) linhas[j].texto,
      ]);
      if (tabela == null) {
        i++;
        continue;
      }

      desenhado(
        linha.inicio,
        linhas[fimDaTabela - 1].fim,
        () => BlocoDeTabela(
          inicio: linha.inicio,
          fim: linhas[fimDaTabela - 1].fim,
          tabela: tabela,
        ),
      );
      i = fimDaTabela;
    }

    // O que sobrou depois da ultima tabela — ou a nota inteira, quando nao ha
    // tabela nenhuma. Sai mesmo vazio: e onde se clica para escrever embaixo.
    blocos.add(texto(inicioDoTexto, corpo.length, antesDeDesenho: false));

    return blocos;
  }

  static final _cerca = RegExp(r'^\s*(```|~~~)');

  /// A cerca que abre um quadro: ``` seguido da palavra e de mais nada.
  static final _cercaDoQuadro = RegExp(
    '^ {0,3}(```|~~~)[ \t]*${QuadroDaNota.marcador}[ \t]*\$',
  );

  /// Em que linha o quadro que começa em [i] termina, ou -1 se nao ha quadro
  /// nenhum ali. O indice devolvido e o de depois da cerca que fecha.
  ///
  /// Quadro sem cerca de fechamento nao conta: enquanto ela nao for escrita, o
  /// bloco ainda esta pela metade, e o resto da nota nao pode ser engolido por
  /// ele.
  static int _ateOndeVaiOQuadro(List<_Linha> linhas, int i) {
    final abertura = _cercaDoQuadro.firstMatch(linhas[i].texto);
    if (abertura == null) return -1;

    final marca = abertura.group(1)!;
    for (var fim = i + 1; fim < linhas.length; fim++) {
      // Fecha com a mesma marca com que abriu, e nada mais na linha.
      if (RegExp('^ {0,3}$marca[ \t]*\$').hasMatch(linhas[fim].texto)) {
        return fim + 1;
      }
    }
    return -1;
  }

  /// A cerca que abre um bloco de codigo: tres crases ou mais (ou tis), e o
  /// nome da linguagem, que nao pode ter crase.
  static final _aberturaDoCodigo = RegExp(r'^ {0,3}(`{3,}|~{3,})([^`]*)$');

  /// Em que linha o bloco de codigo que começa em [i] termina, ou -1 se nao ha
  /// bloco fechado ali. O indice devolvido e o de depois da cerca que fecha.
  ///
  /// Fecha com a mesma marca, pelo menos do mesmo tamanho: e o que deixa um
  /// bloco de quatro crases mostrar, dentro dele, um de tres.
  static int _ateOndeVaiOCodigo(List<_Linha> linhas, int i) {
    final abertura = _aberturaDoCodigo.firstMatch(linhas[i].texto);
    if (abertura == null) return -1;
    // Um quadro que nao se deixou ler continua texto, e nao balao: e na mao
    // que ele vai ser consertado, e consertado ele volta a ser desenho.
    if (_cercaDoQuadro.hasMatch(linhas[i].texto)) return -1;

    final marca = abertura.group(1)!;
    final fechamento = RegExp(
      '^ {0,3}${RegExp.escape(marca[0])}{${marca.length},}[ \t]*\$',
    );
    for (var fim = i + 1; fim < linhas.length; fim++) {
      if (fechamento.hasMatch(linhas[fim].texto)) return fim + 1;
    }
    return -1;
  }

  /// Em que linha a tabela que começa em [i] termina, ou -1 se nao ha tabela
  /// nenhuma ali. O indice devolvido e o de depois da ultima linha dela.
  static int _ateOndeVaiATabela(List<_Linha> linhas, int i) {
    if (i + 1 >= linhas.length) return -1;
    if (!linhas[i].texto.contains('|')) return -1;

    // Sao as duas primeiras linhas que fazem uma tabela: o cabeçalho e os
    // tracinhos embaixo dele, com o mesmo numero de celulas.
    if (TabelaDaNota.ler([linhas[i].texto, linhas[i + 1].texto]) == null) {
      return -1;
    }

    var fim = i + 2;
    while (fim < linhas.length &&
        linhas[fim].texto.contains('|') &&
        linhas[fim].texto.trim().isNotEmpty &&
        !_cerca.hasMatch(linhas[fim].texto)) {
      fim++;
    }
    return fim;
  }

  /// As linhas do corpo, cada uma sabendo onde começa e onde acaba. O fim e
  /// antes da quebra: e ela que separa uma linha da seguinte.
  static List<_Linha> _linhasDe(String corpo) {
    final linhas = <_Linha>[];
    var inicio = 0;

    while (true) {
      final quebra = corpo.indexOf('\n', inicio);
      final fim = quebra < 0 ? corpo.length : quebra;
      linhas.add(
        _Linha(inicio: inicio, fim: fim, texto: corpo.substring(inicio, fim)),
      );
      if (quebra < 0) return linhas;
      inicio = quebra + 1;
    }
  }
}

class _Linha {
  const _Linha({required this.inicio, required this.fim, required this.texto});

  final int inicio;
  final int fim;
  final String texto;
}
