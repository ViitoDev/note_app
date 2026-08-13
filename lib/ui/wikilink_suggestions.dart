import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Um `[[` aberto logo antes do cursor, e o que ja foi digitado dentro dele.
///
/// E o que o editor precisa saber para sugerir notas enquanto se escreve um
/// link: onde o link começa, para poder reescrever o trecho inteiro, e o que
/// filtrar.
@immutable
class WikilinkAberto {
  const WikilinkAberto({required this.inicio, required this.consulta});

  /// Indice do primeiro `[` no texto.
  final int inicio;

  /// O texto entre o `[[` e o cursor. Vazio logo depois de abrir o link.
  final String consulta;

  /// Procura o `[[` que esta sendo escrito na posiçao [cursor].
  ///
  /// Devolve nulo quando nao ha link em aberto ali — e e isso que fecha a
  /// lista de sugestoes. Um `]` no meio quer dizer que o link ja foi fechado;
  /// um `[` quer dizer que outro começou depois; uma quebra de linha quer
  /// dizer que o `[[` ficou para tras, numa linha que o usuario ja deixou.
  static WikilinkAberto? em(String texto, int cursor) {
    if (cursor < 2 || cursor > texto.length) return null;

    final inicio = texto.lastIndexOf('[[', cursor - 2);
    if (inicio < 0) return null;

    final consulta = texto.substring(inicio + 2, cursor);
    for (final proibido in const [']', '[', '\n']) {
      if (consulta.contains(proibido)) return null;
    }
    return WikilinkAberto(inicio: inicio, consulta: consulta);
  }

  @override
  bool operator ==(Object other) =>
      other is WikilinkAberto &&
      other.inicio == inicio &&
      other.consulta == consulta;

  @override
  int get hashCode => Object.hash(inicio, consulta);
}

/// Os titulos que combinam com o que foi digitado, do mais provavel ao menos.
///
/// A ordem importa mais que a lista: quem digita tres letras espera a nota que
/// *começa* com elas na primeira linha, e nao uma que por acaso as tem no meio
/// do nome. Com o campo vazio — logo depois de abrir o `[[` — vem o vault em
/// ordem alfabetica, que ao menos e previsivel.
List<String> sugestoesDeNotas(
  List<String> titulos,
  String consulta, {
  int limite = 8,
}) {
  final busca = consulta.trim().toLowerCase();

  final combinam = [
    for (final titulo in titulos)
      if (busca.isEmpty || titulo.toLowerCase().contains(busca)) titulo,
  ];

  combinam.sort((a, b) {
    final pesoA = _peso(a.toLowerCase(), busca);
    final pesoB = _peso(b.toLowerCase(), busca);
    if (pesoA != pesoB) return pesoA.compareTo(pesoB);
    return a.toLowerCase().compareTo(b.toLowerCase());
  });

  return combinam.take(limite).toList();
}

int _peso(String titulo, String busca) {
  if (busca.isEmpty) return 0;
  if (titulo == busca) return 0;
  if (titulo.startsWith(busca)) return 1;
  // Começo de palavra vale mais que meio de palavra: quem procura "ensino"
  // quer "Plano de ensino" antes de "Reensinar".
  if (titulo.contains(' $busca')) return 2;
  return 3;
}

/// A lista que aparece embaixo do cursor enquanto se escreve `[[`.
class WikilinkSuggestions extends StatelessWidget {
  const WikilinkSuggestions({
    super.key,
    required this.titulos,
    required this.selecionado,
    required this.onEscolher,
  });

  final List<String> titulos;
  final int selecionado;
  final ValueChanged<String> onEscolher;

  /// Altura de cada linha. O editor usa isto para saber se a lista cabe
  /// embaixo do cursor ou se tem que subir.
  static const alturaDoItem = 32.0;

  static double alturaPara(int quantos) => quantos * alturaDoItem + 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: scheme.outline),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < titulos.length; i++)
              _Item(
                titulo: titulos[i],
                marcado: i == selecionado,
                onTap: () => onEscolher(titulos[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.titulo,
    required this.marcado,
    required this.onTap,
  });

  final String titulo;
  final bool marcado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      height: WikilinkSuggestions.alturaDoItem,
      child: Material(
        color: marcado ? scheme.primaryContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 14,
                  color: marcado ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTheme.gapSm),
                Expanded(
                  child: Text(
                    titulo,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: marcado ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
