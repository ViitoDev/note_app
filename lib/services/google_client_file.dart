import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// As credenciais lidas do arquivo que o Google Cloud oferece para baixar.
@immutable
class CredencialBaixada {
  const CredencialBaixada({
    required this.clientId,
    required this.clientSecret,
    required this.arquivo,
  });

  final String clientId;
  final String clientSecret;

  /// De onde veio, para a tela poder dizer qual arquivo usou.
  final String arquivo;
}

/// Por que um arquivo encontrado nao serve.
enum FalhaCredencial {
  nenhum('Nao achei nenhum arquivo client_secret*.json em Downloads.'),
  tipoErrado(
    'Este arquivo e de um cliente do tipo "Aplicativo da Web". Crie a '
    'credencial de novo escolhendo "Aplicativo para computador".',
  ),
  ilegivel('O arquivo existe mas nao deu para ler.');

  const FalhaCredencial(this.mensagem);

  final String mensagem;
}

class CredencialException implements Exception {
  const CredencialException(this.falha);

  final FalhaCredencial falha;

  @override
  String toString() => falha.mensagem;
}

/// Le o `client_secret_*.json` que o Google Cloud entrega ao criar a credencial.
///
/// Existe para o usuario nao precisar copiar duas strings opacas de uma pagina
/// para outra. Ele clica em "Fazer download do JSON" no navegador e o app pega
/// dali — menos passos, e nenhum lugar para colar no campo errado.
class GoogleClientFile {
  const GoogleClientFile();

  /// So arquivos com este formato de nome sao considerados.
  ///
  /// O recorte e proposital: a busca olha uma pasta inteira do usuario, e nao
  /// tem por que enxergar nada alem do arquivo que ela foi mandada procurar.
  static final _nome = RegExp(r'^client_secret.*\.json$', caseSensitive: false);

  /// Onde o navegador costuma deixar o download.
  List<Directory> get pastas {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return const [];
    return [
      Directory(p.join(home, 'Downloads')),
      Directory(p.join(home, 'Desktop')),
    ].where((d) => d.existsSync()).toList();
  }

  /// Procura o JSON mais recente e devolve as credenciais dele.
  Future<CredencialBaixada> procurar() async {
    final candidatos = <File>[];
    for (final pasta in pastas) {
      try {
        for (final f in pasta.listSync()) {
          if (f is File && _nome.hasMatch(p.basename(f.path))) {
            candidatos.add(f);
          }
        }
      } on FileSystemException {
        continue;
      }
    }

    if (candidatos.isEmpty) {
      throw const CredencialException(FalhaCredencial.nenhum);
    }

    // O mais recente: quem baixou duas vezes quer a ultima.
    candidatos.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );

    return ler(candidatos.first);
  }

  /// Extrai as credenciais de um arquivo especifico.
  @visibleForTesting
  static CredencialBaixada ler(File arquivo) {
    final Object? json;
    try {
      json = jsonDecode(arquivo.readAsStringSync());
    } on Exception {
      throw const CredencialException(FalhaCredencial.ilegivel);
    }

    if (json is! Map) throw const CredencialException(FalhaCredencial.ilegivel);

    // `installed` e o cliente de aplicativo para computador, que e o unico
    // que serve para o fluxo de loopback usado aqui.
    if (json['installed'] is! Map) {
      throw CredencialException(
        json['web'] is Map
            ? FalhaCredencial.tipoErrado
            : FalhaCredencial.ilegivel,
      );
    }

    final dados = json['installed'] as Map;
    final id = dados['client_id'];
    final segredo = dados['client_secret'];
    if (id is! String || segredo is! String) {
      throw const CredencialException(FalhaCredencial.ilegivel);
    }

    return CredencialBaixada(
      clientId: id,
      clientSecret: segredo,
      arquivo: p.basename(arquivo.path),
    );
  }
}
