import 'package:flutter/foundation.dart';

import 'atividade.dart';
import 'calendar_event.dart';
import 'markdown_tasks.dart';
import 'note.dart';
import 'vault_graph.dart';

/// Uma nota que foi escrita ou mexida hoje, com o resumo do que ela tem
/// dentro.
///
/// O resumo e **tirado da nota**, nunca inventado: os titulos de seçao sao os
/// assuntos, as caixas marcadas sao o que foi fechado, as tags sao a materia.
/// Nao ha sumarizaçao nenhuma aqui — se o texto nao disser, o painel nao diz.
@immutable
class NotaDoDia {
  const NotaDoDia({
    required this.noteId,
    required this.titulo,
    required this.nova,
    required this.topicos,
    required this.feitas,
    required this.abertas,
    required this.tags,
    required this.palavras,
    this.alteradaEm,
  });

  final String noteId;
  final String titulo;

  /// A nota nasceu hoje, pelo `criado_em:` do frontmatter — o campo que o
  /// proprio app escreve ao criar a nota.
  final bool nova;

  /// Os assuntos da nota, na ordem em que aparecem: os titulos de seçao ou,
  /// numa nota sem titulos, as primeiras linhas de texto.
  final List<String> topicos;

  /// Caixas `- [x]` da nota — o que foi riscado.
  final List<String> feitas;

  /// Quantas caixas continuam abertas.
  final int abertas;

  final List<String> tags;

  /// Tamanho da nota hoje, em palavras. Nao e quanto foi escrito hoje: isso so
  /// o contador de atividade sabe, porque o arquivo guarda o estado atual e
  /// nao a historia dele.
  final int palavras;

  /// Hora da ultima gravaçao. Nulo quando a origem nao informa — o `stat`
  /// falhou, ou o vault do teste nao tem disco atras.
  final DateTime? alteradaEm;

  /// Uma linha so, para quando o resumo esta fechado.
  String get resumo {
    if (topicos.isNotEmpty) return topicos.join('  ·  ');
    if (feitas.isNotEmpty) return 'Fechou: ${feitas.join('; ')}';
    if (abertas > 0) {
      return '$abertas ${abertas == 1 ? 'tarefa' : 'tarefas'} em aberto, '
          'nada riscado ainda.';
    }
    return 'Sem seçoes nem tarefas — $palavras '
        '${palavras == 1 ? 'palavra' : 'palavras'} de texto corrido.';
  }
}

/// O dia de hoje visto pelo vault: quais notas foram tocadas e o que entrou em
/// cada uma.
///
/// Sai da mesma varredura do resto do painel. O que faz uma nota entrar aqui e
/// o disco — a data de gravaçao do `.md` — e o frontmatter `criado_em:`; nao
/// ha registro proprio de "notas de hoje" a manter em dia.
@immutable
class DiarioDoDia {
  const DiarioDoDia({required this.dia, required this.notas});

  /// Vazio, para o painel antes da primeira leitura do vault.
  factory DiarioDoDia.vazio(DateTime agora) =>
      DiarioDoDia(dia: _soDia(agora), notas: const []);

  final DateTime dia;

  /// Da ultima gravaçao para a primeira: o que acabei de mexer vem em cima.
  final List<NotaDoDia> notas;

  bool get isEmpty => notas.isEmpty;

  int get novas {
    var total = 0;
    for (final n in notas) {
      if (n.nova) total++;
    }
    return total;
  }

  int get alteradas => notas.length - novas;

  /// As tags das notas do dia, da mais usada para a menos — a materia que o
  /// dia teve.
  List<String> get assuntos {
    final uso = <String, int>{};
    for (final n in notas) {
      for (final tag in n.tags) {
        uso[tag] = (uso[tag] ?? 0) + 1;
      }
    }
    final ordenadas = uso.entries.toList()
      ..sort((a, b) {
        final porUso = b.value.compareTo(a.value);
        return porUso != 0 ? porUso : a.key.compareTo(b.key);
      });
    return [for (final e in ordenadas) e.key];
  }

  /// Tarefas riscadas nas notas do dia.
  ///
  /// E o total das notas, nao o que foi marcado hoje: a caixa no arquivo diz
  /// que esta feita, nunca quando foi marcada. Quantas foram fechadas hoje e
  /// pergunta para o contador de atividade.
  int get tarefasFeitas {
    var total = 0;
    for (final n in notas) {
      total += n.feitas.length;
    }
    return total;
  }

  /// `3 notas · 1 nova e 2 alteradas`, para o canto do cartao.
  String get manchete {
    if (isEmpty) return 'nada hoje';

    final partes = <String>[];
    if (novas > 0) partes.add('$novas ${novas == 1 ? 'nova' : 'novas'}');
    if (alteradas > 0) {
      partes.add('$alteradas ${alteradas == 1 ? 'alterada' : 'alteradas'}');
    }
    final total = notas.length == 1 ? '1 nota' : '${notas.length} notas';
    return '$total  ·  ${partes.join(' e ')}';
  }

  // ---------------------------------------------------------------- montagem

  /// Escolhe as notas de hoje e resume cada uma.
  ///
  /// [modificadas] traz a data de gravaçao de cada `.md`, vinda da varredura
  /// do vault. Nota sem entrada ali so entra no dia se o `criado_em:` disser
  /// que ela nasceu hoje — e o que mantem o painel montavel num teste sem
  /// disco.
  factory DiarioDoDia.build(
    Iterable<Note> notas, {
    required DateTime agora,
    Map<String, DateTime> modificadas = const {},
  }) {
    final dia = _soDia(agora);
    final doDia = <NotaDoDia>[];

    for (final nota in notas) {
      final alteradaEm = modificadas[nota.id];
      final criadaHoje = criadaEm(nota) == dia;
      final alteradaHoje = alteradaEm != null && _soDia(alteradaEm) == dia;
      if (!criadaHoje && !alteradaHoje) continue;

      final feitas = <String>[];
      var abertas = 0;
      for (final t in MarkdownTasks.listar(nota.body)) {
        if (!t.feita) {
          abertas++;
          continue;
        }
        final texto = _limpar(EventParser.extrairData(t.texto).texto);
        feitas.add(texto.isEmpty ? nota.title : _cortar(texto));
      }

      doDia.add(
        NotaDoDia(
          noteId: nota.id,
          titulo: nota.title,
          nova: criadaHoje,
          topicos: _topicos(nota),
          feitas: feitas,
          abertas: abertas,
          tags: TagParser.fromNote(nota).toList(),
          palavras: Atividade.palavrasEm(nota.body),
          alteradaEm: alteradaHoje ? alteradaEm : null,
        ),
      );
    }

    doDia.sort(_maisRecentePrimeiro);
    return DiarioDoDia(dia: dia, notas: doDia);
  }

  /// O dia em que a nota foi criada, pelo frontmatter.
  ///
  /// `criado_em:` e o que o app escreve ao criar a nota; `criado:` entra como
  /// sinonimo porque e o que se digita a mao. O disco nao serve aqui: o
  /// Windows guarda data de criaçao, mas ela e do arquivo — copiar o vault ou
  /// deixar a sincronizacao baixar tudo de novo faria o vault inteiro nascer
  /// hoje.
  static DateTime? criadaEm(Note nota) =>
      EventParser.diaDoFrontmatter(nota.frontmatter['criado_em']) ??
      EventParser.diaDoFrontmatter(nota.frontmatter['criado']);

  /// Quem tem hora de gravaçao vem primeiro, da mais recente para a mais
  /// antiga; o resto segue por titulo.
  static int _maisRecentePrimeiro(NotaDoDia a, NotaDoDia b) {
    if ((a.alteradaEm == null) != (b.alteradaEm == null)) {
      return a.alteradaEm == null ? 1 : -1;
    }
    if (a.alteradaEm != null) {
      final porHora = b.alteradaEm!.compareTo(a.alteradaEm!);
      if (porHora != 0) return porHora;
    }
    return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
  }

  // ------------------------------------------------------------------ resumo

  /// Quantos assuntos entram no resumo. Uma nota de aula tem dez seçoes; o
  /// cartao nao e a nota, e listar todas seria reescrever o sumario dela.
  static const _limiteDeTopicos = 6;

  /// Tamanho maximo de um topico. Passando disso ele para de ser titulo e
  /// vira paragrafo na tela.
  static const _limiteDoTopico = 90;

  /// Os assuntos da nota.
  ///
  /// Titulo de seçao e a melhor resposta para "o que estudei": foi o proprio
  /// usuario que separou o texto assim. Quando a nota nao tem titulo nenhum,
  /// as primeiras linhas fazem o papel — dizem mais que uma contagem de
  /// palavras diria.
  static List<String> _topicos(Note nota) {
    final titulos = <String>[];
    final linhas = <String>[];
    var dentroDeCodigo = false;

    for (final crua in nota.body.split('\n')) {
      // Cerca abre e fecha bloco de codigo — e de quadro, que tambem mora num
      // bloco cercado. O que esta dentro e sintaxe, nao assunto.
      if (_cerca.hasMatch(crua)) {
        dentroDeCodigo = !dentroDeCodigo;
        continue;
      }
      if (dentroDeCodigo) continue;

      if (_titulo.firstMatch(crua) case final m?) {
        final texto = _limpar(
          (m.group(2) ?? '').replaceAll(_sustenidoNoFim, ''),
        );
        if (texto.isNotEmpty) titulos.add(texto);
        continue;
      }

      // Achado um titulo, o texto corrido deixa de interessar: a nota ja disse
      // como quer ser resumida.
      if (titulos.isNotEmpty || linhas.length >= _limiteDeTopicos) continue;

      final semMarcador = crua
          .replaceFirst(_citacao, '')
          .replaceFirst(_marcadorDeLista, '');

      // Linha de tarefa nao entra como assunto: ela ja e contada em [feitas]
      // ou em [abertas], e repetir o texto faria o resumo aberto mostrar a
      // mesma frase duas vezes — uma com bolinha, outra com tique.
      if (_caixa.hasMatch(semMarcador)) continue;

      final texto = _limpar(semMarcador);
      if (texto.isEmpty || _naoEAssunto.hasMatch(texto)) continue;
      linhas.add(texto);
    }

    // O `# Titulo` que o app escreve ao criar a nota nao e assunto: e o nome
    // do arquivo repetido dentro dele.
    if (titulos.isNotEmpty &&
        titulos.first.toLowerCase() == nota.title.toLowerCase()) {
      titulos.removeAt(0);
    }

    final escolhidos = titulos.isNotEmpty ? titulos : linhas;
    return [for (final t in escolhidos.take(_limiteDeTopicos)) _cortar(t)];
  }

  static final _cerca = RegExp(r'^\s{0,3}(?:```|~~~)');
  static final _titulo = RegExp(r'^\s{0,3}(#{1,6})\s+(.*)$');
  static final _sustenidoNoFim = RegExp(r'\s*#+\s*$');
  static final _marcadorDeLista = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+');
  static final _caixa = RegExp(r'^\[[ xX]\]\s*');
  static final _citacao = RegExp(r'^\s*>+\s*');

  /// Linha que nao carrega assunto: regua horizontal, linha de tabela e
  /// marcaçao de HTML solta.
  static final _naoEAssunto = RegExp(r'^(?:(?:[-*_]\s*){3,}$|\||<)');

  static final _marcaDeData = RegExp(
    r'📅\s*\d{4}-\d{2}-\d{2}(?:\s+\d{1,2}:\d{2})?',
  );
  static final _wikilink = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]*))?\]\]');
  static final _link = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');

  /// Enfase, tachado e cerca de codigo inline. O `_` sozinho fica de fora: ele
  /// aparece dentro de nomes como `criado_em` mais do que como italico.
  static final _enfase = RegExp(r'\*\*|__|\*|~~|`');

  static final _branco = RegExp(r'\s+');

  /// Tira a marcaçao e deixa so o texto — assim o topico chega a tela como
  /// frase, e nao como Markdown cru.
  static String _limpar(String texto) {
    final semLink = texto
        .replaceAll(_marcaDeData, ' ')
        .replaceAllMapped(_wikilink, (m) {
          final rotulo = m.group(2);
          return rotulo != null && rotulo.trim().isNotEmpty
              ? rotulo
              : (m.group(1) ?? '');
        })
        .replaceAllMapped(_link, (m) => m.group(1) ?? '');
    return semLink.replaceAll(_enfase, '').replaceAll(_branco, ' ').trim();
  }

  static String _cortar(String texto) => texto.length <= _limiteDoTopico
      ? texto
      : '${texto.substring(0, _limiteDoTopico).trimRight()}…';

  static DateTime _soDia(DateTime d) => DateTime(d.year, d.month, d.day);
}
