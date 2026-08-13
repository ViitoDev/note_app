import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'markdown_tasks.dart';

/// O que foi feito num dia.
@immutable
class DiaDeAtividade {
  const DiaDeAtividade({
    required this.dia,
    this.palavras = 0,
    this.tarefas = 0,
  });

  final DateTime dia;

  /// Palavras que a nota ganhou. Apagar texto nao conta como negativo — nem
  /// como positivo: o contador mede o que foi escrito, e reescrever um
  /// paragrafo menor nao e trabalho a menos.
  final int palavras;

  /// Caixas `- [ ]` que passaram a `- [x]`.
  final int tarefas;

  bool get vazio => palavras == 0 && tarefas == 0;

  /// Intensidade do quadradinho.
  ///
  /// Uma tarefa concluida vale por 20 palavras. Sem um peso desses um dia de
  /// fechar pendencias — que e trabalho — apareceria em branco ao lado de um
  /// dia de copiar texto.
  int get pontos => palavras + tarefas * 20;

  @override
  String toString() => 'DiaDeAtividade($dia, $palavras palavras, $tarefas)';
}

/// O historico de escrita do vault, dia a dia.
///
/// Existe porque isto e a unica coisa do app que **nao** da para deduzir dos
/// `.md`: o arquivo diz como a nota esta hoje, nunca quanto dela foi escrito
/// ontem. Sem um registro proprio, o contador do painel so conseguiria mostrar
/// o tamanho atual do vault — que nao e atividade nenhuma.
///
/// Mora no proprio vault (`.notas-atividade.json`), como a ordem manual: assim
/// viaja pelo Drive e sobrevive a reinstalar o app.
@immutable
class Atividade {
  const Atividade(this._dias);

  /// Chave `AAAA-MM-DD` para o registro do dia. Mapa, e nao lista, porque o
  /// acesso e sempre por dia — e o JSON fica legivel a olho nu.
  final Map<String, ({int palavras, int tarefas})> _dias;

  static const vazia = Atividade({});

  /// Quanto tempo o historico guarda. O contador mostra um ano; guardar mais
  /// so engordaria um arquivo que viaja pelo Drive a cada gravaçao.
  static const _diasGuardados = 400;

  bool get isEmpty => _dias.isEmpty;

  DiaDeAtividade de(DateTime dia) {
    final r = _dias[chave(dia)];
    return DiaDeAtividade(
      dia: _soDia(dia),
      palavras: r?.palavras ?? 0,
      tarefas: r?.tarefas ?? 0,
    );
  }

  /// Soma ao dia, devolvendo um historico novo — nada e mutado no lugar.
  Atividade somar(DateTime dia, {int palavras = 0, int tarefas = 0}) {
    if (palavras <= 0 && tarefas <= 0) return this;

    final k = chave(dia);
    final atual = _dias[k];
    return Atividade({
      ..._dias,
      k: (
        palavras: (atual?.palavras ?? 0) + (palavras > 0 ? palavras : 0),
        tarefas: (atual?.tarefas ?? 0) + (tarefas > 0 ? tarefas : 0),
      ),
    });
  }

  /// Os dias do ultimo ano, do mais antigo ao mais recente, **sem buracos**.
  ///
  /// Dia sem registro entra zerado: o desenho e uma grade continua, e pular os
  /// dias parados desalinharia todas as semanas seguintes.
  List<DiaDeAtividade> ultimoAno(DateTime hoje) {
    final fim = _soDia(hoje);
    final umAnoAtras = DateTime(fim.year, fim.month, fim.day - 364);

    // Recua ate o domingo para cada coluna da grade ser uma semana fechada.
    // `weekday` vai de 1 (segunda) a 7 (domingo), entao o resto por 7 da
    // exatamente quantos dias faltam para tras.
    final inicio = DateTime(
      umAnoAtras.year,
      umAnoAtras.month,
      umAnoAtras.day - umAnoAtras.weekday % 7,
    );
    final total = fim.difference(inicio).inDays;

    // Contado por indice, e nao somando Duration: um mes com mudança de
    // horario faria a soma pular ou repetir um dia, e a grade sairia torta.
    return [
      for (var i = 0; i <= total; i++)
        de(DateTime(inicio.year, inicio.month, inicio.day + i)),
    ];
  }

  /// Dias seguidos com alguma atividade, contando de tras para frente.
  ///
  /// Hoje ainda em branco nao quebra a sequencia: o dia nao acabou.
  int sequencia(DateTime hoje) {
    final fim = _soDia(hoje);
    var recuo = de(fim).vazio ? 1 : 0;

    var total = 0;
    while (!de(DateTime(fim.year, fim.month, fim.day - recuo)).vazio) {
      total++;
      recuo++;
    }
    return total;
  }

  /// Joga fora o que ja saiu da janela do contador.
  Atividade podar(DateTime hoje) {
    final fim = _soDia(hoje);
    final limite = DateTime(fim.year, fim.month, fim.day - _diasGuardados);

    return Atividade({
      for (final e in _dias.entries)
        if (DateTime.tryParse(e.key) case final d?)
          if (!d.isBefore(limite)) e.key: e.value,
    });
  }

  // ------------------------------------------------------------------ medida

  /// O que mudou entre duas versoes do mesmo arquivo.
  ///
  /// So o crescimento conta. Uma nota que encolheu foi revisada, nao
  /// desescrita — e contar a diferença como negativa apagaria do historico o
  /// dia em que ela foi escrita.
  static ({int palavras, int tarefas}) diferenca(String antes, String depois) {
    final p = palavrasEm(depois) - palavrasEm(antes);
    final t = feitasEm(depois) - feitasEm(antes);
    return (palavras: p > 0 ? p : 0, tarefas: t > 0 ? t : 0);
  }

  /// Marcaçao que nao e texto escrito: marcador de lista, caixa de tarefa,
  /// cerca de codigo, sustenido de titulo e delimitador de frontmatter.
  ///
  /// Sai da conta porque senao `- [ ]` virando `- [x]` mudaria o total sem uma
  /// palavra nova ter sido digitada — o contador registraria escrita onde
  /// houve so um clique.
  static final _marcacao = RegExp(
    r'\[[ xX]\]'
    r'|^[ \t]*(?:[-*+]|\d+[.)])[ \t]'
    r'|^[ \t]*#{1,6}[ \t]'
    r'|`{1,3}'
    r'|^---[ \t]*$',
    multiLine: true,
  );

  /// Uma palavra precisa ter ao menos uma letra ou um numero. Sem isso, o `|`
  /// de uma tabela e o `>` de uma citaçao entrariam na conta como texto.
  static final _temLetra = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Palavras de um texto, ignorando a marcaçao do Markdown.
  static int palavrasEm(String texto) {
    var total = 0;
    for (final palavra in texto.replaceAll(_marcacao, ' ').split(_branco)) {
      if (_temLetra.hasMatch(palavra)) total++;
    }
    return total;
  }

  static final _branco = RegExp(r'\s+');

  /// Caixas ja marcadas no texto.
  static int feitasEm(String texto) {
    var total = 0;
    for (final t in MarkdownTasks.listar(texto)) {
      if (t.feita) total++;
    }
    return total;
  }

  // --------------------------------------------------------------- gravaçao

  static String chave(DateTime dia) =>
      '${dia.year.toString().padLeft(4, '0')}-'
      '${dia.month.toString().padLeft(2, '0')}-'
      '${dia.day.toString().padLeft(2, '0')}';

  static DateTime _soDia(DateTime d) => DateTime(d.year, d.month, d.day);

  String encode() => jsonEncode({
    for (final e in _dias.entries)
      e.key: {'p': e.value.palavras, 't': e.value.tarefas},
  });

  /// Le o formato de [encode]. Arquivo corrompido vira historico vazio: perder
  /// o contador e ruim, mas nao abrir o vault por causa dele seria pior.
  static Atividade decode(String? bruto) {
    if (bruto == null || bruto.trim().isEmpty) return vazia;

    try {
      final json = jsonDecode(bruto);
      if (json is! Map) return vazia;

      final dias = <String, ({int palavras, int tarefas})>{};
      for (final e in json.entries) {
        final chave = e.key;
        final valor = e.value;
        if (chave is! String || valor is! Map) continue;
        if (DateTime.tryParse(chave) == null) continue;

        final p = valor['p'];
        final t = valor['t'];
        dias[chave] = (
          palavras: p is int && p > 0 ? p : 0,
          tarefas: t is int && t > 0 ? t : 0,
        );
      }
      return Atividade(dias);
    } on FormatException {
      return vazia;
    }
  }
}
