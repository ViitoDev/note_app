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

/// Separa o corpo da nota em texto e tabelas.
///
/// O editor mostra Markdown cru, com uma exceçao: tabela em texto e ilegivel
/// — contar barras para saber em que coluna se esta e trabalho de maquina. So
/// ela vira widget; todo o resto continua sendo o texto que se digitou.
abstract final class BlocosDaNota {
  static List<BlocoDaNota> de(String corpo) {
    final linhas = _linhasDe(corpo);
    final blocos = <BlocoDaNota>[];

    var inicioDoTexto = 0;
    var emCodigo = false;
    var i = 0;

    while (i < linhas.length) {
      final linha = linhas[i];

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

      blocos.add(
        BlocoDeTexto(
          inicio: inicioDoTexto,
          fim: linha.inicio,
          texto: corpo.substring(inicioDoTexto, linha.inicio),
        ),
      );
      blocos.add(
        BlocoDeTabela(
          inicio: linha.inicio,
          fim: linhas[fimDaTabela - 1].fim,
          tabela: tabela,
        ),
      );

      inicioDoTexto = linhas[fimDaTabela - 1].fim;
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
