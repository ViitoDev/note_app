import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32/win32.dart';

/// Guarda segredos — hoje, a senha de app do e-mail.
///
/// O texto e cifrado pelo DPAPI do Windows antes de encostar no disco, e so
/// depois vai para as preferencias. O DPAPI amarra a chave a conta do Windows:
/// o arquivo copiado para outra maquina, ou lido por outro usuario, nao abre.
///
/// O caminho obvio seria o `flutter_secure_storage`, mas o plugin dele so
/// compila com a ATL do Visual Studio instalada — um componente extra, com
/// download grande e privilegio de administrador. Chamar o DPAPI direto por FFI
/// entrega a mesma proteçao (e a mesma API do Windows que o plugin usaria) sem
/// exigir nada da maquina.
class SecretStore {
  const SecretStore();

  static const _prefixo = 'secret.';

  Future<String?> read(String chave) async {
    if (Platform.isLinux) return _Chaveiro.ler(chave);

    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString('$_prefixo$chave');
    if (guardado == null) return null;

    try {
      return _decifrar(base64Decode(guardado));
    } on FormatException {
      // Valor corrompido, ou cifrado por outra conta do Windows. Tratar como
      // "nao ha senha" leva o usuario de volta ao formulario, que e o unico
      // desfecho util aqui.
      return null;
    }
  }

  Future<void> write(String chave, String valor) async {
    if (Platform.isLinux) return _Chaveiro.gravar(chave, valor);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixo$chave', base64Encode(_cifrar(valor)));
  }

  Future<void> delete(String chave) async {
    if (Platform.isLinux) return _Chaveiro.apagar(chave);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefixo$chave');
  }

  // ------------------------------------------------------------------ DPAPI

  /// Fora do Windows nao ha DPAPI. No Linux o segredo vai para o chaveiro do
  /// sistema ([_Chaveiro]); em qualquer outro lugar, guardar em texto puro
  /// seria pior do que falhar.
  static bool get _temDpapi => Platform.isWindows;

  static Uint8List _cifrar(String valor) {
    if (!_temDpapi) throw UnsupportedError('Sem DPAPI fora do Windows');
    return _chamar(Uint8List.fromList(utf8.encode(valor)), proteger: true);
  }

  static String _decifrar(Uint8List bytes) {
    if (!_temDpapi) throw UnsupportedError('Sem DPAPI fora do Windows');
    return utf8.decode(_chamar(bytes, proteger: false));
  }

  /// Ponte para `CryptProtectData` / `CryptUnprotectData`.
  ///
  /// As duas tem a mesma forma — blob entra, blob sai — entao vale uma funçao
  /// so: e neste vaivem de ponteiros que mora o risco de vazar memoria, e
  /// escrever isso duas vezes seria escrever dois lugares para errar.
  static Uint8List _chamar(Uint8List entrada, {required bool proteger}) {
    final buffer = calloc<Uint8>(entrada.length);
    final blobIn = calloc<CRYPT_INTEGER_BLOB>();
    final blobOut = calloc<CRYPT_INTEGER_BLOB>();

    try {
      buffer.asTypedList(entrada.length).setAll(0, entrada);
      blobIn.ref
        ..cbData = entrada.length
        ..pbData = buffer;

      final ok = proteger
          ? CryptProtectData(blobIn, null, null, null, 0, blobOut).value
          : CryptUnprotectData(blobIn, null, null, null, 0, blobOut).value;

      if (!ok) throw const FormatException('DPAPI recusou o valor');

      // Copia antes de liberar: `pbData` pertence ao Windows, e `asTypedList`
      // so aponta para ele. Devolver a view daria uma lista que vira lixo no
      // LocalFree logo abaixo.
      return Uint8List.fromList(
        blobOut.ref.pbData.asTypedList(blobOut.ref.cbData),
      );
    } finally {
      // O buffer de saida foi alocado pelo Windows com LocalAlloc, entao quem
      // devolve e o LocalFree — nao o calloc que cuida do resto daqui.
      if (blobOut.ref.pbData != nullptr) {
        LocalFree(HLOCAL(blobOut.ref.pbData));
      }
      calloc
        ..free(buffer)
        ..free(blobIn)
        ..free(blobOut);
    }
  }
}

/// O equivalente do DPAPI no Linux: o chaveiro do sistema (gnome-keyring,
/// KWallet), falado pelo `secret-tool` da libsecret.
///
/// O segredo inteiro vive no chaveiro, nao nas preferencias. Como o DPAPI, a
/// chave fica amarrada a sessao do usuario, e o arquivo de preferencias
/// copiado para outra maquina nao carrega senha nenhuma.
abstract final class _Chaveiro {
  static const _app = 'notas_app';

  static List<String> _atributos(String chave) => ['app', _app, 'chave', chave];

  static Future<String?> ler(String chave) async {
    final r = await Process.run('secret-tool', [
      'lookup',
      ..._atributos(chave),
    ]);
    // Codigo de saida diferente de zero e "nao ha esse segredo" — ou chaveiro
    // trancado. Nos dois casos o formulario volta vazio, como no Windows.
    if (r.exitCode != 0) return null;
    final valor = r.stdout as String;
    return valor.isEmpty ? null : valor;
  }

  static Future<void> gravar(String chave, String valor) async {
    final processo = await Process.start('secret-tool', [
      'store',
      '--label=Notas: $chave',
      ..._atributos(chave),
    ]);
    // A senha entra pelo stdin: na linha de comando ela apareceria para
    // qualquer processo que listasse os outros.
    processo.stdin.write(valor);
    await processo.stdin.close();
    final erro = await processo.stderr.transform(utf8.decoder).join();
    if (await processo.exitCode != 0) {
      throw FileSystemException('O chaveiro recusou o segredo: ${erro.trim()}');
    }
  }

  static Future<void> apagar(String chave) async {
    await Process.run('secret-tool', ['clear', ..._atributos(chave)]);
  }
}
