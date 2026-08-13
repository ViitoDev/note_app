import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/atividade.dart';
import 'package:notas_app/models/dashboard_data.dart';
import 'package:notas_app/models/markdown_tasks.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/services/dashboard_service.dart';
import 'package:notas_app/ui/dashboard_screen.dart';
import 'package:notas_app/ui/graph_screen.dart';
import 'package:notas_app/ui/notas_recentes.dart';
import 'package:notas_app/ui/ui_prefs.dart';

import 'fake_vault.dart';

/// Dia fixo: um painel de "hoje" que lesse o relogio de verdade so daria para
/// testar em algumas horas do ano.
final _hoje = DateTime(2026, 8, 9);

Note _nota(String nome, String conteudo) =>
    Note.parse('/v/$nome.md', conteudo, name: '$nome.md');

DashboardData _painel(List<Note> notas) =>
    DashboardData.build(notas, agora: _hoje);

/// Vault falso que devolve as notas passadas, com a arvore montada a partir
/// delas.
class _VaultComNotas extends FakeVault {
  _VaultComNotas(this.notas);

  final List<Note> notas;
  final gravados = <({String id, String conteudo})>[];

  @override
  Future<VaultFolder> scan(String rootId) async => VaultFolder(
    id: rootPath,
    name: 'vault',
    children: [for (final n in notas) VaultFile(id: n.id, name: n.name)],
  );

  @override
  Future<Note> readNote(String noteId) async =>
      notas.firstWhere((n) => n.id == noteId);

  @override
  Future<void> writeNote(String noteId, String content) async =>
      gravados.add((id: noteId, conteudo: content));
}

void main() {
  group('o que precisa ser feito no dia', () {
    test('tarefa com a data de hoje entra no dia, sem a marcaçao no texto', () {
      final dados = _painel([
        _nota('Estudos', '- [ ] 📅2026-08-09 Revisar algebra\n'),
      ]);

      final tarefa = dados.tarefasDeHoje.single;
      // A data vira etiqueta na tela; repetir `📅2026-08-09` dentro da frase
      // seria dizer a mesma coisa duas vezes.
      expect(tarefa.texto, 'Revisar algebra');
      expect(tarefa.prazo, _hoje);
      expect(tarefa.nota, 'Estudos');
      expect(dados.totalDeHoje, 1);
    });

    test('data passada e atraso, data futura nao', () {
      final dados = _painel([
        _nota(
          'Lista',
          '- [ ] 📅2026-08-01 Entregar relatorio\n'
              '- [ ] 📅2026-08-20 Comprar passagem\n',
        ),
      ]);

      expect(dados.tarefasAtrasadas.single.texto, 'Entregar relatorio');
      expect(dados.tarefasDeHoje, isEmpty);
      expect(dados.totalAtrasado, 1);
    });

    test('tarefa sem data fica de fora do dia, mas continua pendente', () {
      final dados = _painel([_nota('Ideias', '- [ ] Pensar no nome do app\n')]);

      expect(dados.totalDeHoje, 0);
      expect(dados.tarefasSemPrazo.single.texto, 'Pensar no nome do app');
      expect(dados.tarefas, hasLength(1));
    });

    test('tarefa marcada sai da lista e vira numero', () {
      final dados = _painel([
        _nota('Lista', '- [x] Feita\n- [ ] Aberta\n- [X] Feita tambem\n'),
      ]);

      expect(dados.tarefas.map((t) => t.texto), ['Aberta']);
      expect(dados.tarefasFeitas, 2);
      expect(dados.totalTarefas, 3);
    });

    test('o indice da tarefa aberta e o que marca a linha certa', () {
      // A contagem inclui as feitas: se ela pulasse, marcar a segunda aberta
      // reescreveria a linha errada do arquivo.
      const texto =
          '- [x] Ja foi\n- [ ] Primeira\n- [x] Outra\n- [ ] Segunda\n';
      final dados = _painel([_nota('Lista', texto)]);

      final segunda = dados.tarefas.firstWhere((t) => t.texto == 'Segunda');
      final depois = MarkdownTasks.alternar(texto, segunda.indice);

      expect(depois, contains('- [x] Segunda'));
      expect(depois, contains('- [ ] Primeira'));
    });

    test('caixa dentro de bloco de codigo nao vira pendencia', () {
      final dados = _painel([
        _nota(
          'Manual',
          '```\n- [ ] exemplo de sintaxe\n```\n- [ ] de verdade\n',
        ),
      ]);

      expect(dados.tarefas.map((t) => t.texto), ['de verdade']);
    });

    test('evento de hoje entra no dia; o da semana que vem, na semana', () {
      final dados = _painel([
        _nota('Agenda', '📅2026-08-09 14:00 Dentista\n'),
        _nota('Prova', '---\ntipo: evento\ndata: 2026-08-12\n---\n'),
        // Fora da janela de sete dias: nem hoje, nem "proximos".
        _nota('Longe', '📅2026-09-30 Congresso\n'),
      ]);

      expect(dados.eventosDeHoje.single.title, 'Dentista');
      expect(dados.eventosDaSemana.single.title, 'Prova');
      expect(dados.eventos, hasLength(3));
    });

    test('linha de tarefa com data conta uma vez, como tarefa', () {
      // O parser ve as duas coisas nessa linha: caixa e data. No calendario
      // ela e evento; aqui seria a mesma frase na agenda e na lista, e so uma
      // das copias teria caixa para marcar.
      final dados = _painel([_nota('Lista', '- [ ] 📅2026-08-09 Ler cap 3\n')]);

      expect(dados.tarefasDeHoje.single.texto, 'Ler cap 3');
      expect(dados.eventosDeHoje, isEmpty);
      expect(dados.totalDeHoje, 1);
    });

    test('tarefa datada ja marcada nao volta pela porta do evento', () {
      final dados = _painel([_nota('Lista', '- [x] 📅2026-08-09 Ja fiz\n')]);

      expect(dados.tarefas, isEmpty);
      expect(dados.diaLimpo, isTrue);
    });

    test('data em linha comum continua sendo evento', () {
      final dados = _painel([_nota('Agenda', '📅2026-08-09 Reuniao\n')]);

      expect(dados.eventosDeHoje.single.title, 'Reuniao');
      expect(dados.tarefas, isEmpty);
    });

    test('card vencido cobra, card pronto nao', () {
      final dados = _painel([
        _nota('Atrasado', '---\nstatus: fazendo\ndata: 2026-08-01\n---\n'),
        _nota('Hoje', '---\nstatus: a-fazer\ndata: 2026-08-09\n---\n'),
        // Entregue, mesmo que tarde: cobrar de novo seria ruido.
        _nota('Entregue', '---\nstatus: pronto\ndata: 2026-07-01\n---\n'),
      ]);

      expect(dados.cardsAtrasados.single.titulo, 'Atrasado');
      expect(dados.cardsDeHoje.single.titulo, 'Hoje');
      expect(dados.emAndamento.single.titulo, 'Atrasado');
    });

    test('dia limpo e dia sem nada marcado e sem nada vencido', () {
      final dados = _painel([_nota('Solta', '# So um texto\n')]);

      expect(dados.diaLimpo, isTrue);
      expect(dados.semNada, isFalse);
      expect(_painel(const []).semNada, isTrue);
    });
  });

  group('resumo do vault', () {
    test('conta as notas por tag, da mais usada para a menos', () {
      final dados = _painel([
        _nota('A', '---\ntags: [estudo, flutter]\n---\n'),
        _nota('B', '#estudo em qualquer lugar do corpo\n'),
        _nota('C', '#flutter #estudo\n'),
      ]);

      expect(dados.tags['estudo'], 3);
      expect(dados.tags['flutter'], 2);
      // A ordem e a do painel: quem aparece mais vem antes.
      expect(dados.tags.keys.first, 'estudo');
      expect(dados.totalNotas, 3);
    });

    test('a mesma tag repetida na nota conta uma vez so', () {
      final dados = _painel([_nota('A', '#estudo #estudo #estudo\n')]);

      expect(dados.tags['estudo'], 1);
    });
  });

  group('servico', () {
    test('le o vault inteiro numa passada', () async {
      final vault = _VaultComNotas([
        _nota('Hoje', '- [ ] 📅2026-08-09 Fazer\n'),
        _nota('Card', '---\nstatus: fazendo\n---\n'),
      ]);

      final dados = await DashboardService(
        vault,
      ).build(await vault.scan(vault.rootPath), agora: _hoje);

      expect(dados.totalNotas, 2);
      expect(dados.tarefasDeHoje, hasLength(1));
      expect(dados.board.total, 1);
    });

    test(
      'marcar a tarefa reescreve a linha e preserva o frontmatter',
      () async {
        final vault = _VaultComNotas([
          _nota(
            'Lista',
            '---\ntags: [x]\n---\n\n- [ ] Primeira\n- [ ] Segunda\n',
          ),
        ]);

        await DashboardService(vault).alternarTarefa('/v/Lista.md', 1);

        final gravado = vault.gravados.single.conteudo;
        expect(gravado, startsWith('---\ntags: [x]\n---\n'));
        expect(gravado, contains('- [ ] Primeira'));
        expect(gravado, contains('- [x] Segunda'));
      },
    );

    test('indice que nao existe mais nao grava nada', () async {
      // O arquivo pode ter mudado por fora entre o desenho e o clique; marcar
      // "a linha que sobrou" seria pior do que nao fazer nada.
      final vault = _VaultComNotas([_nota('Lista', '- [ ] Unica\n')]);

      await DashboardService(vault).alternarTarefa('/v/Lista.md', 7);

      expect(vault.gravados, isEmpty);
    });
  });

  group('historico de escrita', () {
    test('so o crescimento conta como escrita', () {
      // Uma nota que encolheu foi revisada, nao desescrita. Contar a diferença
      // como negativa apagaria do historico o dia em que ela foi escrita.
      expect(
        Atividade.diferenca('uma frase', 'uma frase bem maior que a outra'),
        (palavras: 5, tarefas: 0),
      );
      expect(Atividade.diferenca('uma frase curta', 'uma'), (
        palavras: 0,
        tarefas: 0,
      ));
    });

    test('marcar uma caixa conta como tarefa concluida', () {
      expect(Atividade.diferenca('- [ ] a\n- [ ] b\n', '- [x] a\n- [ ] b\n'), (
        palavras: 0,
        tarefas: 1,
      ));
      // Desmarcar nao tira do historico: o trabalho daquele dia foi feito.
      expect(Atividade.diferenca('- [x] a\n', '- [ ] a\n'), (
        palavras: 0,
        tarefas: 0,
      ));
    });

    test('marcaçao de Markdown nao conta como palavra escrita', () {
      // Senao um clique na caixa registraria escrita, e uma lista de tres
      // itens valeria mais que uma frase de tres palavras.
      expect(Atividade.palavrasEm('- [ ] comprar cafe'), 2);
      expect(Atividade.palavrasEm('- [x] comprar cafe'), 2);
      expect(Atividade.palavrasEm('## Titulo da nota'), 3);
      expect(Atividade.palavrasEm('| a | b |'), 2);
      expect(Atividade.palavrasEm('   \n\n  '), 0);
    });

    test('soma no dia e acumula', () {
      final a = Atividade.vazia
          .somar(_hoje, palavras: 10)
          .somar(_hoje, palavras: 5, tarefas: 2);

      expect(a.de(_hoje).palavras, 15);
      expect(a.de(_hoje).tarefas, 2);
      // Uma tarefa concluida pesa como 20 palavras no desenho.
      expect(a.de(_hoje).pontos, 55);
      expect(a.de(DateTime(2026, 8, 8)).vazio, isTrue);
    });

    test('a grade do ano comeca num domingo e termina hoje', () {
      final dias = Atividade.vazia.ultimoAno(_hoje);

      expect(dias.first.dia.weekday, DateTime.sunday);
      expect(dias.last.dia, _hoje);
      // Um ano inteiro, sem buracos: dia parado entra zerado, senao as semanas
      // seguintes sairiam desalinhadas.
      expect(dias.length, greaterThanOrEqualTo(365));
      expect(dias.length % 7, greaterThanOrEqualTo(0));
    });

    test('sequencia conta dias seguidos, e hoje em branco nao quebra', () {
      final ontem = DateTime(2026, 8, 8);
      final anteontem = DateTime(2026, 8, 7);

      final a = Atividade.vazia
          .somar(ontem, palavras: 3)
          .somar(anteontem, palavras: 3);

      // O dia ainda nao acabou: nao ter escrito hoje nao zera a sequencia.
      expect(a.sequencia(_hoje), 2);
      expect(a.somar(_hoje, palavras: 1).sequencia(_hoje), 3);
      expect(Atividade.vazia.sequencia(_hoje), 0);
    });

    test('sobrevive a ida e volta pelo arquivo', () {
      final a = Atividade.vazia.somar(_hoje, palavras: 42, tarefas: 3);
      final voltou = Atividade.decode(a.encode());

      expect(voltou.de(_hoje).palavras, 42);
      expect(voltou.de(_hoje).tarefas, 3);
    });

    test('arquivo corrompido vira historico vazio', () {
      // Perder o contador e chato; nao abrir o vault por causa dele seria pior.
      expect(Atividade.decode('{isso nao e json').isEmpty, isTrue);
      expect(Atividade.decode('[]').isEmpty, isTrue);
      expect(Atividade.decode('{"nao-e-data": {"p": 1}}').isEmpty, isTrue);
      expect(Atividade.decode(null).isEmpty, isTrue);
    });

    test('poda joga fora o que saiu da janela do contador', () {
      final velho = DateTime(2024, 1, 1);
      final a = Atividade.vazia
          .somar(velho, palavras: 9)
          .somar(_hoje, palavras: 9)
          .podar(_hoje);

      expect(a.de(velho).vazio, isTrue);
      expect(a.de(_hoje).palavras, 9);
    });
  });

  group('ultimas notas abertas', () {
    setUp(UiPrefs.resetForTesting);

    test('a mais recente fica na frente e nao duplica', () {
      NotasRecentes.registrar('/v/A.md');
      NotasRecentes.registrar('/v/B.md');
      final lista = NotasRecentes.registrar('/v/A.md');

      expect(lista, ['/v/A.md', '/v/B.md']);
    });

    test('a lista tem teto', () {
      for (var i = 0; i < NotasRecentes.limite + 5; i++) {
        NotasRecentes.registrar('/v/$i.md');
      }

      expect(NotasRecentes.ler(), hasLength(NotasRecentes.limite));
      expect(NotasRecentes.ler().first, '/v/${NotasRecentes.limite + 4}.md');
    });

    test('preferencia corrompida nao derruba a leitura', () {
      UiPrefs.writeString('notas_recentes', 'nao e json');

      expect(NotasRecentes.ler(), isEmpty);
    });
  });

  group('tela do painel', () {
    Future<List<String>> montar(
      WidgetTester tester,
      DashboardData dados, {
      void Function(String, int)? onAlternar,
      Atividade atividade = Atividade.vazia,
      List<NotaRecente> recentes = const [],
    }) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final abertos = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              dados: dados,
              atividade: atividade,
              recentes: recentes,
              onOpenNote: abertos.add,
              onAlternarTarefa: onAlternar ?? (_, _) {},
              onRefresh: () {},
              // Sem ticker o grafo assenta de uma vez; com ele o
              // `pumpAndSettle` nunca voltaria.
              animarGrafo: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return abertos;
    }

    testWidgets('o relogio e a manchete, com o dia e o ano embaixo', (
      tester,
    ) async {
      await montar(tester, _painel([_nota('A', 'texto\n')]));

      final data = find.text(_porExtenso(DateTime.now()));
      expect(data, findsOneWidget);

      // O relogio manda no cabeçalho: e ele que vem primeiro e em corpo bem
      // maior que a data.
      final relogio = find.text(_relogioNaTela(tester));
      expect(tester.getRect(relogio).top, lessThan(tester.getRect(data).top));
      expect(
        tester.widget<Text>(relogio).style?.fontSize,
        greaterThan(tester.widget<Text>(data).style?.fontSize ?? 0),
      );

      // Os dois no meio da tela, e nao no meio do que sobra do botao de
      // recarregar.
      final meio = tester.getRect(find.byType(DashboardScreen)).center.dx;
      expect(tester.getRect(relogio).center.dx, closeTo(meio, 1));
      expect(tester.getRect(data).center.dx, closeTo(meio, 1));

      final antes = _relogioNaTela(tester);
      // O relogio bate de segundo em segundo; depois de um segundo e um
      // pouco, o texto tem que ser outro.
      await tester.pump(const Duration(milliseconds: 1100));
      expect(_relogioNaTela(tester), isNot(antes));
    });

    testWidgets('as tres colunas sao tarefas, grafo e ultimas notas', (
      tester,
    ) async {
      await montar(
        tester,
        _painel([
          _nota('A', '#estudo liga com [[B]]\n'),
          _nota('B', 'texto\n'),
        ]),
        recentes: const [NotaRecente('/v/B.md')],
      );

      expect(find.text('Tarefas de hoje'), findsOneWidget);
      expect(find.text('Grafo'), findsOneWidget);
      expect(find.text('Ultimas notas'), findsOneWidget);

      expect(find.byType(GraphScreen), findsOneWidget);
      expect(find.text('B'), findsWidgets);

      // A ordem na tela e a pedida: tarefas, grafo, recentes.
      final tarefas = tester.getRect(find.text('Tarefas de hoje'));
      final grafo = tester.getRect(find.text('Grafo'));
      final recentes = tester.getRect(find.text('Ultimas notas'));
      expect(tarefas.left, lessThan(grafo.left));
      expect(grafo.left, lessThan(recentes.left));
    });

    testWidgets('o que venceu vem antes do resto do dia', (tester) async {
      await montar(
        tester,
        _painel([
          _nota('Lista', '- [ ] 📅2026-07-30 Entregar relatorio\n'),
          _nota('Hoje', '- [ ] 📅2026-08-09 Revisar\n'),
        ]),
      );

      expect(find.text('ATRASADO'), findsOneWidget);
      expect(find.text('PARA HOJE'), findsOneWidget);
      expect(
        tester.getRect(find.text('Entregar relatorio')).top,
        lessThan(tester.getRect(find.text('Revisar')).top),
      );
    });

    testWidgets('clicar na caixa pede para marcar a tarefa', (tester) async {
      final marcadas = <({String nota, int indice})>[];
      await montar(
        tester,
        _painel([_nota('Lista', '- [x] Feita\n- [ ] 📅2026-08-09 Fazer\n')]),
        onAlternar: (nota, i) => marcadas.add((nota: nota, indice: i)),
      );

      await tester.tap(find.byTooltip('Marcar como feita'));
      await tester.pump();

      // Indice 1: a primeira caixa do arquivo ja estava marcada.
      expect(marcadas.single, (nota: '/v/Lista.md', indice: 1));
    });

    testWidgets('clicar no texto da tarefa abre a nota de origem', (
      tester,
    ) async {
      final abertos = await montar(
        tester,
        _painel([_nota('Estudos', '- [ ] 📅2026-08-09 Revisar algebra\n')]),
      );

      await tester.tap(find.text('Revisar algebra'));
      await tester.pump();

      expect(abertos, ['/v/Estudos.md']);
    });

    testWidgets('dia livre mostra o que esta aberto sem data', (tester) async {
      await montar(
        tester,
        _painel([_nota('Ideias', '- [ ] Pensar no nome\n')]),
      );

      expect(find.textContaining('Nada marcado para hoje'), findsOneWidget);
      // Tela vazia nao ajuda: o que sobra e o que da para puxar hoje.
      expect(find.text('ABERTAS, SEM DATA'), findsOneWidget);
      expect(find.text('Pensar no nome'), findsOneWidget);
    });

    testWidgets('o contador soma o ano e mostra a sequencia', (tester) async {
      await montar(
        tester,
        _painel([_nota('A', 'texto\n')]),
        atividade: Atividade.vazia
            .somar(_hoje, palavras: 120, tarefas: 2)
            .somar(DateTime(2026, 8, 8), palavras: 30),
      );

      expect(find.textContaining('150 palavras escritas'), findsOneWidget);
      expect(find.textContaining('2 tarefas concluidas'), findsOneWidget);
      expect(find.text('2 dias seguidos'), findsOneWidget);
    });

    testWidgets('sem historico, o contador diz que nao ha nada', (
      tester,
    ) async {
      await montar(tester, _painel([_nota('A', 'texto\n')]));

      expect(find.textContaining('Nada escrito ainda'), findsOneWidget);
    });

    testWidgets('sem notas recentes, explica em vez de ficar vazio', (
      tester,
    ) async {
      await montar(tester, _painel([_nota('A', 'texto\n')]));

      expect(
        find.textContaining('Ainda nao abri nenhuma nota'),
        findsOneWidget,
      );
    });
  });
}

/// O texto do relogio que esta na tela agora.
String _relogioNaTela(WidgetTester tester) {
  final agora = DateTime.now();
  // Procura pelo formato, e nao por um horario fixo: o teste roda a qualquer
  // hora do dia.
  final alvo = RegExp(r'^\d{2}:\d{2}:\d{2}$');
  final textos = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where(alvo.hasMatch);

  expect(textos, isNotEmpty, reason: 'nenhum relogio na tela as $agora');
  return textos.first;
}

const _diasDaSemanaTeste = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sabado',
  'domingo',
];

const _mesesTeste = [
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

String _porExtenso(DateTime d) =>
    '${_diasDaSemanaTeste[d.weekday - 1]}, ${d.day} de '
    '${_mesesTeste[d.month - 1]} de ${d.year}';
