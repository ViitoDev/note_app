import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'vault_entry.dart';

/// A ordem manual das linhas da arvore, guardada por pasta.
///
/// O sistema de arquivos nao tem ordem: `list()` devolve o que devolver, e por
/// isso a varredura ordena por nome. Quando o usuario arrasta uma nota para
/// cima de outra, essa escolha precisa morar em algum lugar — e este e o lugar.
///
/// A chave e o caminho da pasta relativo a raiz do vault, com `/` como
/// separador para o arquivo nao mudar de forma entre sistemas. A raiz e a
/// string vazia. O valor e a sequencia de nomes escolhida.
///
/// A lista pode ser parcial de proposito: quem nao aparece nela entra depois,
/// na ordem alfabetica de sempre. E isso que faz uma nota criada fora do app
/// aparecer sozinha, sem precisar reescrever a ordem toda a cada arquivo novo.
@immutable
class VaultOrder {
  const VaultOrder(this._porPasta);

  final Map<String, List<String>> _porPasta;

  static const vazia = VaultOrder({});

  bool get isEmpty => _porPasta.isEmpty;

  List<String> of(String pasta) => _porPasta[pasta] ?? const [];

  /// Devolve uma copia com a ordem de [pasta] trocada.
  ///
  /// Lista vazia apaga a entrada: sem isso o arquivo so cresceria, guardando
  /// ordens de pastas que nao existem mais.
  VaultOrder comOrdem(String pasta, List<String> nomes) {
    final novo = Map<String, List<String>>.from(_porPasta);
    if (nomes.isEmpty) {
      novo.remove(pasta);
    } else {
      novo[pasta] = List.unmodifiable(nomes);
    }
    return VaultOrder(novo);
  }

  /// Acompanha a troca de nome de uma entrada, para a posiçao escolhida a mao
  /// nao se perder junto com o nome antigo.
  ///
  /// Duas coisas mudam, e a segunda e facil de esquecer:
  ///
  ///  * o nome dentro da lista da pasta que contem a entrada — sem isso a nota
  ///    renomeada cairia para o fim da pasta, como se nunca tivesse sido
  ///    arrastada;
  ///  * quando a entrada e pasta, a chave dela **e a de tudo que esta abaixo**,
  ///    porque a chave e o caminho. Renomear "Estudos" sem isto abandonaria a
  ///    ordem de "Estudos/UFMS" numa chave que nao aponta mais para lugar
  ///    nenhum.
  VaultOrder renomeado({
    required String pasta,
    required String de,
    required String para,
    required bool ehPasta,
  }) {
    if (de == para) return this;

    final antigo = pasta.isEmpty ? de : '$pasta/$de';
    final novo = pasta.isEmpty ? para : '$pasta/$para';

    final saida = <String, List<String>>{};
    for (final entrada in _porPasta.entries) {
      final chave = entrada.key;

      final chaveNova =
          ehPasta && (chave == antigo || chave.startsWith('$antigo/'))
          ? novo + chave.substring(antigo.length)
          : chave;

      saida[chaveNova] = chave == pasta
          ? List.unmodifiable([
              for (final nome in entrada.value) nome == de ? para : nome,
            ])
          : entrada.value;
    }
    return VaultOrder(saida);
  }

  /// Reordena a arvore inteira lida do disco.
  ///
  /// [raiz] e a pasta do vault; as chaves saem do caminho de cada pasta
  /// relativo a ela.
  VaultFolder aplicar(VaultFolder raiz) => _aplicar(raiz, raiz.id);

  VaultFolder _aplicar(VaultFolder pasta, String raizId) {
    final filhos = [
      for (final filho in pasta.children)
        if (filho is VaultFolder) _aplicar(filho, raizId) else filho,
    ];

    return VaultFolder(
      id: pasta.id,
      name: pasta.name,
      children: ordenar(chaveDe(pasta.id, raizId), filhos),
    );
  }

  /// Ordena uma lista de filhos: primeiro os nomes escolhidos, na ordem
  /// escolhida; depois o resto, como veio.
  List<VaultEntry> ordenar(String chave, List<VaultEntry> filhos) {
    final escolhidos = of(chave);
    if (escolhidos.isEmpty) return filhos;

    final porNome = {for (final f in filhos) f.name: f};
    final saida = <VaultEntry>[];
    final usados = <String>{};

    for (final nome in escolhidos) {
      final filho = porNome[nome];
      // Nome que nao existe mais (apagado, renomeado, movido) e so ignorado —
      // nao vale limpar a lista a cada leitura.
      if (filho != null && usados.add(nome)) saida.add(filho);
    }
    for (final filho in filhos) {
      if (!usados.contains(filho.name)) saida.add(filho);
    }

    return saida;
  }

  /// Chave de uma pasta: o caminho relativo a raiz, sempre com `/`.
  static String chaveDe(String pastaId, String raizId) {
    if (p.equals(pastaId, raizId)) return '';
    final rel = p.relative(pastaId, from: raizId);
    return p.split(rel).join('/');
  }

  String encode() => jsonEncode(_porPasta);

  /// Le o formato de [encode]. Qualquer coisa fora do esperado vira ordem
  /// vazia: um arquivo corrompido nao pode impedir o vault de abrir — sem
  /// ordem manual a arvore ainda funciona, so volta ao alfabetico.
  static VaultOrder decode(String? bruto) {
    if (bruto == null || bruto.trim().isEmpty) return vazia;

    try {
      final json = jsonDecode(bruto);
      if (json is! Map) return vazia;

      final saida = <String, List<String>>{};
      for (final entrada in json.entries) {
        final chave = entrada.key;
        final valor = entrada.value;
        if (chave is! String || valor is! List) continue;

        final nomes = [
          for (final nome in valor)
            if (nome is String) nome,
        ];
        if (nomes.isNotEmpty) saida[chave] = List.unmodifiable(nomes);
      }
      return VaultOrder(saida);
    } on FormatException {
      return vazia;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VaultOrder &&
      _porPasta.length == other._porPasta.length &&
      _porPasta.entries.every(
        (e) => listEquals(e.value, other._porPasta[e.key]),
      );

  // XOR em vez de `Object.hashAll`: a ordem em que o mapa itera nao pode
  // mudar o hash, senao dois mapas iguais sairiam com hashes diferentes.
  @override
  int get hashCode {
    var h = 0;
    for (final e in _porPasta.entries) {
      h ^= Object.hash(e.key, Object.hashAll(e.value));
    }
    return h;
  }

  @override
  String toString() => 'VaultOrder(${encode()})';
}
