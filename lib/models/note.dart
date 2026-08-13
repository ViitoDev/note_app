import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Uma nota do vault: o texto cru do arquivo `.md` mais o frontmatter YAML
/// ja interpretado.
///
/// O arquivo em disco continua sendo a fonte da verdade. Esta classe e so uma
/// leitura dele em memoria — nada aqui vira banco de dados.
class Note {
  const Note({
    required this.id,
    required this.name,
    required this.raw,
    required this.frontmatter,
    required this.body,
  });

  /// Identidade no armazenamento. Localmente e o caminho; no Drive sera o
  /// `fileId`, que sobrevive a renomeaçoes e movimentos.
  final String id;

  /// Nome atual do arquivo, com extensao.
  final String name;

  /// Conteudo integral do arquivo, frontmatter incluso. E isto que e gravado
  /// de volta no disco.
  final String raw;

  /// Frontmatter YAML do topo do arquivo, vazio quando a nota nao tem.
  final Map<String, dynamic> frontmatter;

  /// Conteudo sem o bloco de frontmatter — o que vai para o preview.
  final String body;

  String get title => p.basenameWithoutExtension(name);

  /// `tipo:` do frontmatter. `tipo: evento` e o que faz a nota aparecer no
  /// calendario — ver [EventParser].
  String? get tipo => frontmatter['tipo'] as String?;

  /// Delimitador `---` na primeira linha, conteudo YAML, `---` fechando.
  /// Aceita tanto LF quanto CRLF porque o Drive replica os bytes sem
  /// normalizar quebra de linha, e o vault pode receber arquivos de fora.
  static final RegExp _frontmatterPattern = RegExp(
    r'^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|$)',
    dotAll: true,
  );

  factory Note.parse(String id, String raw, {String? name}) {
    final resolvedName = name ?? p.basename(id);
    final match = _frontmatterPattern.firstMatch(raw);
    if (match == null) {
      return Note(
        id: id,
        name: resolvedName,
        raw: raw,
        frontmatter: const {},
        body: raw,
      );
    }

    Map<String, dynamic> parsed = const {};
    try {
      final doc = loadYaml(match.group(1) ?? '');
      if (doc is YamlMap) parsed = _toPlainMap(doc);
    } on YamlException {
      // Frontmatter quebrado nao pode impedir a nota de abrir: o texto e que
      // importa. A nota abre como se nao tivesse metadados.
      parsed = const {};
    }

    return Note(
      id: id,
      name: resolvedName,
      raw: raw,
      frontmatter: parsed,
      body: raw.substring(match.end),
    );
  }

  Note copyWithRaw(String newRaw) => Note.parse(id, newRaw, name: name);

  /// Converte as estruturas do pacote `yaml` (YamlMap/YamlList) em coleçoes
  /// comuns do Dart, para o resto do app nao depender desses tipos.
  static Map<String, dynamic> _toPlainMap(YamlMap map) {
    return {
      for (final entry in map.entries)
        entry.key.toString(): _toPlainValue(entry.value),
    };
  }

  static dynamic _toPlainValue(dynamic value) {
    if (value is YamlMap) return _toPlainMap(value);
    if (value is YamlList) return value.map(_toPlainValue).toList();
    return value;
  }
}
