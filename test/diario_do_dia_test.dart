import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/atividade.dart';
import 'package:notas_app/models/dashboard_data.dart';
import 'package:notas_app/models/diario_do_dia.dart';
import 'package:notas_app/models/note.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/services/dashboard_service.dart';
import 'package:notas_app/ui/dashboard_screen.dart';
import 'package:notas_app/ui/note_editor.dart';
import 'package:notas_app/ui/note_tree.dart';
import 'package:notas_app/ui/vault_screen.dart';

import 'fake_vault.dart';

/// Dia fixo: um diario de "hoje" que lesse o relogio de verdade so daria para
/// testar em algumas horas do ano.
final _hoje = DateTime(2026, 8, 9);
final _ontem = DateTime(2026, 8, 8);

Note _nota(String nome, String conteudo) =>
    Note.parse('/v/$nome.md', conteudo, name: '$nome.md');

/// Dez da manha de hoje: a hora de gravaçao padrao das notas do teste, e o
/// que faz uma nota ser do dia.
final _deHoje = _hoje.add(const Duration(hours: 10));

/// Data de gravaçao de cada nota, como a varredura do vault a entrega.
Map<String, DateTime> _gravadasHoje(List<Note> notas) => {
  for (final n in notas) n.id: _deHoje,
};

DiarioDoDia _diario(List<Note> notas, {Map<String, DateTime>? gravadas}) =>
    DiarioDoDia.build(
      notas,
      agora: _hoje,
      modificadas: gravadas ?? _gravadasHoje(notas),
    );

/// O painel inteiro, para os testes de tela: o diario nasce de dentro dele, e
/// nao ao lado.
DashboardData _painel(List<Note> notas, {Map<String, DateTime>? gravadas}) =>
    DashboardData.build(
      notas,
      agora: _hoje,
      modificadas: gravadas ?? _gravadasHoje(notas),
    );

/// Vault falso que devolve as notas passadas, com a data de gravaçao que o
/// teste escolher.
class _VaultComNotas extends FakeVault {
  _VaultComNotas(this.notas, {this.gravadas = const {}});

  final List<Note> notas;
  final Map<String, DateTime> gravadas;

  @override
  Future<VaultFolder> scan(String rootId) async => VaultFolder(
    id: rootPath,
    name: 'vault',
    children: [
      for (final n in notas)
        VaultFile(id: n.id, name: n.name, modificadoEm: gravadas[n.id]),
    ],
  );

  @override
  Future<Note> readNote(String noteId) async =>
      notas.firstWhere((n) => n.id == noteId);
}

/// Vault de uma nota so, gravada pela ultima vez ontem, que guarda o que a
/// tela escrever.
///
/// A varredura continua devolvendo a data de ontem de proposito: o app nao
/// releu o disco: quem gravou foi ele. E o caso do teste.
class _VaultDeUmaNota extends FakeVault {
  static const id = r'C:\vault\Aula de Fisica.md';

  String conteudo = '# Aula de Fisica\n';

  @override
  Future<VaultFolder> scan(String rootId) async => VaultFolder(
    id: rootPath,
    name: 'vault',
    children: [
      VaultFile(
        id: id,
        name: 'Aula de Fisica.md',
        modificadoEm: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ],
  );

  @override
  Future<Note> readNote(String noteId) async =>
      Note.parse(noteId, conteudo, name: 'Aula de Fisica.md');

  @override
  Future<void> writeNote(String noteId, String content) async {
    conteudo = content;
  }
}

void main() {
  group('quais notas sao do dia', () {
    test('nota gravada hoje entra; nota gravada ontem nao', () {
      final hoje = _nota('Calculo', '## Derivadas\n');
      final velha = _nota('Historia', '## Roma\n');

      final diario = _diario(
        [hoje, velha],
        gravadas: {
          hoje.id: _hoje.add(const Duration(hours: 9)),
          velha.id: _ontem.add(const Duration(hours: 9)),
        },
      );

      expect(diario.notas.map((n) => n.titulo), ['Calculo']);
      expect(diario.alteradas, 1);
      expect(diario.novas, 0);
    });

    test('`criado_em` de hoje marca a nota como nova', () {
      final diario = _diario([
        _nota(
          'Aula 1',
          '---\ntipo: nota\ncriado_em: 2026-08-09\n---\n\n## Limites\n',
        ),
      ]);

      final nota = diario.notas.single;
      expect(nota.nova, isTrue);
      expect(diario.novas, 1);
      expect(diario.alteradas, 0);
    });

    test('`criado_em` antigo faz da nota uma ediçao, nao uma estreia', () {
      final diario = _diario([
        _nota('Aula 1', '---\ncriado_em: 2026-07-01\n---\n\n## Limites\n'),
      ]);

      expect(diario.notas.single.nova, isFalse);
    });

    test('nota criada hoje entra mesmo sem data de gravaçao', () {
      // E o caso do vault que nao informa `stat` — e o do painel montado num
      // teste sem disco. Perder a nota do dia por causa disso seria pior que
      // mostrar ela sem a hora.
      final diario = _diario([
        _nota('Nova', '---\ncriado_em: 2026-08-09\n---\n\n## Assunto\n'),
      ], gravadas: const {});

      final nota = diario.notas.single;
      expect(nota.nova, isTrue);
      expect(nota.alteradaEm, isNull);
    });

    test('nota que nao mudou hoje nem nasceu hoje fica de fora', () {
      final diario = _diario([
        _nota('Antiga', '---\ncriado_em: 2026-01-02\n---\n\ntexto\n'),
      ], gravadas: const {});

      expect(diario.isEmpty, isTrue);
      expect(diario.manchete, 'nada hoje');
    });

    test('a mais recente vem em cima; sem hora, no fim e por titulo', () {
      final tarde = _nota('Tarde', 'texto\n');
      final manha = _nota('Manha', 'texto\n');
      final semHora = _nota('Zeta', '---\ncriado_em: 2026-08-09\n---\n\nx\n');
      final semHora2 = _nota('Alfa', '---\ncriado_em: 2026-08-09\n---\n\nx\n');

      final diario = _diario(
        [manha, semHora, tarde, semHora2],
        gravadas: {
          tarde.id: _hoje.add(const Duration(hours: 18)),
          manha.id: _hoje.add(const Duration(hours: 8)),
        },
      );

      expect(diario.notas.map((n) => n.titulo), [
        'Tarde',
        'Manha',
        'Alfa',
        'Zeta',
      ]);
    });
  });

  group('o resumo sai da nota', () {
    test('os titulos de seçao sao os assuntos', () {
      final diario = _diario([
        _nota(
          'Calculo',
          '# Calculo\n\n'
              '## Derivadas\n'
              'texto qualquer\n\n'
              '### Regra da cadeia\n'
              'mais texto\n',
        ),
      ]);

      // O `# Calculo` do topo e o nome do arquivo repetido dentro dele, e nao
      // um assunto: se aparecesse, todo resumo começaria repetindo o titulo.
      expect(diario.notas.single.topicos, ['Derivadas', 'Regra da cadeia']);
      expect(diario.notas.single.resumo, 'Derivadas  ·  Regra da cadeia');
    });

    test('sem titulo nenhum, as primeiras linhas fazem o resumo', () {
      final diario = _diario([
        _nota(
          'Ideias',
          '\n'
              '- comprar o livro de algebra\n'
              '- terminar a lista 3\n'
              '\n'
              'e revisar a prova\n',
        ),
      ]);

      expect(diario.notas.single.topicos, [
        'comprar o livro de algebra',
        'terminar a lista 3',
        'e revisar a prova',
      ]);
    });

    test('achado um titulo, o texto corrido nao entra', () {
      final diario = _diario([
        _nota('Aula', 'uma introduçao solta\n\n## Vetores\ncorpo\n'),
      ]);

      expect(diario.notas.single.topicos, ['Vetores']);
    });

    test('o que esta dentro de bloco cercado e sintaxe, nao assunto', () {
      final diario = _diario([
        _nota(
          'Codigo',
          '## Exemplo\n'
              '```dart\n'
              '# isto e comentario, nao titulo\n'
              '```\n'
              '## Resultado\n',
        ),
      ]);

      expect(diario.notas.single.topicos, ['Exemplo', 'Resultado']);
    });

    test('o topico chega limpo da marcaçao do Markdown', () {
      final diario = _diario([
        _nota(
          'Notas',
          '## **Derivada** de `x^2` ##\n'
              '## Ver [[Algebra|a nota de algebra]]\n'
              '## O [manual](https://exemplo.com) da materia\n',
        ),
      ]);

      expect(diario.notas.single.topicos, [
        'Derivada de x^2',
        'Ver a nota de algebra',
        'O manual da materia',
      ]);
    });

    test('regua, linha de tabela e HTML nao valem como assunto', () {
      final diario = _diario([
        _nota(
          'Tabela',
          '---\n'
              '| a | b |\n'
              '|---|---|\n'
              '<br>\n'
              'o que sobrou de texto\n',
        ),
      ]);

      expect(diario.notas.single.topicos, ['o que sobrou de texto']);
    });

    test('o resumo tem teto, e o topico longo e cortado', () {
      final diario = _diario([
        _nota(
          'Longa',
          [
            for (var i = 1; i <= 9; i++) '## Seçao $i',
            '## ${'a' * 200}',
          ].join('\n'),
        ),
      ]);

      final topicos = diario.notas.single.topicos;
      expect(topicos, hasLength(6));
      expect(topicos.first, 'Seçao 1');
      expect(topicos.every((t) => t.length <= 91), isTrue);
    });

    test('a caixa marcada e o que foi riscado; a vazia fica pendente', () {
      final diario = _diario([
        _nota(
          'Lista',
          '## Estudo\n'
              '- [x] 📅2026-08-09 refazer a lista 3\n'
              '- [x] ler o capitulo 4\n'
              '- [ ] resolver os exercicios\n'
              '- [ ] revisar\n',
        ),
      ]);

      final nota = diario.notas.single;
      // A data vira etiqueta em outros cantos do painel; dentro do resumo ela
      // so tomaria espaço do texto da tarefa.
      expect(nota.feitas, ['refazer a lista 3', 'ler o capitulo 4']);
      expect(nota.abertas, 2);
      expect(diario.tarefasFeitas, 2);
    });

    test('nota que nao tem assunto nenhum se resume pelo tamanho', () {
      // So marcaçao: nada ali serve de titulo nem de frase, e o tamanho e a
      // unica coisa verdadeira que sobra para dizer.
      final diario = _diario([_nota('Solta', '| a | b |\n<br>\n')]);

      final nota = diario.notas.single;
      expect(nota.topicos, isEmpty);
      expect(nota.resumo, contains('${nota.palavras} palavras'));
    });

    test('so tarefas riscadas, sem seçao: o resumo e o que foi fechado', () {
      // A linha da tarefa nao vira assunto tambem: se virasse, o resumo
      // aberto mostraria a mesma frase duas vezes, com bolinha e com tique.
      final diario = _diario([_nota('Feitas', '- [x] entregar o relatorio\n')]);

      final nota = diario.notas.single;
      expect(nota.topicos, isEmpty);
      expect(nota.resumo, 'Fechou: entregar o relatorio');
    });

    test('so tarefas em aberto: o resumo diz que nada foi riscado', () {
      final diario = _diario([_nota('Aberta', '- [ ] entregar\n- [ ] ler\n')]);

      expect(
        diario.notas.single.resumo,
        '2 tarefas em aberto, nada riscado ainda.',
      );
    });

    test('as tags do dia vem da mais usada para a menos', () {
      final diario = _diario([
        _nota('A', '---\ntags: [estudo, calculo]\n---\n\n## Um\n'),
        _nota('B', '---\ntags: [estudo]\n---\n\n## Dois\n'),
      ]);

      expect(diario.assuntos, ['estudo', 'calculo']);
    });

    test('a manchete conta as novas e as alteradas', () {
      final nova = _nota('Nova', '---\ncriado_em: 2026-08-09\n---\n\n## X\n');
      final velha = _nota('Velha', '## Y\n');

      final diario = _diario(
        [nova, velha],
        gravadas: {
          nova.id: _hoje.add(const Duration(hours: 9)),
          velha.id: _hoje.add(const Duration(hours: 8)),
        },
      );

      expect(diario.manchete, '2 notas  ·  1 nova e 1 alterada');
    });
  });

  group('o diario no painel', () {
    test('o painel monta o diario junto com o resto, numa passada so', () {
      final dados = DashboardData.build(
        [_nota('Aula', '## Integrais\n')],
        agora: _hoje,
        modificadas: {'/v/Aula.md': _hoje.add(const Duration(hours: 15))},
      );

      expect(dados.diario.notas.single.topicos, ['Integrais']);
    });

    test('sem as datas de gravaçao o diario nao inventa notas', () {
      final dados = DashboardData.build([
        _nota('Aula', '## Integrais\n'),
      ], agora: _hoje);

      expect(dados.diario.isEmpty, isTrue);
    });

    test('o serviço leva ao diario a data que a varredura leu', () async {
      final nota = _nota('Aula', '## Integrais\n');
      final vault = _VaultComNotas(
        [nota],
        gravadas: {nota.id: _hoje.add(const Duration(hours: 11))},
      );

      final dados = await DashboardService(
        vault,
      ).build(await vault.scan(vault.rootPath), agora: _hoje);

      expect(dados.diario.notas.single.titulo, 'Aula');
      expect(
        dados.diario.notas.single.alteradaEm,
        _hoje.add(const Duration(hours: 11)),
      );
    });
  });

  group('cartao do dia na tela', () {
    Future<List<String>> montar(
      WidgetTester tester,
      DashboardData dados,
    ) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final abertos = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardScreen(
              dados: dados,
              atividade: Atividade.vazia,
              recentes: const [],
              onOpenNote: abertos.add,
              onAlternarTarefa: (_, _) {},
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

    testWidgets('o cartao lista a nota do dia com o resumo aberto', (
      tester,
    ) async {
      await montar(
        tester,
        _painel([
          _nota(
            'Calculo 2',
            '---\ntags: [estudo]\ncriado_em: 2026-08-09\n---\n\n'
                '## Integrais por partes\n'
                '- [x] refazer a lista 3\n'
                // Com prazo la na frente: sem data, a tarefa aberta cairia
                // tambem no cartao de hoje, e o titulo da nota apareceria duas
                // vezes na tela.
                '- [ ] 📅2026-08-20 entregar o relatorio\n',
          ),
        ]),
      );

      expect(find.text('O que fiz hoje'), findsOneWidget);
      expect(find.text('1 nota  ·  1 nova'), findsOneWidget);
      expect(find.text('Calculo 2'), findsOneWidget);

      // Nova de hoje, e a hora da gravaçao ao lado.
      expect(find.text('nova'), findsOneWidget);
      expect(find.text('10:00'), findsOneWidget);

      // O resumo vem aberto num dia de uma nota so.
      expect(find.text('Integrais por partes'), findsOneWidget);
      expect(find.text('refazer a lista 3'), findsOneWidget);
      expect(find.textContaining('1 tarefa em aberto'), findsOneWidget);
      expect(find.text('#estudo'), findsOneWidget);
    });

    testWidgets('tocar no titulo abre a nota', (tester) async {
      final abertos = await montar(
        tester,
        _painel([_nota('Calculo 2', '## Integrais\n')]),
      );

      await tester.tap(find.text('Calculo 2'));
      await tester.pump();

      expect(abertos, ['/v/Calculo 2.md']);
    });

    testWidgets('dia cheio nasce fechado, e o chevron abre a nota escolhida', (
      tester,
    ) async {
      await montar(
        tester,
        _painel([
          for (var i = 1; i <= 4; i++)
            _nota('Nota $i', '## Assunto $i\ntexto\n'),
        ]),
      );

      // Quatro notas: mostrar quatro resumos abertos empurraria o contador
      // para fora da tela, entao cada uma fica na sua linha de resumo.
      expect(find.text('4 notas  ·  4 alteradas'), findsOneWidget);
      expect(find.text('Assunto 1'), findsOneWidget);
      expect(find.textContaining('palavras na nota'), findsNothing);

      await tester.tap(find.byTooltip('Ver o resumo').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('palavras na nota'), findsOneWidget);
    });

    testWidgets('dia sem nota escrita ensina como o cartao se enche', (
      tester,
    ) async {
      await montar(tester, _painel(const []));

      expect(find.text('O que fiz hoje'), findsOneWidget);
      expect(find.textContaining('Nenhuma nota gravada hoje'), findsOneWidget);
    });
  });

  group('a nota gravada agora entra no dia', () {
    test('a arvore aprende a hora da gravaçao sem uma varredura nova', () {
      final antes = DateTime(2026, 8, 8, 9);
      final arvore = VaultFolder(
        id: r'C:\vault',
        name: 'vault',
        children: [
          VaultFolder(
            id: r'C:\vault\Estudos',
            name: 'Estudos',
            children: [
              VaultFile(
                id: r'C:\vault\Estudos\Aula.md',
                name: 'Aula.md',
                modificadoEm: antes,
              ),
            ],
          ),
          VaultFile(
            id: r'C:\vault\Solta.md',
            name: 'Solta.md',
            modificadoEm: antes,
          ),
        ],
      );

      final depois = arvore.comGravacao(r'C:\vault\Estudos\Aula.md', _deHoje);

      final pasta = depois.children.first as VaultFolder;
      expect((pasta.children.single as VaultFile).modificadoEm, _deHoje);
      // O galho que nao foi tocado continua sendo o mesmo objeto: gravar uma
      // nota nao pode custar uma copia do vault inteiro.
      expect(depois.children.last, same(arvore.children.last));
    });

    test('gravaçao de nota que nao esta na arvore nao mexe em nada', () {
      final arvore = VaultFolder(
        id: r'C:\vault',
        name: 'vault',
        children: [VaultFile(id: r'C:\vault\Solta.md', name: 'Solta.md')],
      );

      expect(arvore.comGravacao(r'C:\vault\Outra.md', _deHoje), same(arvore));
    });

    testWidgets('escrever numa nota velha ja aparece no painel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final vault = _VaultDeUmaNota();
      await tester.pumpWidget(
        MaterialApp(home: VaultScreen(repository: vault)),
      );
      await tester.pumpAndSettle();

      // A nota foi gravada ontem: o dia começa vazio.
      expect(find.textContaining('Nenhuma nota gravada hoje'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('rail-item-notas')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NoteTree),
          matching: find.text('Aula de Fisica'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(NoteEditor),
          matching: find.byType(TextField),
        ),
        '## Integrais por partes\n',
      );
      // A gravaçao automatica espera a pausa de quem digita.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('rail-item-dashboard')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nenhuma nota gravada hoje'), findsNothing);
      expect(find.text('1 nota  ·  1 alterada'), findsOneWidget);
      expect(find.text('Integrais por partes'), findsOneWidget);
    });
  });
}
