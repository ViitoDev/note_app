import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/excalidraw.dart';
import '../models/quadro_da_nota.dart';
import '../models/wikilink.dart';
import 'app_theme.dart';
import 'desenho_do_quadro.dart';

/// Abre o quadro numa tela so, para desenhar com espaço.
///
/// Dentro da nota o quadro e um cartao pequeno, do tamanho de um paragrafo —
/// bom para lembrar o que ele diz, apertado para mexer. E aqui que se mexe.
///
/// Cada mudança sobe na hora por [onMudar]: fechar a tela nao e "salvar", e o
/// `.md` nunca fica atrasado em relaçao ao que esta na tela.
Future<void> abrirQuadro(
  BuildContext context, {
  required QuadroDaNota quadro,
  required ValueChanged<QuadroDaNota> onMudar,
  String titulo = 'Quadro',
}) {
  return showDialog<void>(
    context: context,
    // Sem barreira para clicar fora: a tela ocupa tudo, e um clique perdido no
    // meio do desenho nao pode fechar o que se esta construindo.
    barrierDismissible: false,
    builder: (_) =>
        QuadroTelaCheia(quadro: quadro, onMudar: onMudar, titulo: titulo),
  );
}

/// O que um gesto pega num ponto da area, do alvo mais fino ao mais largo.
///
/// O traço vem antes da caixa porque esta por cima dela — e porque e um alvo
/// de dois pixels de largura contra uma caixa do tamanho de um paragrafo: se a
/// caixa ganhasse, um risco feito em cima dela nao poderia mais ser pego.
enum _Pegavel { canto, ancora, traco, caixa, nada }

/// O que a mao esta segurando: o que um arrasto na area vazia vai fazer.
///
/// Uma ferramenta de cada vez, como numa mesa de desenho. O quadro nasceu so
/// com a seta — arrastar era sempre mover ou passear —, e nao da para enfiar
/// caneta e borracha nisso sem alguem dizer qual das tres esta na mao.
enum _Ferramenta {
  /// Selecionar, mover, redimensionar, ligar e passear: tudo o que o quadro ja
  /// fazia antes de existir caneta.
  seta,

  caneta,
  reta,
  setaLivre,

  /// Escrever solto: um clique na area e o cursor, sem caixa nenhuma em volta.
  ///
  /// E a forma [FormaDoNo.texto], que ja existia mas so nascia pelo botao de
  /// criar — e ai nascia com o tamanho de uma caixa, no meio da area, como se
  /// fosse mais um passo do fluxo. Escrever solto e outro gesto: aponta-se o
  /// lugar e escreve-se ali.
  texto,

  borracha;

  /// Se esta ferramenta desenha um traço novo.
  bool get desenha => this == caneta || this == reta || this == setaLivre;

  TipoDoTraco get tipoDoTraco => switch (this) {
    _Ferramenta.reta => TipoDoTraco.reta,
    _Ferramenta.setaLivre => TipoDoTraco.seta,
    _ => TipoDoTraco.livre,
  };

  String get rotulo => switch (this) {
    _Ferramenta.seta => 'Selecionar',
    _Ferramenta.caneta => 'Caneta',
    _Ferramenta.reta => 'Reta',
    _Ferramenta.setaLivre => 'Seta solta',
    _Ferramenta.texto => 'Escrever solto',
    _Ferramenta.borracha => 'Borracha',
  };

  IconData get icone => switch (this) {
    _Ferramenta.seta => Icons.near_me_outlined,
    _Ferramenta.caneta => Icons.gesture,
    _Ferramenta.reta => Icons.horizontal_rule,
    _Ferramenta.setaLivre => Icons.north_east,
    _Ferramenta.texto => Icons.text_fields,
    // O conjunto de icones do Material nao tem borracha; a vassourinha e o
    // que mais se parece com passar a mao por cima para limpar.
    _Ferramenta.borracha => Icons.cleaning_services_outlined,
  };

  /// A tecla que chama esta ferramenta, como em qualquer programa de desenho.
  String get tecla => switch (this) {
    _Ferramenta.seta => 'v',
    _Ferramenta.caneta => 'c',
    _Ferramenta.reta => 'r',
    _Ferramenta.setaLivre => 'f',
    _Ferramenta.texto => 't',
    _Ferramenta.borracha => 'b',
  };
}

class QuadroTelaCheia extends StatefulWidget {
  const QuadroTelaCheia({
    super.key,
    required this.quadro,
    required this.onMudar,
    this.titulo = 'Quadro',
    this.emJanela = true,
    this.somenteLeitura = false,
    this.onAbrirNota,
  });

  final QuadroDaNota quadro;
  final ValueChanged<QuadroDaNota> onMudar;
  final String titulo;

  /// Se esta tela e um dialogo por cima do app, com um X para fechar.
  ///
  /// Falsa quando o quadro *e* a nota aberta: ai ele nao esta por cima de nada
  /// — ele e o conteudo do editor, e fechar ele seria fechar a nota, que e
  /// coisa da arvore de arquivos e nao daqui.
  final bool emJanela;

  /// Se o desenho so pode ser olhado.
  ///
  /// Verdadeiro para os `.excalidraw` do vault. Regravar um arquivo desses
  /// daqui apagaria dele tudo o que este app nao entende — a rotaçao, o
  /// tracejado, as imagens —, e quem guardou aquele arquivo no vault nao pediu
  /// isso ao abrir para ver. Para mexer, copia-se o desenho para dentro de uma
  /// nota.
  final bool somenteLeitura;

  /// Chamado ao abrir uma caixa que e um `[[link]]` para outra nota.
  ///
  /// Nulo quando nao ha vault por perto — no cartao dentro do editor, por
  /// exemplo. Sem ele o link continua desenhado como link, mas duplo clique
  /// volta a ser "escrever nesta caixa".
  final ValueChanged<String>? onAbrirNota;

  @override
  State<QuadroTelaCheia> createState() => _QuadroTelaCheiaState();
}

class _QuadroTelaCheiaState extends State<QuadroTelaCheia> {
  /// O quadro como esta agora na tela.
  ///
  /// Fica aqui, e nao so no arquivo, por causa do arrasto: enquanto a caixa
  /// esta sendo arrastada, cada quadro de animaçao mexeria no texto da nota
  /// inteira. O texto recebe o resultado quando a mao solta.
  late QuadroDaNota _quadro = widget.quadro;

  /// A camera: onde a origem do quadro cai na tela, e o zoom.
  Offset _pan = Offset.zero;
  double _escala = 1;

  Size _area = Size.zero;

  /// Se a area de desenho ja foi medida alguma vez. E a primeira medida que
  /// enquadra o quadro; as seguintes sao so a janela mudando de tamanho.
  bool _medido = false;

  String? _selecionado;
  int? _ligacaoSelecionada;
  String? _tracoSelecionado;

  /// O que a mao esta segurando, e com que tinta.
  ///
  /// A ferramenta volta sozinha para a seta depois de um traço, como no
  /// Excalidraw: desenhar uma seta e logo querer arrasta-la para o lugar e o
  /// que acontece nove vezes em dez, e sem a volta automatica cada traço
  /// custaria um clique a mais na barra. A caneta e a borracha ficam na mao —
  /// essas duas quase nunca sao usadas uma vez so.
  _Ferramenta _ferramenta = _Ferramenta.seta;
  CorDoTraco _cor = CorDoTraco.tinta;
  double _grossura = TracoDoQuadro.grossuraPadrao;

  /// O traço que a caneta esta fazendo agora, ainda fora do quadro.
  TracoDoQuadro? _tracando;

  /// Onde a borracha esta, enquanto ela esta na area.
  Offset? _borrachaEm;

  /// O raio da borracha, em pixels do quadro. Generoso: apagar um risco fino
  /// nao pode ser um exercicio de pontaria.
  static const _raioDaBorracha = 12.0;

  /// A caixa sob o ponteiro. E ela que mostra as bolinhas de ligar antes de
  /// qualquer clique.
  String? _emFoco;

  /// O que esta debaixo do ponteiro agora — o que um arrasto daqui pegaria.
  _Pegavel _sobre = _Pegavel.nada;

  /// O ponto de ligar que o ponteiro esta mirando, para ele acender sozinho.
  Offset? _ancoraEmFoco;

  /// O que a mao esta fazendo agora. Um de cada vez, por construçao: quem
  /// começa um arrasto decide ali qual dos tres e.
  String? _movendo;
  String? _redimensionando;
  ({String de, Offset ponto})? _ligando;

  /// O traço que esta sendo arrastado, e onde ele estava quando a mao pegou.
  String? _movendoTraco;
  ({Offset ponteiro, TracoDoQuadro traco})? _pegadaDoTraco;

  /// Onde a mao pegou e como a caixa estava naquele instante. E o ponto de
  /// referencia do arrasto inteiro.
  ({Offset ponteiro, NoDoQuadro no})? _pegada;

  /// Por onde passa o alinhamento em que a caixa arrastada encostou. So
  /// enquanto o arrasto dura.
  ({double? x, double? y})? _guias;

  /// Quando e onde foi o ultimo clique, para reconhecer o duplo.
  ({DateTime quando, Offset onde})? _ultimoClique;

  /// Dois cliques dentro desta janela, e a menos de [_pertoDoDuplo] um do
  /// outro, sao um duplo clique. Os numeros sao os do sistema.
  static const _janelaDoDuplo = Duration(milliseconds: 320);
  static const _pertoDoDuplo = 40.0;

  /// A caixa cujo texto esta sendo digitado, com o campo por cima dela.
  String? _editando;
  TextEditingController? _campo;
  FocusNode? _focoDoCampo;

  /// O rotulo da flecha selecionada.
  TextEditingController? _campoDoRotulo;

  final _foco = FocusNode();

  /// Uma linha de aviso no pe da area, e o relogio que a apaga.
  ///
  /// Aqui, e nao numa `SnackBar`: a tela cheia e um dialogo por cima de tudo, e
  /// a barra de recados do app aparece na tela que ficou embaixo — ou seja,
  /// escondida justamente de quem precisava ler o aviso.
  String? _recado;
  Timer? _tempoDoRecado;

  @override
  void dispose() {
    _campo?.dispose();
    _focoDoCampo?.dispose();
    _campoDoRotulo?.dispose();
    _tempoDoRecado?.cancel();
    _foco.dispose();
    super.dispose();
  }

  void _avisar(String texto) {
    setState(() => _recado = texto);
    _tempoDoRecado?.cancel();
    _tempoDoRecado = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _recado = null);
    });
  }

  /// Leva a mudança ao texto da nota. Chamado nos pontos de descanso — soltar
  /// a caixa, escrever uma letra, criar ou apagar algo —, nao a cada pixel.
  void _mudou() => widget.onMudar(_quadro);

  /// Se esta tela so pode ser olhada.
  ///
  /// Perguntado nos poucos pontos por onde *toda* mudança passa — [_mexer] e o
  /// começo de cada gesto —, e nao em cada botao: um botao esquecido seria um
  /// caminho aberto para gravar por cima de um arquivo que nao e nosso.
  bool get _travado => widget.somenteLeitura;

  void _mexer(QuadroDaNota novo, {bool avisar = true}) {
    if (_travado) return;
    setState(() => _quadro = novo);
    if (avisar) _mudou();
  }

  Offset _paraQuadro(Offset tela) => (tela - _pan) / _escala;

  // -------------------------------------------------------------- desfazer

  /// O quadro antes de cada mexida, do mais antigo para o mais recente.
  ///
  /// Nasceu com a caneta. Mover uma caixa para o lugar errado se conserta
  /// movendo ela de volta; um risco de dois segundos por cima do desenho, nao —
  /// e uma borracha sem desfazer e uma faca sem cabo. O quadro inteiro por
  /// passo, e nao a descriçao da mudança: sao algumas dezenas de caixas, o
  /// custo e desprezivel, e nao ha como um passo "desfazer errado".
  final _desfazer = <QuadroDaNota>[];
  final _refazer = <QuadroDaNota>[];

  /// Quantos passos ficam guardados. O bastante para voltar de um engano; nao
  /// tanto que o app carregue o dia inteiro de rascunho na memoria.
  static const _passosGuardados = 80;

  /// Marca o começo de uma mexida. Chamado *antes* de mexer, e uma vez por
  /// gesto — nao uma vez por pixel de arrasto.
  void _guardar() {
    _desfazer.add(_quadro);
    if (_desfazer.length > _passosGuardados) _desfazer.removeAt(0);
    _refazer.clear();
  }

  void _voltarPara(QuadroDaNota quadro, List<QuadroDaNota> paraOnde) {
    _pararDeEditar();
    paraOnde.add(_quadro);

    setState(() {
      _quadro = quadro;
      // A seleçao nao sobrevive: ela pode apontar para uma caixa que este passo
      // acabou de trazer de volta — ou de levar embora.
      _selecionado = null;
      _tracoSelecionado = null;
      _ligacaoSelecionada = null;
      _rotuloEm(null);
    });

    _mudou();
    _foco.requestFocus();
  }

  void _desfazerPasso() {
    if (_desfazer.isEmpty) return;
    _voltarPara(_desfazer.removeLast(), _refazer);
  }

  void _refazerPasso() {
    if (_refazer.isEmpty) return;
    _voltarPara(_refazer.removeLast(), _desfazer);
  }

  // ---------------------------------------------------------------- camera

  void _zoom(double fator, [Offset? emTorno]) {
    final foco = emTorno ?? Offset(_area.width / 2, _area.height / 2);
    final antes = _paraQuadro(foco);

    setState(() {
      _escala = (_escala * fator).clamp(0.2, 3.0);
      // O ponto do quadro que estava debaixo do ponteiro continua debaixo
      // dele: e o que faz o zoom parecer aproximaçao, e nao salto.
      _pan = foco - antes * _escala;
    });
  }

  void _enquadrar() {
    final visao = DesenhoDoQuadro.enquadrar(
      DesenhoDoQuadro.limitesDe(_quadro),
      _area,
    );
    setState(() {
      _pan = visao.pan;
      _escala = visao.escala;
    });
  }

  // ------------------------------------------------------------- seleçao

  void _selecionarNo(String? id) {
    setState(() {
      _selecionado = id;
      _ligacaoSelecionada = null;
      _tracoSelecionado = null;
      _rotuloEm(null);
    });
    _foco.requestFocus();
  }

  void _selecionarLigacao(int? indice) {
    setState(() {
      _ligacaoSelecionada = indice;
      _selecionado = null;
      _tracoSelecionado = null;
      _rotuloEm(indice);
    });
    _foco.requestFocus();
  }

  void _selecionarTraco(String? id) {
    setState(() {
      _tracoSelecionado = id;
      _selecionado = null;
      _ligacaoSelecionada = null;
      _rotuloEm(null);
    });
    _foco.requestFocus();
  }

  /// Nada selecionado: o estado em que o Delete nao apaga nada e o Esc nao tem
  /// mais camada para desfazer.
  void _limparSelecao() {
    setState(() {
      _selecionado = null;
      _ligacaoSelecionada = null;
      _tracoSelecionado = null;
      _rotuloEm(null);
    });
  }

  bool get _temSelecao =>
      _selecionado != null ||
      _ligacaoSelecionada != null ||
      _tracoSelecionado != null;

  /// Acerta o campo do rotulo para a flecha [indice], ou o descarta.
  void _rotuloEm(int? indice) {
    // O antigo so e solto depois do quadro: neste ponto o campo dele ainda
    // esta montado, e soltar agora derrubaria o widget vivo.
    _soltarDepois(_campoDoRotulo);
    _campoDoRotulo = indice == null || indice >= _quadro.ligacoes.length
        ? null
        : TextEditingController(text: _quadro.ligacoes[indice].rotulo);
  }

  static void _soltarDepois(ChangeNotifier? velho) {
    if (velho == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => velho.dispose());
  }

  void _excluirSelecao() {
    final no = _selecionado;
    final ligacao = _ligacaoSelecionada;
    final traco = _tracoSelecionado;

    if (no != null) {
      _pararDeEditar();
      _guardar();
      setState(() => _selecionado = null);
      _mexer(_quadro.semNo(no));
      return;
    }
    if (ligacao != null) {
      _guardar();
      setState(() {
        _ligacaoSelecionada = null;
        _rotuloEm(null);
      });
      _mexer(_quadro.semLigacao(ligacao));
      return;
    }
    if (traco != null) {
      _guardar();
      setState(() => _tracoSelecionado = null);
      _mexer(_quadro.semTraco(traco));
    }
  }

  // -------------------------------------------------------------- caixas

  /// Cria uma caixa e ja abre o cursor dentro dela — como numa planilha, onde
  /// a celula nova nasce pronta para receber texto.
  void _novaCaixa(FormaDoNo forma, [Offset? onde]) {
    final tamanho = forma.tamanhoInicial;

    // Sem lugar pedido, a caixa nova nasce embaixo da que esta selecionada e
    // no eixo dela — que e como um fluxo cresce, um passo abaixo do outro.
    //
    // E o alinhamento nasce junto: a caixa criada logo depois de outra ja sai
    // com o centro no mesmo lugar, entao a flecha entre as duas sai reta sem
    // ninguem precisar acertar isso com a mao. Sem caixa selecionada, o lugar
    // e o meio do que se esta vendo.
    // O painel nao entra nessa conta: ele nao e um passo do fluxo, e sim o
    // cenario em volta de passos que ja existem. Nasce no meio do que se esta
    // vendo, por cima do que estiver ali — cobrir e o serviço dele.
    // Com lugar pedido — o duplo clique na area —, e ali e ponto final.
    final anterior = forma.eFundo || onde != null || _selecionado == null
        ? null
        : _quadro.no(_selecionado!);

    final centro =
        onde ??
        (anterior == null
            ? _paraQuadro(Offset(_area.width / 2, _area.height / 2))
            : Offset(
                anterior.centroX,
                anterior.y +
                    anterior.altura +
                    DesenhoDoQuadro.respiro +
                    tamanho.altura / 2,
              ));

    // Alinhada com a anterior, o centro manda mais que a malha.
    final pedido = anterior == null
        ? Offset(
            _naMalha(centro.dx - tamanho.largura / 2),
            _naMalha(centro.dy - tamanho.altura / 2),
          )
        : Offset(
            centro.dx - tamanho.largura / 2,
            _naMalha(centro.dy - tamanho.altura / 2),
          );

    final canto = forma.eFundo
        ? pedido
        : _lugarLivre(
            pedido,
            Size(tamanho.largura, tamanho.altura),
            // Embaixo da anterior, o desvio e so para baixo: de lado ele
            // desfaria o alinhamento que acabou de ser dado a caixa.
            passo: anterior == null
                ? const Offset(
                    DesenhoDoQuadro.malha * 3,
                    DesenhoDoQuadro.malha * 3,
                  )
                : const Offset(0, DesenhoDoQuadro.malha * 3),
          );

    final no = NoDoQuadro(
      id: _quadro.idLivre,
      forma: forma,
      x: canto.dx,
      y: canto.dy,
      largura: tamanho.largura,
      altura: tamanho.altura,
    );

    _guardar();
    _mexer(_quadro.comNo(no));
    _selecionarNo(no.id);
    // Sem guardar de novo: criar a caixa e começar a escrever nela sao o mesmo
    // gesto, e desfazer tem que tirar a caixa inteira, e nao so o texto dela.
    _editar(no.id, guardar: false);
  }

  /// A caixa com [texto] dentro, ja do tamanho que esse texto pede.
  ///
  /// Do tamanho certo so a anotaçao solta. As outras formas tem moldura, e a
  /// moldura e que manda no tamanho: um retangulo que encolhesse ao se apagar
  /// uma palavra sairia dançando no meio do fluxograma, e desalinharia as
  /// flechas presas a ele. A anotaçao nao tem moldura nenhuma — o tamanho dela
  /// *e* o texto —, entao ela acompanha, e quem escreve nunca pensa em tamanho.
  NoDoQuadro _comTexto(NoDoQuadro no, String texto) {
    if (no.forma != FormaDoNo.texto) return no.com(texto: texto);

    final tamanho = DesenhoDoQuadro.tamanhoDoTexto(
      texto,
      no,
      aMao: _quadro.aMao,
    );

    return no.com(
      texto: texto,
      largura: tamanho.largura,
      altura: tamanho.altura,
      // Cresce para a direita e para os dois lados na vertical: a esquerda fica
      // onde foi apontada, e a linha nova empurra o texto meia linha para cima
      // e meia para baixo, em vez de arrastar tudo para baixo.
      y: no.centroY - tamanho.altura / 2,
    );
  }

  /// Escreve solto em [onde]: uma anotaçao sem moldura, com o cursor ja aberto.
  ///
  /// Sem passar por [_novaCaixa] de proposito. Aquela procura um lugar livre,
  /// desviando de quem ja esta ali; escrever solto e o contrario — o lugar e
  /// exatamente onde se apontou, inclusive por cima do que ja existe, que e o
  /// caso de quem esta anotando *sobre* um desenho.
  void _novoTexto(Offset onde) {
    final tamanho = FormaDoNo.texto.tamanhoInicial;

    final no = NoDoQuadro(
      id: _quadro.idLivre,
      forma: FormaDoNo.texto,
      // A esquerda no ponto apontado, e nao o centro: escrever começa onde o
      // cursor esta e cresce para a direita, como em qualquer lugar onde se
      // escreve.
      x: onde.dx,
      y: onde.dy - tamanho.altura / 2,
      largura: tamanho.largura,
      altura: tamanho.altura,
    );

    _guardar();
    _mexer(_quadro.comNo(no));
    _selecionarNo(no.id);
    _editar(no.id, guardar: false);

    // A mao volta para a seta: escrever num lugar e um gesto que se encerra.
    setState(() => _ferramenta = _Ferramenta.seta);
  }

  /// Desvia a caixa nova enquanto ela estiver caindo em cima de outra.
  ///
  /// Sem isto, apertar duas vezes o mesmo botao da barra deixa duas caixas
  /// exatamente empilhadas — e a de baixo desaparece atras da de cima.
  Offset _lugarLivre(Offset canto, Size tamanho, {required Offset passo}) {
    var tentativa = canto;

    for (var i = 0; i < 40; i++) {
      final area = Rect.fromLTWH(
        tentativa.dx,
        tentativa.dy,
        tamanho.width,
        tamanho.height,
      );
      final ocupado = _quadro.nos.any(
        (no) => DesenhoDoQuadro.retanguloDe(no).overlaps(area.deflate(4)),
      );
      if (!ocupado) return tentativa;
      tentativa += passo;
    }

    return tentativa;
  }

  static double _naMalha(double valor) =>
      (valor / DesenhoDoQuadro.malha).round() * DesenhoDoQuadro.malha;

  /// Troca a forma da caixa selecionada.
  ///
  /// O tamanho vai atras da forma quando ele ainda era o de fabrica: um
  /// retangulo virando losango sem crescer nao caberia o proprio texto. Caixa
  /// que ja foi redimensionada a mao fica do tamanho que se escolheu.
  void _trocarForma(FormaDoNo forma) {
    final no = _selecionado == null ? null : _quadro.no(_selecionado!);
    if (no == null || no.forma == forma) return;

    final antes = no.forma.tamanhoInicial;
    final agora = forma.tamanhoInicial;
    final deFabrica = no.largura == antes.largura && no.altura == antes.altura;

    _guardar();
    _mexer(
      _quadro.comNo(
        no.com(
          forma: forma,
          largura: deFabrica ? agora.largura : null,
          altura: deFabrica ? agora.altura : null,
        ),
      ),
    );
  }

  // -------------------------------------------------------------- escrita

  /// Abre o cursor dentro da caixa [id].
  ///
  /// [guardar] marca um passo de desfazer *antes* da primeira letra: um passo
  /// por sessao de escrita, e nao um por tecla. Desfazer ao escrever devolve o
  /// texto como ele estava quando se começou a mexer, que e o que se espera —
  /// letra a letra seria uma dezena de passos para desfazer uma palavra.
  void _editar(String id, {bool guardar = true}) {
    final no = _quadro.no(id);
    if (no == null) return;

    if (guardar) _guardar();
    _soltarDepois(_campo);
    _soltarDepois(_focoDoCampo);

    _campo = TextEditingController(text: no.texto)
      ..selection = TextSelection.collapsed(offset: no.texto.length);
    _focoDoCampo = FocusNode();

    setState(() => _editando = id);
    // Depois do quadro: o campo ainda nao existe na arvore neste instante.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoDoCampo?.requestFocus();
    });
  }

  void _pararDeEditar() {
    if (_editando == null) return;

    final no = _quadro.no(_editando!);
    setState(() => _editando = null);

    // Anotaçao solta sem nada escrito nao fica.
    //
    // Ela nao tem moldura: ficaria no quadro como uma area invisivel, que so se
    // descobre quando o ponteiro esbarra nela e o cursor muda. Um clique que
    // nao virou texto e um clique que nao virou nada — o mesmo trato que o
    // traço de um ponto so recebe.
    if (no != null && no.forma == FormaDoNo.texto && no.texto.trim().isEmpty) {
      setState(() => _selecionado = null);
      _mexer(_quadro.semNo(no.id));
    }

    _foco.requestFocus();
  }

  // --------------------------------------------------------------- gestos

  void _clique(Offset tela) {
    final agora = DateTime.now();
    final anterior = _ultimoClique;
    _ultimoClique = (quando: agora, onde: tela);

    if (anterior != null &&
        agora.difference(anterior.quando) < _janelaDoDuplo &&
        (tela - anterior.onde).distance < _pertoDoDuplo) {
      // Um duplo clique nao serve de primeiro clique para o proximo: sem isto,
      // tres cliques seguidos abririam duas vezes o que o segundo ja abriu.
      _ultimoClique = null;
      _cliqueDuplo(tela);
      return;
    }

    final ponto = _paraQuadro(tela);

    // Num desenho que so se olha, o clique nao seleciona: seleçao e o começo
    // de uma mexida, e aqui nao ha mexida nenhuma para começar.
    if (_travado) return;

    // Com a borracha na mao, o clique parado apaga o que estiver debaixo dela:
    // e o gesto de quem quer tirar um risco so, sem passar a mao por cima.
    if (_ferramenta == _Ferramenta.borracha) {
      _apagarEm(ponto);
      _acabouDeApagar();
      return;
    }

    // Escrever solto e um clique: aponta-se o lugar e o cursor abre ali.
    if (_ferramenta == _Ferramenta.texto) {
      final ja = DesenhoDoQuadro.noEm(_quadro, ponto);
      // Em cima de uma caixa que ja existe, escrever solto vira escrever
      // nela — e o que a mao estava pedindo, e criar uma anotaçao por cima
      // deixaria dois textos empilhados no mesmo lugar.
      //
      // O painel de fundo e a exceçao: ele e cenario, cobre meia area, e
      // escrever em cima dele quase nunca quer dizer renomear o painel — quer
      // dizer anotar ali dentro.
      if (ja != null && !ja.forma.eFundo) {
        _selecionarNo(ja.id);
        _editar(ja.id);
        setState(() => _ferramenta = _Ferramenta.seta);
        return;
      }
      _novoTexto(ponto);
      return;
    }

    // As outras ferramentas nao tem o que fazer com um clique parado — um
    // traço precisa de dois pontos, e o segundo so vem com o arrasto.
    if (_ferramenta.desenha) return;

    final traco = DesenhoDoQuadro.tracoEm(_quadro, ponto, _folgaDoTraco);
    if (traco != null) {
      _pararDeEditar();
      _selecionarTraco(traco.id);
      return;
    }

    final no = DesenhoDoQuadro.noEm(_quadro, ponto);

    if (no != null) {
      // Clique na moldura da caixa que esta sendo escrita: o cursor volta
      // para o texto dela, e nao para a area. O campo cobre so o miolo, e sem
      // isto acertar a borda deixaria de escrever sem avisar.
      if (_editando == no.id) {
        _focoDoCampo?.requestFocus();
        return;
      }
      if (_editando != null) _pararDeEditar();
      _selecionarNo(no.id);
      return;
    }

    final ligacao = DesenhoDoQuadro.ligacaoEm(_quadro, ponto, 10 / _escala);
    _pararDeEditar();
    if (ligacao != null) {
      _selecionarLigacao(ligacao);
      return;
    }

    _limparSelecao();
    _foco.requestFocus();
  }

  void _cliqueDuplo(Offset tela) {
    // Com a caneta ou a borracha na mao, dois cliques sao dois cliques: criar
    // uma caixa no meio de um desenho seria o oposto do que se pediu.
    if (_ferramenta != _Ferramenta.seta) return;

    final ponto = _paraQuadro(tela);
    // Com uma folga de um fio: acertar a propria borda da caixa e escrever
    // nela, e nao criar outra caixa em cima dela.
    final no = DesenhoDoQuadro.noEm(_quadro, ponto, folga: 2);

    if (no != null) {
      // A caixa que e um `[[link]]` abre a nota, e nao o cursor: e um atalho
      // desenhado, e o que se espera de um atalho e que ele leve a algum
      // lugar. Para mexer no texto dele, resta a seta e o campo — que e o
      // mesmo trato do link no meio do texto.
      final atalho = Wikilink.sozinho(no.texto);
      if (atalho != null && widget.onAbrirNota != null) {
        widget.onAbrirNota!(atalho.alvo);
        return;
      }

      if (_travado) return;
      _selecionarNo(no.id);
      _editar(no.id);
      return;
    }

    if (_travado) return;

    // Area vazia: o duplo clique escreve ali, solto.
    //
    // E o gesto que se tenta primeiro num quadro em branco, antes de procurar
    // qualquer barra — e o que se quer nesse primeiro gesto quase sempre e
    // *anotar*, nao montar um fluxograma. Criava um retangulo, e ai quem so
    // queria escrever uma palavra ganhava uma moldura em volta dela e tinha que
    // descobrir sozinho como tirar.
    //
    // A caixa continua a um clique de distancia, na barra de formas, que e onde
    // se procura uma forma quando se sabe que se quer uma.
    _novoTexto(ponto);
  }

  /// O que o ponteiro pega em [ponto].
  ///
  /// Um lugar so para essa decisao, e nao um em cada gesto: o cursor que
  /// aparece no ar e o que o arrasto faz sao respostas da mesma pergunta, e se
  /// cada um respondesse por conta o desenho mentiria sobre o que vai pegar.
  ///
  /// A ordem e por precisao: o canto de tamanho e as bolinhas de ligar sao
  /// alvos pequenos e ficam por cima da caixa, entao ganham dela.
  ({_Pegavel tipo, NoDoQuadro? no, TracoDoQuadro? traco, Offset? ancora})
  _debaixo(Offset ponto) {
    final selecionado = _selecionado == null ? null : _quadro.no(_selecionado!);

    if (selecionado != null) {
      final canto = DesenhoDoQuadro.retanguloDe(selecionado).bottomRight;
      if ((ponto - canto).distance <= DesenhoDoQuadro.folgaDoCanto / _escala) {
        return (
          tipo: _Pegavel.canto,
          no: selecionado,
          traco: null,
          ancora: null,
        );
      }
    }

    // So a caixa que esta debaixo do ponteiro oferece ponto de ligar, e nao
    // tambem a que esta selecionada: os pontos sao desenhados assim, e um alvo
    // invisivel e pior que um alvo que nao existe.
    //
    // A caixa e procurada aqui, no proprio ponto, e nao lida de `_emFoco`.
    // A conta e a mesma — e a mesma folga de [_apontar], entao o que se pega e
    // exatamente o que esta desenhado —, mas ela nao depende de o ponteiro ter
    // passeado por cima antes. Dependia, e ai um toque que apertasse sem
    // passear — o dedo, a caneta, um teste — nao achava ponto nenhum.
    //
    // O painel de fundo nao tem ponto nenhum: nada se liga a ele.
    final perto = DesenhoDoQuadro.noEm(
      _quadro,
      ponto,
      folga:
          (DesenhoDoQuadro.foraDaBorda + DesenhoDoQuadro.folgaDaAncora) /
          _escala,
    );

    if (perto != null && DesenhoDoQuadro.ligavel(perto)) {
      for (final ancora in DesenhoDoQuadro.ancorasDe(perto)) {
        if ((ponto - ancora).distance <=
            DesenhoDoQuadro.folgaDaAncora / _escala) {
          return (
            tipo: _Pegavel.ancora,
            no: perto,
            traco: null,
            ancora: ancora,
          );
        }
      }
    }

    final traco = DesenhoDoQuadro.tracoEm(_quadro, ponto, _folgaDoTraco);
    if (traco != null) {
      return (tipo: _Pegavel.traco, no: null, traco: traco, ancora: null);
    }

    final no = DesenhoDoQuadro.noEm(_quadro, ponto);
    if (no != null) {
      return (tipo: _Pegavel.caixa, no: no, traco: null, ancora: null);
    }

    return (tipo: _Pegavel.nada, no: null, traco: null, ancora: null);
  }

  /// A que distancia de um traço o ponteiro ja conta como estando nele.
  ///
  /// Dividida pelo zoom, como as outras folgas: o alvo e do tamanho que a mao
  /// ve na tela, e nao do tamanho que ele tem no quadro.
  double get _folgaDoTraco => 8 / _escala;

  void _comecarArrasto(Offset tela) {
    final ponto = _paraQuadro(tela);

    // Travado, todo arrasto e passeio: e o unico gesto que nao muda nada.
    if (_travado) return;

    if (_ferramenta.desenha) {
      _pararDeEditar();
      _limparSelecao();
      setState(
        () => _tracando = TracoDoQuadro(
          id: _quadro.idLivreDoTraco,
          tipo: _ferramenta.tipoDoTraco,
          // Nasce com o mesmo ponto duas vezes: o traço precisa de duas pontas
          // para existir, e a segunda ainda e onde a primeira esta.
          pontos: [ponto.dx, ponto.dy, ponto.dx, ponto.dy],
          cor: _cor,
          grossura: _grossura,
        ),
      );
      return;
    }

    if (_ferramenta == _Ferramenta.borracha) {
      _pararDeEditar();
      _apagarEm(ponto);
      return;
    }

    // Com a ferramenta de escrever na mao, arrastar passeia pela area: mover
    // uma caixa e coisa da seta, e arrastar sem querer enquanto se procura
    // onde escrever nao pode desmontar o desenho.
    if (_ferramenta == _Ferramenta.texto) return;

    final pego = _debaixo(ponto);
    final no = pego.no;

    switch (pego.tipo) {
      case _Pegavel.traco:
        if (_editando != null) _pararDeEditar();
        setState(() {
          _movendoTraco = pego.traco!.id;
          _tracoSelecionado = pego.traco!.id;
          _selecionado = null;
          _ligacaoSelecionada = null;
          _rotuloEm(null);
          _pegadaDoTraco = (ponteiro: ponto, traco: pego.traco!);
        });
        _guardar();
      case _Pegavel.canto:
        setState(() {
          _redimensionando = no!.id;
          _pegada = (ponteiro: ponto, no: no);
        });
        _guardar();

      case _Pegavel.ancora:
        _pararDeEditar();
        setState(() => _ligando = (de: no!.id, ponto: ponto));

      case _Pegavel.caixa:
        if (_editando != null && _editando != no!.id) _pararDeEditar();
        setState(() {
          _movendo = no!.id;
          _selecionado = no.id;
          _ligacaoSelecionada = null;
          _tracoSelecionado = null;
          _rotuloEm(null);
          // De onde a mao pegou, e como a caixa estava. Todo o arrasto e
          // medido contra isto, e nao contra o quadro anterior — veja
          // [_arrastar].
          _pegada = (ponteiro: ponto, no: no);
        });
        _guardar();

      case _Pegavel.nada:
        // Fora de tudo: o arrasto passeia pela area, como em qualquer mapa.
        break;
    }
  }

  /// Move, redimensiona, liga ou passeia — conforme o que a mao pegou.
  ///
  /// A conta e sempre *do inicio do arrasto ate o ponteiro agora*, nunca do
  /// quadro anterior mais um pedacinho. A diferença nao e de estilo: somar
  /// deslocamentos de dois ou tres pixels a uma posiçao ja encaixada na malha
  /// faz cada soma voltar para o mesmo lugar, e a caixa fica presa no chao ate
  /// o mouse dar um pulo — que foi como este arrasto nasceu.
  void _arrastar(DragUpdateDetails d) {
    final ponteiro = _paraQuadro(d.localPosition);
    final pegada = _pegada;

    final tracando = _tracando;
    if (tracando != null) {
      setState(() => _tracando = _maisUmPonto(tracando, ponteiro));
      return;
    }

    if (_ferramenta == _Ferramenta.borracha) {
      _apagarEm(ponteiro);
      return;
    }

    final pegadaDoTraco = _pegadaDoTraco;
    if (_movendoTraco != null && pegadaDoTraco != null) {
      final desde = ponteiro - pegadaDoTraco.ponteiro;
      // Sem malha: o traço foi feito a mao solta, e encaixa-lo de oito em oito
      // pixels ao arrasta-lo seria dar regua a quem escolheu nao usar regua.
      _mexer(
        _quadro.comTraco(pegadaDoTraco.traco.movido(desde.dx, desde.dy)),
        avisar: false,
      );
      return;
    }

    final movendo = _movendo;
    if (movendo != null && pegada != null) {
      final desde = ponteiro - pegada.ponteiro;
      // Primeiro a malha, depois o imã: o alinhamento com a caixa vizinha vale
      // mais que o encaixe na malha, senao a flecha ficaria com o degrauzinho
      // de quem parou a meio passo do alinhamento.
      final arrastada = pegada.no.com(
        x: _naMalha(pegada.no.x + desde.dx),
        y: _naMalha(pegada.no.y + desde.dy),
      );
      final encostada = DesenhoDoQuadro.alinhar(_quadro, arrastada);

      setState(() => _guias = (x: encostada.guiaX, y: encostada.guiaY));
      // Enquanto a mao nao solta, o texto da nota fica quieto.
      _mexer(_quadro.comNo(encostada.no), avisar: false);
      return;
    }

    final redimensionando = _redimensionando;
    if (redimensionando != null && pegada != null) {
      final desde = ponteiro - pegada.ponteiro;
      _mexer(
        _quadro.comNo(
          pegada.no.com(
            largura: _naMalha(
              (pegada.no.largura + desde.dx).clamp(
                NoDoQuadro.larguraMinima,
                1200,
              ),
            ),
            altura: _naMalha(
              (pegada.no.altura + desde.dy).clamp(
                NoDoQuadro.alturaMinima,
                1200,
              ),
            ),
          ),
        ),
        avisar: false,
      );
      return;
    }

    final ligando = _ligando;
    if (ligando != null) {
      // A ponta da linha e o ponteiro, sem intermediario: e a unica coisa que
      // ela precisa acompanhar.
      setState(() => _ligando = (de: ligando.de, ponto: ponteiro));
      return;
    }

    setState(() => _pan += d.delta);
  }

  void _soltar() {
    final tracando = _tracando;
    if (tracando != null) {
      setState(() => _tracando = null);
      _guardarTraco(tracando);
      return;
    }

    if (_ferramenta == _Ferramenta.borracha) {
      _acabouDeApagar();
      return;
    }

    if (_movendoTraco != null) {
      setState(() {
        _movendoTraco = null;
        _pegadaDoTraco = null;
      });
      _mudou();
      return;
    }

    final ligando = _ligando;
    if (ligando != null) {
      final alvo = DesenhoDoQuadro.noEm(_quadro, ligando.ponto);
      setState(() => _ligando = null);
      // Soltar a flecha sobre um painel de fundo nao liga nada: ele e cenario,
      // e a flecha ficaria presa a uma area em vez de a um passo.
      if (alvo != null &&
          alvo.id != ligando.de &&
          DesenhoDoQuadro.ligavel(alvo)) {
        _guardar();
        _mexer(_quadro.comLigacao(ligando.de, alvo.id));
      }
      return;
    }

    if (_movendo != null || _redimensionando != null) {
      setState(() {
        _movendo = null;
        _redimensionando = null;
        _pegada = null;
        _guias = null;
      });
      // Agora sim: a posiçao final vai para o `.md`.
      _mudou();
    }
  }

  // -------------------------------------------------------------- desenho

  /// De quantos em quantos pixels a caneta guarda um ponto.
  ///
  /// O ponteiro entrega uma coordenada por quadro de animaçao — sessenta por
  /// segundo, quase todas a menos de um pixel da anterior. Guardar todas
  /// encheria a linha do traço no `.md` de casas decimais que ninguem ve, e a
  /// curva que passa entre elas sairia igual.
  static const _passoDaCaneta = 2.0;

  /// Menor que isto, o que a mao fez foi um clique, e nao um traço.
  static const _minimoDoTraco = 3.0;

  /// Acrescenta [ponto] ao traço em curso.
  TracoDoQuadro _maisUmPonto(TracoDoQuadro traco, Offset ponto) {
    // A reta e a seta tem duas pontas e so duas: o ponto novo *troca* a
    // segunda, em vez de entrar na fila atras dela.
    if (traco.tipo.ePonta) {
      return traco.com(pontos: [traco.x(0), traco.y(0), ponto.dx, ponto.dy]);
    }

    final ultimo = Offset(
      traco.x(traco.quantos - 1),
      traco.y(traco.quantos - 1),
    );

    // O segundo ponto do traço recem-nascido ainda esta em cima do primeiro: e
    // ele que o primeiro movimento troca, senao o traço começaria com um
    // pedaço de comprimento zero.
    if (traco.quantos == 2 && ultimo == Offset(traco.x(0), traco.y(0))) {
      return traco.com(pontos: [traco.x(0), traco.y(0), ponto.dx, ponto.dy]);
    }

    if ((ponto - ultimo).distance < _passoDaCaneta / _escala) return traco;
    return traco.com(pontos: [...traco.pontos, ponto.dx, ponto.dy]);
  }

  /// Guarda o traço que a mao acabou de fazer, se ele chegou a ser um traço.
  void _guardarTraco(TracoDoQuadro traco) {
    var andou = 0.0;
    for (var i = 0; i < traco.quantos - 1; i++) {
      andou +=
          (Offset(traco.x(i + 1), traco.y(i + 1)) -
                  Offset(traco.x(i), traco.y(i)))
              .distance;
    }
    if (andou < _minimoDoTraco / _escala) return;

    _guardar();
    _mexer(_quadro.comTraco(traco));

    // A reta e a seta sao quase sempre uma so; a caneta quase nunca. Entao a
    // mao volta para a seta depois de uma reta — ja com ela selecionada, que e
    // o que se quer para arrasta-la para o lugar — e fica na caneta depois de
    // um rabisco.
    if (_ferramenta != _Ferramenta.caneta) {
      setState(() => _ferramenta = _Ferramenta.seta);
      _selecionarTraco(traco.id);
    }
  }

  /// Se esta passada da borracha ja marcou um passo de desfazer.
  ///
  /// Uma passada e um passo, e nao um passo por traço apagado: quem passa a
  /// borracha por cima de tres riscos fez um gesto, e desfazer devolve os tres.
  bool _borrachaGuardou = false;

  void _apagarEm(Offset ponto) {
    setState(() => _borrachaEm = ponto);

    final traco = DesenhoDoQuadro.tracoEm(
      _quadro,
      ponto,
      _raioDaBorracha / _escala,
    );
    if (traco == null) return;

    if (!_borrachaGuardou) {
      _guardar();
      _borrachaGuardou = true;
    }
    _mexer(_quadro.semTraco(traco.id), avisar: false);
  }

  void _acabouDeApagar() {
    if (!_borrachaGuardou) return;
    _borrachaGuardou = false;
    _mudou();
  }

  /// Troca a ferramenta na mao.
  void _pegar(_Ferramenta ferramenta) {
    if (_ferramenta == ferramenta) return;
    _pararDeEditar();
    setState(() => _ferramenta = ferramenta);
    // A seleçao continua: trocar para a caneta com um traço selecionado e o
    // caminho de quem vai desenhar mais um igual, e perder a seleçao ali
    // apagaria a cor e a grossura que a barra estava mostrando.
    _foco.requestFocus();
  }

  /// Troca a cor da caneta — e, se houver um traço selecionado, a dele.
  ///
  /// As duas coisas, e nao uma escolha entre elas: com um traço selecionado, o
  /// clique numa cor quer dizer "esse ai fica assim"; sem nenhum, quer dizer "o
  /// proximo sai assim". Em qualquer dos dois casos a caneta fica com a cor
  /// escolhida, que e o que a barra passa a mostrar.
  void _usarCor(CorDoTraco cor) {
    setState(() => _cor = cor);

    final traco = _tracoSelecionado == null
        ? null
        : _quadro.traco(_tracoSelecionado!);
    if (traco == null) return;

    _guardar();
    _mexer(_quadro.comTraco(traco.com(cor: cor)));
  }

  void _usarGrossura(double grossura) {
    setState(() => _grossura = grossura);

    final traco = _tracoSelecionado == null
        ? null
        : _quadro.traco(_tracoSelecionado!);
    if (traco == null) return;

    _guardar();
    _mexer(_quadro.comTraco(traco.com(grossura: grossura)));
  }

  /// Liga e desliga o traço a mao do quadro inteiro.
  void _trocarMao() {
    _guardar();
    _mexer(_quadro.comMao(!_quadro.aMao));
  }

  // ----------------------------------------------------------- Excalidraw

  /// Traz para dentro do quadro o desenho que estiver na area de
  /// transferencia.
  ///
  /// Pela area de transferencia, e nao por um seletor de arquivos: o desenho
  /// que se quer trazer quase sempre esta *aberto* no excalidraw.com naquele
  /// instante, e Ctrl+C la, Ctrl+V aqui e o caminho mais curto entre os dois —
  /// sem exportar arquivo, sem procurar a pasta de downloads, sem plugin
  /// nativo de janela de arquivo.
  Future<void> _colarDoExcalidraw() async {
    final area = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = area?.text ?? '';

    if (!Excalidraw.pareceExcalidraw(texto)) {
      _avisar(
        'Nao ha desenho do Excalidraw para colar. No excalidraw.com, '
        'selecione e aperte Ctrl+C.',
      );
      return;
    }

    final vindo = Excalidraw.ler(texto);
    if (vindo == null || vindo.semNada) {
      _avisar('O desenho copiado esta vazio, ou nao deu para ler.');
      return;
    }

    // Ao lado do que ja existe, e nao por cima: o desenho de la tem as
    // coordenadas de la, e elas nao querem dizer nada aqui — cair em cima do
    // que ja estava desenhado seria o mais provavel dos acasos.
    final desloca = _quadro.semNada
        ? Offset.zero
        : () {
            final meus = DesenhoDoQuadro.limitesDe(_quadro, folga: 0);
            final deles = DesenhoDoQuadro.limitesDe(vindo, folga: 0);
            return Offset(
              meus.right + DesenhoDoQuadro.respiro - deles.left,
              meus.top - deles.top,
            );
          }();

    _guardar();
    _mexer(_quadro.juntar(vindo, dx: desloca.dx, dy: desloca.dy));
    _enquadrar();

    final quantos = vindo.nos.length + vindo.tracos.length;
    _avisar(
      '$quantos ${quantos == 1 ? 'peça veio' : 'peças vieram'} do '
      'Excalidraw.',
    );
  }

  /// Poe o quadro na area de transferencia como um bloco de Markdown.
  ///
  /// E o mesmo texto que mora dentro de uma nota — ` ```quadro ` e o JSON —,
  /// entao colar isso no corpo de qualquer nota faz o desenho aparecer
  /// desenhado, e dali em diante ele e uma copia sua, que se mexe a vontade.
  Future<void> _copiarComoBloco() async {
    if (_quadro.semNada) {
      _avisar('O quadro esta vazio: nao ha o que copiar.');
      return;
    }

    // Com uma linha em branco de cada lado: o Markdown so le um bloco como
    // bloco proprio quando ele esta separado do paragrafo em volta.
    await Clipboard.setData(ClipboardData(text: '\n${_quadro.markdown}\n'));
    _avisar('Copiado. Cole no corpo de uma nota para ter uma copia editavel.');
  }

  /// Poe o quadro inteiro na area de transferencia, no formato do Excalidraw.
  Future<void> _copiarParaOExcalidraw() async {
    if (_quadro.semNada) {
      _avisar('O quadro esta vazio: nao ha o que copiar.');
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: Excalidraw.escrever(_quadro, paraColar: true)),
    );
    _avisar('Quadro copiado. Cole no excalidraw.com com Ctrl+V.');
  }

  void _apontar(Offset tela) {
    if (_travado) return;

    final ponto = _paraQuadro(tela);

    // Com a borracha na mao, o que importa e onde ela esta — e nao que caixa o
    // ponteiro atravessou. Mostrar as bolinhas de ligar aqui prometeria uma
    // ligaçao que a borracha nao faz.
    if (_ferramenta == _Ferramenta.borracha) {
      setState(() {
        _borrachaEm = ponto;
        _emFoco = null;
        _sobre = _Pegavel.nada;
        _ancoraEmFoco = null;
      });
      return;
    }

    if (_borrachaEm != null) setState(() => _borrachaEm = null);

    if (_ferramenta.desenha) {
      if (_emFoco != null || _sobre != _Pegavel.nada) {
        setState(() {
          _emFoco = null;
          _sobre = _Pegavel.nada;
          _ancoraEmFoco = null;
        });
      }
      return;
    }

    // A caixa em foco continua sendo a do ponteiro, so que com a folga das
    // bolinhas: elas moram para fora da borda, e sem essa margem sumiriam no
    // instante em que a mao sai da caixa para pegar uma delas.
    final perto = DesenhoDoQuadro.noEm(
      _quadro,
      ponto,
      folga:
          (DesenhoDoQuadro.foraDaBorda + DesenhoDoQuadro.folgaDaAncora) /
          _escala,
    );

    if (perto?.id != _emFoco) {
      // O foco entra antes de perguntar o que esta debaixo do ponteiro: e ele
      // que diz de quem sao as bolinhas visiveis.
      setState(() => _emFoco = perto?.id);
    }

    final pego = _debaixo(ponto);
    if (pego.tipo != _sobre || pego.ancora != _ancoraEmFoco) {
      setState(() {
        _sobre = pego.tipo;
        _ancoraEmFoco = pego.ancora;
      });
    }
  }

  /// Empurra a caixa selecionada com as setas.
  ///
  /// A mao no mouse acerta o lugar aproximado; o ajuste fino de um passo — ou
  /// de um pixel, com Shift — e mais rapido e mais exato pelo teclado do que
  /// perseguindo a malha com o ponteiro.
  bool _empurrar(
    LogicalKeyboardKey tecla, {
    required bool fino,
    required bool novo,
  }) {
    final no = _selecionado == null ? null : _quadro.no(_selecionado!);
    final traco = _tracoSelecionado == null
        ? null
        : _quadro.traco(_tracoSelecionado!);
    if (no == null && traco == null) return false;

    final passo = fino ? 1.0 : DesenhoDoQuadro.malha;
    final para = switch (tecla) {
      LogicalKeyboardKey.arrowLeft => Offset(-passo, 0),
      LogicalKeyboardKey.arrowRight => Offset(passo, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -passo),
      LogicalKeyboardKey.arrowDown => Offset(0, passo),
      _ => null,
    };
    if (para == null) return false;

    // So o primeiro toque marca um passo de desfazer. Com a tecla segurada, o
    // sistema repete o evento dezenas de vezes por segundo, e cada repetiçao
    // guardando um passo enterraria o resto do historico em dois segundos.
    if (novo) _guardar();

    if (no != null) {
      _mexer(_quadro.comNo(no.com(x: no.x + para.dx, y: no.y + para.dy)));
    } else {
      _mexer(_quadro.comTraco(traco!.movido(para.dx, para.dy)));
    }
    return true;
  }

  KeyEventResult _teclas(FocusNode node, KeyEvent evento) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final tecla = evento.logicalKey;

    // Com o cursor num campo — o texto de dentro da caixa, o rotulo da flecha
    // — as teclas sao do texto, e nao da area.
    //
    // Esta guarda nao e um detalhe: as teclas sobem do campo focado para os
    // ancestrais dele, e este widget e ancestral dos campos, enquanto quem
    // apaga letra (`DefaultTextEditingShortcuts`) mora bem acima, perto da
    // raiz do app. Sem a guarda, o Backspace de quem estava escrevendo chegava
    // aqui primeiro — e apagava a caixa inteira em vez da letra.
    if (!_foco.hasPrimaryFocus) {
      // Esc continua sendo da area: e assim que se sai da escrita sem apagar
      // nem fechar nada.
      if (tecla == LogicalKeyboardKey.escape) {
        if (_editando != null) {
          _pararDeEditar();
          return KeyEventResult.handled;
        }
        if (_ligacaoSelecionada != null) {
          setState(() {
            _ligacaoSelecionada = null;
            _rotuloEm(null);
          });
          _foco.requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    final comando =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Num desenho que so se olha, a unica tecla que faz sentido e a que leva
    // uma copia dele embora.
    if (_travado) {
      if (comando && tecla == LogicalKeyboardKey.keyC) {
        unawaited(_copiarParaOExcalidraw());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (comando) {
      // Ctrl+Z e Ctrl+Shift+Z sao o par de sempre; Ctrl+Y esta ai porque e o
      // refazer que o Windows ensinou a uma geraçao inteira.
      if (tecla == LogicalKeyboardKey.keyZ) {
        HardwareKeyboard.instance.isShiftPressed
            ? _refazerPasso()
            : _desfazerPasso();
        return KeyEventResult.handled;
      }
      if (tecla == LogicalKeyboardKey.keyY) {
        _refazerPasso();
        return KeyEventResult.handled;
      }
      if (tecla == LogicalKeyboardKey.keyV) {
        unawaited(_colarDoExcalidraw());
        return KeyEventResult.handled;
      }
      if (tecla == LogicalKeyboardKey.keyC) {
        unawaited(_copiarParaOExcalidraw());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // As letras da barra de ferramentas. Uma tecla por ferramenta, como em
    // qualquer programa de desenho: a mao que esta desenhando nao larga o
    // desenho para ir ate a barra e voltar.
    for (final ferramenta in _Ferramenta.values) {
      if (evento.character?.toLowerCase() == ferramenta.tecla) {
        _pegar(ferramenta);
        return KeyEventResult.handled;
      }
    }

    if (_empurrar(
      tecla,
      fino: HardwareKeyboard.instance.isShiftPressed,
      novo: evento is KeyDownEvent,
    )) {
      return KeyEventResult.handled;
    }

    if (tecla == LogicalKeyboardKey.delete ||
        tecla == LogicalKeyboardKey.backspace) {
      if (!_temSelecao) return KeyEventResult.ignored;
      _excluirSelecao();
      return KeyEventResult.handled;
    }

    if (tecla == LogicalKeyboardKey.escape) {
      // Esc desfaz a camada de cima: primeiro o cursor na caixa, depois a
      // ferramenta na mao, depois a seleçao. Sem nada disso ele volta a fechar
      // a tela.
      if (_editando != null) {
        _pararDeEditar();
        return KeyEventResult.handled;
      }
      if (_ferramenta != _Ferramenta.seta) {
        _pegar(_Ferramenta.seta);
        return KeyEventResult.handled;
      }
      if (_temSelecao) {
        _limparSelecao();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ----------------------------------------------------------------- tela

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final corpo = _corpo(theme);

    return widget.emJanela
        ? Dialog.fullscreen(
            backgroundColor: theme.colorScheme.surfaceContainerLowest,
            child: corpo,
          )
        : ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
            child: corpo,
          );
  }

  Widget _corpo(ThemeData theme) {
    return Column(
      children: [
        _barra(theme),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final area = Size(constraints.maxWidth, constraints.maxHeight);
              if (area != _area) {
                final primeiraMedida = !_medido;
                _area = area;
                _medido = true;

                // Enquadra uma vez, na primeira medida, e nunca mais: dai em
                // diante a camera e do usuario, e reenquadrar seria puxar o
                // desenho da mao dele.
                //
                // "Nunca mais" inclui as mudanças de altura desta propria
                // tela: a barra crescia um fio ao ganhar o grupo de formas, e
                // isso bastava para o quadro inteiro saltar no clique que
                // selecionava uma caixa.
                if (primeiraMedida && !_quadro.semNada) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _enquadrar();
                  });
                }
              }
              return _tela(theme, area);
            },
          ),
        ),
        // O rodape e a lista do que a mao pode fazer aqui. Num desenho que so
        // se olha ele nao teria o que dizer, e a risca acima dele ficaria
        // fechando um rodape que nao existe.
        if (!widget.somenteLeitura) ...[
          const Divider(height: 1),
          _rodape(theme),
        ],
      ],
    );
  }

  Widget _tela(ThemeData theme, Size area) {
    return Focus(
      focusNode: _foco,
      autofocus: true,
      onKeyEvent: _teclas,
      child: ClipRect(
        child: MouseRegion(
          cursor: _cursor(),
          onHover: (e) => _apontar(e.localPosition),
          onExit: (_) => setState(() {
            _emFoco = null;
            _sobre = _Pegavel.nada;
            _ancoraEmFoco = null;
          }),
          child: Listener(
            // Roda do mouse dá zoom em torno do ponteiro, como em qualquer mapa.
            onPointerSignal: (sinal) {
              if (sinal is! PointerScrollEvent) return;
              _zoom(sinal.scrollDelta.dy > 0 ? 0.9 : 1.1, sinal.localPosition);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // O arrasto começa onde a mao apertou, e nao onde o Flutter
              // percebeu que era arrasto.
              //
              // No padrao (`start`), o pedacinho de movimento que o
              // reconhecedor gasta para se decidir e descartado: a caixa
              // andava sempre um tico atras do ponteiro, e o que se pegava era
              // avaliado num ponto adiante do apertado — o bastante para uma
              // bolinha de ligar de nove pixels escapar da mao.
              dragStartBehavior: DragStartBehavior.down,
              // O duplo clique e contado aqui, no clique simples, e nao pelo
              // reconhecedor de duplo toque do Flutter.
              //
              // Aquele reconhecedor disputa o ponteiro com o arrasto: depois
              // de um clique, ele segura por um instante todo pressionar que
              // caia perto dele, esperando o segundo toque — e o arrasto que
              // vinha em seguida se perdia nessa espera. Num quadro, clicar
              // numa caixa e ja arrastar dela e o gesto mais comum que existe.
              onTapUp: (d) => _clique(d.localPosition),
              onPanStart: (d) => _comecarArrasto(d.localPosition),
              onPanUpdate: _arrastar,
              onPanEnd: (_) => _soltar(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: QuadroPintado(
                        quadro: _quadro,
                        cores: theme.colorScheme,
                        pan: _pan,
                        escala: _escala,
                        malha: true,
                        noSelecionado: _selecionado,
                        noEmFoco: _emFoco,
                        ligacaoSelecionada: _ligacaoSelecionada,
                        ligando: _ligando,
                        semTexto: _editando,
                        guias: _guias,
                        tracoSelecionado: _tracoSelecionado,
                        tracando: _tracando,
                        ancoraEmFoco: _ancoraEmFoco,
                        borracha:
                            _ferramenta == _Ferramenta.borracha &&
                                _borrachaEm != null
                            ? (
                                ponto: _borrachaEm!,
                                raio: _raioDaBorracha / _escala,
                              )
                            : null,
                      ),
                    ),
                  ),
                  if (_quadro.semNada && _editando == null) _vazio(theme),
                  if (_editando != null) _campoDaCaixa(theme),
                  if (_ligacaoSelecionada != null) _campoDaFlecha(theme),
                  if (_recado != null) _oRecado(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// O ponteiro diz, antes do clique, o que aquele pixel vai pegar.
  MouseCursor _cursor() {
    // Travado, nao ha o que pegar: o unico gesto e arrastar a area.
    if (_travado) return SystemMouseCursors.grab;

    // A ferramenta na mao manda mais que o que esta debaixo do ponteiro: com a
    // caneta pega, passar por cima de uma caixa nao vai move-la.
    if (_ferramenta.desenha) return SystemMouseCursors.precise;
    // A borracha e o proprio circulo desenhado na area; o cursor do sistema so
    // acompanha, sem prometer outra coisa.
    if (_ferramenta == _Ferramenta.borracha) return SystemMouseCursors.cell;

    if (_movendo != null || _movendoTraco != null) {
      return SystemMouseCursors.grabbing;
    }
    if (_redimensionando != null) return SystemMouseCursors.resizeDownRight;
    if (_ligando != null) return SystemMouseCursors.precise;

    return switch (_sobre) {
      _Pegavel.canto => SystemMouseCursors.resizeDownRight,
      _Pegavel.ancora => SystemMouseCursors.precise,
      _Pegavel.traco => SystemMouseCursors.grab,
      _Pegavel.caixa => SystemMouseCursors.grab,
      _Pegavel.nada => SystemMouseCursors.basic,
    };
  }

  /// A letra dos campos que ficam por cima do desenho, igual a que o pintor
  /// usa embaixo deles.
  TextStyle? get _letraDoQuadro => _quadro.aMao
      ? const TextStyle(
          fontFamily: MaoLivre.fonte,
          fontFamilyFallback: MaoLivre.fontesAlternativas,
        )
      : null;

  /// O aviso no pe da area. Some sozinho: e uma nota de rodape do que acabou
  /// de acontecer, e nao um recado a ser fechado.
  Widget _oRecado(ThemeData theme) => Positioned(
    left: AppTheme.gapLg,
    right: AppTheme.gapLg,
    bottom: AppTheme.gapLg,
    child: IgnorePointer(
      child: Center(
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.gapMd,
              vertical: AppTheme.gapSm,
            ),
            child: Text(_recado!, style: theme.textTheme.bodySmall),
          ),
        ),
      ),
    ),
  );

  /// O que aparece no quadro em branco. Um quadro vazio nao tem nada para ver,
  /// e sem uma palavra ele parece quebrado em vez de novo.
  Widget _vazio(ThemeData theme) {
    return Center(
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_tree_outlined,
              size: 30,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.gapMd),
            Text('Quadro vazio', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.gapXs),
            Text(
              'Duplo clique aqui escreve, solto. Aperte C para desenhar a mao '
              'livre — ou escolha uma forma na barra de cima.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// O campo de texto por cima da caixa que esta sendo escrita.
  ///
  /// Em cima do desenho, e nao numa caixinha de dialogo, para se escrever
  /// olhando o fluxo: o que se digita aparece do tamanho e no lugar em que vai
  /// ficar.
  Widget _campoDaCaixa(ThemeData theme) {
    final no = _quadro.no(_editando!);
    if (no == null) return const SizedBox.shrink();

    final r = DesenhoDoQuadro.retanguloDe(no);
    final folga = DesenhoDoQuadro.folgaDoTexto(no);

    // O nome do painel e escrito onde ele aparece: no alto, e nao no meio.
    final noAlto = no.forma.eFundo;

    return Positioned(
      left: r.left * _escala + _pan.dx,
      top: r.top * _escala + _pan.dy,
      width: r.width * _escala,
      height: r.height * _escala,
      child: Align(
        alignment: noAlto ? Alignment.topCenter : Alignment.center,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            folga * _escala,
            noAlto ? 10 * _escala : 0,
            folga * _escala,
            0,
          ),
          child: TextField(
            controller: _campo,
            focusNode: _focoDoCampo,
            maxLines: null,
            textAlign: TextAlign.center,
            cursorColor: theme.colorScheme.primary,
            cursorWidth: 1.6,
            style: TextStyle(
              color: noAlto ? AppTheme.realce : theme.colorScheme.onSurface,
              // Acompanha o zoom: o texto do campo tem que ter o tamanho do
              // texto desenhado, senao ele salta ao sair do campo.
              fontSize: (noAlto ? 13.5 : 13) * _escala,
              height: 1.3,
              fontWeight: no.forma == FormaDoNo.terminal || noAlto
                  ? FontWeight.w600
                  : FontWeight.w400,
              // A mesma letra com que o texto vai ser pintado quando o campo
              // sair de cena: sem isto, a palavra dava um salto de forma no
              // instante em que se parava de escrever.
            ).merge(_letraDoQuadro),
            decoration: const InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (texto) {
              final atual = _quadro.no(no.id);
              if (atual == null) return;
              _mexer(_quadro.comNo(_comTexto(atual, texto)));
            },
          ),
        ),
      ),
    );
  }

  /// O rotulo da flecha selecionada, num selo no meio dela — e ali que o "Sim"
  /// e o "Nao" de uma decisao vao ficar.
  Widget _campoDaFlecha(ThemeData theme) {
    final indice = _ligacaoSelecionada!;
    if (indice >= _quadro.ligacoes.length) return const SizedBox.shrink();

    final ligacao = _quadro.ligacoes[indice];
    final de = _quadro.no(ligacao.de);
    final para = _quadro.no(ligacao.para);
    if (de == null || para == null) return const SizedBox.shrink();

    final meio = DesenhoDoQuadro.meioDaRota(
      DesenhoDoQuadro.rotaEntre(de, para, desviarDe: _quadro.nos),
    );

    const largura = 190.0;
    return Positioned(
      left: (meio.dx * _escala + _pan.dx - largura / 2).clamp(
        AppTheme.gapSm,
        (_area.width - largura - AppTheme.gapSm).clamp(
          AppTheme.gapSm,
          double.infinity,
        ),
      ),
      top: (meio.dy * _escala + _pan.dy + 12).clamp(
        AppTheme.gapSm,
        (_area.height - 52).clamp(AppTheme.gapSm, double.infinity),
      ),
      width: largura,
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          padding: const EdgeInsets.fromLTRB(AppTheme.gapSm, 0, 0, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _campoDoRotulo,
                  style: theme.textTheme.bodyMedium,
                  cursorColor: theme.colorScheme.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Rotulo da flecha',
                    hintStyle: theme.textTheme.bodySmall,
                  ),
                  onChanged: (texto) =>
                      _mexer(_quadro.comRotulo(indice, texto)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 17),
                tooltip: 'Apagar a flecha',
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.error,
                onPressed: _excluirSelecao,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barra(ThemeData theme) {
    final selecionado = _selecionado == null ? null : _quadro.no(_selecionado!);

    // Duas linhas, e nao uma fila so.
    //
    // Numa fila, as formas e os controles de camera disputavam a largura da
    // janela — e com a rolagem lateral que segurava o excesso, o botao da
    // primeira forma era justamente o que saia de vista. Numa tela cheia sobra
    // altura; o que nao sobra e largura.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapLg,
        AppTheme.gapSm,
        AppTheme.gapSm,
        AppTheme.gapSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.somenteLeitura
                    ? Icons.visibility_outlined
                    : Icons.account_tree_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppTheme.gapSm),
              Flexible(
                child: Text(
                  widget.titulo,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.somenteLeitura) ...[
                const SizedBox(width: AppTheme.gapSm),
                Text('so leitura', style: theme.textTheme.labelSmall),
              ],
              const Spacer(),
              if (!widget.somenteLeitura) ...[
                IconButton(
                  icon: const Icon(Icons.undo, size: 18),
                  tooltip: 'Desfazer (Ctrl+Z)',
                  onPressed: _desfazer.isEmpty ? null : _desfazerPasso,
                ),
                IconButton(
                  icon: const Icon(Icons.redo, size: 18),
                  tooltip: 'Refazer (Ctrl+Shift+Z)',
                  onPressed: _refazer.isEmpty ? null : _refazerPasso,
                ),
                _divisor(theme),
              ],
              IconButton(
                icon: const Icon(Icons.remove, size: 18),
                tooltip: 'Afastar',
                onPressed: () => _zoom(0.9),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(_escala * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                tooltip: 'Aproximar',
                onPressed: () => _zoom(1.1),
              ),
              IconButton(
                icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
                tooltip: 'Enquadrar o quadro',
                onPressed: _enquadrar,
              ),
              // O X so quando esta tela e uma janela por cima do app. Quando o
              // quadro *e* a nota aberta, fechar ele seria fechar a nota — e
              // isso se pede na arvore de arquivos, nao aqui.
              if (widget.emJanela) ...[
                _divisor(theme),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Fechar',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppTheme.gapXs),
          // Num desenho que so se olha, as duas filas de baixo — criar uma
          // caixa, pegar a caneta — nao teriam o que fazer: elas mexem, e aqui
          // nada se mexe. No lugar delas fica a fila das duas saidas.
          if (widget.somenteLeitura) _barraDeLeitura(theme),
          if (!widget.somenteLeitura) ...[
            // A rolagem lateral fica como rede de segurança para uma janela
            // muito estreita — e agora sem `reverse`, entao o que escapa e o
            // grupo da direita, e nao a primeira forma.
            //
            // Altura fixa: os botoes so de icone sao um fio mais altos que os
            // com nome, e a linha mudando de altura ao ganhar o grupo de formas
            // mexia na altura da area de desenho embaixo dela.
            SizedBox(
              height: 30,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Criar e trocar a forma sao dois grupos separados, e nao um
                    // botao que faz as duas coisas conforme o que esta
                    // selecionado.
                    //
                    // Eram um so, e o resultado era o pior tipo de surpresa:
                    // depois de criar a primeira caixa — que nasce selecionada —
                    // o clique na forma seguinte transformava aquela caixa em vez
                    // de acrescentar outra. Quem quisesse duas caixas tinha que
                    // descobrir sozinho que precisava clicar no vazio primeiro.
                    // So o icone, e nao o icone com o nome escrito ao lado.
                    //
                    // Eram sete botoes com nome, e sete nomes nao cabem numa
                    // janela de mil e duzentos pixels junto com o grupo que troca
                    // a forma — e o que sobrava de fora, pela rolagem lateral, era
                    // justamente o grupo contextual, que e o que se procura logo
                    // depois de selecionar uma caixa. O desenho de cada forma
                    // dentro do botao ja diz o que ela e; o nome mora na dica que
                    // aparece ao parar o ponteiro em cima.
                    _rotulo(theme, 'Criar'),
                    for (final forma in FormaDoNo.values)
                      _BotaoDeForma(
                        forma: forma,
                        trocar: false,
                        onTap: () => _novaCaixa(forma),
                      ),
                    if (selecionado != null) ...[
                      _divisor(theme),
                      _rotulo(theme, 'Forma'),
                      for (final forma in FormaDoNo.values)
                        _BotaoDeForma(
                          forma: forma,
                          trocar: true,
                          selecionada: selecionado.forma == forma,
                          onTap: () => _trocarForma(forma),
                        ),
                    ],
                    if (_temSelecao) ...[
                      _divisor(theme),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: 'Excluir o que esta selecionado (Delete)',
                        color: theme.colorScheme.error,
                        onPressed: _excluirSelecao,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppTheme.gapXs),
            _barraDoDesenho(theme),
          ],
        ],
      ),
    );
  }

  /// A barra de um desenho que so se olha.
  ///
  /// Duas saidas, e nenhuma entrada. O arquivo continua como estava; o que se
  /// leva daqui e uma copia — para dentro de uma nota, onde ela passa a ser
  /// sua e pode ser mexida, ou de volta para o Excalidraw, que e de onde ela
  /// veio e onde tudo o que este app nao entende continua valendo.
  Widget _barraDeLeitura(ThemeData theme) => SizedBox(
    height: 30,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BotaoDeTexto(
            icone: Icons.note_add_outlined,
            texto: 'Copiar para uma nota',
            ligado: false,
            dica: 'Copia o desenho como bloco de quadro, para colar numa nota',
            onTap: () => unawaited(_copiarComoBloco()),
          ),
          const SizedBox(width: AppTheme.gapXs),
          _BotaoDeTexto(
            icone: Icons.copy_all_outlined,
            texto: 'Copiar para o Excalidraw',
            ligado: false,
            dica: 'Poe o desenho na area de transferencia (Ctrl+C)',
            onTap: () => unawaited(_copiarParaOExcalidraw()),
          ),
        ],
      ),
    ),
  );

  /// A linha das ferramentas de desenho.
  ///
  /// Uma terceira linha, e nao mais um punhado de botoes na segunda. As formas
  /// respondem "o que eu crio"; a caneta responde "o que a minha mao faz
  /// agora" — sao perguntas diferentes, e misturar as duas na mesma fila
  /// deixaria o botao da caneta parecendo mais uma forma de caixa.
  Widget _barraDoDesenho(ThemeData theme) {
    final tracoAberto = _ferramenta.desenha || _tracoSelecionado != null;

    return SizedBox(
      height: 30,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rotulo(theme, 'Mao'),
            for (final ferramenta in _Ferramenta.values)
              _BotaoDeFerramenta(
                ferramenta: ferramenta,
                escolhida: _ferramenta == ferramenta,
                onTap: () => _pegar(ferramenta),
              ),

            // A cor e a grossura so aparecem quando ha o que pintar com elas:
            // uma caneta na mao, ou um traço selecionado para repintar.
            if (tracoAberto) ...[
              _divisor(theme),
              for (final cor in CorDoTraco.values)
                _BotaoDeCor(
                  cor: cor,
                  tinta: DesenhoDoQuadro.tintaDe(cor, theme.colorScheme),
                  escolhida: _cor == cor,
                  onTap: () => _usarCor(cor),
                ),
              _divisor(theme),
              for (final grossura in TracoDoQuadro.grossuras)
                _BotaoDeGrossura(
                  grossura: grossura,
                  escolhida: _grossura == grossura,
                  onTap: () => _usarGrossura(grossura),
                ),
            ],

            _divisor(theme),
            _BotaoDeTexto(
              icone: Icons.draw_outlined,
              texto: 'A mao',
              ligado: _quadro.aMao,
              dica: _quadro.aMao
                  ? 'Desenhar com regua, em vez de a mao'
                  : 'Desenhar a mao, com o traço torto',
              onTap: _trocarMao,
            ),

            _divisor(theme),
            _rotulo(theme, 'Excalidraw'),
            IconButton(
              icon: const Icon(Icons.content_paste_go, size: 18),
              tooltip: 'Colar um desenho do Excalidraw (Ctrl+V)',
              onPressed: () => unawaited(_colarDoExcalidraw()),
            ),
            IconButton(
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              tooltip: 'Copiar este quadro para o Excalidraw (Ctrl+C)',
              onPressed: () => unawaited(_copiarParaOExcalidraw()),
            ),
          ],
        ),
      ),
    );
  }

  /// O nome de um grupo da barra, para os botoes ao lado nao ficarem sem dizer
  /// o que fazem com eles.
  Widget _rotulo(ThemeData theme, String texto) => Padding(
    padding: const EdgeInsets.only(left: AppTheme.gapXs, right: 2),
    child: Text(texto, style: theme.textTheme.labelSmall),
  );

  Widget _divisor(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapXs),
    child: SizedBox(
      height: 20,
      child: VerticalDivider(width: 1, color: theme.colorScheme.outline),
    ),
  );

  Widget _rodape(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.gapLg,
        vertical: AppTheme.gapSm,
      ),
      child: DefaultTextStyle(
        style:
            theme.textTheme.bodySmall ??
            const TextStyle(fontSize: 12, height: 1.5),
        child: const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text('Duplo clique escreve solto'),
              _Ponto(),
              Text('arraste a caixa para mover, o canto para redimensionar'),
              _Ponto(),
              Text('arraste uma bolinha ate outra caixa para ligar'),
              _Ponto(),
              Text('C desenha a mao, T escreve, B apaga, V volta para a seta'),
              _Ponto(),
              Text('setas ajustam o lugar (Shift, de um em um pixel)'),
              _Ponto(),
              Text('Delete apaga o que esta selecionado'),
              _Ponto(),
              Text('Ctrl+Z desfaz'),
              _Ponto(),
              Text('roda do mouse dá zoom'),
            ],
          ),
        ),
      ),
    );
  }
}

/// O separador entre duas dicas do rodape.
class _Ponto extends StatelessWidget {
  const _Ponto();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: AppTheme.gapSm),
    child: Text('·'),
  );
}

/// Um botao de ferramenta da barra: a seta, a caneta, a borracha.
class _BotaoDeFerramenta extends StatelessWidget {
  const _BotaoDeFerramenta({
    required this.ferramenta,
    required this.escolhida,
    required this.onTap,
  });

  final _Ferramenta ferramenta;
  final bool escolhida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Tooltip(
      message: '${ferramenta.rotulo} (${ferramenta.tecla.toUpperCase()})',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.gapSm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: escolhida ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Icon(
            ferramenta.icone,
            size: 16,
            color: escolhida ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Uma cor da paleta: a bolinha da propria tinta.
///
/// A cor, e nao o nome dela. "Ambar" so quer dizer alguma coisa depois de ver
/// o traço sair ambar — e ai o nome ja nao e mais necessario.
class _BotaoDeCor extends StatelessWidget {
  const _BotaoDeCor({
    required this.cor,
    required this.tinta,
    required this.escolhida,
    required this.onTap,
  });

  final CorDoTraco cor;
  final Color tinta;
  final bool escolhida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: cor.rotulo,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: tinta,
              shape: BoxShape.circle,
              // O aro so na escolhida, e da cor do app: com aro em todas, a
              // fila de bolinhas vira uma fila de alvos.
              border: escolhida
                  ? Border.all(color: scheme.primary, width: 2)
                  : Border.all(color: scheme.outline, width: 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma grossura da barra, desenhada com um risco daquela grossura.
class _BotaoDeGrossura extends StatelessWidget {
  const _BotaoDeGrossura({
    required this.grossura,
    required this.escolhida,
    required this.onTap,
  });

  final double grossura;
  final bool escolhida;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cor = escolhida ? scheme.primary : scheme.onSurfaceVariant;

    return Tooltip(
      message: 'Traço de ${grossura.toStringAsFixed(0)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.gapSm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: escolhida ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Container(
            width: 18,
            height: grossura,
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(grossura / 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Um interruptor da barra, com icone e nome.
class _BotaoDeTexto extends StatelessWidget {
  const _BotaoDeTexto({
    required this.icone,
    required this.texto,
    required this.ligado,
    required this.dica,
    required this.onTap,
  });

  final IconData icone;
  final String texto;
  final bool ligado;
  final String dica;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cor = ligado ? scheme.primary : scheme.onSurfaceVariant;

    return Tooltip(
      message: dica,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.gapSm,
            vertical: AppTheme.gapXs,
          ),
          decoration: BoxDecoration(
            color: ligado ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 15, color: cor),
              const SizedBox(width: AppTheme.gapXs),
              Text(
                texto,
                style: theme.textTheme.bodySmall?.copyWith(color: cor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Um botao de forma da barra.
///
/// O mesmo botao serve aos dois grupos — o que cria e o que troca a forma do
/// que esta selecionado —, e o que muda entre eles e so a dica: sao dois verbos
/// diferentes para o mesmo desenho, e sem a dica os dois grupos seriam duas
/// filas identicas de icones.
class _BotaoDeForma extends StatelessWidget {
  const _BotaoDeForma({
    required this.forma,
    required this.onTap,
    required this.trocar,
    this.selecionada = false,
  });

  final FormaDoNo forma;

  /// Se este botao troca a forma do que esta selecionado, em vez de criar.
  final bool trocar;

  final bool selecionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cor = selecionada ? scheme.primary : scheme.onSurfaceVariant;

    return Tooltip(
      message: trocar ? 'Deixar em ${forma.rotulo}' : 'Criar ${forma.rotulo}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.gapSm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: selecionada ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          child: CustomPaint(
            size: const Size(18, 14),
            painter: _IconeDaForma(forma: forma, cor: cor),
          ),
        ),
      ),
    );
  }
}

/// O icone de cada forma, desenhado com a propria forma: e o desenho, e nao o
/// nome, que diz o que vai aparecer no quadro.
class _IconeDaForma extends CustomPainter {
  const _IconeDaForma({required this.forma, required this.cor});

  final FormaDoNo forma;
  final Color cor;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(0.8, 0.8, size.width - 1.6, size.height - 1.6);
    final tinta = Paint()
      ..color = cor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    switch (forma) {
      case FormaDoNo.terminal:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)),
          tinta,
        );
      case FormaDoNo.processo:
        canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)),
          tinta,
        );
      case FormaDoNo.entrada:
        final inclinacao = r.width * 0.22;
        canvas.drawPath(
          Path()
            ..moveTo(r.left + inclinacao, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right - inclinacao, r.bottom)
            ..lineTo(r.left, r.bottom)
            ..close(),
          tinta,
        );
      case FormaDoNo.decisao:
        canvas.drawPath(
          Path()
            ..moveTo(r.center.dx, r.top)
            ..lineTo(r.right, r.center.dy)
            ..lineTo(r.center.dx, r.bottom)
            ..lineTo(r.left, r.center.dy)
            ..close(),
          tinta,
        );
      case FormaDoNo.elipse:
        canvas.drawOval(r, tinta);
      case FormaDoNo.fundo:
        // Um painel com um nome no alto: o traço de cima e o rotulo dele.
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(3)),
            Paint()
              ..color = cor.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          )
          ..drawLine(
            Offset(r.left + r.width * 0.3, r.top + 4),
            Offset(r.right - r.width * 0.3, r.top + 4),
            tinta..strokeWidth = 1.6,
          );
      case FormaDoNo.texto:
        for (var i = 0; i < 3; i++) {
          final y = r.top + 2 + i * (r.height - 4) / 2;
          canvas.drawLine(
            Offset(r.left, y),
            Offset(r.right - (i == 2 ? r.width * 0.35 : 0), y),
            tinta,
          );
        }
    }
  }

  @override
  bool shouldRepaint(_IconeDaForma antigo) =>
      antigo.forma != forma || antigo.cor != cor;
}
