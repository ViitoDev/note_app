import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'ui_prefs.dart';

/// Uma nota da lista de abertas recentemente.
@immutable
class NotaRecente {
  const NotaRecente(this.id);

  final String id;

  String get titulo => p.basenameWithoutExtension(id);
}

/// As ultimas notas abertas, da mais recente para a mais antiga.
///
/// Fica nas preferencias, e nao no vault: "quais notas **eu** abri por ultimo"
/// e estado desta maquina, como o arranjo dos paineis — nao e conteudo da
/// nota, e nao teria sentido o Drive levar isso para outro computador.
abstract final class NotasRecentes {
  static const _chave = 'notas_recentes';

  /// Quantas guardar. O cartao mostra poucas; guardar cem so faria a lista
  /// envelhecer sem ninguem olhar.
  static const limite = 12;

  static List<String> ler() {
    final bruto = UiPrefs.readString(_chave);
    if (bruto == null || bruto.isEmpty) return const [];

    try {
      final json = jsonDecode(bruto);
      if (json is! List) return const [];
      return [
        for (final id in json)
          if (id is String && id.isNotEmpty) id,
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Poe [noteId] na frente e devolve a lista nova.
  ///
  /// Reabrir uma nota nao duplica: ela sobe para o topo. Sem isso, abrir a
  /// mesma nota tres vezes ocuparia o cartao inteiro com ela.
  static List<String> registrar(String noteId) {
    final lista = [noteId, ...ler().where((id) => id != noteId)];
    if (lista.length > limite) lista.removeRange(limite, lista.length);

    UiPrefs.writeString(_chave, jsonEncode(lista));
    return lista;
  }
}
