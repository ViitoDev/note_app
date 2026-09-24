import 'package:flutter/material.dart';

import '../servidor/cliente_webdav.dart';
import '../servidor/config_do_servidor.dart';
import 'app_theme.dart';

/// Formulario do servidor privado: endereco, usuario e senha.
///
/// O botao "Testar" faz um PROPFIND de verdade antes de salvar. Guardar uma
/// configuracao que nunca funcionou e o jeito mais rapido de o usuario passar
/// uma semana achando que sincronizou.
///
/// Devolve a configuracao salva, ou nulo se o usuario desistir.
Future<ConfigDoServidor?> showServidorConfigDialog(
  BuildContext context, {
  required ConfigDoServidor atual,
  ServidorPrefs prefs = const ServidorPrefs(),
}) => showDialog<ConfigDoServidor>(
  context: context,
  builder: (_) => _ServidorConfigDialog(atual: atual, prefs: prefs),
);

class _ServidorConfigDialog extends StatefulWidget {
  const _ServidorConfigDialog({required this.atual, required this.prefs});

  final ConfigDoServidor atual;
  final ServidorPrefs prefs;

  @override
  State<_ServidorConfigDialog> createState() => _ServidorConfigDialogState();
}

class _ServidorConfigDialogState extends State<_ServidorConfigDialog> {
  final _form = GlobalKey<FormState>();

  late final _endereco = TextEditingController(text: widget.atual.endereco);
  late final _usuario = TextEditingController(text: widget.atual.usuario);
  late final _senha = TextEditingController(text: widget.atual.senha);

  bool _senhaVisivel = false;
  bool _testando = false;
  String? _erro;
  bool _passou = false;

  @override
  void dispose() {
    _endereco.dispose();
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  ConfigDoServidor get _digitado => ConfigDoServidor(
    endereco: _endereco.text.trim(),
    usuario: _usuario.text.trim(),
    senha: _senha.text,
  );

  Future<void> _testar() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _testando = true;
      _erro = null;
      _passou = false;
    });

    final config = _digitado;
    final cliente = ClienteWebDav(
      base: config.uri!,
      usuario: config.usuario,
      senha: config.senha,
    );

    try {
      await cliente.testar();
      if (mounted) setState(() => _passou = true);
    } on ServidorException catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } finally {
      cliente.fechar();
      if (mounted) setState(() => _testando = false);
    }
  }

  Future<void> _salvar() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final config = _digitado;
    await widget.prefs.salvar(config);
    if (mounted) Navigator.of(context).pop(config);
  }

  Future<void> _desligar() async {
    await widget.prefs.limpar();
    if (mounted) Navigator.of(context).pop(ConfigDoServidor.vazia);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Servidor do vault'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'As notas continuam sendo arquivos na sua pasta. O servidor '
                  'e uma copia que mantem as maquinas iguais — editar sem '
                  'rede funciona, e o que mudou sobe depois.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.gapLg),

                TextFormField(
                  controller: _endereco,
                  autofocus: true,
                  enabled: !_testando,
                  decoration: const InputDecoration(
                    labelText: 'Endereco',
                    hintText:
                        'http://192.168.0.10:5005/  ou  [2804::e044]:5005',
                  ),
                  onChanged: (_) => setState(() => _passou = false),
                  validator: (v) {
                    final texto = v?.trim() ?? '';
                    if (texto.isEmpty) return 'Informe o endereco do servidor.';
                    if (ConfigDoServidor(
                          endereco: texto,
                          usuario: '',
                          senha: '',
                        ).uri ==
                        null) {
                      return 'Endereco invalido. Use http://ip:porta/ — '
                          'IPv6 vai entre colchetes.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.gapMd),

                TextFormField(
                  controller: _usuario,
                  enabled: !_testando,
                  decoration: const InputDecoration(labelText: 'Usuario'),
                  onChanged: (_) => setState(() => _passou = false),
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'Informe o usuario do WebDAV.'
                      : null,
                ),
                const SizedBox(height: AppTheme.gapMd),

                TextFormField(
                  controller: _senha,
                  enabled: !_testando,
                  obscureText: !_senhaVisivel,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaVisivel
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      tooltip: _senhaVisivel ? 'Ocultar' : 'Mostrar',
                      onPressed: () =>
                          setState(() => _senhaVisivel = !_senhaVisivel),
                    ),
                  ),
                  onChanged: (_) => setState(() => _passou = false),
                  validator: (v) =>
                      (v?.isEmpty ?? true) ? 'Informe a senha.' : null,
                ),

                if (_erro != null) ...[
                  const SizedBox(height: AppTheme.gapLg),
                  _Aviso(
                    icone: Icons.error_outline,
                    cor: theme.colorScheme.error,
                    texto: _erro!,
                  ),
                ],
                if (_passou) ...[
                  const SizedBox(height: AppTheme.gapLg),
                  _Aviso(
                    icone: Icons.check_circle_outline,
                    cor: theme.colorScheme.primary,
                    texto: 'O servidor respondeu. Salvar liga a sincronizacao.',
                  ),
                ],

                const SizedBox(height: AppTheme.gapLg),
                Text(
                  'A senha e cifrada pelo DPAPI do Windows antes de tocar o '
                  'disco — o arquivo copiado para outra maquina nao abre. Em '
                  'HTTP, porem, ela viaja legivel pela rede local; so ponha '
                  'este servidor na internet atras de HTTPS.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // Sem `Spacer` para empurrar o "Desligar" para a esquerda: `actions` vai
      // para um `OverflowBar`, que nao e um Flex, e `Spacer` e um `Expanded`
      // por dentro — fora de um Flex ele estoura na construçao, e em release
      // o conteudo inteiro do dialogo vira um retangulo cinza.
      actions: [
        if (widget.atual.configurado)
          TextButton(
            onPressed: _testando ? null : _desligar,
            child: const Text('Desligar'),
          ),
        TextButton(
          onPressed: _testando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _testando ? null : _testar,
          child: _testando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Testar'),
        ),
        FilledButton(
          onPressed: _testando ? null : _salvar,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.cor, required this.texto});

  final IconData icone;
  final Color cor;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 16, color: cor),
        const SizedBox(width: AppTheme.gapSm),
        Expanded(
          child: Text(
            texto,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cor),
          ),
        ),
      ],
    );
  }
}
