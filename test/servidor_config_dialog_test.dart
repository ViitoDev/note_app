import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/servidor/config_do_servidor.dart';
import 'package:notas_app/services/secret_store.dart';
import 'package:notas_app/ui/app_theme.dart';
import 'package:notas_app/ui/servidor_config_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SegredosFalsos implements SecretStore {
  final valores = <String, String>{};

  @override
  Future<String?> read(String chave) async => valores[chave];

  @override
  Future<void> write(String chave, String valor) async =>
      valores[chave] = valor;

  @override
  Future<void> delete(String chave) async => valores.remove(chave);
}

void main() {
  late ServidorPrefs prefs;
  ConfigDoServidor? devolvido;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = ServidorPrefs(segredos: _SegredosFalsos());
    devolvido = null;
  });

  /// Abre o dialogo de verdade, com o tema de producao.
  Future<void> abrir(
    WidgetTester tester, {
    ConfigDoServidor atual = ConfigDoServidor.vazia,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  devolvido = await showServidorConfigDialog(
                    context,
                    atual: atual,
                    prefs: prefs,
                  );
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('desenha os tres campos sem estourar na construcao', (
    tester,
  ) async {
    await abrir(tester);

    // O teste que faltava. Um `Spacer` dentro de `AlertDialog.actions` — que e
    // um `OverflowBar`, nao um Flex — passa pelo analisador e so quebra na
    // hora de desenhar. Em release nem tela vermelha aparece: o dialogo fica
    // um retangulo cinza, e o usuario nao tem como adivinhar o motivo.
    expect(tester.takeException(), isNull);

    expect(find.text('Servidor do vault'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Endereco'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Usuario'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Senha'), findsOneWidget);
    expect(find.text('Testar'), findsOneWidget);
    expect(find.text('Salvar'), findsOneWidget);
  });

  testWidgets('so oferece Desligar quando ja ha um servidor', (tester) async {
    await abrir(tester);
    expect(find.text('Desligar'), findsNothing);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await abrir(
      tester,
      atual: const ConfigDoServidor(
        endereco: 'http://192.168.15.158:5005/',
        usuario: 'vito',
        senha: 'x',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Desligar'), findsOneWidget);
  });

  testWidgets('reabre ja preenchido com o que estava salvo', (tester) async {
    await abrir(
      tester,
      atual: const ConfigDoServidor(
        endereco: 'http://192.168.15.158:5005/',
        usuario: 'vito',
        senha: 'segredo',
      ),
    );

    expect(find.text('http://192.168.15.158:5005/'), findsOneWidget);
    expect(find.text('vito'), findsOneWidget);
  });

  testWidgets('recusa salvar endereco que nao da para usar', (tester) async {
    await abrir(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Endereco'),
      'ftp://casa/',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Usuario'),
      'vito',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), 'x');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Endereco invalido'), findsOneWidget);
    // O dialogo continua aberto: salvar o que nao funciona seria pior do que
    // nao salvar.
    expect(find.text('Servidor do vault'), findsOneWidget);
  });

  testWidgets('salva o que foi digitado e devolve para a tela', (tester) async {
    await abrir(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Endereco'),
      'http://192.168.15.158:5005/',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Usuario'),
      'vito',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      '04082005a',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Servidor do vault'), findsNothing);
    expect(devolvido?.usuario, 'vito');
    expect(devolvido?.uri, Uri.parse('http://192.168.15.158:5005/'));

    // E ficou guardado, senao a proxima abertura do app nasceria sem servidor.
    expect((await prefs.carregar()).senha, '04082005a');
  });

  testWidgets('a senha nasce oculta e o olho revela', (tester) async {
    await abrir(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Senha'),
      'segredo',
    );
    await tester.pump();

    EditableText campoDaSenha() => tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Senha'),
        matching: find.byType(EditableText),
      ),
    );

    expect(campoDaSenha().obscureText, isTrue);

    await tester.tap(find.byTooltip('Mostrar'));
    await tester.pumpAndSettle();

    expect(campoDaSenha().obscureText, isFalse);
  });
}
