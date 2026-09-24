import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/excalidraw.dart';
import '../services/vault_service.dart';
import 'cliente_webdav.dart';
import 'item_remoto.dart';

/// O que uma sincronizacao fez, para a interface poder contar ao usuario.
class ResultadoDaSync {
  const ResultadoDaSync({
    this.enviados = const [],
    this.baixados = const [],
    this.apagadosAqui = const [],
    this.apagadosLa = const [],
    this.conflitos = const [],
  });

  final List<String> enviados;
  final List<String> baixados;

  /// Notas que sumiram do servidor e sairam daqui — para a lixeira do vault,
  /// nunca para o nada.
  final List<String> apagadosAqui;

  final List<String> apagadosLa;

  /// Notas que mudaram nos dois lados. A versao do servidor foi guardada ao
  /// lado, com outro nome; a daqui continuou sendo a nota.
  final List<String> conflitos;

  int get total =>
      enviados.length +
      baixados.length +
      apagadosAqui.length +
      apagadosLa.length +
      conflitos.length;

  bool get semMudanca => total == 0;

  /// Uma linha para a interface mostrar depois de sincronizar.
  String get resumo {
    if (semMudanca) return 'Tudo em dia com o servidor.';
    final partes = <String>[
      if (enviados.isNotEmpty) '${enviados.length} enviada(s)',
      if (baixados.isNotEmpty) '${baixados.length} baixada(s)',
      if (apagadosLa.isNotEmpty) '${apagadosLa.length} apagada(s) no servidor',
      if (apagadosAqui.isNotEmpty)
        '${apagadosAqui.length} movida(s) para a lixeira',
      if (conflitos.isNotEmpty) '${conflitos.length} em conflito',
    ];
    return partes.join(', ');
  }
}

/// Espelha a pasta do vault contra o servidor WebDAV, nos dois sentidos.
///
/// O vault local continua sendo o que a interface le e escreve — editar
/// offline funciona igual, e a rede so entra depois. Esta classe e o unico
/// lugar que sabe da existencia do servidor.
///
/// Como saber quem mudou: um arquivo de estado no proprio vault guarda, para
/// cada nota, a data de gravacao dos dois lados na ultima vez que eles
/// estavam iguais. Comparar com essas duas datas responde as tres perguntas
/// que importam — mudou aqui, mudou la, ou foi apagada — sem precisar confiar
/// no relogio de nenhuma das duas maquinas.
///
/// Em conflito nada e descartado. Quem escolhe entre duas versoes de um texto
/// e quem escreveu o texto, nunca o programa.
class Sincronizador {
  Sincronizador({
    required this.cliente,
    required this.raiz,
    VaultService? vault,
    DateTime Function()? agora,
  }) : _vault = vault ?? VaultService(),
       _agora = agora ?? DateTime.now;

  final ClienteWebDav cliente;

  /// Caminho da pasta do vault no disco.
  final String raiz;

  final VaultService _vault;
  final DateTime Function() _agora;

  /// Onde ficam as datas da ultima sincronizacao.
  ///
  /// No vault, e nao nas preferencias do app, pelo mesmo motivo da ordem da
  /// arvore: o estado pertence a este par de pastas. Trocar o vault de lugar
  /// leva o estado junto; apagar o vault apaga um estado que nao servia mais.
  static const arquivoDeEstado = '.notas-servidor.json';

  /// Os dois `.json` que o app guarda no vault e que precisam viajar junto das
  /// notas: sem eles a ordem da arvore e o historico de escrita ficariam presos
  /// a uma maquina so.
  static const _metadados = {'.notas-ordem.json', '.notas-atividade.json'};

  /// Para onde vai uma nota que sumiu do servidor.
  ///
  /// O app nunca apaga do disco o que ele mesmo nao apagou. Se o servidor
  /// perder a nota — restauracao de backup errada, outro cliente com defeito,
  /// dedo torto no Explorer — o texto ainda esta aqui. A varredura do vault ja
  /// pula pastas com ponto, entao a lixeira nao aparece na arvore.
  static const pastaDaLixeira = '.trash';

  // ---------------------------------------------------------------- decisao

  Future<ResultadoDaSync> sincronizar() async {
    final locais = await _lerLocal();
    final remotos = <String, ItemRemoto>{
      for (final item in await cliente.listarTudo(
        ignorar: (item) => !_sincronizavel(item.caminho, ehPasta: item.ehPasta),
      ))
        item.caminho: item,
    };
    final estado = await _lerEstado();

    final enviados = <String>[];
    final baixados = <String>[];
    final apagadosAqui = <String>[];
    final apagadosLa = <String>[];
    final conflitos = <String>[];
    final novoEstado = <String, _Marca>{};

    await _espelharPastas(locais, remotos);

    final caminhos = <String>{
      ...locais.keys.where((c) => !locais[c]!.ehPasta),
      ...remotos.keys.where((c) => !remotos[c]!.ehPasta),
      ...estado.keys,
    }.toList()..sort();

    for (final caminho in caminhos) {
      final local = locais[caminho];
      final remoto = remotos[caminho];
      final marca = estado[caminho];

      // Some dos dois lados: o estado so estaria guardando lixo.
      if (local == null && remoto == null) continue;

      if (local != null && remoto == null) {
        if (marca == null) {
          // Nasceu aqui desde a ultima sincronizacao.
          await _subir(caminho, novoEstado, remotos);
          enviados.add(caminho);
        } else {
          // Estava nos dois e sumiu de la: foi apagada no servidor.
          await _paraALixeira(caminho);
          apagadosAqui.add(caminho);
        }
        continue;
      }

      if (local == null && remoto != null) {
        if (marca == null) {
          await _descer(caminho, remoto, novoEstado);
          baixados.add(caminho);
        } else {
          await cliente.apagar(caminho);
          apagadosLa.add(caminho);
        }
        continue;
      }

      final aqui = _milis(local!.modificadoEm);
      final la = _milis(remoto!.modificadoEm);
      final mudouAqui = marca == null || marca.local != aqui;
      final mudouLa = marca == null || marca.remoto != la;

      if (!mudouAqui && !mudouLa) {
        novoEstado[caminho] = marca;
        continue;
      }

      if (mudouAqui && !mudouLa) {
        await _subir(caminho, novoEstado, remotos);
        enviados.add(caminho);
        continue;
      }

      if (!mudouAqui && mudouLa) {
        await _descer(caminho, remoto, novoEstado);
        baixados.add(caminho);
        continue;
      }

      // Mudou nos dois. Antes de gritar conflito, conferir se o texto e o
      // mesmo: na primeira sincronizacao de um vault que ja existia dos dois
      // lados, *tudo* parece ter mudado nos dois, e sem esta comparacao o
      // usuario ganharia uma copia de conflito de cada nota que ja tinha.
      final textoDeLa = await cliente.baixar(caminho);
      final textoDaqui = await File(_absoluto(caminho)).readAsString();
      if (textoDeLa == textoDaqui) {
        novoEstado[caminho] = _Marca(local: aqui, remoto: la);
        continue;
      }

      final copia = await _guardarCopiaDeConflito(caminho, textoDeLa);
      await _subir(caminho, novoEstado, remotos);
      conflitos.add(copia);
    }

    await _limparPastasVazias(locais, remotos, estado, novoEstado);
    await _gravarEstado(novoEstado);

    return ResultadoDaSync(
      enviados: enviados,
      baixados: baixados,
      apagadosAqui: apagadosAqui,
      apagadosLa: apagadosLa,
      conflitos: conflitos,
    );
  }

  /// Sobe uma nota so, sem a rodada completa.
  ///
  /// E o caminho do "acabei de gravar". O editor grava um segundo depois que
  /// voce para de escrever, e reconciliar o vault inteiro a cada pausa custaria
  /// uma varredura dos dois lados por frase escrita — quando o que mudou foi um
  /// arquivo, e o app sabe qual.
  ///
  /// Devolve `false` quando nao da para subir por cima com seguranca: a nota
  /// nunca foi sincronizada, ou o servidor mexeu nela desde a ultima rodada.
  /// Nesses casos quem decide e [sincronizar], que sabe comparar o texto e
  /// guardar a copia de conflito. Subir direto seria apagar o que veio de la.
  Future<bool> subirNota(String caminho) async {
    final relativo = ClienteWebDav.normalizar(caminho);
    if (!_sincronizavel(relativo, ehPasta: false)) return true;

    final arquivo = File(_absoluto(relativo));
    if (!arquivo.existsSync()) return false;

    final estado = await _lerEstado();
    final marca = estado[relativo];
    // Sem marca a nota e nova para esta sincronizacao, e pode ja existir no
    // servidor com outro texto. A rodada completa resolve; esta nao.
    if (marca == null) return false;

    final pai = _pai(relativo);
    final antes = await cliente.listar(pai);
    final remotoAntes = _acharem(antes, relativo);
    if (remotoAntes == null) return false;
    if (_milis(remotoAntes.modificadoEm) != marca.remoto) return false;

    await cliente.enviar(relativo, await arquivo.readAsString());

    final depois = await cliente.listar(pai);
    estado[relativo] = _Marca(
      local: _milis((await arquivo.stat()).modified),
      remoto: _milis(_acharem(depois, relativo)?.modificadoEm),
    );
    await _gravarEstado(estado);
    return true;
  }

  static ItemRemoto? _acharem(List<ItemRemoto> itens, String caminho) {
    for (final item in itens) {
      if (item.caminho == caminho) return item;
    }
    return null;
  }

  // ----------------------------------------------------------------- acoes

  /// Manda a nota daqui para o servidor e anota as duas datas.
  ///
  /// A data remota vem de um PROPFIND depois do PUT em vez do relogio local:
  /// o servidor carimba o arquivo com a hora *dele*, e anotar um palpite faria
  /// a proxima sincronizacao achar que a nota mudou la sozinha.
  Future<void> _subir(
    String caminho,
    Map<String, _Marca> novoEstado,
    Map<String, ItemRemoto> remotos,
  ) async {
    final arquivo = File(_absoluto(caminho));
    await cliente.enviar(caminho, await arquivo.readAsString());

    final pai = _pai(caminho);
    final depois = await cliente.listar(pai);
    remotos.addAll({for (final item in depois) item.caminho: item});

    novoEstado[caminho] = _Marca(
      local: _milis((await arquivo.stat()).modified),
      remoto: _milis(_acharem(depois, caminho)?.modificadoEm),
    );
  }

  Future<void> _descer(
    String caminho,
    ItemRemoto remoto,
    Map<String, _Marca> novoEstado,
  ) async {
    final destino = _absoluto(caminho);
    await Directory(p.dirname(destino)).create(recursive: true);

    // A gravacao segura do vault, e nao um `writeAsString` cru: baixar por
    // cima e o momento em que uma queda de rede ou de energia poderia deixar
    // um `.md` pela metade no disco.
    await _vault.writeNote(destino, await cliente.baixar(caminho));

    novoEstado[caminho] = _Marca(
      local: _milis((await File(destino).stat()).modified),
      remoto: _milis(remoto.modificadoEm),
    );
  }

  /// Cria de cada lado as pastas que existem so do outro.
  ///
  /// Da mais rasa para a mais funda: criar `a/b` antes de `a` faria o servidor
  /// responder 409.
  Future<void> _espelharPastas(
    Map<String, _Local> locais,
    Map<String, ItemRemoto> remotos,
  ) async {
    int porProfundidade(String a, String b) =>
        a.split('/').length.compareTo(b.split('/').length);

    final soLocais =
        locais.keys
            .where((c) => locais[c]!.ehPasta && !remotos.containsKey(c))
            .toList()
          ..sort(porProfundidade);
    for (final caminho in soLocais) {
      await cliente.criarPasta(caminho);
    }

    final soRemotas =
        remotos.keys
            .where((c) => remotos[c]!.ehPasta && !locais.containsKey(c))
            .toList()
          ..sort(porProfundidade);
    for (final caminho in soRemotas) {
      await Directory(_absoluto(caminho)).create(recursive: true);
    }
  }

  /// Tira do caminho as pastas que ficaram vazias dos dois lados depois das
  /// exclusoes. So pasta vazia, e so se ela ja tinha sido sincronizada antes:
  /// apagar uma pasta com conteudo dentro nunca e decisao desta classe.
  Future<void> _limparPastasVazias(
    Map<String, _Local> locais,
    Map<String, ItemRemoto> remotos,
    Map<String, _Marca> estado,
    Map<String, _Marca> novoEstado,
  ) async {
    final conhecidas = estado.keys.map(_pai).where((c) => c.isNotEmpty).toSet();
    final vivos = novoEstado.keys.toSet();

    bool temConteudo(String pasta) =>
        vivos.any((c) => c == pasta || c.startsWith('$pasta/'));

    // Da mais funda para a mais rasa, senao a pasta de cima ainda conteria a
    // de baixo na hora de decidir.
    final candidatas = conhecidas.toList()
      ..sort((a, b) => b.split('/').length.compareTo(a.split('/').length));

    for (final pasta in candidatas) {
      if (temConteudo(pasta)) continue;

      if (!locais.containsKey(pasta) && remotos.containsKey(pasta)) {
        await cliente.apagar(pasta, pasta: true);
      } else if (locais.containsKey(pasta) && !remotos.containsKey(pasta)) {
        final dir = Directory(_absoluto(pasta));
        if (dir.existsSync() && dir.listSync().isEmpty) await dir.delete();
      }
    }
  }

  /// Guarda a versao do servidor ao lado da nota, com a hora no nome, e
  /// devolve o caminho da copia.
  Future<String> _guardarCopiaDeConflito(String caminho, String texto) async {
    final q = _agora();
    final carimbo =
        '${q.year}-${_dois(q.month)}-${_dois(q.day)} '
        '${_dois(q.hour)}h${_dois(q.minute)}';
    final sem = p.withoutExtension(caminho);
    final ext = p.extension(caminho);

    var alvo = '$sem (do servidor $carimbo)$ext';
    var n = 2;
    while (File(_absoluto(alvo)).existsSync()) {
      alvo = '$sem (do servidor $carimbo, $n)$ext';
      n++;
    }

    await _vault.writeNote(_absoluto(alvo), texto);
    return alvo;
  }

  /// Move para a lixeira do vault, preservando a pasta de origem no nome do
  /// destino para duas notas de mesmo nome nao se atropelarem la dentro.
  Future<void> _paraALixeira(String caminho) async {
    final origem = File(_absoluto(caminho));
    if (!origem.existsSync()) return;

    final destino = p.join(
      raiz,
      pastaDaLixeira,
      caminho.replaceAll('/', ' - '),
    );
    await Directory(p.dirname(destino)).create(recursive: true);

    var alvo = destino;
    var n = 2;
    while (File(alvo).existsSync()) {
      alvo = '${p.withoutExtension(destino)} ($n)${p.extension(destino)}';
      n++;
    }
    await origem.rename(alvo);
  }

  // --------------------------------------------------------------- leitura

  Future<Map<String, _Local>> _lerLocal() async {
    final encontrados = <String, _Local>{};
    final fila = <String>[''];

    while (fila.isNotEmpty) {
      final relativo = fila.removeLast();
      final dir = Directory(relativo.isEmpty ? raiz : _absoluto(relativo));

      final List<FileSystemEntity> entidades;
      try {
        entidades = await dir.list(followLinks: false).toList();
      } on FileSystemException {
        // Uma subpasta ilegivel nao derruba a sincronizacao do resto.
        continue;
      }

      for (final entidade in entidades) {
        final nome = p.basename(entidade.path);
        final caminho = relativo.isEmpty ? nome : '$relativo/$nome';
        final ehPasta = entidade is Directory;
        if (!_sincronizavel(caminho, ehPasta: ehPasta)) continue;

        DateTime? modificado;
        try {
          modificado = (await entidade.stat()).modified;
        } on FileSystemException {
          modificado = null;
        }

        encontrados[caminho] = _Local(
          caminho: caminho,
          ehPasta: ehPasta,
          modificadoEm: modificado,
        );
        if (ehPasta) fila.add(caminho);
      }
    }
    return encontrados;
  }

  Future<Map<String, _Marca>> _lerEstado() async {
    final arquivo = File(p.join(raiz, arquivoDeEstado));
    if (!arquivo.existsSync()) return {};

    try {
      final bruto = jsonDecode(await arquivo.readAsString());
      if (bruto is! Map) return {};
      final itens = bruto['itens'];
      if (itens is! Map) return {};

      return {
        for (final entrada in itens.entries)
          if (entrada.key is String && entrada.value is Map)
            entrada.key as String: _Marca(
              local: _inteiro((entrada.value as Map)['local']),
              remoto: _inteiro((entrada.value as Map)['remoto']),
            ),
      };
    } on FormatException {
      // Estado corrompido nao pode travar o app. Sem ele tudo parece novo, e
      // a comparacao de conteudo do caso de conflito segura o estrago: nota
      // igual dos dois lados so volta para o estado, sem copia nenhuma.
      return {};
    } on FileSystemException {
      return {};
    }
  }

  Future<void> _gravarEstado(Map<String, _Marca> estado) async {
    final arquivo = File(p.join(raiz, arquivoDeEstado));
    final json = jsonEncode({
      'versao': 1,
      'itens': {
        for (final entrada in estado.entries)
          entrada.key: {
            'local': entrada.value.local,
            'remoto': entrada.value.remoto,
          },
      },
    });

    try {
      await arquivo.writeAsString(json, flush: true);
    } on FileSystemException {
      // Nao conseguir anotar o estado nao desfaz o que ja subiu e desceu. A
      // proxima sincronizacao recomeca do zero, que e lento, nao errado.
    }
  }

  // -------------------------------------------------------------- detalhes

  /// O que entra na sincronizacao: as notas e os dois `.json` de metadados.
  ///
  /// Tudo que comeca com ponto fica de fora — `.git`, `.obsidian`, `.trash`,
  /// os temporarios da gravacao segura e o proprio arquivo de estado. Sao
  /// coisas de uma maquina so, e sincronizar `.obsidian` entre dois
  /// computadores e a receita conhecida de brigar com o proprio editor.
  static bool _sincronizavel(String caminho, {required bool ehPasta}) {
    final partes = ClienteWebDav.normalizar(caminho).split('/');
    if (partes.isEmpty || partes.first.isEmpty) return false;

    for (var i = 0; i < partes.length - 1; i++) {
      if (partes[i].startsWith('.')) return false;
    }

    final nome = partes.last;
    if (ehPasta) return !nome.startsWith('.');
    // Os metadados so contam na raiz: um `.notas-ordem.json` no meio da arvore
    // nao e do app.
    if (_metadados.contains(nome)) return partes.length == 1;
    if (nome.startsWith('.')) return false;

    // Os `.excalidraw` viajam junto das notas. Eles aparecem na arvore e abrem
    // no app, e um desenho que esta no vault de uma maquina e nao esta no da
    // outra e o mesmo tipo de surpresa que uma nota faltando. O quadro que vive
    // *dentro* de uma nota nao precisa disto: ele ja e o `.md`.
    final extensao = p.extension(nome).toLowerCase();
    return extensao == '.md' || extensao == Excalidraw.extensao;
  }

  String _absoluto(String caminho) =>
      p.join(raiz, p.joinAll(caminho.split('/')));

  static String _pai(String caminho) {
    final corte = caminho.lastIndexOf('/');
    return corte < 0 ? '' : caminho.substring(0, corte);
  }

  static int _milis(DateTime? data) =>
      data?.toUtc().millisecondsSinceEpoch ?? 0;

  static int _inteiro(Object? valor) => valor is int ? valor : 0;

  static String _dois(int n) => n.toString().padLeft(2, '0');
}

/// Um item do vault no disco, no mesmo formato do [ItemRemoto].
class _Local {
  const _Local({
    required this.caminho,
    required this.ehPasta,
    this.modificadoEm,
  });

  final String caminho;
  final bool ehPasta;
  final DateTime? modificadoEm;
}

/// As duas datas de gravacao da ultima vez que os dois lados estavam iguais.
class _Marca {
  const _Marca({required this.local, required this.remoto});

  final int local;
  final int remoto;
}
