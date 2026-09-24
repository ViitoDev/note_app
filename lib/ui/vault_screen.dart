import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/atividade.dart';
import '../models/calendar_event.dart';
import '../models/dashboard_data.dart';
import '../models/email_account.dart';
import '../models/email_message.dart';
import '../models/frontmatter_writer.dart';
import '../models/kanban_card.dart';
import '../models/note.dart';
import '../models/vault_entry.dart';
import '../models/vault_graph.dart';
import '../models/vault_order.dart';
import '../repositories/email_repository.dart';
import '../repositories/vault_repository.dart';
import '../services/calendar_service.dart';
import '../services/dashboard_service.dart';
import '../services/email_service.dart';
import '../services/graph_service.dart';
import '../services/kanban_service.dart';
import '../services/vault_service.dart';
import '../servidor/cliente_webdav.dart';
import '../servidor/config_do_servidor.dart';
import '../servidor/sincronizador.dart';
import 'app_theme.dart';
import 'calendar_screen.dart';
import 'dashboard_screen.dart';
import 'dock_area.dart';
import 'email_config_dialog.dart';
import 'email_screen.dart';
import 'google_login_dialog.dart';
import 'folder_picker.dart';
import 'graph_screen.dart';
import 'kanban_screen.dart';
import 'notas_recentes.dart';
import 'note_editor.dart';
import 'note_tree.dart';
import 'panel_layout.dart';
import 'resizable_split.dart';
import 'servidor_config_dialog.dart';
import 'ui_prefs.dart';

/// As abas do app, escolhidas na barra de navegaçao a esquerda.
enum _View {
  notas('Notas', Icons.description_outlined, Icons.description),
  dashboard('Painel', Icons.dashboard_outlined, Icons.dashboard),
  calendario('Calendario', Icons.calendar_month_outlined, Icons.calendar_month),
  grafo('Grafo', Icons.hub_outlined, Icons.hub),
  kanban('Quadro', Icons.view_kanban_outlined, Icons.view_kanban),
  email('E-mail', Icons.mail_outline, Icons.mail);

  const _View(this.label, this.icon, this.iconSelecionado);

  final String label;
  final IconData icon;
  final IconData iconSelecionado;
}

/// Em que pe esta a conversa com o servidor privado.
enum _Sync {
  /// Nenhum servidor configurado: o vault e so a pasta local.
  desligado,

  /// Configurado e parado, esperando a proxima rodada.
  ocioso,

  sincronizando,

  /// A ultima tentativa falhou. O app continua funcionando: o que nao subiu
  /// sobe na proxima.
  erro,
}

enum _AcaoDoServidor { sincronizar, configurar }

/// Tela principal: editor de nota no centro, paineis acoplaveis nas laterais.
///
/// O editor e a unica coisa fixa. Arvore, calendario e grafo sao paineis que o
/// usuario arrasta para a barra da esquerda ou da direita, empilha e
/// redimensiona — e o arranjo escolhido sobrevive ao fechamento do app.
///
/// Numa janela estreita nao ha barras: a arvore vira um Drawer, porque nao
/// cabem tres colunas lado a lado.
class VaultScreen extends StatefulWidget {
  const VaultScreen({
    super.key,
    this.repository,
    this.email,
    this.servidorPrefs,
  });

  /// Injetavel para o teste rodar sem tocar em disco. Em producao fica nulo e
  /// a tela usa o [VaultService].
  final VaultRepository? repository;

  /// Idem, para o teste nao precisar de servidor IMAP.
  final EmailRepository? email;

  /// Idem, para o teste nao depender do cofre de senhas do Windows.
  final ServidorPrefs? servidorPrefs;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  static const _wideBreakpoint = 700.0;

  late final VaultRepository _repository = widget.repository ?? VaultService();
  late final CalendarService _calendar = CalendarService(_repository);
  late final GraphService _graphService = GraphService(_repository);
  late final KanbanService _kanban = KanbanService(_repository);
  late final DashboardService _dashboard = DashboardService(_repository);
  late final EmailRepository _email = widget.email ?? EmailService();
  late final ServidorPrefs _servidorPrefs =
      widget.servidorPrefs ?? const ServidorPrefs();
  final _editorKey = GlobalKey<NoteEditorState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _vaultPath;
  VaultFolder? _tree;

  /// Ordem manual das linhas, lida do vault e reaplicada a cada varredura.
  VaultOrder _order = VaultOrder.vazia;

  Note? _openNote;
  bool _loading = true;
  bool _dirty = false;
  String? _error;

  /// O painel abre primeiro: e a tela que responde "o que eu faço agora?".
  /// Escolher uma nota antes de saber isso e o passo seguinte, nao o primeiro.
  _View _view = _View.dashboard;

  List<CalendarEvent> _events = const [];
  bool _loadingEvents = false;
  bool _eventosProntos = false;

  VaultGraph? _graph;
  bool _loadingGraph = false;
  bool _grafoPronto = false;

  KanbanBoard _board = KanbanBoard.vazio;
  bool _loadingBoard = false;
  bool _quadroPronto = false;

  DashboardData _painel = DashboardData.vazia();
  bool _loadingPainel = false;
  bool _painelPronto = false;

  /// O historico de escrita que alimenta o contador do painel.
  Atividade _atividade = Atividade.vazia;

  /// Ids das ultimas notas abertas, do mais recente para o mais antigo.
  List<String> _recentes = NotasRecentes.ler();

  EmailAccount? _conta;
  List<EmailMessage> _emails = const [];
  bool _loadingEmails = false;
  bool _emailPronto = false;
  bool _entrandoComGoogle = false;
  EmailException? _erroEmail;

  /// Onde cada painel esta acoplado. Lido de forma sincrona no primeiro frame
  /// para a tela ja nascer no arranjo escolhido, sem piscar no padrao.
  PanelLayout _layout = PanelLayout.decode(UiPrefs.readString('paineis'));

  /// Painel que esta sendo arrastado, ou nulo. Enquanto ele nao e nulo a tela
  /// mostra onde da para soltar.
  PanelKind? _arrastando;

  ConfigDoServidor _servidor = ConfigDoServidor.vazia;
  _Sync _sync = _Sync.desligado;
  String? _erroDaSync;
  DateTime? _ultimaSync;

  /// A rodada de fundo e a que segue o que outra maquina escreveu no servidor.
  Timer? _relogioDaSync;

  /// Espera a digitacao parar antes de subir. Sem isso, cada Ctrl+S viraria
  /// uma ida a rede no meio da escrita.
  Timer? _atrasoDaSync;

  /// Cada barra recolhe por conta propria. A da esquerda leva junto a barra de
  /// navegaçao, que fica encostada nela.
  bool _esquerdaVisivel = UiPrefs.readBool('sidebar_visivel') ?? true;
  bool _direitaVisivel = UiPrefs.readBool('sidebar_direita_visivel') ?? true;

  // ---------------------------------------------------------------- paineis

  /// A aba que a tela realmente desenha.
  ///
  /// Durante um arrasto o corpo volta para as notas mesmo que a aba escolhida
  /// seja outra: sem isso, arrastar um painel a partir do calendario nao teria
  /// nenhuma barra visivel onde soltar.
  _View get _viewAtual => _arrastando != null ? _View.notas : _view;

  bool _barraVisivel(DockSide side) =>
      side == DockSide.esquerda ? _esquerdaVisivel : _direitaVisivel;

  /// A barra ocupa espaço: tem painel, nao esta recolhida e a aba e a de notas.
  bool _barraAtiva(DockSide side) =>
      _layout.of(side).isNotEmpty &&
      _barraVisivel(side) &&
      _viewAtual == _View.notas;

  void _alternarBarra(DockSide side) {
    setState(() {
      if (side == DockSide.esquerda) {
        _esquerdaVisivel = !_esquerdaVisivel;
      } else {
        _direitaVisivel = !_direitaVisivel;
      }
    });
    _guardarVisibilidade();
  }

  void _guardarVisibilidade() {
    UiPrefs.writeBool('sidebar_visivel', value: _esquerdaVisivel);
    UiPrefs.writeBool('sidebar_direita_visivel', value: _direitaVisivel);
  }

  /// Aplica um arranjo novo e o guarda em disco.
  ///
  /// [revelar] e a barra que precisa aparecer para o painel recem-acoplado nao
  /// sumir dentro de uma barra recolhida.
  void _aplicarArranjo(PanelLayout novo, {DockSide? revelar}) {
    setState(() {
      _layout = novo;
      _arrastando = null;
      if (revelar != null) {
        // Acoplar um painel sempre volta para as notas e reabre a barra que
        // recebeu: sem isso o resultado do arrasto ficaria invisivel.
        _view = _View.notas;
        if (revelar == DockSide.esquerda) {
          _esquerdaVisivel = true;
        } else {
          _direitaVisivel = true;
        }
      }
    });
    UiPrefs.writeString('paineis', novo.encode());
    if (revelar != null) _guardarVisibilidade();
    _carregarDadosDosPaineis();
  }

  void _moverPainel(PanelKind painel, DockSide side, {PanelKind? antesDe}) =>
      _aplicarArranjo(
        _layout.mover(painel, side, antesDe: antesDe),
        revelar: side,
      );

  void _fecharPainel(PanelKind painel) =>
      _aplicarArranjo(_layout.ocultar(painel));

  /// Clique no botao do painel na barra de navegaçao.
  void _alternarPainel(PanelKind painel) {
    if (_layout.contains(painel)) {
      _fecharPainel(painel);
      return;
    }
    // A arvore volta para a esquerda; calendario e grafo vao para a direita,
    // que e o lado livre enquanto se escreve no centro.
    _moverPainel(
      painel,
      painel == PanelKind.arquivos ? DockSide.esquerda : DockSide.direita,
    );
  }

  void _arrastoMudou(PanelKind? painel) => setState(() => _arrastando = painel);

  /// O painel que fica logo abaixo de [painel] na barra, ou nulo se ele for o
  /// ultimo. Usado para traduzir "soltar embaixo deste" em "entrar antes do
  /// proximo".
  PanelKind? _abaixoDe(PanelKind painel, DockSide side) {
    final lista = _layout.of(side);
    final i = lista.indexOf(painel);
    return i >= 0 && i + 1 < lista.length ? lista[i + 1] : null;
  }

  // ------------------------------------------------------------------ vault

  @override
  void initState() {
    super.initState();
    // As duas leituras sao independentes de proposito.
    //
    // O servidor ja entrou encadeado no fim da leitura do vault, e foi um
    // erro: a pasta pode demorar — a do usuario mora num sistema de arquivos
    // virtual — ou nem montar, e nesses casos o `then` nunca chegava. O app
    // ficava sem servidor, sem relogio de fundo e sem icone, e nada na tela
    // explicava por que. Quem terminar por ultimo dispara a primeira rodada;
    // `_sincronizar` ja ignora sozinho a chamada que chega antes do vault.
    unawaited(_restoreLastVault());
    unawaited(_carregarServidor());
  }

  Future<void> _restoreLastVault() async {
    final String? saved;
    try {
      saved = await _repository.loadSavedVaultPath();
    } catch (e) {
      // Ler a preferencia nao deveria falhar, mas se falhar o desfecho util e
      // pedir a pasta de novo — nunca uma tela travada em "carregando".
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Nao foi possivel lembrar a ultima pasta: $e';
        });
      }
      return;
    }

    if (saved == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await _openVault(saved);
  }

  Future<void> _chooseVault() async {
    if (!await _garantirSalvo()) return;
    if (!mounted) return;
    final picked = await showFolderPicker(
      context,
      startPath: _vaultPath ?? _repository.defaultStartPath,
    );
    if (picked == null) return;
    await _repository.saveVaultPath(picked);
    await _openVault(picked);
  }

  Future<void> _openVault(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await _repository.loadOrder(path);
      final tree = order.aplicar(await _repository.scan(path));
      final atividade = await _repository.loadAtividade(path);
      if (!mounted) return;
      setState(() {
        _vaultPath = path;
        _order = order;
        _atividade = atividade;
        _tree = tree;
        _openNote = null;
        _dirty = false;
        _loading = false;
        _invalidarDerivados();
      });
      // O vault ficou pronto: se ja ha servidor, e a hora da primeira rodada.
      // Vale tambem para quem trocou de pasta com o app aberto. Fora do
      // `await` para a rede nao segurar a abertura da tela.
      if (_servidor.configurado) unawaited(_sincronizar());
      await _carregarDadosDosPaineis();
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Nao foi possivel ler a pasta:\n${e.message}';
        _loading = false;
      });
    } catch (e) {
      // Captura larga de proposito. O vault pode morar numa unidade de rede ou
      // num sistema de arquivos virtual, e o que essas coisas lancam quando
      // tropecam nao cabe numa lista. Deixar escapar daqui congela a tela em
      // "carregando" e leva junto tudo que dependesse deste await.
      if (!mounted) return;
      setState(() {
        _error = 'Nao foi possivel ler a pasta:\n$e';
        _loading = false;
      });
    }
  }

  /// Reconstroi a arvore a partir do disco.
  ///
  /// [agendarSync] desliga o aviso ao servidor na releitura que *vem* de uma
  /// sincronizacao — senao cada rodada pediria a proxima, de tres em tres
  /// segundos, para sempre.
  Future<void> _refreshTree({bool agendarSync = true}) async {
    final path = _vaultPath;
    if (path == null) return;
    try {
      // A ordem manual e reaplicada a cada varredura: o disco devolve os nomes
      // em ordem alfabetica e nao sabe nada da escolha do usuario.
      final tree = _order.aplicar(await _repository.scan(path));
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _invalidarDerivados();
      });
      if (agendarSync) _agendarSync();
      await _carregarDadosDosPaineis();
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel reler o vault: ${e.message}');
    }
  }

  /// Calendario e grafo sao derivados do conteudo das notas: quando a arvore
  /// muda, os dois precisam ser relidos.
  void _invalidarDerivados() {
    _eventosProntos = false;
    _grafoPronto = false;
    _quadroPronto = false;
    _painelPronto = false;
  }

  /// A nota acabou de ser gravada pelo app: anota a hora na arvore e derruba
  /// o que deriva das notas.
  ///
  /// A arvore na tela so sabe do disco o que a ultima varredura contou. Quem
  /// grava por aqui nao passa por ela, e o diario do painel pergunta a arvore
  /// quando cada nota mudou — sem esta linha, escrever numa nota antiga nao a
  /// traria para o dia de hoje ate o vault ser relido.
  void _marcarGravada(String noteId) {
    _tree = _tree?.comGravacao(noteId, DateTime.now());
    _invalidarDerivados();
    _agendarSync(nota: noteId);
  }

  // --------------------------------------------------------------- servidor

  /// Intervalo da rodada de fundo. Cinco minutos e o meio-termo entre ver
  /// depressa o que a outra maquina escreveu e nao bater no servidor a toa
  /// enquanto ninguem mexe em nada.
  static const _intervaloDaSync = Duration(minutes: 5);

  /// Quanto tempo depois de uma mudanca de estrutura — nota criada, movida,
  /// renomeada, apagada — a rodada completa acontece. Ela varre os dois lados,
  /// entao vale esperar a rajada terminar.
  static const _atrasoDaRodadaCompleta = Duration(seconds: 3);

  /// Quanto tempo depois de gravar a nota sobe sozinha.
  ///
  /// Curto porque e barato: uma nota so, um PUT. O editor ja espera um segundo
  /// de silencio antes de gravar, entao o texto chega ao servidor cerca de um
  /// segundo e meio depois de voce parar de escrever.
  static const _atrasoDeUmaNota = Duration(milliseconds: 400);

  /// A nota gravada esperando para subir, quando foi so isso que mudou.
  String? _notaPendente;

  /// Alguma mudanca que a subida de uma nota so nao cobre — pasta criada, nota
  /// movida, exclusao. Obriga a rodada completa.
  bool _rodadaCompletaPendente = false;

  Future<void> _carregarServidor() async {
    final config = await _servidorPrefs.carregar();
    if (!mounted || !config.configurado) return;
    setState(() {
      _servidor = config;
      _sync = _Sync.ocioso;
    });
    _ligarRelogio();
    await _sincronizar();
  }

  void _ligarRelogio() {
    _relogioDaSync?.cancel();
    _relogioDaSync = Timer.periodic(
      _intervaloDaSync,
      (_) => unawaited(_sincronizar()),
    );
  }

  /// Marca que ha coisa nova para subir.
  ///
  /// [nota] e o caminho da que acabou de ser gravada, quando foi so isso que
  /// mudou — e o caso comum, o de alguem escrevendo. Ai sobe so ela, que custa
  /// um PUT. Sem [nota], ou quando duas notas diferentes mudam na mesma janela,
  /// vai a rodada completa: e a unica que sabe de pasta criada, nota movida,
  /// exclusao e conflito.
  void _agendarSync({String? nota}) {
    if (!_servidor.configurado) return;

    if (nota == null) {
      _rodadaCompletaPendente = true;
      _notaPendente = null;
    } else if (!_rodadaCompletaPendente) {
      if (_notaPendente != null && _notaPendente != nota) {
        _rodadaCompletaPendente = true;
        _notaPendente = null;
      } else {
        _notaPendente = nota;
      }
    }

    _atrasoDaSync?.cancel();
    _atrasoDaSync = Timer(
      _notaPendente != null ? _atrasoDeUmaNota : _atrasoDaRodadaCompleta,
      () => unawaited(_subirOPendente()),
    );
  }

  /// Faz o que [_agendarSync] marcou: a nota so, ou a rodada completa.
  Future<void> _subirOPendente() async {
    final nota = _notaPendente;
    final raiz = _vaultPath;
    final base = _servidor.uri;

    _notaPendente = null;
    _rodadaCompletaPendente = false;

    if (nota == null || raiz == null || base == null) {
      await _sincronizar();
      return;
    }

    // Rodada em curso: esta subida espera a proxima janela em vez de disputar
    // o mesmo arquivo de estado.
    if (_sync == _Sync.sincronizando) {
      _agendarSync(nota: nota);
      return;
    }

    setState(() {
      _sync = _Sync.sincronizando;
      _erroDaSync = null;
    });

    final cliente = ClienteWebDav(
      base: base,
      usuario: _servidor.usuario,
      senha: _servidor.senha,
    );

    try {
      final subiu = await Sincronizador(
        cliente: cliente,
        raiz: raiz,
      ).subirNota(p.relative(nota, from: raiz));
      if (!mounted) return;

      setState(() {
        _sync = _Sync.ocioso;
        _ultimaSync = DateTime.now();
      });

      // O caminho rapido devolve falso quando nao sabe resolver sozinho — nota
      // nova, ou texto que mudou tambem no servidor. Quem decide e a rodada
      // completa, que compara o conteudo e guarda a copia de conflito.
      if (!subiu) await _sincronizar();
    } on ServidorException catch (e) {
      if (!mounted) return;
      setState(() {
        _sync = _Sync.erro;
        _erroDaSync = e.mensagem;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _sync = _Sync.erro;
        _erroDaSync = 'Falha ao ler a nota: ${e.message}';
      });
    } finally {
      cliente.fechar();
    }
  }

  Future<void> _sincronizar({bool avisar = false}) async {
    final raiz = _vaultPath;
    final base = _servidor.uri;
    if (raiz == null || base == null) return;
    // Duas rodadas ao mesmo tempo disputariam os mesmos arquivos e o mesmo
    // estado; a segunda espera a proxima vez.
    if (_sync == _Sync.sincronizando) return;

    setState(() {
      _sync = _Sync.sincronizando;
      _erroDaSync = null;
    });

    final cliente = ClienteWebDav(
      base: base,
      usuario: _servidor.usuario,
      senha: _servidor.senha,
    );

    try {
      final resultado = await Sincronizador(
        cliente: cliente,
        raiz: raiz,
      ).sincronizar();
      if (!mounted) return;

      setState(() {
        _sync = _Sync.ocioso;
        _ultimaSync = DateTime.now();
      });

      final mudouODisco =
          resultado.baixados.isNotEmpty ||
          resultado.apagadosAqui.isNotEmpty ||
          resultado.conflitos.isNotEmpty;
      if (mudouODisco) await _relerDepoisDaSync(raiz, resultado);

      // Conflito sempre e dito, mesmo numa rodada de fundo: uma copia que
      // aparece no vault sem ninguem avisar e uma copia que ninguem le.
      if (resultado.conflitos.isNotEmpty) {
        _snack(
          'A mesma nota mudou aqui e no servidor. A versao de la ficou '
          'guardada ao lado: ${resultado.conflitos.join(', ')}',
        );
      } else if (avisar) {
        _snack(resultado.resumo);
      }
    } on ServidorException catch (e) {
      if (!mounted) return;
      setState(() {
        _sync = _Sync.erro;
        _erroDaSync = e.mensagem;
      });
      // Falha de fundo nao interrompe quem esta escrevendo: o indicador na
      // barra conta, e o que nao subiu sobe na proxima rodada.
      if (avisar) _snack(e.mensagem);
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _sync = _Sync.erro;
        _erroDaSync = 'Falha ao gravar no vault: ${e.message}';
      });
      if (avisar) _snack(_erroDaSync!);
    } finally {
      cliente.fechar();
    }
  }

  /// Poe na tela o que a sincronizacao mudou no disco.
  ///
  /// A ordem da arvore e o historico de escrita tambem viajam pelo servidor, e
  /// os dois vivem em memoria aqui — reler so a arvore deixaria a ordem antiga
  /// sendo reaplicada por cima da que acabou de chegar.
  Future<void> _relerDepoisDaSync(
    String raiz,
    ResultadoDaSync resultado,
  ) async {
    try {
      final order = await _repository.loadOrder(raiz);
      final atividade = await _repository.loadAtividade(raiz);
      if (!mounted) return;
      setState(() {
        _order = order;
        _atividade = atividade;
      });
    } on FileSystemException {
      // Sem a ordem nova a arvore volta ao alfabetico, o que nao justifica
      // abandonar o resto da releitura.
    }

    await _refreshTree(agendarSync: false);

    // A nota aberta pode ter sido justamente uma das que desceram. Com edicao
    // pendente ela fica como esta: sobrescrever o que o usuario acabou de
    // digitar seria trocar um conflito resolvido por um dado perdido.
    final aberta = _openNote?.id;
    if (aberta == null || _dirty) return;
    final baixadas = resultado.baixados.map(
      (c) => p.join(raiz, p.joinAll(c.split('/'))),
    );
    if (baixadas.any((caminho) => p.equals(caminho, aberta))) {
      await _reabrir(aberta);
    }
  }

  Future<void> _configurarServidor() async {
    final config = await showServidorConfigDialog(context, atual: _servidor);
    if (config == null || !mounted) return;

    _relogioDaSync?.cancel();
    setState(() {
      _servidor = config;
      _erroDaSync = null;
      _sync = config.configurado ? _Sync.ocioso : _Sync.desligado;
    });
    if (!config.configurado) return;

    _ligarRelogio();
    await _sincronizar(avisar: true);
  }

  @override
  void dispose() {
    _relogioDaSync?.cancel();
    _atrasoDaSync?.cancel();
    super.dispose();
  }

  bool get _precisaCalendario =>
      _view == _View.calendario || _layout.contains(PanelKind.calendario);

  bool get _precisaGrafo =>
      _view == _View.grafo || _layout.contains(PanelKind.grafo);

  bool get _precisaPainel =>
      _view == _View.dashboard || _layout.contains(PanelKind.dashboard);

  bool get _precisaEmail =>
      _view == _View.email || _layout.contains(PanelKind.email);

  /// Le o vault so para o que esta a vista. Um painel fechado nao custa nada.
  Future<void> _carregarDadosDosPaineis() async {
    // O e-mail vem antes do resto e nao depende da arvore: ele nao sai do
    // vault, sai da rede.
    if (_precisaEmail && !_emailPronto && !_loadingEmails) {
      await _loadEmails();
    }
    if (_tree == null) return;
    if (_precisaCalendario && !_eventosProntos && !_loadingEvents) {
      await _loadEvents();
    }
    if (_precisaGrafo && !_grafoPronto && !_loadingGraph) {
      await _loadGraph();
    }
    if (_precisaQuadro && !_quadroPronto && !_loadingBoard) {
      await _loadBoard();
    }
    if (_precisaPainel && !_painelPronto && !_loadingPainel) {
      await _loadPainel();
    }
  }

  bool get _precisaQuadro =>
      _view == _View.kanban || _layout.contains(PanelKind.kanban);

  Future<void> _loadBoard() async {
    final tree = _tree;
    if (tree == null) return;

    setState(() => _loadingBoard = true);
    final board = await _kanban.build(tree);
    if (!mounted) return;
    setState(() {
      _board = board;
      _loadingBoard = false;
      _quadroPronto = true;
    });
  }

  Future<void> _loadPainel() async {
    final tree = _tree;
    if (tree == null) return;

    setState(() => _loadingPainel = true);
    final dados = await _dashboard.build(tree);
    if (!mounted) return;
    setState(() {
      _painel = dados;
      _loadingPainel = false;
      _painelPronto = true;
    });
  }

  /// Anota no historico o que uma gravaçao acabou de produzir.
  ///
  /// So o crescimento conta, e a conta e feita comparando as duas versoes do
  /// texto — nao ha de onde tirar isso depois: o arquivo gravado diz como a
  /// nota ficou, nunca quanto dela foi escrito hoje.
  Future<void> _registrarAtividade(String antes, String depois) async {
    final path = _vaultPath;
    if (path == null) return;

    final delta = Atividade.diferenca(antes, depois);
    if (delta.palavras == 0 && delta.tarefas == 0) return;

    final novo = _atividade
        .somar(DateTime.now(), palavras: delta.palavras, tarefas: delta.tarefas)
        .podar(DateTime.now());

    setState(() => _atividade = novo);
    await _repository.saveAtividade(path, novo);
  }

  /// Marca ou desmarca no arquivo uma tarefa clicada no painel.
  ///
  /// O mesmo caminho da caixa do preview: a linha do `.md` e a unica verdade
  /// sobre a tarefa, entao marcar aqui e reescrever aquela linha.
  Future<void> _alternarTarefaDoPainel(String noteId, int indice) async {
    try {
      final mudanca = await _dashboard.alternarTarefa(noteId, indice);
      if (mudanca == null) return;
      await _registrarAtividade(mudanca.antes, mudanca.depois);
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel marcar a tarefa: ${e.message}');
      return;
    }

    // A nota da tarefa pode ser a que esta aberta no editor; sem reler, o
    // texto na tela continuaria com a caixa vazia.
    if (_openNote?.id == noteId && !_dirty) await _reabrir(noteId);

    setState(() => _marcarGravada(noteId));
    await _carregarDadosDosPaineis();
  }

  /// Cria um card direto do quadro: uma nota nova, ja com o `status:` da
  /// coluna onde o `+` foi clicado.
  ///
  /// A nota nasce na raiz do vault. Perguntar a pasta no meio do quadro seria
  /// um segundo dialogo para uma decisao que se desfaz arrastando a nota na
  /// arvore depois.
  Future<void> _novoCard(KanbanColumn coluna) async {
    final raiz = _tree;
    if (raiz == null) return;

    final pedido = await showDialog<({String nome, bool tela})>(
      context: context,
      builder: (context) => _NomeDialog(
        titulo: 'Novo card em ${coluna.label}',
        rotulo: 'Titulo',
        dica: 'Ex.: Revisar o capitulo 3',
        acao: 'Criar',
      ),
    );
    if (pedido == null || pedido.nome.trim().isEmpty) return;

    try {
      final id = await _repository.createNote(raiz.id, pedido.nome.trim());
      final nota = await _repository.readNote(id);
      // O `status:` entra por cima do frontmatter que a nota ja nasce tendo,
      // em vez de a criaçao ganhar um parametro que so o quadro usaria.
      await _repository.writeNote(
        id,
        FrontmatterWriter.definir(nota.raw, 'status', coluna.valor),
      );
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel criar o card: ${e.message}');
      return;
    }

    await _refreshTree();
  }

  /// Troca a coluna de um card, gravando o `status:` na nota.
  Future<void> _moverCard(KanbanCard card, KanbanColumn destino) async {
    try {
      await _kanban.mover(card.noteId, destino);
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel mover o card: ${e.message}');
      return;
    }

    // A nota aberta pode ser a que acabou de mudar de coluna; sem reler, o
    // editor continuaria mostrando o status antigo.
    if (_openNote?.id == card.noteId && !_dirty) {
      await _reabrir(card.noteId);
    }

    setState(() => _marcarGravada(card.noteId));
    await _carregarDadosDosPaineis();
  }

  // ----------------------------------------------------------------- e-mail

  /// Busca a caixa de entrada.
  ///
  /// O erro fica guardado em vez de virar snackbar: o painel de e-mail pode
  /// estar fechado quando a busca falha, e um aviso que some nao ajuda quem
  /// abrir depois.
  Future<void> _loadEmails() async {
    final conta = await _email.loadAccount();
    if (!mounted) return;

    setState(() {
      _conta = conta;
      _erroEmail = null;
    });
    if (conta == null) {
      setState(() => _emailPronto = true);
      return;
    }

    setState(() => _loadingEmails = true);
    try {
      final mensagens = await _email.fetchInbox(limite: 40);
      if (!mounted) return;
      setState(() {
        _emails = mensagens;
        _loadingEmails = false;
        _emailPronto = true;
      });
    } on EmailException catch (e) {
      if (!mounted) return;
      setState(() {
        _erroEmail = e;
        _emails = const [];
        _loadingEmails = false;
        _emailPronto = true;
      });
    }
  }

  Future<void> _acaoDeConta(AcaoConta acao) => switch (acao) {
    AcaoConta.senhaDeApp => _configurarSenhaDeApp(),
    AcaoConta.entrarComGoogle => _entrarComGoogle(),
    AcaoConta.refazerCadastroGoogle => _entrarComGoogle(refazerCadastro: true),
  };

  Future<void> _configurarSenhaDeApp() async {
    // O dialogo ja descobre o servidor, confere a senha entrando e guarda: se
    // ele devolve uma conta, ela funciona.
    final conta = await showEmailConfigDialog(
      context,
      repositorio: _email,
      atual: _conta,
    );
    if (conta == null || !mounted) return;

    _recomecarCaixa(conta);
    await _loadEmails();
  }

  /// Login com o Google.
  ///
  /// Na primeira vez passa pelo cadastro do Client ID; nas seguintes vai
  /// direto ao navegador, porque o cadastro ja esta guardado.
  Future<void> _entrarComGoogle({bool refazerCadastro = false}) async {
    final guardado = await _email.loadClientId();
    if (!mounted) return;

    String? clientId;
    String? clientSecret;
    if (refazerCadastro || guardado == null || guardado.isEmpty) {
      final cred = await showGoogleSetupDialog(
        context,
        clientIdAtual: guardado,
      );
      if (cred == null || !mounted) return;
      clientId = cred.clientId;
      clientSecret = cred.clientSecret;
    }

    setState(() => _entrandoComGoogle = true);
    try {
      final conta = await _email.loginComGoogle(
        clientId: clientId,
        clientSecret: clientSecret,
      );
      if (!mounted) return;
      setState(() => _entrandoComGoogle = false);
      _recomecarCaixa(conta);
      await _loadEmails();
    } on EmailException catch (e) {
      if (!mounted) return;
      setState(() {
        _entrandoComGoogle = false;
        _erroEmail = e;
        _emailPronto = true;
      });
    }
  }

  /// Conta nova, caixa nova: o que estava na tela nao vale mais.
  void _recomecarCaixa(EmailAccount conta) {
    setState(() {
      _conta = conta;
      _emails = const [];
      _erroEmail = null;
      _emailPronto = false;
    });
  }

  /// Rele o vault inteiro para extrair os eventos das notas — nunca ha indice
  /// guardado, entao um evento apagado do arquivo some na proxima leitura.
  Future<void> _loadEvents() async {
    final tree = _tree;
    if (tree == null) return;

    setState(() => _loadingEvents = true);
    final events = await _calendar.collect(tree);
    if (!mounted) return;
    setState(() {
      _events = events;
      _loadingEvents = false;
      _eventosProntos = true;
    });
  }

  /// Rele o vault para montar o grafo de notas e tags.
  Future<void> _loadGraph() async {
    final tree = _tree;
    if (tree == null) return;

    setState(() => _loadingGraph = true);
    final graph = await _graphService.build(tree);
    if (!mounted) return;
    setState(() {
      _graph = graph;
      _loadingGraph = false;
      _grafoPronto = true;
    });
  }

  Future<void> _switchTo(_View view) async {
    if (view == _view) return;
    if (view != _View.notas && !await _garantirSalvo()) return;
    if (!mounted) return;

    setState(() => _view = view);
    await _carregarDadosDosPaineis();
  }

  /// Abre a nota de origem de um evento ou de um no do grafo.
  Future<void> _openNoteById(String noteId) async {
    try {
      final note = await _repository.readNote(noteId);
      if (!mounted) return;
      setState(() {
        _openNote = note;
        _dirty = false;
        _view = _View.notas;
        _recentes = NotasRecentes.registrar(note.id);
      });
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel abrir a nota de origem: ${e.message}');
    }
  }

  Future<void> _openFile(VaultFile file) async {
    if (file.id == _openNote?.id) return;
    if (!await _garantirSalvo()) return;

    try {
      final note = await _repository.readNote(file.id);
      if (!mounted) return;
      setState(() {
        _openNote = note;
        _dirty = false;
        _recentes = NotasRecentes.registrar(note.id);
      });
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel abrir a nota: ${e.message}');
    }
  }

  /// Descarrega no arquivo o que ainda estava pendente, antes de sair da nota.
  ///
  /// Nao pergunta nada: o editor grava sozinho, entao sair de uma nota e so
  /// antecipar a gravaçao que ja ia acontecer. A pergunta so aparece quando a
  /// gravaçao **falha** — ai perder o texto vira uma decisao de verdade, e
  /// quem tem que tomar e o usuario.
  Future<bool> _garantirSalvo() async {
    if (!_dirty) return true;
    if (await _editorKey.currentState?.save() ?? false) return true;

    if (!mounted) return false;
    final descartar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nao consegui salvar'),
        content: Text(
          'A nota "${_openNote?.title ?? ''}" tem mudanças que nao foram para '
          'o arquivo. Sair agora perde o que voce escreveu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar para a nota'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return descartar ?? false;
  }

  Future<void> _saveNote(String content) async {
    final note = _openNote;
    if (note == null) return;
    try {
      await _repository.writeNote(note.id, content);
      await _registrarAtividade(note.raw, content);
      if (!mounted) return;
      setState(() {
        // O texto gravado muda tags, links e datas: o que deriva das notas
        // fica velho na hora.
        _marcarGravada(note.id);
        // A gravaçao pode chegar depois de a nota ter saido da tela — quem
        // troca de nota descarrega o que estava pendente. Nesse caso o editor
        // ja mostra outra coisa, e mexer em `_dirty` apagaria o aviso de que a
        // nota nova esta por gravar.
        if (_openNote?.id == note.id) {
          _openNote = note.copyWithRaw(content);
          _dirty = false;
        }
      });
      await _carregarDadosDosPaineis();
    } on FileSystemException catch (e) {
      _snack('Falha ao salvar: ${e.message}');
      rethrow;
    }
  }

  Future<void> _newNote(VaultFolder folder) async {
    if (!await _garantirSalvo()) return;
    if (!mounted) return;

    final pedido = await showDialog<({String nome, bool tela})>(
      context: context,
      builder: (context) => const _NomeDialog(
        titulo: 'Nova nota',
        rotulo: 'Titulo',
        dica: 'Ex.: Estudo de React Hooks',
        acao: 'Criar',
        ofereceTela: true,
      ),
    );
    if (pedido == null) return;

    try {
      final created = await _repository.createNote(
        folder.id,
        pedido.nome,
        tela: pedido.tela,
      );
      await _refreshTree();
      final note = await _repository.readNote(created);
      if (!mounted) return;
      setState(() {
        _openNote = note;
        _dirty = false;
        _recentes = NotasRecentes.registrar(note.id);
      });
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel criar a nota: ${e.message}');
    }
  }

  Future<void> _newFolder(VaultFolder folder) async {
    if (!await _garantirSalvo()) return;
    if (!mounted) return;

    final pedido = await showDialog<({String nome, bool tela})>(
      context: context,
      builder: (context) => const _NomeDialog(
        titulo: 'Nova pasta',
        rotulo: 'Nome',
        dica: 'Ex.: Receitas',
        acao: 'Criar',
      ),
    );
    if (pedido == null) return;

    try {
      await _repository.createFolder(folder.id, pedido.nome);
      await _refreshTree();
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel criar a pasta: ${e.message}');
    }
  }

  /// Recebe uma linha arrastada na arvore.
  ///
  /// Um movimento pode ser duas coisas ao mesmo tempo: trocar de pasta (que
  /// mexe no disco) e trocar de posiçao (que so mexe na ordem guardada). Os
  /// dois passos vivem aqui porque um arrasto so, do ponto de vista de quem
  /// usa, tem que valer os dois.
  Future<void> _moverEntrada(
    VaultEntry item,
    VaultFolder destino, {
    VaultEntry? antesDe,
  }) async {
    final raiz = _tree;
    final path = _vaultPath;
    if (raiz == null || path == null) return;

    var id = item.id;
    final trocouDePasta = !p.equals(p.dirname(item.id), destino.id);

    if (trocouDePasta) {
      try {
        id = await _repository.move(item.id, destino.id);
      } on FileSystemException catch (e) {
        _snack('Nao foi possivel mover: ${e.message}');
        return;
      }

      // O caminho da nota aberta muda junto quando ela e a movida, ou quando
      // esta dentro da pasta movida. Sem isso o editor ficaria apontando para
      // um arquivo que nao existe mais naquele lugar.
      final aberta = _openNote?.id;
      if (aberta != null) {
        final novoId = aberta == item.id
            ? id
            : p.isWithin(item.id, aberta)
            ? p.join(id, p.relative(aberta, from: item.id))
            : null;
        if (novoId != null) await _reabrir(novoId);
      }
    }

    // A ordem e por nome, e o nome pode ter ganhado sufixo ao evitar colisao.
    final nome = p.basename(id);
    final nomes = destino.children.map((e) => e.name).toList()
      ..remove(item.name)
      ..remove(nome);

    final alvo = antesDe == null ? -1 : nomes.indexOf(antesDe.name);
    if (alvo < 0) {
      nomes.add(nome);
    } else {
      nomes.insert(alvo, nome);
    }

    final order = _order.comOrdem(
      VaultOrder.chaveDe(destino.id, raiz.id),
      nomes,
    );
    setState(() => _order = order);
    await _repository.saveOrder(path, order);
    await _refreshTree();
  }

  /// Reabre a nota aberta num caminho novo, preservando o texto na tela.
  Future<void> _reabrir(String novoId) async {
    try {
      final note = await _repository.readNote(novoId);
      if (!mounted) return;
      setState(() {
        _openNote = note;
        _dirty = false;
        // A nota pode ter mudado de caminho: sem registrar de novo, a lista de
        // recentes ficaria apontando para um lugar que nao existe mais.
        _recentes = NotasRecentes.registrar(note.id);
      });
    } on FileSystemException {
      if (mounted) setState(() => _openNote = null);
    }
  }

  /// Troca o nome de uma nota ou pasta, sem tirar ela do lugar.
  ///
  /// O nome no disco e a identidade da entrada neste app — nao ha id separado —
  /// entao renomear mexe em tres coisas de uma vez: o arquivo, a ordem manual
  /// (que guarda nomes) e o editor, se a nota aberta for a renomeada ou estiver
  /// dentro da pasta renomeada.
  Future<void> _renomear(VaultEntry entry) async {
    final raiz = _tree;
    final path = _vaultPath;
    if (raiz == null || path == null) return;

    final ehPasta = entry is VaultFolder;
    final atual = ehPasta ? entry.name : p.basenameWithoutExtension(entry.name);

    final pedido = await showDialog<({String nome, bool tela})>(
      context: context,
      builder: (context) => _NomeDialog(
        titulo: ehPasta ? 'Renomear a pasta' : 'Renomear a nota',
        rotulo: 'Nome',
        dica: ehPasta ? 'Ex.: Estudos' : 'Ex.: Aula de calculo',
        acao: 'Renomear',
        inicial: atual,
      ),
    );
    final novo = pedido?.nome;
    if (novo == null || novo.trim().isEmpty || novo.trim() == atual) return;

    final String id;
    try {
      id = await _repository.rename(entry.id, novo.trim());
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel renomear: ${e.message}');
      return;
    }
    if (id == entry.id) return;

    // A ordem guarda nomes, e o nome acabou de mudar: sem isto a entrada
    // renomeada cairia para o fim da pasta, como se nunca tivesse sido
    // arrastada para o lugar onde esta.
    final order = _order.renomeado(
      pasta: VaultOrder.chaveDe(p.dirname(entry.id), raiz.id),
      de: entry.name,
      para: p.basename(id),
      ehPasta: ehPasta,
    );
    setState(() => _order = order);
    await _repository.saveOrder(path, order);

    final aberta = _openNote?.id;
    if (aberta != null) {
      final novoId = aberta == entry.id
          ? id
          : p.isWithin(entry.id, aberta)
          ? p.join(id, p.relative(aberta, from: entry.id))
          : null;
      if (novoId != null) await _reabrir(novoId);
    }

    await _refreshTree();
  }

  /// Apaga uma nota ou uma pasta, depois de confirmar.
  ///
  /// Nao ha desfazer aqui, e por isso o aviso do dialogo e direto: com o
  /// servidor privado no lugar do Drive, nao existe mais uma lixeira na nuvem
  /// atras desta — o que sai daqui sai tambem de la na proxima rodada.
  Future<void> _excluir(VaultEntry entry) async {
    final pasta = entry is VaultFolder ? entry : null;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pasta == null ? 'Excluir a nota?' : 'Excluir a pasta?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pasta == null
                  ? '"${entry.name}" sai do disco.'
                  : '"${entry.name}" sai do disco com tudo que esta dentro '
                        '(${pasta.noteCount} nota(s)).',
            ),
            const SizedBox(height: AppTheme.gapMd),
            Text(
              'A exclusao sobe ao servidor na proxima sincronizacao e o '
              'arquivo some das outras maquinas. Nao ha lixeira: so o backup '
              'do servidor traz de volta.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    try {
      await _repository.delete(entry.id);
      if (!mounted) return;
      // A nota aberta pode ser a que sumiu, ou pode estar dentro da pasta que
      // sumiu: nos dois casos o editor nao pode continuar mostrando ela.
      final aberta = _openNote?.id;
      if (aberta != null &&
          (aberta == entry.id || p.isWithin(entry.id, aberta))) {
        setState(() {
          _openNote = null;
          _dirty = false;
        });
      }
      await _refreshTree();
    } on FileSystemException catch (e) {
      _snack('Nao foi possivel excluir: ${e.message}');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final tree = _tree;

    // Os botoes de recolher so fazem sentido quando ha barra: com o vault
    // fechado, em janela estreita ou fora da aba de notas nao ha o que ocultar.
    final base = tree != null && wide && _view == _View.notas;
    // A esquerda vale mesmo sem painel acoplado: recolher tambem tira a barra
    // de navegaçao, entao sempre ha o que esconder desse lado.
    final podeEsquerda = base;
    final podeDireita = base && _layout.direita.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        titleSpacing: podeEsquerda ? AppTheme.gapSm : AppTheme.gapXl,
        leading: podeEsquerda
            ? Padding(
                padding: const EdgeInsets.only(left: AppTheme.gapMd),
                child: IconButton(
                  icon: Icon(
                    _esquerdaVisivel ? Icons.menu_open : Icons.menu,
                    size: 18,
                  ),
                  tooltip: _esquerdaVisivel
                      ? 'Ocultar a barra da esquerda  (Ctrl+B)'
                      : 'Mostrar a barra da esquerda  (Ctrl+B)',
                  onPressed: () => _alternarBarra(DockSide.esquerda),
                ),
              )
            : null,
        leadingWidth: podeEsquerda ? 56 : null,
        title: Row(
          children: [
            Flexible(
              child: Text(
                _vaultPath == null ? 'Notas' : p.basename(_vaultPath!),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Aparece tambem sem vault aberto: e justamente quando a pasta
            // nao monta que o usuario precisa ver que ha um servidor ali.
            if (_vaultPath != null || _servidor.configurado) ...[
              const SizedBox(width: AppTheme.gapSm),
              _indicadorDoServidor(),
            ],
          ],
        ),
        actions: [
          if (_vaultPath != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 17),
              tooltip: 'Reler o vault do disco',
              onPressed: _refreshTree,
            ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined, size: 17),
            tooltip: 'Trocar a pasta do vault',
            onPressed: _chooseVault,
          ),
          if (podeDireita)
            IconButton(
              icon: Icon(
                _direitaVisivel
                    ? Icons.vertical_split
                    : Icons.vertical_split_outlined,
                size: 17,
              ),
              tooltip: _direitaVisivel
                  ? 'Ocultar a barra da direita  (Ctrl+Shift+B)'
                  : 'Mostrar a barra da direita  (Ctrl+Shift+B)',
              onPressed: () => _alternarBarra(DockSide.direita),
            ),
          const SizedBox(width: AppTheme.gapMd),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: (!wide && tree != null && _view == _View.notas)
          ? Drawer(child: SafeArea(child: _sidebar(tree)))
          : null,
      body: tree == null
          ? _body(wide, tree)
          // Ctrl+B e o atalho consagrado para a barra lateral em editores de
          // nota e de codigo; com Shift ele vale para a barra da direita.
          // `CallbackShortcuts` fica acima do editor de texto para o atalho
          // funcionar mesmo com o cursor dentro da nota.
          : CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyB,
                  control: true,
                ): () {
                  if (podeEsquerda) _alternarBarra(DockSide.esquerda);
                },
                const SingleActivator(
                  LogicalKeyboardKey.keyB,
                  control: true,
                  shift: true,
                ): () {
                  if (podeDireita) _alternarBarra(DockSide.direita);
                },
              },
              child: Focus(
                autofocus: true,
                child: Row(
                  children: [
                    // A barra de navegaçao acompanha a da esquerda: ela fica
                    // encostada ali e sozinha ainda ocuparia uma coluna. Fora
                    // da aba de notas ela fica, senao nao haveria como voltar.
                    if (_esquerdaVisivel || _view != _View.notas) ...[
                      _rail(),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(child: _body(wide, tree)),
                  ],
                ),
              ),
            ),
    );
  }

  /// Como esta a conversa com o servidor, e o menu para agir sobre ela.
  ///
  /// Um controle so, no lugar onde antes ficava o icone do Drive: "esta em
  /// dia?" e "sobe agora" sao a mesma pergunta feita de dois jeitos, e separar
  /// as duas so gastaria mais barra.
  Widget _indicadorDoServidor() {
    final theme = Theme.of(context);
    final apagado = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);
    final onde = _servidor.uri?.host ?? 'o servidor';

    final (IconData icone, Color cor, String recado) = switch (_sync) {
      _Sync.desligado => (
        Icons.cloud_off_outlined,
        apagado,
        'Sem servidor: o vault e so esta pasta.',
      ),
      _Sync.sincronizando => (
        Icons.cloud_sync_outlined,
        theme.colorScheme.primary,
        'Sincronizando com $onde...',
      ),
      _Sync.erro => (
        Icons.cloud_off,
        theme.colorScheme.error,
        _erroDaSync ?? 'A ultima sincronizacao falhou.',
      ),
      _Sync.ocioso => (
        Icons.cloud_done_outlined,
        apagado,
        _ultimaSync == null
            ? 'Ligado a $onde.'
            : 'Em dia com $onde — ultima as ${_hora(_ultimaSync!)}.',
      ),
    };

    return PopupMenuButton<_AcaoDoServidor>(
      tooltip: recado,
      position: PopupMenuPosition.under,
      icon: Icon(icone, size: 15, color: cor),
      iconSize: 15,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 220),
      onSelected: (acao) {
        switch (acao) {
          case _AcaoDoServidor.sincronizar:
            unawaited(_sincronizar(avisar: true));
          case _AcaoDoServidor.configurar:
            unawaited(_configurarServidor());
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _AcaoDoServidor.sincronizar,
          enabled: _servidor.configurado && _sync != _Sync.sincronizando,
          child: const Text('Sincronizar agora'),
        ),
        const PopupMenuItem(
          value: _AcaoDoServidor.configurar,
          child: Text('Configurar o servidor...'),
        ),
      ],
    );
  }

  static String _hora(DateTime q) =>
      '${q.hour.toString().padLeft(2, '0')}:'
      '${q.minute.toString().padLeft(2, '0')}';

  Widget _rail() {
    final theme = Theme.of(context);

    // Material, e nao Container: os itens usam InkWell, e uma cor pintada por
    // cima do Material esconderia o realce do toque.
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SizedBox(
        width: 92,
        height: double.infinity,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: AppTheme.gapMd),
              // Uma lista so. Cada item e a propria coisa: clicar abre, e
              // arrastar leva ela para a barra onde for solta.
              //
              // O aceso marca *onde voce esta*, e nao o que esta acoplado numa
              // barra: um painel na lateral ja se ve na tela, e deixar o item
              // sempre aceso tiraria do realce a unica coisa que ele diz.
              _RailItem(
                key: const ValueKey('rail-item-dashboard'),
                icone: _View.dashboard.icon,
                iconeAtivo: _View.dashboard.iconSelecionado,
                rotulo: _View.dashboard.label,
                ativo: _view == _View.dashboard,
                painel: PanelKind.dashboard,
                onDragChanged: _arrastoMudou,
                onTap: () => _switchTo(_View.dashboard),
                dica: 'O dia de hoje e o resumo de tudo que esta no vault',
              ),
              _RailItem(
                key: const ValueKey('rail-item-notas'),
                icone: _View.notas.icon,
                iconeAtivo: _View.notas.iconSelecionado,
                rotulo: _View.notas.label,
                ativo: _view == _View.notas,
                onTap: () => _switchTo(_View.notas),
                dica: 'A nota aberta, sempre no centro da tela',
              ),
              _RailItem(
                key: const ValueKey('rail-item-arquivos'),
                icone: PanelKind.arquivos.icon,
                iconeAtivo: Icons.folder,
                rotulo: PanelKind.arquivos.label,
                // A arvore e a excecao: ela nao tem aba propria, so existe
                // acoplada, entao aqui o aceso e mesmo "esta aberta".
                ativo: _layout.contains(PanelKind.arquivos),
                painel: PanelKind.arquivos,
                onDragChanged: _arrastoMudou,
                onTap: () => _alternarPainel(PanelKind.arquivos),
                dica: 'Arraste para o lado onde quer a arvore do vault',
              ),
              _RailItem(
                key: const ValueKey('rail-item-calendario'),
                icone: _View.calendario.icon,
                iconeAtivo: _View.calendario.iconSelecionado,
                rotulo: _View.calendario.label,
                ativo: _view == _View.calendario,
                painel: PanelKind.calendario,
                onDragChanged: _arrastoMudou,
                onTap: () => _switchTo(_View.calendario),
                dica:
                    'Clique para abrir no centro, arraste para acoplar '
                    'numa barra',
              ),
              _RailItem(
                key: const ValueKey('rail-item-grafo'),
                icone: _View.grafo.icon,
                iconeAtivo: _View.grafo.iconSelecionado,
                rotulo: _View.grafo.label,
                ativo: _view == _View.grafo,
                painel: PanelKind.grafo,
                onDragChanged: _arrastoMudou,
                onTap: () => _switchTo(_View.grafo),
                dica:
                    'Clique para abrir no centro, arraste para acoplar '
                    'numa barra',
              ),
              _RailItem(
                key: const ValueKey('rail-item-kanban'),
                icone: _View.kanban.icon,
                iconeAtivo: _View.kanban.iconSelecionado,
                rotulo: _View.kanban.label,
                ativo: _view == _View.kanban,
                painel: PanelKind.kanban,
                onDragChanged: _arrastoMudou,
                onTap: () => _switchTo(_View.kanban),
                dica:
                    'Clique para abrir no centro, arraste para acoplar '
                    'numa barra',
              ),
              _RailItem(
                key: const ValueKey('rail-item-email'),
                icone: _View.email.icon,
                iconeAtivo: _View.email.iconSelecionado,
                rotulo: _View.email.label,
                ativo: _view == _View.email,
                painel: PanelKind.email,
                onDragChanged: _arrastoMudou,
                onTap: () => _switchTo(_View.email),
                dica:
                    'Clique para abrir no centro, arraste para acoplar '
                    'numa barra',
              ),
              const SizedBox(height: AppTheme.gapMd),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(bool wide, VaultFolder? tree) {
    // O e-mail vem antes de tudo: e o unico painel que nao sai do vault, entao
    // funciona mesmo com o vault fechado ou ilegivel.
    if (_viewAtual == _View.email) return _painelDeEmail();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        title: 'Erro ao ler o vault',
        detail: _error!,
        actionLabel: 'Escolher outra pasta',
        onAction: _chooseVault,
      );
    }
    if (tree == null) {
      // Com servidor configurado a tela vazia muda de assunto. Quem chega aqui
      // com as notas ja no servidor — maquina nova, pasta que nao montou —
      // precisa saber que basta apontar um lugar e elas descem. Sem isto o app
      // pede "a pasta de arquivos .md" para alguem que, nesta maquina, nao tem
      // nenhum, e nao ha nada na tela dizendo que o servidor resolve.
      final noServidor = _servidor.configurado;
      return _CenteredMessage(
        icon: noServidor
            ? Icons.cloud_download_outlined
            : Icons.folder_special_outlined,
        title: noServidor
            ? 'Escolha onde guardar as notas'
            : 'Escolha a pasta do vault',
        detail: noServidor
            ? 'Suas notas estao em ${_servidor.uri?.host}. Escolha uma pasta '
                  'nesta maquina — pode estar vazia — e elas descem na '
                  'primeira sincronizacao. Uma pasta que ja tenha .md tambem '
                  'serve: os dois lados se juntam, e nada e descartado.'
            : 'Aponte para a pasta de arquivos .md. Os arquivos continuam '
                  'sendo a fonte da verdade — o app so le e grava neles, e o '
                  'servidor privado, se configurado, mantem as outras '
                  'maquinas iguais.',
        actionLabel: noServidor ? 'Escolher pasta e baixar' : 'Escolher pasta',
        onAction: _chooseVault,
      );
    }

    // Fora da aba de notas o painel escolhido ocupa a tela inteira, sem barras.
    if (_viewAtual == _View.dashboard) {
      return _conteudoDoPainel(PanelKind.dashboard, tree);
    }
    if (_viewAtual == _View.calendario) {
      return _conteudoDoPainel(PanelKind.calendario, tree);
    }
    if (_viewAtual == _View.grafo) {
      return _conteudoDoPainel(PanelKind.grafo, tree);
    }
    if (_viewAtual == _View.kanban) {
      return _conteudoDoPainel(PanelKind.kanban, tree);
    }

    // Em janela estreita a arvore vive num Drawer e nao ha barras laterais.
    if (!wide) return _editorArea();

    return _comBarras(tree);
  }

  /// Monta o centro fixo com as barras laterais em volta.
  ///
  /// A ordem importa: a barra da direita e aninhada primeiro para o divisor
  /// dela medir o centro, e a da esquerda envolve o conjunto.
  Widget _comBarras(VaultFolder tree) {
    Widget centro = _editorArea();

    if (_barraAtiva(DockSide.direita)) {
      centro = ResizableSplit(
        storageKey: 'barra.direita',
        initialSecond: 320,
        minFirst: 300,
        minSecond: 200,
        first: centro,
        second: _dock(DockSide.direita, tree),
      );
    }
    if (_barraAtiva(DockSide.esquerda)) {
      centro = ResizableSplit(
        storageKey: 'sidebar',
        initialFirst: 268,
        minFirst: 180,
        minSecond: 320,
        first: _dock(DockSide.esquerda, tree),
        second: centro,
      );
    }

    final arrastando = _arrastando != null;
    return Row(
      // Estica para as faixas de encaixe ocuparem a altura toda sem precisarem
      // declarar altura infinita.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (arrastando && !_barraAtiva(DockSide.esquerda))
          EmptyDockTarget(
            side: DockSide.esquerda,
            onSoltar: (painel) => _moverPainel(painel, DockSide.esquerda),
          ),
        Expanded(child: centro),
        if (arrastando && !_barraAtiva(DockSide.direita))
          EmptyDockTarget(
            side: DockSide.direita,
            onSoltar: (painel) => _moverPainel(painel, DockSide.direita),
          ),
      ],
    );
  }

  Widget _dock(DockSide side, VaultFolder tree) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: _pilha(_layout.of(side), side, tree),
    );
  }

  /// Empilha os paineis de uma barra, um divisor arrastavel entre cada par.
  ///
  /// Com dois paineis a barra nasce meio a meio; com tres, em tres faixas. A
  /// chave de persistencia inclui quantos paineis restam para o tamanho
  /// guardado nao ser aplicado a uma divisao diferente.
  Widget _pilha(List<PanelKind> paineis, DockSide side, VaultFolder tree) {
    final primeiro = _fatia(paineis.first, side, tree);
    if (paineis.length == 1) return primeiro;

    return ResizableSplit(
      axis: Axis.vertical,
      storageKey: 'dock.${side.name}.${paineis.length}',
      minFirst: 120,
      minSecond: 120,
      first: primeiro,
      second: _pilha(paineis.sublist(1), side, tree),
    );
  }

  Widget _fatia(PanelKind painel, DockSide side, VaultFolder tree) {
    return PanelDropSlot(
      onSoltar: (PanelKind largado, {required bool antes}) => _moverPainel(
        largado,
        side,
        antesDe: antes ? painel : _abaixoDe(painel, side),
      ),
      child: Column(
        children: [
          PanelHeader(
            key: ValueKey('cabecalho-${painel.name}'),
            painel: painel,
            onDragChanged: _arrastoMudou,
            onOcultar: () => _fecharPainel(painel),
          ),
          const Divider(height: 1),
          Expanded(child: _conteudoDoPainel(painel, tree)),
        ],
      ),
    );
  }

  Widget _conteudoDoPainel(PanelKind painel, VaultFolder tree) {
    switch (painel) {
      case PanelKind.arquivos:
        return _sidebar(tree);

      case PanelKind.calendario:
        if (_loadingEvents) {
          return const Center(child: CircularProgressIndicator());
        }
        return CalendarScreen(
          events: _events,
          onOpenNote: _openNoteById,
          onRefresh: _loadEvents,
        );

      case PanelKind.grafo:
        final graph = _graph;
        if (_loadingGraph || graph == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return GraphScreen(
          graph: graph,
          onOpenNote: _openNoteById,
          onRefresh: _loadGraph,
        );

      case PanelKind.kanban:
        if (_loadingBoard) {
          return const Center(child: CircularProgressIndicator());
        }
        return KanbanScreen(
          board: _board,
          onMover: _moverCard,
          onOpenNote: _openNoteById,
          onRefresh: _loadBoard,
          onNovoCard: _novoCard,
        );

      case PanelKind.email:
        return _painelDeEmail();

      case PanelKind.dashboard:
        if (_loadingPainel) {
          return const Center(child: CircularProgressIndicator());
        }
        return DashboardScreen(
          dados: _painel,
          atividade: _atividade,
          recentes: _notasRecentes(tree),
          onOpenNote: _openNoteById,
          onAlternarTarefa: _alternarTarefaDoPainel,
          onRefresh: _loadPainel,
        );
    }
  }

  /// As ultimas notas abertas que ainda existem no vault.
  ///
  /// A lista guardada e so de caminhos: uma nota apagada ou renomeada por fora
  /// continua la, e abrir um caminho morto do painel daria erro sem motivo.
  List<NotaRecente> _notasRecentes(VaultFolder tree) {
    final existentes = {for (final f in CalendarService.filesIn(tree)) f.id};
    return [
      for (final id in _recentes)
        if (existentes.contains(id)) NotaRecente(id),
    ];
  }

  Widget _painelDeEmail() => EmailScreen(
    conta: _conta,
    mensagens: _emails,
    carregando: _loadingEmails,
    erro: _erroEmail,
    entrando: _entrandoComGoogle,
    onRefresh: _loadEmails,
    onConta: _acaoDeConta,
  );

  Widget _sidebar(VaultFolder tree) {
    return NoteTree(
      root: tree,
      selectedId: _openNote?.id,
      onFileTap: (file) {
        _openFile(file);
        // Em janela estreita a arvore esta num Drawer: fecha ao escolher.
        if (MediaQuery.sizeOf(context).width < _wideBreakpoint) {
          Navigator.of(context).maybePop();
        }
      },
      onNewNoteInFolder: _newNote,
      onNewFolderIn: _newFolder,
      onDelete: _excluir,
      onRenomear: _renomear,
      onMover: _moverEntrada,
    );
  }

  Widget _editorArea() {
    final note = _openNote;
    if (note == null) {
      return _CenteredMessage(
        icon: Icons.description_outlined,
        title: 'Nenhuma nota aberta',
        detail: _layout.contains(PanelKind.arquivos)
            ? 'Escolha uma nota na arvore do vault, ou crie uma nova pelo '
                  'icone de nota na pasta desejada.'
            : 'O painel de arquivos esta fechado. Abra ele pelo icone de '
                  'pasta na barra da esquerda, ou arraste o icone para o lado '
                  'onde voce quer a arvore.',
      );
    }
    return NoteEditor(
      key: _editorKey,
      note: note,
      notasDoVault: _titulosDoVault(note.id),
      onAbrirLink: _abrirPorTitulo,
      onSave: _saveNote,
      onDirtyChanged: (dirty) => setState(() => _dirty = dirty),
      onSugerirTags: _tagsDoVault,
    );
  }

  /// As tags ja usadas em alguma nota do vault, para a ficha sugerir no `+`.
  ///
  /// Reaproveita o grafo se ele ja tiver sido montado (quem visitou a aba
  /// Grafo nesta sessao); senao le o vault agora, do mesmo jeito que o grafo
  /// leria. So paga essa releitura quem realmente clicar no `+`.
  Future<List<String>> _tagsDoVault() async {
    final tree = _tree;
    if (tree == null) return const [];

    var graph = _graph;
    if (graph == null) {
      graph = await _graphService.build(tree);
      if (!mounted) return const [];
      setState(() {
        _graph = graph;
        _grafoPronto = true;
      });
    }

    return [for (final tag in graph.tags) tag.label]..sort();
  }

  /// Abre a nota apontada por um `[[link]]` do preview.
  ///
  /// A busca e pelo titulo sem diferenciar maiusculas, a mesma regra que o
  /// grafo usa para ligar as notas — se o link vale uma aresta la, tem que
  /// abrir a nota aqui.
  Future<void> _abrirPorTitulo(String titulo) async {
    final tree = _tree;
    if (tree == null) return;

    final alvo = titulo.trim().toLowerCase();
    for (final arquivo in CalendarService.filesIn(tree)) {
      if (arquivo.title.toLowerCase() == alvo) {
        await _openNoteById(arquivo.id);
        return;
      }
    }

    // Link para nota que ainda nao existe. O grafo tambem o ignora; aqui ao
    // menos se diz por que o clique nao levou a lugar nenhum.
    _snack('Nao ha nota chamada "$titulo" no vault.');
  }

  /// Titulos das outras notas, para o autocompletar de `[[` no editor.
  ///
  /// Sai da arvore que ja esta em memoria — nenhum arquivo e lido para isso. A
  /// propria nota fica de fora: um link para ela mesma nao leva a lugar nenhum,
  /// e o grafo ja o descarta.
  List<String> _titulosDoVault(String abertaId) {
    final tree = _tree;
    if (tree == null) return const [];

    return [
      for (final arquivo in CalendarService.filesIn(tree))
        if (arquivo.id != abertaId) arquivo.title,
    ];
  }
}

/// Item da barra de navegaçao.
///
/// Um item so faz as duas coisas: clicar abre o que ele representa, e arrastar
/// leva esse mesmo conteudo para a barra onde for solto. Nao ha lista separada
/// de "paineis" — o painel e o proprio item.
class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.icone,
    required this.iconeAtivo,
    required this.rotulo,
    required this.ativo,
    required this.onTap,
    required this.dica,
    this.painel,
    this.onDragChanged,
  });

  final IconData icone;
  final IconData iconeAtivo;
  final String rotulo;

  /// Em destaque: ou e a aba aberta, ou e um painel acoplado em alguma barra.
  final bool ativo;

  final VoidCallback onTap;
  final String dica;

  /// Preenchido quando o item pode virar painel. Nulo no item das notas, que e
  /// o centro fixo e nao se move.
  final PanelKind? painel;

  final ValueChanged<PanelKind?>? onDragChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final corpo = Tooltip(
      message: dica,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.gapSm,
            horizontal: AppTheme.gapXs,
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 28,
                decoration: BoxDecoration(
                  color: ativo ? scheme.primaryContainer : null,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  ativo ? iconeAtivo : icone,
                  size: 18,
                  color: ativo ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppTheme.gapXs),
              Text(
                rotulo,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: ativo ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontWeight: ativo ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final kind = painel;
    if (kind == null || onDragChanged == null) return corpo;

    return PanelDraggable(
      painel: kind,
      onDragChanged: onDragChanged!,
      child: corpo,
    );
  }
}

/// Dialogo de nome unico, usado para criar nota e pasta.
class _NomeDialog extends StatefulWidget {
  const _NomeDialog({
    required this.titulo,
    required this.rotulo,
    required this.dica,
    required this.acao,
    this.inicial,
    this.ofereceTela = false,
  });

  final String titulo;
  final String rotulo;
  final String dica;
  final String acao;

  /// Nome que ja existe, para renomear partir dele em vez de de um campo em
  /// branco.
  final String? inicial;

  /// Se este dialogo pergunta tambem que *tipo* de nota criar.
  ///
  /// Aqui, junto do nome, e nao num terceiro botao na arvore de arquivos: a
  /// arvore ja tem dois botoes por pasta, e o terceiro faria a linha de cada
  /// pasta virar uma barra de ferramentas. E a escolha e da mesma conversa —
  /// "uma nota nova, chamada assim, deste tipo".
  final bool ofereceTela;

  @override
  State<_NomeDialog> createState() => _NomeDialogState();
}

class _NomeDialogState extends State<_NomeDialog> {
  late final _controller = TextEditingController(text: widget.inicial ?? '')
    // Nome inteiro selecionado: digitar troca tudo, e as setas mantem o texto
    // para quem so quer corrigir uma letra.
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.inicial?.length ?? 0,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Se o que se esta criando e uma tela de desenho.
  bool _tela = false;

  void _submit() =>
      Navigator.pop(context, (nome: _controller.text, tela: _tela));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.rotulo,
              hintText: widget.dica,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.ofereceTela) ...[
            const SizedBox(height: AppTheme.gapLg),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.description_outlined, size: 15),
                  label: Text('Texto'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.gesture, size: 15),
                  label: Text('Tela'),
                ),
              ],
              selected: {_tela},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (escolha) =>
                  setState(() => _tela = escolha.first),
            ),
            const SizedBox(height: AppTheme.gapXs),
            Text(
              _tela
                  ? 'Uma area de desenho sem fim, que ocupa a nota inteira.'
                  : 'Uma nota de Markdown, com preview ao lado.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.acao)),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icone contido num quadro suave em vez de solto e grande: pesa
              // menos na tela e nao rouba atençao do texto.
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: scheme.outline),
                ),
                child: Icon(icon, size: 24, color: scheme.primary),
              ),
              const SizedBox(height: AppTheme.gapXl),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppTheme.gapSm),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppTheme.gapXl),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.folder_open_outlined, size: 16),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
