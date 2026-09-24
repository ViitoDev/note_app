import 'package:path/path.dart' as p;

import 'blocos_da_nota.dart';
import 'excalidraw.dart';
import 'note.dart';
import 'quadro_da_nota.dart';

/// A nota que *e* uma tela, e nao um texto com um quadro dentro.
///
/// O quadro comum mora no meio de uma nota: um cartao do tamanho de um
/// paragrafo, entre duas frases. Isso cobre o fluxograma que ilustra o que se
/// esta escrevendo, e nao cobre o outro caso — o mapa, o painel, o mural de
/// ideias soltas, onde nao ha texto em volta porque o *espaço* e a organizaçao.
/// Numa nota dessas, o quadro nao ilustra a nota: ele e a nota.
///
/// Uma tela dessas continua sendo um `.md` do vault. Nao ha tipo de arquivo
/// novo, nem pasta a parte, nem banco de dados: a sincronizaçao, a lixeira, o
/// renomear, o mover e o diario do dia continuam valendo sem uma linha de
/// codigo a mais, e qualquer editor de Markdown abre o arquivo e ve um bloco de
/// codigo em vez de sujeira.
///
/// O que diz que aquele `.md` e uma tela e o nome: `mapa.quadro.md`. Pelo nome,
/// e nao por um campo no frontmatter, por tres razoes:
///
///   * ele aparece na arvore de arquivos sem abrir a nota;
///   * ele sobrevive a uma copia feita por fora do app;
///   * e o titulo continua sendo `mapa`, porque [Note.title] ja tira a
///     extensao — e `.quadro.md` inteiro e extensao.
abstract final class NotaDeQuadro {
  /// O que termina o nome de uma nota-tela.
  static const sufixo = '.quadro.md';

  static bool eTela(String nome) => nome.toLowerCase().endsWith(sufixo);

  /// Se o arquivo e um desenho do Excalidraw guardado no vault.
  ///
  /// Estes nao sao notas: sao desenhos de fora, e o app so os mostra. Ver
  /// [Excalidraw] sobre o que se perderia ao regrava-los daqui.
  static bool eDesenhoDeFora(String nome) =>
      p.extension(nome).toLowerCase() == Excalidraw.extensao;

  /// Se este arquivo abre como tela em vez de como texto.
  static bool desenhado(String nome) => eTela(nome) || eDesenhoDeFora(nome);

  /// O titulo de uma nota-tela, sem o `.quadro.md`.
  ///
  /// [Note.title] tira so o `.md` e deixa o `.quadro` pendurado, que e ruido
  /// no alto da tela e na aba.
  static String tituloDe(String nome) {
    if (!eTela(nome)) return p.basenameWithoutExtension(nome);
    return nome.substring(0, nome.length - sufixo.length);
  }

  /// O quadro guardado no corpo de uma nota-tela.
  ///
  /// O primeiro bloco de quadro do corpo, e nao "o corpo inteiro lido como
  /// JSON": uma tela e uma nota comum que por acaso so tem um quadro dentro, e
  /// nada impede alguem de ter escrito uma linha de texto em cima dele. O que
  /// estiver escrito em volta e deixado em paz — ver [comQuadro].
  static QuadroDaNota doCorpo(String corpo) {
    for (final bloco in BlocosDaNota.de(corpo)) {
      if (bloco is BlocoDeQuadro) return bloco.quadro;
    }
    return QuadroDaNota.vazio;
  }

  /// O corpo com [quadro] no lugar do quadro que estava la.
  ///
  /// O texto em volta atravessa intacto. Sem quadro nenhum no corpo — uma nota
  /// que acabou de ser renomeada para `.quadro.md`, por exemplo — o quadro
  /// entra no fim, embaixo do que ja existia.
  static String comQuadro(String corpo, QuadroDaNota quadro) {
    for (final bloco in BlocosDaNota.de(corpo)) {
      if (bloco is BlocoDeQuadro) {
        return corpo.replaceRange(bloco.inicio, bloco.fim, quadro.markdown);
      }
    }

    final antes = corpo.trimRight();
    return antes.isEmpty
        ? '${quadro.markdown}\n'
        : '$antes\n\n${quadro.markdown}\n';
  }

  /// O desenho de um arquivo que abre como tela, seja ele qual for.
  ///
  /// Um lugar so para a pergunta "o que esta desenhado neste arquivo?", porque
  /// quem abre a tela nao deveria precisar saber de que formato ela veio.
  static QuadroDaNota doArquivo(Note nota) {
    if (eDesenhoDeFora(nota.name)) {
      return Excalidraw.ler(nota.raw) ?? QuadroDaNota.vazio;
    }
    return doCorpo(nota.body);
  }

  /// O conteudo de uma tela recem-criada.
  ///
  /// Com frontmatter, como qualquer nota nova: uma tela tambem tem data de
  /// criaçao e tags, e tirar isso dela a deixaria de fora do painel e da busca
  /// por tag sem nenhum ganho em troca.
  static String nova(String titulo, String data) =>
      '---\n'
      'tipo: quadro\n'
      'criado_em: $data\n'
      'tags: []\n'
      '---\n\n'
      '${QuadroDaNota.vazio.markdown}\n';
}
