import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/servidor/config_do_servidor.dart';
import 'package:notas_app/services/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda os segredos num mapa.
///
/// O [SecretStore] de verdade chama o DPAPI do Windows, que amarra o valor a
/// conta que cifrou — util em producao, inutil num teste que precisa so saber
/// se a senha foi parar no cofre em vez das preferencias.
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

ConfigDoServidor _com(String endereco) =>
    ConfigDoServidor(endereco: endereco, usuario: 'u', senha: 's');

void main() {
  group('endereco', () {
    test('completa com http quando o esquema falta', () {
      expect(
        _com('192.168.0.10:5005').uri,
        Uri.parse('http://192.168.0.10:5005'),
      );
    });

    test('preserva https e o caminho', () {
      expect(
        _com('https://notas.casa/vault/').uri,
        Uri.parse('https://notas.casa/vault/'),
      );
    });

    test('aceita IPv6 entre colchetes, com porta', () {
      final uri = _com('[2804:7f0:90c1:f098::e044]:5005').uri!;

      expect(uri.host, '2804:7f0:90c1:f098::e044');
      expect(uri.port, 5005);
    });

    test('poe os colchetes num IPv6 colado sem eles', () {
      // E o formato que se tem a mao: o endereco do `ssh`, o que o roteador
      // mostra. Sem esta gentileza a tela so diria "endereco invalido".
      final uri = _com('2804:7f0:90c1:f098:36e6:d7ff:fefb:e044').uri!;

      expect(uri.host, '2804:7f0:90c1:f098:36e6:d7ff:fefb:e044');
      expect(uri.scheme, 'http');
    });

    test('nao confunde host:porta com IPv6', () {
      expect(_com('casa:5005').uri!.host, 'casa');
      expect(_com('casa:5005').uri!.port, 5005);
    });

    test('recusa o que nao da para usar', () {
      expect(_com('').uri, isNull);
      expect(_com('   ').uri, isNull);
      expect(_com('ftp://casa/').uri, isNull);
      expect(_com('http://').uri, isNull);
    });

    test('so esta configurado quando o endereco serve', () {
      expect(ConfigDoServidor.vazia.configurado, isFalse);
      expect(_com('casa:5005').configurado, isTrue);
    });
  });

  group('persistencia', () {
    late _SegredosFalsos segredos;
    late ServidorPrefs prefs;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      segredos = _SegredosFalsos();
      prefs = ServidorPrefs(segredos: segredos);
    });

    test('devolve o que foi salvo', () async {
      await prefs.salvar(
        const ConfigDoServidor(
          endereco: 'http://casa:5005/',
          usuario: 'notas',
          senha: 'abc123',
        ),
      );

      final lido = await prefs.carregar();

      expect(lido.endereco, 'http://casa:5005/');
      expect(lido.usuario, 'notas');
      expect(lido.senha, 'abc123');
    });

    test('a senha vai para o cofre, nunca para as preferencias', () async {
      await prefs.salvar(
        const ConfigDoServidor(
          endereco: 'http://casa:5005/',
          usuario: 'notas',
          senha: 'abc123',
        ),
      );

      final guardadas = await SharedPreferences.getInstance();
      expect(guardadas.getKeys().map(guardadas.get), isNot(contains('abc123')));
      expect(segredos.valores.values, contains('abc123'));
    });

    test('sem nada salvo devolve vazia', () async {
      expect(await prefs.carregar(), ConfigDoServidor.vazia);
    });

    test('senha ilegivel devolve o resto, para a tela poder abrir', () async {
      await prefs.salvar(
        const ConfigDoServidor(
          endereco: 'http://casa:5005/',
          usuario: 'notas',
          senha: 'abc123',
        ),
      );
      // Foi o que sobrou de um perfil do Windows trocado: o cofre nao abre.
      segredos.valores.clear();

      final lido = await prefs.carregar();

      expect(lido.usuario, 'notas');
      expect(lido.senha, isEmpty);
    });

    test('limpar tira o endereco e a senha', () async {
      await prefs.salvar(
        const ConfigDoServidor(
          endereco: 'http://casa:5005/',
          usuario: 'notas',
          senha: 'abc123',
        ),
      );

      await prefs.limpar();

      expect(await prefs.carregar(), ConfigDoServidor.vazia);
      expect(segredos.valores, isEmpty);
    });
  });
}
