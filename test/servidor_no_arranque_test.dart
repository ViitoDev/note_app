import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/servidor/config_do_servidor.dart';
import 'package:notas_app/services/secret_store.dart';
import 'package:notas_app/ui/vault_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_email.dart';
import 'fake_vault.dart';

class _SegredosFalsos implements SecretStore {
  _SegredosFalsos([this.valores = const {}]);

  final Map<String, String> valores;

  @override
  Future<String?> read(String chave) async => valores[chave];

  @override
  Future<void> write(String chave, String valor) async {}

  @override
  Future<void> delete(String chave) async {}
}

/// Vault cuja pasta nao monta — o caso de quem guarda as notas numa unidade de
/// nuvem que nem sempre esta la.
class _VaultQueNaoMonta extends FakeVault {
  @override
  Future<String?> loadSavedVaultPath() async => null;
}

/// Vault cuja varredura estoura no meio, com a falha que a tela espera.
class _VaultQueEstoura extends FakeVault {
  @override
  Future<VaultFolder> scan(String rootId) async =>
      throw const FileSystemException('unidade nao esta pronta');
}

/// Vault que estoura com algo que a tela *nao* esperava.
///
/// E o caso que quebrava de verdade: o servidor era carregado encadeado no
/// fim da leitura do vault, entao uma falha que escapasse do `catch` daqui
/// levava o servidor junto — sem icone, sem relogio, sem recado.
class _VaultComFalhaEstranha extends FakeVault {
  @override
  Future<VaultFolder> scan(String rootId) async =>
      throw StateError('a unidade virtual respondeu besteira');
}

void main() {
  /// Como as preferencias ficam depois de o usuario configurar o servidor.
  void comServidorSalvo() {
    SharedPreferences.setMockInitialValues({
      'flutter.servidor.endereco': 'http://192.168.15.158:5005/',
      'flutter.servidor.usuario': 'vito',
    });
  }

  ServidorPrefs prefs() =>
      ServidorPrefs(segredos: _SegredosFalsos(const {'servidor': 'x'}));

  Future<void> abrir(WidgetTester tester, FakeVault vault) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VaultScreen(
          repository: vault,
          email: FakeEmail(),
          servidorPrefs: prefs(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra o servidor mesmo com a pasta do vault fora do ar', (
    tester,
  ) async {
    comServidorSalvo();

    await abrir(tester, _VaultQueNaoMonta());

    // A regressao: o servidor entrava encadeado no fim da leitura do vault, e
    // sem vault ele nunca era lido — nem icone aparecia. Quem abrisse o app
    // com a unidade desmontada nao tinha como sequer descobrir que havia um
    // servidor configurado.
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('mostra o servidor mesmo quando a varredura estoura', (
    tester,
  ) async {
    comServidorSalvo();

    await abrir(tester, _VaultQueEstoura());

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('falha inesperada do vault nao leva o servidor junto', (
    tester,
  ) async {
    comServidorSalvo();

    await abrir(tester, _VaultComFalhaEstranha());

    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    // E a falha vira recado na tela, em vez de "carregando" para sempre.
    expect(find.textContaining('Nao foi possivel ler a pasta'), findsOneWidget);
  });

  testWidgets('sem vault, a tela vazia oferece baixar do servidor', (
    tester,
  ) async {
    comServidorSalvo();

    await abrir(tester, _VaultQueNaoMonta());

    // O recado tem de falar do servidor. Pedir "a pasta de arquivos .md" para
    // quem acabou de instalar numa maquina nova e mandar a pessoa procurar
    // uma pasta que so existe do outro lado.
    expect(find.text('Escolha onde guardar as notas'), findsOneWidget);
    expect(find.textContaining('192.168.15.158'), findsOneWidget);
    expect(find.text('Escolher pasta e baixar'), findsOneWidget);
  });

  testWidgets('sem servidor, a tela vazia continua falando so da pasta', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await abrir(tester, _VaultQueNaoMonta());

    expect(find.text('Escolha a pasta do vault'), findsOneWidget);
    expect(find.text('Escolher pasta'), findsOneWidget);
  });

  testWidgets('sem servidor salvo, nao inventa icone com o vault fora', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await abrir(tester, _VaultQueNaoMonta());

    expect(find.byIcon(Icons.cloud_done_outlined), findsNothing);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('com vault e sem servidor, o icone convida a configurar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await abrir(tester, FakeVault());

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });
}
