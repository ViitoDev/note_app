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
