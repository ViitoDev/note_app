import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/secret_store.dart';

/// Endereco e credenciais do servidor privado que guarda o vault.
@immutable
class ConfigDoServidor {
  const ConfigDoServidor({
    required this.endereco,
    required this.usuario,
    required this.senha,
  });

  static const vazia = ConfigDoServidor(endereco: '', usuario: '', senha: '');

  /// Como o usuario digitou: `http://192.168.0.10:5005/`.
  final String endereco;
  final String usuario;
  final String senha;

  bool get configurado => uri != null;

  /// O endereco como URL utilizavel, ou nulo se o que foi digitado nao serve.
  ///
  /// Sem esquema o `Uri.parse` aceita "192.168.0.10:5005" como se `192.168.0.10`
  /// fosse o esquema — um erro que nao aparece ate a primeira chamada falhar
  /// sem explicacao. Completar com `http://` e mais util do que recusar.
  Uri? get uri {
    final texto = endereco.trim();
    if (texto.isEmpty) return null;

    final comEsquema = texto.contains('://') ? texto : 'http://$texto';
    final uri = Uri.tryParse(_colchetesNoIpv6(comEsquema));
    if (uri == null) return null;
    if (uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  /// Poe colchetes num IPv6 digitado sem eles.
  ///
  /// `Uri.parse` exige `http://[2804::1]:5005`, mas o endereco que a pessoa
  /// tem a mao — o do `ssh`, o que o roteador mostra — vem sem colchetes, e
  /// sem eles o parse devolve nulo e a tela so diz "endereco invalido".
  ///
  /// Sem colchetes nao da para separar o endereco da porta: em
  /// `2804:7f0::1:5005` o ultimo grupo tanto pode ser porta quanto parte do
  /// endereco. Entao a autoridade inteira vira o host, e quem precisa de porta
  /// escreve os colchetes — que e justamente o que a dica do campo pede.
  static String _colchetesNoIpv6(String url) {
    final corte = url.indexOf('://') + 3;
    final fim = url.indexOf('/', corte);
    final autoridade = fim < 0
        ? url.substring(corte)
        : url.substring(corte, fim);
    final resto = fim < 0 ? '' : url.substring(fim);

    if (autoridade.contains('[')) return url;
    // Dois pontos ou mais so acontece em IPv6: `casa:5005` tem um.
    if (':'.allMatches(autoridade).length < 2) return url;

    return '${url.substring(0, corte)}[$autoridade]$resto';
  }

  ConfigDoServidor copyWith({
    String? endereco,
    String? usuario,
    String? senha,
  }) => ConfigDoServidor(
    endereco: endereco ?? this.endereco,
    usuario: usuario ?? this.usuario,
    senha: senha ?? this.senha,
  );

  @override
  bool operator ==(Object other) =>
      other is ConfigDoServidor &&
      other.endereco == endereco &&
      other.usuario == usuario &&
      other.senha == senha;

  @override
  int get hashCode => Object.hash(endereco, usuario, senha);
}

/// Guarda a configuracao do servidor entre execucoes.
///
/// Endereco e usuario vao para as preferencias; a senha vai para o
/// [SecretStore], cifrada pelo DPAPI do Windows. Sao caminhos diferentes de
/// proposito: o arquivo de preferencias e texto puro, e uma senha de servidor
/// la dentro seria uma senha publicada para qualquer processo do usuario.
class ServidorPrefs {
  const ServidorPrefs({this.segredos = const SecretStore()});

  final SecretStore segredos;

  static const _chaveEndereco = 'servidor.endereco';
  static const _chaveUsuario = 'servidor.usuario';
  static const _chaveSenha = 'servidor';

  Future<ConfigDoServidor> carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final endereco = prefs.getString(_chaveEndereco) ?? '';
    if (endereco.isEmpty) return ConfigDoServidor.vazia;

    return ConfigDoServidor(
      endereco: endereco,
      usuario: prefs.getString(_chaveUsuario) ?? '',
      // Senha ilegivel — perfil do Windows trocado, valor corrompido — nao
      // pode impedir a tela de abrir. O campo volta vazio e o usuario digita
      // de novo, que e o unico desfecho util.
      senha: await segredos.read(_chaveSenha) ?? '',
    );
  }

  Future<void> salvar(ConfigDoServidor config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chaveEndereco, config.endereco.trim());
    await prefs.setString(_chaveUsuario, config.usuario.trim());
    if (config.senha.isEmpty) {
      await segredos.delete(_chaveSenha);
    } else {
      await segredos.write(_chaveSenha, config.senha);
    }
  }

  Future<void> limpar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chaveEndereco);
    await prefs.remove(_chaveUsuario);
    await segredos.delete(_chaveSenha);
  }
}
