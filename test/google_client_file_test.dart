import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/services/google_client_file.dart';
import 'package:notas_app/ui/google_login_dialog.dart';
import 'package:path/path.dart' as p;

/// Leitor apontado para uma pasta de teste, em vez do Downloads da maquina.
class _LeitorFalso extends GoogleClientFile {
  const _LeitorFalso(this._pasta);

  final Directory _pasta;

  @override
  List<Directory> get pastas => [_pasta];
}

File _escrever(Directory dir, String nome, Object json) =>
    File(p.join(dir.path, nome))..writeAsStringSync(jsonEncode(json));

Object _credencialValida({
  String id = '000-abc.apps.googleusercontent.com',
  String segredo = 'GOCSPX-segredo',
}) => {
  'installed': {
    'client_id': id,
    'project_id': 'meu-projeto',
    'client_secret': segredo,
    'redirect_uris': ['http://localhost'],
  },
};

void main() {
  late Directory pasta;

  setUp(() => pasta = Directory.systemTemp.createTempSync('google_json_'));
  tearDown(() => pasta.deleteSync(recursive: true));

  group('ler o JSON baixado', () {
    test('extrai id e chave de um cliente de computador', () async {
      _escrever(pasta, 'client_secret_123.json', _credencialValida());

      final cred = await _LeitorFalso(pasta).procurar();

      expect(cred.clientId, '000-abc.apps.googleusercontent.com');
      expect(cred.clientSecret, 'GOCSPX-segredo');
      expect(cred.arquivo, 'client_secret_123.json');
    });

    test('pega o mais recente quando ha mais de um', () async {
      _escrever(
        pasta,
        'client_secret_velho.json',
        _credencialValida(id: 'velho.apps.googleusercontent.com'),
      );
      // Quem baixou duas vezes quer a ultima.
      final novo = _escrever(
        pasta,
        'client_secret_novo.json',
        _credencialValida(id: 'novo.apps.googleusercontent.com'),
      );
      novo.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));

      final cred = await _LeitorFalso(pasta).procurar();

      expect(cred.clientId, 'novo.apps.googleusercontent.com');
    });

    test('ignora arquivo com outro nome', () async {
      // A busca varre uma pasta inteira do usuario; ela nao tem por que
      // enxergar nada alem do arquivo que foi mandada procurar.
      _escrever(pasta, 'anotacoes.json', _credencialValida());

      expect(
        () => _LeitorFalso(pasta).procurar(),
        throwsA(
          isA<CredencialException>().having(
            (e) => e.falha,
            'falha',
            FalhaCredencial.nenhum,
          ),
        ),
      );
    });

    test('cliente do tipo web e recusado com o motivo certo', () async {
      _escrever(pasta, 'client_secret_web.json', {
        'web': {'client_id': 'x', 'client_secret': 'y'},
      });

      expect(
        () => _LeitorFalso(pasta).procurar(),
        throwsA(
          isA<CredencialException>().having(
            (e) => e.falha,
            'falha',
            FalhaCredencial.tipoErrado,
          ),
        ),
      );
    });

    test('JSON quebrado nao derruba a tela', () async {
      File(
        p.join(pasta.path, 'client_secret_x.json'),
      ).writeAsStringSync('{isso nao e json');

      expect(
        () => _LeitorFalso(pasta).procurar(),
        throwsA(isA<CredencialException>()),
      );
    });

    test('pasta vazia avisa que nao achou', () async {
      expect(
        () => _LeitorFalso(pasta).procurar(),
        throwsA(
          isA<CredencialException>().having(
            (e) => e.falha,
            'falha',
            FalhaCredencial.nenhum,
          ),
        ),
      );
    });
  });

  group('tela de cadastro', () {
    Future<void> abrir(WidgetTester tester, Directory dir) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showGoogleSetupDialog(context, arquivos: _LeitorFalso(dir)),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('o botao preenche os dois campos a partir do arquivo', (
      tester,
    ) async {
      _escrever(pasta, 'client_secret_abc.json', _credencialValida());
      await abrir(tester, pasta);

      await tester.tap(find.text('Ler o JSON baixado'));
      await tester.pumpAndSettle();

      // Nenhuma string opaca copiada a mao de uma pagina para outra.
      expect(find.text('000-abc.apps.googleusercontent.com'), findsOneWidget);
      expect(find.text('GOCSPX-segredo'), findsOneWidget);
      expect(
        find.textContaining('Lido de client_secret_abc.json'),
        findsOneWidget,
      );
    });

    testWidgets('sem arquivo, avisa em vez de falhar calado', (tester) async {
      await abrir(tester, pasta);

      await tester.tap(find.text('Ler o JSON baixado'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nao achei nenhum arquivo'), findsOneWidget);
    });

    testWidgets('cada passo tem um botao que abre a pagina dele', (
      tester,
    ) async {
      await abrir(tester, pasta);

      // Quatro dos cinco passos apontam para uma pagina do Google Cloud; o
      // ultimo e aqui dentro mesmo.
      expect(
        find.byTooltip('Abrir esta pagina no navegador'),
        findsNWidgets(4),
      );
    });
  });
}
