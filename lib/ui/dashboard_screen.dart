import 'dart:async';

import 'package:flutter/material.dart';

import '../models/atividade.dart';
import '../models/calendar_event.dart';
import '../models/dashboard_data.dart';
import '../models/kanban_card.dart';
import 'app_theme.dart';
import 'graph_screen.dart';
import 'notas_recentes.dart';

/// O painel: a primeira tela do app.
///
/// Responde a uma pergunta so — **hoje, o que disso e meu problema?** — e por
/// isso o dia vem no titulo, em tamanho de manchete, com a hora andando.
///
/// Nao inventa convençao nenhuma. Evento vem do `📅` e do `tipo: evento`, card
/// vem do `status:`, tarefa vem do `- [ ]`, o grafo vem das tags e dos links.
/// O painel so junta e ordena pelo dia.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.dados,
    required this.atividade,
    required this.recentes,
    required this.onOpenNote,
    required this.onAlternarTarefa,
    required this.onRefresh,
    this.animarGrafo = true,
  });

  final DashboardData dados;

  /// O historico de escrita que alimenta o contador.
  final Atividade atividade;

  /// As ultimas notas abertas, da mais recente para a mais antiga.
  final List<NotaRecente> recentes;

  final ValueChanged<String> onOpenNote;

  /// Marca a tarefa [indice] da nota, gravando no arquivo. Quem monta a tela
  /// cuida da gravaçao — aqui so se sabe qual caixa foi clicada.
  final void Function(String noteId, int indice) onAlternarTarefa;

  final VoidCallback onRefresh;

  /// Desligado no teste: sem ticker, a simulaçao do grafo roda de uma vez.
  final bool animarGrafo;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Altura da fileira do meio. Fixa porque o grafo precisa de area para se
  /// desenhar: deixado crescer com o conteudo, ele ficaria com a altura da
  /// lista de tarefas ao lado.
  static const _alturaDaFileira = 400.0;

  Timer? _relogio;
  DateTime _agora = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Um tique por segundo, e o `setState` so troca o texto da hora: o resto
    // do painel nao depende de `_agora` e nao e remontado.
    _relogio = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _agora = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tres colunas so quando cada uma ainda tem largura util; abaixo disso
        // elas viram tres fileiras empilhadas.
        final lado = constraints.maxWidth >= 1000;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Titulo(agora: _agora, onRefresh: widget.onRefresh),
              const SizedBox(height: AppTheme.gapLg),
              if (lado)
                SizedBox(height: _alturaDaFileira, child: _fileira())
              else
                for (final cartao in _cartoes())
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppTheme.gapLg),
                    child: SizedBox(height: 320, child: cartao),
                  ),
              if (lado) const SizedBox(height: AppTheme.gapLg),
              _Contador(atividade: widget.atividade, hoje: widget.dados.hoje),
            ],
          ),
        );
      },
    );
  }

  Widget _fileira() {
    final cartoes = _cartoes();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // O grafo no meio pede mais espaço que as duas listas: com tudo igual
        // ele fica apertado demais para as bolinhas se separarem.
        Expanded(flex: 4, child: cartoes[0]),
        const SizedBox(width: AppTheme.gapLg),
        Expanded(flex: 5, child: cartoes[1]),
        const SizedBox(width: AppTheme.gapLg),
        Expanded(flex: 3, child: cartoes[2]),
      ],
    );
  }

  List<Widget> _cartoes() => [
    _Hoje(
      dados: widget.dados,
      onOpenNote: widget.onOpenNote,
      onAlternarTarefa: widget.onAlternarTarefa,
    ),
    _Grafo(
      dados: widget.dados,
      onOpenNote: widget.onOpenNote,
      onRefresh: widget.onRefresh,
      animar: widget.animarGrafo,
    ),
    _Recentes(recentes: widget.recentes, onOpenNote: widget.onOpenNote),
  ];
}

// ------------------------------------------------------------------- titulo

/// A hora andando, em tamanho de manchete, com o dia embaixo.
class _Titulo extends StatelessWidget {
  const _Titulo({required this.agora, required this.onRefresh});

  final DateTime agora;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vazio do tamanho do botao do outro lado: sem ele o relogio ficaria
        // centrado no espaço que sobra, e nao no cartao — deslocado meio botao
        // para a esquerda.
        const SizedBox(width: 40),
        Expanded(
          child: Column(
            children: [
              // Encolhe em vez de estourar: o painel tambem vive acoplado numa
              // barra estreita, e la nao cabe relogio deste tamanho.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _horaCompleta(agora),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 76,
                    height: 1.05,
                    color: theme.colorScheme.primary,
                    letterSpacing: -2,
                    // Sem largura fixa por digito o relogio treme a cada
                    // segundo, porque `1` e mais estreito que `8`.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                _porExtenso(agora),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 40,
          child: IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Reler o vault',
            onPressed: onRefresh,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ cartoes

/// Moldura comum dos tres cartoes da fileira.
class _Cartao extends StatelessWidget {
  const _Cartao({
    required this.titulo,
    required this.icone,
    required this.filho,
    this.contador,
    this.semPadding = false,
  });

  final String titulo;
  final IconData icone;
  final Widget filho;
  final String? contador;

  /// O grafo se desenha ate a borda; as listas respiram.
  final bool semPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.gapLg,
              AppTheme.gapMd,
              AppTheme.gapLg,
              AppTheme.gapMd,
            ),
            child: Row(
              children: [
                Icon(icone, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppTheme.gapSm),
                Expanded(
                  child: Text(titulo, style: theme.textTheme.titleSmall),
                ),
                if (contador != null)
                  Text(contador!, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: semPadding
                ? filho
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.gapLg,
                      AppTheme.gapSm,
                      AppTheme.gapLg,
                      AppTheme.gapLg,
                    ),
                    child: filho,
                  ),
          ),
        ],
      ),
    );
  }
}

/// O que precisa ser feito hoje: o que venceu, a agenda do dia, as tarefas e
/// os cards com prazo.
class _Hoje extends StatelessWidget {
  const _Hoje({
    required this.dados,
    required this.onOpenNote,
    required this.onAlternarTarefa,
  });

  final DashboardData dados;
  final ValueChanged<String> onOpenNote;
  final void Function(String, int) onAlternarTarefa;

  @override
  Widget build(BuildContext context) {
    final atrasadas = dados.tarefasAtrasadas;
    final cardsAtrasados = dados.cardsAtrasados;

    return _Cartao(
      titulo: 'Tarefas de hoje',
      icone: Icons.today_outlined,
      contador: _resumo(),
      filho: dados.semNada
          ? const _Nada(
              texto:
                  'O vault esta vazio. Crie uma nota e o painel começa a '
                  'mostrar o que ela tem dentro.',
            )
          : dados.diaLimpo
          ? _diaLimpo(context)
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                if (atrasadas.isNotEmpty || cardsAtrasados.isNotEmpty) ...[
                  const _Rotulo(texto: 'ATRASADO', alerta: true),
                  for (final t in atrasadas) _tarefa(t),
                  for (final c in cardsAtrasados) _card(c),
                  const SizedBox(height: AppTheme.gapMd),
                ],
                if (dados.eventosDeHoje.isNotEmpty) ...[
                  const _Rotulo(texto: 'AGENDA'),
                  for (final e in dados.eventosDeHoje)
                    _LinhaEvento(
                      evento: e,
                      onAbrir: () => onOpenNote(e.noteId),
                    ),
                  const SizedBox(height: AppTheme.gapMd),
                ],
                if (dados.tarefasDeHoje.isNotEmpty) ...[
                  const _Rotulo(texto: 'PARA HOJE'),
                  for (final t in dados.tarefasDeHoje) _tarefa(t),
                  const SizedBox(height: AppTheme.gapMd),
                ],
                if (dados.cardsDeHoje.isNotEmpty) ...[
                  const _Rotulo(texto: 'CARDS COM PRAZO HOJE'),
                  for (final c in dados.cardsDeHoje) _card(c),
                ],
              ],
            ),
    );
  }

  Widget _tarefa(TarefaAberta t) => _LinhaTarefa(
    tarefa: t,
    hoje: dados.hoje,
    onAbrir: () => onOpenNote(t.noteId),
    onMarcar: () => onAlternarTarefa(t.noteId, t.indice),
  );

  Widget _card(KanbanCard c) => _LinhaCard(
    card: c,
    hoje: dados.hoje,
    onAbrir: () => onOpenNote(c.noteId),
  );

  /// Dia livre nao e tela vazia: mostra o que esta aberto sem data, que e o
  /// que da para puxar quando sobra tempo.
  Widget _diaLimpo(BuildContext context) {
    final soltas = dados.tarefasSemPrazo;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _Nada(
          texto:
              'Nada marcado para hoje e nada vencido. Escreva '
              '📅${_iso(dados.hoje)} numa linha de tarefa para ela aparecer '
              'aqui.',
        ),
        if (soltas.isNotEmpty) ...[
          const SizedBox(height: AppTheme.gapMd),
          const _Rotulo(texto: 'ABERTAS, SEM DATA'),
          for (final t in soltas.take(8)) _tarefa(t),
        ],
      ],
    );
  }

  String? _resumo() {
    if (dados.semNada) return null;
    if (dados.totalAtrasado > 0) {
      return '${dados.totalAtrasado} atrasado(s)  ·  ${dados.totalDeHoje} hoje';
    }
    return '${dados.totalDeHoje} para hoje';
  }
}

/// O grafo do vault, do mesmo jeito da aba — so menor.
class _Grafo extends StatelessWidget {
  const _Grafo({
    required this.dados,
    required this.onOpenNote,
    required this.onRefresh,
    required this.animar,
  });

  final DashboardData dados;
  final ValueChanged<String> onOpenNote;
  final VoidCallback onRefresh;
  final bool animar;

  @override
  Widget build(BuildContext context) {
    return _Cartao(
      titulo: 'Grafo',
      icone: Icons.hub_outlined,
      semPadding: true,
      contador: dados.grafo.isEmpty
          ? null
          : '${dados.totalNotas} notas  ·  ${dados.tags.length} tags',
      filho: GraphScreen(
        graph: dados.grafo,
        onOpenNote: onOpenNote,
        onRefresh: onRefresh,
        animate: animar,
      ),
    );
  }
}

/// As ultimas notas abertas.
class _Recentes extends StatelessWidget {
  const _Recentes({required this.recentes, required this.onOpenNote});

  final List<NotaRecente> recentes;
  final ValueChanged<String> onOpenNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return _Cartao(
      titulo: 'Ultimas notas',
      icone: Icons.history,
      filho: recentes.isEmpty
          ? const _Nada(
              texto:
                  'Ainda nao abri nenhuma nota. As que voce abrir aparecem '
                  'aqui, da mais recente para a mais antiga.',
            )
          : ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: recentes.length,
              itemBuilder: (context, i) => InkWell(
                onTap: () => onOpenNote(recentes[i].id),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: 14,
                        color: i == 0
                            // A primeira e a que esta aberta agora.
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppTheme.gapSm),
                      Expanded(
                        child: Text(
                          recentes[i].titulo,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

// ----------------------------------------------------------------- contador

/// O contador de atividade, no formato do quadro de contribuiçoes do GitHub.
///
/// Um quadradinho por dia do ultimo ano, mais escuro quando o dia foi parado e
/// mais aceso quando foi de escrever. A intensidade e relativa ao melhor dia
/// do periodo: numa escala fixa, um vault tranquilo ficaria cinza o ano
/// inteiro e o desenho nao diria nada.
class _Contador extends StatelessWidget {
  const _Contador({required this.atividade, required this.hoje});

  final Atividade atividade;
  final DateTime hoje;

  static const _lado = 11.0;
  static const _vao = 3.0;
  static const _passo = _lado + _vao;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final dias = atividade.ultimoAno(hoje);
    final semanas = (dias.length / 7).ceil();
    final maximo = dias.fold(0, (m, d) => d.pontos > m ? d.pontos : m);
    final palavras = dias.fold(0, (t, d) => t + d.palavras);
    final tarefas = dias.fold(0, (t, d) => t + d.tarefas);
    final sequencia = atividade.sequencia(hoje);

    return Container(
      padding: const EdgeInsets.all(AppTheme.gapLg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppTheme.gapSm),
              Expanded(
                child: Text(
                  palavras == 0 && tarefas == 0
                      ? 'Nada escrito ainda neste ultimo ano'
                      : '$palavras ${palavras == 1 ? 'palavra escrita' : 'palavras escritas'}'
                            ' e $tarefas ${tarefas == 1 ? 'tarefa concluida' : 'tarefas concluidas'}'
                            ' no ultimo ano',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sequencia > 0)
                Text(
                  '$sequencia ${sequencia == 1 ? 'dia seguido' : 'dias seguidos'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.gapMd),
          // A grade tem largura fixa (53 semanas): em janela estreita ela rola
          // de lado, como no GitHub, em vez de espremer os quadradinhos.
          _quadro(theme, scheme, dias, semanas, maximo),
        ],
      ),
    );
  }

  /// A grade com os meses em cima e a legenda embaixo, sempre no meio do
  /// cartao.
  ///
  /// Quando o ano inteiro cabe, o bloco e centrado; quando nao cabe, ele rola
  /// de lado como no GitHub, em vez de espremer os quadradinhos. O
  /// `LayoutBuilder` existe por isso: um `SingleChildScrollView` sozinho nao
  /// sabe centrar — o espaço dele e infinito, entao ele sempre encosta o
  /// conteudo numa das pontas.
  Widget _quadro(
    ThemeData theme,
    ColorScheme scheme,
    List<DiaDeAtividade> dias,
    int semanas,
    int maximo,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final largura = semanas * _passo;
        final bloco = SizedBox(
          width: largura,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _meses(theme, dias, semanas),
              const SizedBox(height: 2),
              _grade(scheme, dias, semanas, maximo),
              const SizedBox(height: AppTheme.gapSm),
              // A legenda acompanha a grade em vez de ir para a borda do
              // cartao: solta la longe, ela nao se leria como parte do desenho.
              _legenda(theme, scheme),
            ],
          ),
        );

        if (largura <= constraints.maxWidth) return Center(child: bloco);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Começa mostrando o fim: o que interessa e o mes corrente.
          reverse: true,
          child: bloco,
        );
      },
    );
  }

  /// Rotulo do mes acima da primeira semana em que ele aparece.
  Widget _meses(ThemeData theme, List<DiaDeAtividade> dias, int semanas) {
    final rotulos = <int, String>{};
    var ultimo = -1;
    for (var semana = 0; semana < semanas; semana++) {
      final dia = dias[semana * 7];
      if (dia.dia.month != ultimo) {
        ultimo = dia.dia.month;
        rotulos[semana] = _mesesCurtos[dia.dia.month - 1];
      }
    }

    return SizedBox(
      height: 13,
      width: semanas * _passo,
      child: Stack(
        children: [
          for (final e in rotulos.entries)
            Positioned(
              left: e.key * _passo,
              child: Text(e.value, style: theme.textTheme.labelSmall),
            ),
        ],
      ),
    );
  }

  Widget _grade(
    ColorScheme scheme,
    List<DiaDeAtividade> dias,
    int semanas,
    int maximo,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var semana = 0; semana < semanas; semana++)
          Padding(
            padding: const EdgeInsets.only(right: _vao),
            child: Column(
              children: [
                for (var d = 0; d < 7; d++)
                  if (semana * 7 + d < dias.length)
                    _quadrado(scheme, dias[semana * 7 + d], maximo)
                  else
                    // A ultima semana costuma estar pela metade: o espaço fica
                    // reservado para as colunas nao subirem de nivel.
                    const SizedBox(width: _lado, height: _passo),
              ],
            ),
          ),
      ],
    );
  }

  Widget _quadrado(ColorScheme scheme, DiaDeAtividade dia, int maximo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _vao),
      child: Tooltip(
        message: dia.vazio
            ? 'Nada em ${_diaCurto(dia.dia)}'
            : '${dia.palavras} palavras e ${dia.tarefas} tarefas '
                  'em ${_diaCurto(dia.dia)}',
        waitDuration: const Duration(milliseconds: 300),
        child: Container(
          width: _lado,
          height: _lado,
          decoration: BoxDecoration(
            color: _cor(scheme, dia.pontos, maximo),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// Quatro niveis acesos mais o apagado, como no GitHub.
  static Color _cor(ColorScheme scheme, int pontos, int maximo) {
    if (pontos <= 0 || maximo <= 0) return scheme.surfaceContainerHighest;

    final fatia = pontos / maximo;
    final alpha = fatia > 0.75
        ? 1.0
        : fatia > 0.5
        ? 0.75
        : fatia > 0.25
        ? 0.5
        : 0.28;
    return scheme.primary.withValues(alpha: alpha);
  }

  Widget _legenda(ThemeData theme, ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Menos', style: theme.textTheme.labelSmall),
        const SizedBox(width: AppTheme.gapXs),
        for (final pontos in [0, 1, 2, 3, 4])
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: _lado,
              height: _lado,
              decoration: BoxDecoration(
                color: _cor(scheme, pontos, 4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: AppTheme.gapXs),
        Text('Mais', style: theme.textTheme.labelSmall),
      ],
    );
  }
}

// ------------------------------------------------------------------- linhas

class _Rotulo extends StatelessWidget {
  const _Rotulo({required this.texto, this.alerta = false});

  final String texto;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapXs),
      child: Text(
        texto,
        style: theme.textTheme.labelSmall?.copyWith(
          color: alerta ? theme.colorScheme.error : null,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Uma tarefa com caixa clicavel.
///
/// A caixa marca no arquivo, o resto da linha abre a nota. Sao dois destinos
/// diferentes no mesmo item porque sao as duas coisas que se quer fazer com
/// uma pendencia: riscar, ou ir ver do que se trata.
class _LinhaTarefa extends StatelessWidget {
  const _LinhaTarefa({
    required this.tarefa,
    required this.hoje,
    required this.onAbrir,
    required this.onMarcar,
  });

  final TarefaAberta tarefa;
  final DateTime hoje;
  final VoidCallback onAbrir;
  final VoidCallback onMarcar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final atrasada = tarefa.prazo != null && tarefa.prazo!.isBefore(hoje);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tooltip(
          message: 'Marcar como feita',
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(
            onTap: onMarcar,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(
                Icons.check_box_outline_blank_rounded,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: InkWell(
            onTap: onAbrir,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tarefa.texto,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      if (tarefa.prazo != null) ...[
                        Text(
                          _diaCurto(tarefa.prazo!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: atrasada ? scheme.error : scheme.primary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.gapSm),
                      ],
                      Flexible(
                        child: Text(
                          tarefa.nota,
                          style: theme.textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LinhaEvento extends StatelessWidget {
  const _LinhaEvento({required this.evento, required this.onAbrir});

  final CalendarEvent evento;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onAbrir,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                evento.timeLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppTheme.gapSm),
            Expanded(
              child: Text(
                evento.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaCard extends StatelessWidget {
  const _LinhaCard({
    required this.card,
    required this.hoje,
    required this.onAbrir,
  });

  final KanbanCard card;
  final DateTime hoje;
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final atrasado = card.prazo != null && card.prazo!.isBefore(hoje);

    return InkWell(
      onTap: onAbrir,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 5, right: AppTheme.gapSm),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: atrasado ? scheme.error : scheme.primary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.titulo,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    card.prazo == null
                        ? card.coluna.label
                        : '${card.coluna.label}  ·  ${_diaCurto(card.prazo!)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: atrasado ? scheme.error : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Nada extends StatelessWidget {
  const _Nada({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) =>
      Text(texto, style: Theme.of(context).textTheme.bodySmall);
}

// ------------------------------------------------------------------- datas

const _diasDaSemana = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sabado',
  'domingo',
];

const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

const _mesesCurtos = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// `quinta-feira, 9 de agosto de 2026`.
///
/// Escrito a mao em vez de vir do `intl`: e uma linha de cabeçalho, e a
/// dependencia traria o pacote inteiro de localizaçao junto.
String _porExtenso(DateTime d) =>
    '${_diasDaSemana[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]} '
    'de ${d.year}';

String _horaCompleta(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';

String _diaCurto(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
