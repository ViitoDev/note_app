/// Como um `[[link interno]]` e escrito no `.md` e como ele vira link na tela.
///
/// O arquivo continua guardando `[[Nome da nota]]`, que e a convençao que o
/// grafo ja le e que qualquer outro editor de Markdown entende. O preview e
/// que troca isso por um link de verdade, na hora de desenhar — nada e
/// reescrito em disco.
abstract final class Wikilink {
  /// Esquema inventado para o destino do link.
  ///
  /// Serve para o preview separar, no toque, o que e nota do vault do que e
  /// endereço de internet — os dois chegam pelo mesmo `onTapLink`.
  static const esquema = 'wikilink';

  /// Codigo primeiro na alternancia: dentro de crase, `[[assim]]` e exemplo
  /// escrito de proposito, e virar link atrapalharia justamente quem estava
  /// mostrando a sintaxe.
  static final _padrao = RegExp(
    r'(```.*?```|~~~.*?~~~|`[^`\n]*`)'
    r'|\[\[([^\]\|\n]+)(?:\|([^\]\n]*))?\]\]',
    dotAll: true,
  );

  /// Troca cada `[[nota]]` por um link Markdown comum.
  ///
  /// `[[Nota|outro texto]]` mostra o texto depois da barra, como no Obsidian.
  /// O destino vai percent-codificado: titulo com espaço, acento ou parenteses
  /// quebraria o link, e o parser preserva `%XX` intacto ate o outro lado.
  static String paraMarkdown(String corpo) {
    return corpo.replaceAllMapped(_padrao, (m) {
      final codigo = m.group(1);
      if (codigo != null) return codigo;

      final alvo = m.group(2)!.trim();
      final texto = (m.group(3) ?? alvo).trim();
      if (alvo.isEmpty) return m.group(0)!;

      return '[${_escapar(texto.isEmpty ? alvo : texto)}]'
          '($esquema:${Uri.encodeComponent(alvo)})';
    });
  }

  /// O alvo de um texto que e *so* um `[[link]]`, e o que esse link mostra.
  ///
  /// Nasceu para o quadro. Uma caixa cujo texto inteiro e um wikilink nao e uma
  /// caixa com um link dentro: e um atalho para aquela nota, e o quadro desenha
  /// isso de outro jeito — e abre a nota quando se clica duas vezes nela.
  ///
  /// Assim, e nao com um campo proprio na caixa: o `.md` ja tem um jeito de
  /// apontar para uma nota, o grafo ja sabe ler aquele jeito, e um segundo
  /// campo dizendo a mesma coisa seria uma segunda verdade para manter em dia.
  static ({String alvo, String texto})? sozinho(String texto) {
    final achado = _sozinho.firstMatch(texto.trim());
    if (achado == null) return null;

    final alvo = achado.group(1)!.trim();
    if (alvo.isEmpty) return null;

    final rotulo = (achado.group(2) ?? '').trim();
    return (alvo: alvo, texto: rotulo.isEmpty ? alvo : rotulo);
  }

  static final _sozinho = RegExp(r'^\[\[([^\]\|\n]+)(?:\|([^\]\n]*))?\]\]$');

  /// O titulo da nota apontada por [href], ou nulo se o link nao for interno.
  static String? tituloDe(String href) {
    if (!href.startsWith('$esquema:')) return null;
    try {
      return Uri.decodeComponent(href.substring(esquema.length + 1));
    } on FormatException {
      // Destino estragado no meio do caminho: melhor nao abrir nada do que
      // abrir a nota errada.
      return null;
    }
  }

  /// Colchete e barra invertida no texto exibido quebrariam o link em volta.
  static String _escapar(String texto) =>
      texto.replaceAllMapped(RegExp(r'[\\\[\]]'), (m) => '\\${m[0]}');
}
