import 'nota_de_quadro.dart';

/// Um item da arvore do vault: pasta ou arquivo `.md`.
sealed class VaultEntry {
  const VaultEntry({required this.id, required this.name});

  /// Identidade estavel no armazenamento: o caminho do arquivo. E tambem o
  /// que o servidor usa, relativo a raiz do vault.
  final String id;

  /// Nome atual do item, independente de sua identidade.
  final String name;
}

class VaultFolder extends VaultEntry {
  const VaultFolder({
    required super.id,
    required super.name,
    required this.children,
  });

  /// Subpastas primeiro, depois arquivos — cada grupo em ordem alfabetica.
  final List<VaultEntry> children;

  bool get isEmpty => children.isEmpty;

  /// Total de notas na pasta e em tudo abaixo dela.
  int get noteCount => children.fold(
    0,
    (total, child) => total + (child is VaultFolder ? child.noteCount : 1),
  );

  /// A mesma arvore, com a nota [noteId] gravada em [quando].
  ///
  /// O `modificadoEm` de cada arquivo vem do `stat` da varredura. Gravar uma
  /// nota por dentro do app nao refaz a varredura, entao sem isto o arquivo
  /// continuaria na tela com a data de gravaçao anterior — o bastante para o
  /// diario do painel, que decide o dia da nota por essa data, nao ver hoje a
  /// nota que acabou de ser escrita.
  ///
  /// Refaz so as pastas do caminho ate o arquivo; o resto da arvore continua
  /// sendo o mesmo objeto. Devolve `this` quando [noteId] nao esta aqui.
  VaultFolder comGravacao(String noteId, DateTime quando) {
    var mudou = false;
    final novos = <VaultEntry>[];

    for (final filho in children) {
      switch (filho) {
        case VaultFile() when filho.id == noteId:
          novos.add(
            VaultFile(id: filho.id, name: filho.name, modificadoEm: quando),
          );
          mudou = true;
        case VaultFolder():
          final sub = filho.comGravacao(noteId, quando);
          if (!identical(sub, filho)) mudou = true;
          novos.add(sub);
        default:
          novos.add(filho);
      }
    }

    return mudou ? VaultFolder(id: id, name: name, children: novos) : this;
  }
}

class VaultFile extends VaultEntry {
  const VaultFile({required super.id, required super.name, this.modificadoEm});

  /// Ultima gravaçao do arquivo, como o disco a conhece.
  ///
  /// Nao e indice: e o proprio `.md` dizendo quando mudou. E o que permite ao
  /// painel saber quais notas foram tocadas hoje sem manter um registro
  /// paralelo que envelheceria a cada ediçao feita por fora do app.
  ///
  /// Nulo quando a origem nao informa — o `stat` falhou, ou o vault de teste
  /// nao tem disco atras.
  final DateTime? modificadoEm;

  /// Nome exibido na arvore: sem a extensao.
  ///
  /// Sem a extensao *inteira*: numa nota-tela ela e `.quadro.md`, e cortar so o
  /// `.md` deixaria "mapa.quadro" pendurado em cada linha da arvore.
  String get title => NotaDeQuadro.tituloDe(name);

  /// Se esta linha da arvore abre desenhada, e nao como texto.
  bool get desenhada => NotaDeQuadro.desenhado(name);
}
