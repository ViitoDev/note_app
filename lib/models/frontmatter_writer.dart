/// Escrita cirurgica de um campo do frontmatter.
///
/// Arrastar um card entre colunas grava `status:` na nota. Reserializar o YAML
/// inteiro resolveria, mas destruiria comentarios, ordem dos campos, aspas e
/// estilo de lista — o arquivo e do usuario, e ele escreveu daquele jeito. Por
/// isso aqui se mexe so na linha do campo.
class FrontmatterWriter {
  const FrontmatterWriter._();

  /// Delimitadores do bloco de frontmatter, tolerando CRLF.
  static final _bloco = RegExp(
    r'^---[ \t]*\r?\n(.*?)(\r?\n)---[ \t]*(\r?\n|$)',
    dotAll: true,
  );

  /// Devolve [texto] com `campo: valor` no frontmatter.
  ///
  /// Substitui a linha se o campo ja existir, acrescenta antes do `---` de
  /// fechamento se nao existir, e cria o bloco inteiro se a nota nao tiver
  /// frontmatter nenhum.
  static String definir(String texto, String campo, String valor) {
    final bloco = _bloco.firstMatch(texto);

    if (bloco == null) return _criarBloco(texto, campo, valor);

    final miolo = bloco.group(1) ?? '';
    final quebra = bloco.group(2) ?? '\n';
    final linha = RegExp(
      '^[ \\t]*${RegExp.escape(campo)}[ \\t]*:.*\$',
      multiLine: true,
    );

    final novoMiolo = linha.hasMatch(miolo)
        ? miolo.replaceFirst(linha, '$campo: $valor')
        : '$miolo$quebra$campo: $valor';

    return texto.replaceRange(
      bloco.start,
      bloco.end,
      '---$quebra$novoMiolo$quebra---${bloco.group(3)}',
    );
  }

  /// Devolve [texto] sem a linha do campo.
  ///
  /// E o par de [definir], e existe porque campo vazio nao se escreve: a ficha
  /// da nota mostra `data`, `hora` e `status` sempre, mas o arquivo so ganha a
  /// linha quando ha o que guardar. Limpar um campo tem que devolver o `.md` ao
  /// estado de antes, sem deixar `data:` solto para o calendario tropeçar.
  ///
  /// Sobrando um bloco vazio, ele sai inteiro — `---` seguido de `---` nao e
  /// metadado nenhum, e so atrapalha quem abrir o arquivo noutro editor.
  static String remover(String texto, String campo) {
    final bloco = _bloco.firstMatch(texto);
    if (bloco == null) return texto;

    final quebra = bloco.group(2) ?? '\n';
    final linha = RegExp(
      '^[ \\t]*${RegExp.escape(campo)}[ \\t]*:.*\$',
      multiLine: true,
    );

    final miolo = bloco.group(1) ?? '';
    if (!linha.hasMatch(miolo)) return texto;

    final restantes = miolo
        .split(RegExp(r'\r?\n'))
        .where((l) => !linha.hasMatch(l))
        .toList();

    if (restantes.every((l) => l.trim().isEmpty)) {
      // Bloco vazio sai junto, e com ele a linha em branco que o separava do
      // texto — senao a nota começaria com um vao a cada campo limpo.
      final resto = texto.substring(bloco.end);
      return resto.replaceFirst(RegExp(r'^(\r?\n)+'), '');
    }

    return texto.replaceRange(
      bloco.start,
      bloco.end,
      '---$quebra${restantes.join(quebra)}$quebra---${bloco.group(3)}',
    );
  }

  /// Nota sem frontmatter ganha um bloco novo no topo.
  static String _criarBloco(String texto, String campo, String valor) {
    // Segue a quebra de linha que a nota ja usa: misturar CRLF e LF no mesmo
    // arquivo confunde `git diff` e alguns editores.
    final quebra = texto.contains('\r\n') ? '\r\n' : '\n';
    return '---$quebra$campo: $valor$quebra---$quebra$quebra$texto';
  }
}
