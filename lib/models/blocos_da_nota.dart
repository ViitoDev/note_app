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

/// Separa o corpo da nota em texto, tabelas e quadros.
///
/// O editor mostra Markdown cru, com duas exceçoes: tabela em texto e ilegivel
/// — contar barras para saber em que coluna se esta e trabalho de maquina — e
/// quadro em texto e pior ainda, um punhado de coordenadas. So esses dois viram
/// widget; todo o resto continua sendo o texto que se digitou.
abstract final class BlocosDaNota {
  static List<BlocoDaNota> de(String corpo) {
    final linhas = _linhasDe(corpo);
    final blocos = <BlocoDaNota>[];

    var inicioDoTexto = 0;
    var emCodigo = false;
    var i = 0;

    /// Fecha o texto acumulado ate [ate] e entrega o bloco desenhado que
    /// começa ali, do jeito que os dois casos abaixo precisam.
    void desenhado(int ate, int fim, BlocoDaNota Function() bloco) {
      blocos.add(
        BlocoDeTexto(
          inicio: inicioDoTexto,
          fim: ate,
          texto: corpo.substring(inicioDoTexto, ate),
        ),
      );
      blocos.add(bloco());
      inicioDoTexto = fim;
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

      // Bloco de codigo tem prioridade: uma tabela ali dentro esta sendo
      // mostrada como exemplo, e desenha-la seria apagar o exemplo.
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
    blocos.add(
      BlocoDeTexto(
        inicio: inicioDoTexto,
        fim: corpo.length,
        texto: corpo.substring(inicioDoTexto),
      ),
    );

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
