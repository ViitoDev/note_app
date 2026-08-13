import 'package:flutter/foundation.dart';

/// Uma caixa de tarefa encontrada no texto.
@immutable
class Tarefa {
  const Tarefa({
    required this.indice,
    required this.texto,
    required this.feita,
  });

  /// Posiçao na contagem do texto — e o numero que [MarkdownTasks.alternar]
  /// espera receber.
  final int indice;

  /// O resto da linha depois da caixa, sem o marcador de lista.
  final String texto;

  final bool feita;
}

/// Marcar e desmarcar caixas de tarefa direto no texto Markdown.
///
/// O preview nao guarda estado proprio: clicar numa caixa reescreve o `- [ ]`
/// para `- [x]` no arquivo, e o preview so reflete o que o texto passou a
/// dizer. Sem isso haveria duas verdades sobre a mesma tarefa.
class MarkdownTasks {
  const MarkdownTasks._();

  /// Uma linha de tarefa: marcador de lista, a caixa, e um espaço depois dela.
  ///
  /// O espaço final e o que separa `- [x] feito` de `- [x]feito`, que o
  /// GitHub — e o parser usado no preview — nao trata como tarefa.
  static final _linha = RegExp(
    r'^(\s*(?:[-*+]|\d+[.)])\s+)\[([ xX])\](?=\s)',
    multiLine: true,
  );

  /// Cerca de bloco de codigo, aberta ou fechada.
  static final _cerca = RegExp(r'^\s*(?:```|~~~)', multiLine: true);

  /// Quantas tarefas o preview vai desenhar.
  static int contar(String texto) => _posicoes(texto).length;

  /// As tarefas do texto, na mesma ordem e com os mesmos indices que
  /// [alternar] usa.
  ///
  /// O texto da tarefa e o resto da linha — quebras de linha de continuaçao
  /// nao entram. Uma tarefa e uma linha; o que vem indentado embaixo dela e
  /// detalhe da nota, e nao caberia numa lista de pendencias.
  static List<Tarefa> listar(String texto) {
    final saida = <Tarefa>[];
    final posicoes = _posicoes(texto);

    for (var i = 0; i < posicoes.length; i++) {
      final m = posicoes[i];
      final fim = texto.indexOf('\n', m.end);
      saida.add(
        Tarefa(
          indice: i,
          texto: texto
              .substring(m.end, fim < 0 ? texto.length : fim)
              .trim()
              // O `- [x]` exige um espaço depois da caixa, entao a `\r` de um
              // arquivo CRLF fica no fim do que sobrou.
              .replaceAll('\r', ''),
          feita: m.group(2) != ' ',
        ),
      );
    }
    return saida;
  }

  /// Inverte a tarefa [indice] do corpo e devolve o arquivo inteiro.
  ///
  /// A contagem e sempre do corpo, nunca do arquivo: o frontmatter nao vira
  /// caixa no preview, e incluir uma linha dele desalinharia todos os indices.
  /// O prefixo — que e exatamente o frontmatter — sai daqui sem um caractere
  /// trocado.
  static String alternarNoArquivo(String arquivo, String corpo, int indice) {
    final novo = alternar(corpo, indice);
    if (novo == corpo) return arquivo;
    return arquivo.substring(0, arquivo.length - corpo.length) + novo;
  }

  /// Devolve [texto] com a tarefa de indice [indice] invertida.
  ///
  /// Indice fora da conta devolve o texto intacto: e o que acontece quando o
  /// arquivo muda por fora entre o desenho e o clique, e reescrever a linha
  /// errada seria pior do que nao fazer nada.
  static String alternar(String texto, int indice) {
    final posicoes = _posicoes(texto);
    if (indice < 0 || indice >= posicoes.length) return texto;

    final m = posicoes[indice];
    final marcada = m.group(2) != ' ';
    // Reescreve so os tres caracteres da caixa: o resto da linha, inclusive a
    // indentaçao e o marcador de lista, fica exatamente como estava.
    return texto.replaceRange(
      m.start,
      m.end,
      '${m.group(1)}[${marcada ? ' ' : 'x'}]',
    );
  }

  /// As tarefas do texto, em ordem, pulando o que esta dentro de bloco de
  /// codigo — ali `- [ ]` e exemplo, nao tarefa, e o preview nao desenha caixa
  /// nenhuma. Contar essas linhas desalinharia todos os indices seguintes.
  static List<RegExpMatch> _posicoes(String texto) {
    final cercas = [for (final c in _cerca.allMatches(texto)) c.start];

    return [
      for (final m in _linha.allMatches(texto))
        if (!_dentroDeCodigo(m.start, cercas)) m,
    ];
  }

  /// Esta dentro de bloco de codigo quem tem um numero impar de cercas antes.
  static bool _dentroDeCodigo(int posicao, List<int> cercas) {
    var antes = 0;
    for (final c in cercas) {
      if (c < posicao) antes++;
    }
    return antes.isOdd;
  }
}
