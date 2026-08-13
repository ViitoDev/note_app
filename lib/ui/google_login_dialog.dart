import 'package:flutter/material.dart';

import '../services/abrir_url.dart';
import '../services/google_client_file.dart';
import 'app_theme.dart';

/// As credenciais do projeto do usuario no Google Cloud.
typedef CredenciaisGoogle = ({String clientId, String clientSecret});

/// Pede o Client ID do Google Cloud, com o passo a passo do cadastro.
///
/// Este dialogo existe por uma limitaçao que nao da para contornar: o Google so
/// emite token para um aplicativo registrado, e o registro tem que ser feito
/// pelo dono da conta, no navegador. O app pede isso uma vez e nunca mais.
Future<CredenciaisGoogle?> showGoogleSetupDialog(
  BuildContext context, {
  String? clientIdAtual,
  GoogleClientFile arquivos = const GoogleClientFile(),
}) => showDialog<CredenciaisGoogle>(
  context: context,
  builder: (_) =>
      _GoogleSetupDialog(clientIdAtual: clientIdAtual, arquivos: arquivos),
);

class _GoogleSetupDialog extends StatefulWidget {
  const _GoogleSetupDialog({required this.arquivos, this.clientIdAtual});

  final String? clientIdAtual;

  /// Leitor do JSON baixado. Injetavel para o teste nao varrer a pasta de
  /// Downloads da maquina de quem roda a suite.
  final GoogleClientFile arquivos;

  @override
  State<_GoogleSetupDialog> createState() => _GoogleSetupDialogState();
}

class _GoogleSetupDialogState extends State<_GoogleSetupDialog> {
  final _form = GlobalKey<FormState>();
  late final _id = TextEditingController(text: widget.clientIdAtual ?? '');
  final _segredo = TextEditingController();

  /// Cada passo com a pagina que ele exige, para o botao levar direto la.
  static const _passos = <({String texto, String? url})>[
    (
      texto: 'Crie um projeto (qualquer nome).',
      url: 'https://console.cloud.google.com/projectcreate',
    ),
    (
      texto: 'Ative a Gmail API no projeto.',
      url: 'https://console.cloud.google.com/apis/library/gmail.googleapis.com',
    ),
    (
      texto:
          'Em "Público-alvo", escolha Externo e adicione em "Usuários de '
          'teste" cada conta que você pode usar para entrar — depois clique '
          'em Salvar. Conta fora da lista recebe "Acesso bloqueado".',
      // A pagina saiu de "Tela de permissao OAuth" na reorganizaçao de 2025;
      // este e o endereço novo, e e onde a lista de testadores mora hoje.
      url: 'https://console.cloud.google.com/auth/audience',
    ),
    (
      texto:
          'Crie um ID do cliente OAuth do tipo "Aplicativo para computador" '
          'e clique em "Fazer download do JSON".',
      url: 'https://console.cloud.google.com/apis/credentials',
    ),
    (texto: 'Volte aqui e clique em "Ler o JSON baixado".', url: null),
  ];

  bool _procurando = false;
  String? _aviso;
  String? _origem;

  /// Le o `client_secret_*.json` que o navegador acabou de baixar.
  Future<void> _lerJson() async {
    setState(() {
      _procurando = true;
      _aviso = null;
    });

    try {
      final cred = await widget.arquivos.procurar();
      if (!mounted) return;
      setState(() {
        _id.text = cred.clientId;
        _segredo.text = cred.clientSecret;
        _origem = cred.arquivo;
        _procurando = false;
      });
    } on CredencialException catch (e) {
      if (!mounted) return;
      setState(() {
        _aviso = e.falha.mensagem;
        _procurando = false;
      });
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _segredo.dispose();
    super.dispose();
  }

  void _confirmar() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(
      context,
    ).pop((clientId: _id.text.trim(), clientSecret: _segredo.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Cadastrar o app no Google'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'O Google so aceita login de um app registrado, e o registro '
                  'precisa ser feito por voce, com a sua conta. E uma vez so — '
                  'depois disso o app entra sozinho.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppTheme.gapLg),
                for (final (i, passo) in _passos.indexed)
                  _Passo(numero: i + 1, texto: passo.texto, url: passo.url),
                const SizedBox(height: AppTheme.gapMd),
                FilledButton.tonalIcon(
                  icon: _procurando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined, size: 16),
                  label: const Text('Ler o JSON baixado'),
                  onPressed: _procurando ? null : _lerJson,
                ),
                if (_origem != null) ...[
                  const SizedBox(height: AppTheme.gapSm),
                  Text(
                    'Lido de $_origem',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
                if (_aviso != null) ...[
                  const SizedBox(height: AppTheme.gapSm),
                  Text(
                    _aviso!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppTheme.gapLg),
                TextFormField(
                  controller: _id,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'ID do cliente',
                    hintText: '000000-abc.apps.googleusercontent.com',
                  ),
                  validator: (v) {
                    final texto = v?.trim() ?? '';
                    if (texto.isEmpty) return 'Cole o ID do cliente.';
                    // Erro comum: colar a chave secreta neste campo. O sufixo
                    // e a unica parte previsivel do formato.
                    if (!texto.endsWith('.apps.googleusercontent.com')) {
                      return 'Deve terminar em .apps.googleusercontent.com';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.gapMd),
                TextFormField(
                  controller: _segredo,
                  decoration: const InputDecoration(
                    labelText: 'Chave secreta do cliente',
                    hintText: 'GOCSPX-...',
                  ),
                  validator: (v) =>
                      (v?.trim() ?? '').isEmpty ? 'Cole a chave.' : null,
                ),
                const SizedBox(height: AppTheme.gapMd),
                Text(
                  'Os dois ficam guardados cifrados nesta maquina. Numa tela '
                  'de permissao "Externo" sem verificaçao, o Google avisa que '
                  'o app nao e verificado — e esperado, o app e seu.',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: AppTheme.gapSm),
                Text(
                  'Atençao: enquanto a tela de permissao estiver em modo '
                  'Teste, o Google expira o acesso a cada 7 dias e este login '
                  'tera que ser refeito. Para uma caixa do Gmail que voce vai '
                  'ler todo dia, senha de app costuma dar menos trabalho.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _confirmar,
          child: const Text('Entrar com o Google'),
        ),
      ],
    );
  }
}

class _Passo extends StatelessWidget {
  const _Passo({required this.numero, required this.texto, this.url});

  final int numero;
  final String texto;

  /// Pagina do Google Cloud que este passo pede. O botao leva direto la, em
  /// vez de o usuario ter que caçar o menu.
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final destino = url;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.gapSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '$numero',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.gapMd),
          Expanded(child: Text(texto, style: theme.textTheme.bodySmall)),
          if (destino != null)
            IconButton(
              icon: const Icon(Icons.open_in_new, size: 15),
              tooltip: 'Abrir esta pagina no navegador',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
              padding: EdgeInsets.zero,
              onPressed: () => abrirNoNavegador(Uri.parse(destino)),
            ),
        ],
      ),
    );
  }
}

/// Botao "Entrar com o Google", no estilo que a marca pede.
class BotaoGoogle extends StatelessWidget {
  const BotaoGoogle({super.key, required this.onPressed, this.ocupado = false});

  final VoidCallback onPressed;
  final bool ocupado;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return OutlinedButton(
      onPressed: ocupado ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapLg,
          vertical: AppTheme.gapMd,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ocupado)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const _LogoGoogle(),
          const SizedBox(width: AppTheme.gapMd),
          Text(
            ocupado ? 'Aguardando o navegador...' : 'Entrar com o Google',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// O "G" de quatro cores, desenhado em vez de carregado.
///
/// Um SVG ou PNG exigiria asset e pacote de imagem; o desenho cabe aqui e nao
/// pesa nada.
class _LogoGoogle extends StatelessWidget {
  const _LogoGoogle();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 16, height: 16, child: CustomPaint(painter: _G()));
}

class _G extends CustomPainter {
  const _G();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final centro = Offset(r, r);
    final traco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.28;
    final raio = Rect.fromCircle(center: centro, radius: r * 0.86);

    // Os quatro arcos da marca, em sentido horario a partir da direita.
    const cores = [
      (start: -0.35, sweep: 1.2, cor: Color(0xFF4285F4)),
      (start: 0.85, sweep: 1.6, cor: Color(0xFF34A853)),
      (start: 2.45, sweep: 1.3, cor: Color(0xFFFBBC05)),
      (start: 3.75, sweep: 1.6, cor: Color(0xFFEA4335)),
    ];
    for (final arco in cores) {
      canvas.drawArc(
        raio,
        arco.start,
        arco.sweep,
        false,
        traco..color = arco.cor,
      );
    }

    // A barra horizontal que fecha o G.
    canvas.drawLine(
      Offset(centro.dx + r * 0.1, centro.dy),
      Offset(centro.dx + r * 0.86, centro.dy),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = size.width * 0.28,
    );
  }

  @override
  bool shouldRepaint(_G oldDelegate) => false;
}
