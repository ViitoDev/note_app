import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de interface: tamanhos de painel, paineis ocultos e afins.
///
/// Ficam em memoria para a interface conseguir ler de forma sincrona no
/// primeiro frame. Ler direto das preferencias dentro de cada widget obrigaria
/// a esperar um future, e a tela apareceria no estado errado antes de corrigir.
abstract final class UiPrefs {
  static const _prefix = 'ui.';
  static final Map<String, Object> _cache = {};

  /// Carrega tudo antes do `runApp`. Falhar aqui nao impede o app de abrir —
  /// a interface so volta aos padroes.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final value = prefs.get(key);
        if (value != null) _cache[key.substring(_prefix.length)] = value;
      }
    } on Object {
      _cache.clear();
    }
  }

  /// Zera o cache entre testes. Sem isso o estado de um teste vaza para o
  /// seguinte, ja que este cache e estatico e vive o processo inteiro.
  @visibleForTesting
  static void resetForTesting() => _cache.clear();

  static double? readDouble(String key) {
    final value = _cache[key];
    return value is double ? value : null;
  }

  static bool? readBool(String key) {
    final value = _cache[key];
    return value is bool ? value : null;
  }

  static String? readString(String key) {
    final value = _cache[key];
    return value is String ? value : null;
  }

  static void writeDouble(String key, double value) {
    _cache[key] = value;
    _persist((prefs) => prefs.setDouble('$_prefix$key', value));
  }

  static void writeBool(String key, {required bool value}) {
    _cache[key] = value;
    _persist((prefs) => prefs.setBool('$_prefix$key', value));
  }

  static void writeString(String key, String value) {
    _cache[key] = value;
    _persist((prefs) => prefs.setString('$_prefix$key', value));
  }

  static Future<void> _persist(
    Future<bool> Function(SharedPreferences) write,
  ) async {
    try {
      await write(await SharedPreferences.getInstance());
    } on Object {
      // Nao conseguir gravar a preferencia nao pode quebrar a interacao.
    }
  }
}
