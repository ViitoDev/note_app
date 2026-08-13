import 'package:flutter/material.dart';

import '../models/email_account.dart';
import '../models/email_message.dart';
import '../repositories/email_repository.dart';
import '../services/email_autoconfig.dart';
import 'app_theme.dart';

/// Formulario de conta de e-mail: endereço e senha.
///
/// O servidor nao e pedido. O app descobre a partir do dominio e so mostra os
/// campos tecnicos quando a descoberta falha — saber o que e "servidor IMAP"
/// nao pode ser condiçao para ler a propria caixa.
///
/// Devolve a conta ligada, ou nulo se o usuario desistir.
Future<EmailAccount?> showEmailConfigDialog(
  BuildContext context, {
  required EmailRepository repositorio,
  EmailAccount? atual,
}) => showDialog<EmailAccount>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _EmailConfigDialog(repositorio: repositorio, atual: atual),
);

class _EmailConfigDialog extends StatefulWidget {
  const _EmailConfigDialog({required this.repositorio, this.atual});

  final EmailRepository repositorio;
  final EmailAccount? atual;

  @override
  State<_EmailConfigDialog> createState() => _EmailConfigDialogState();
}

class _EmailConfigDialogState extends State<_EmailConfigDialog> {
  final _form = GlobalKey<FormState>();

  late final _email = TextEditingController(text: widget.atual?.email ?? '');
  final _senha = TextEditingController();
  late final _host = TextEditingController(text: widget.atual?.host ?? '');
  late final _porta = TextEditingController(
    text: '${widget.atual?.porta ?? 993}',
  );

  bool _senhaVisivel = false;
  bool _servidorAberto = false;
  bool _ligando = false;
  EmailException? _erro;

  @override
  void initState() {
    super.initState();
    // Reabrir uma conta que ja existe mostra o servidor dela: quem chegou aqui
    // por um erro de conexao veio justamente conferir esse campo.
    _servidorAberto = widget.atual != null;
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    _host.dispose();
    _porta.dispose();
    super.dispose();
  }

  /// Provedor reconhecido pelo dominio digitado, se houver.
  ProvedorEmail? get _provedor =>
      EmailAutoconfig.provedorDe(_email.text.trim());

  Future<void> _ligar() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() {
      _ligando = true;
      _erro = null;
    });

    // Servidor preenchido a mao vence a descoberta: se o usuario abriu o
    // campo e escreveu ali, foi porque a adivinhaçao nao serviu.
    final manual = _servidorAberto && _host.text.trim().isNotEmpty
        ? EmailAccount(
            email: _email.text.trim(),
            host: _host.text.trim(),
            porta: int.tryParse(_porta.text.trim()) ?? 993,
          )
        : null;

    try {
      final conta = await widget.repositorio.ligarComSenha(
        _email.text.trim(),
        _senha.text,
        manual: manual,
      );
      if (mounted) Navigator.of(context).pop(conta);
    } on EmailException catch (e) {
      if (!mounted) return;
      setState(() {
        _ligando = false;
        _erro = e;
        // Falhou por conexao: o proximo passo util e informar o servidor.
        if (e.falha == FalhaEmail.conexao) _servidorAberto = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provedor = _provedor;

    return AlertDialog(
      title: const Text('Conta de e-mail'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  autofocus: true,
                  enabled: !_ligando,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    hintText: 'voce@exemplo.com',
                  ),
                  // Redesenha para o aviso de senha de app acompanhar o
                  // dominio enquanto ele e digitado.
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final texto = v?.trim() ?? '';
                    if (texto.isEmpty) return 'Informe o e-mail.';
                    // Validaçao minima de proposito: quem decide se o endereço
                    // existe e o servidor, nao uma expressao regular.
                    if (!texto.contains('@') || texto.endsWith('@')) {
                      return 'Endereço incompleto.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppTheme.gapMd),
                TextFormField(
                  controller: _senha,
                  obscureText: !_senhaVisivel,
                  enabled: !_ligando,
                  decoration: InputDecoration(
                    labelText: 'Senha',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _senhaVisivel
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                      ),
                      tooltip: _senhaVisivel
                          ? 'Ocultar a senha'
                          : 'Mostrar a senha',
                      onPressed: () =>
                          setState(() => _senhaVisivel = !_senhaVisivel),
                    ),
                  ),
                  onFieldSubmitted: (_) => _ligar(),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Informe a senha.' : null,
                ),
                // O aviso so aparece para quem precisa dele. Mostrar "use senha
                // de app" para uma caixa de dominio proprio so faria o usuario
                // procurar uma tela que nao existe no painel dele.
                if (provedor?.senhaDeApp ?? false) ...[
                  const SizedBox(height: AppTheme.gapMd),
                  _Aviso(provedor: provedor!),
                ],
                const SizedBox(height: AppTheme.gapSm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(
                      _servidorAberto ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                    ),
                    label: const Text('Servidor'),
                    onPressed: _ligando
                        ? null
                        : () => setState(
                            () => _servidorAberto = !_servidorAberto,
                          ),
                  ),
                ),
                if (_servidorAberto) _campos(theme),
                if (_erro != null) ...[
                  const SizedBox(height: AppTheme.gapMd),
                  _Falha(erro: _erro!),
                ],
                const SizedBox(height: AppTheme.gapMd),
                Text(
                  'A senha e guardada cifrada pelo Windows, presa a esta conta '
                  'de usuario. O app so le a caixa: nao envia, nao apaga e nao '
                  'marca nada como lido.',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _ligando ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _ligando ? null : _ligar,
          child: _ligando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Ligar'),
        ),
      ],
    );
  }

  Widget _campos(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppTheme.gapSm),
        DropdownButtonFormField<ProvedorEmail>(
          initialValue: ProvedorEmail.porHost(_host.text.trim()),
          // Sem isto o nome mais longo da lista estoura a largura do dialogo
          // em vez de ser cortado com reticencias.
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Provedor'),
          items: [
            for (final p in ProvedorEmail.values)
              DropdownMenuItem(value: p, child: Text(p.label)),
          ],
          onChanged: _ligando
              ? null
              : (p) {
                  if (p == null || p == ProvedorEmail.manual) return;
                  setState(() {
                    _host.text = p.host;
                    _porta.text = '${p.porta}';
                  });
                },
        ),
        const SizedBox(height: AppTheme.gapMd),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _host,
                enabled: !_ligando,
                decoration: const InputDecoration(
                  labelText: 'Servidor IMAP',
                  helperText: 'Em branco, o app tenta descobrir.',
                ),
              ),
            ),
            const SizedBox(width: AppTheme.gapMd),
            Expanded(
              child: TextFormField(
                controller: _porta,
                enabled: !_ligando,
                decoration: const InputDecoration(labelText: 'Porta'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  // A porta so importa quando ha servidor escrito a mao.
                  if (!_servidorAberto || _host.text.trim().isEmpty) {
                    return null;
                  }
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n <= 0 || n > 65535) return 'Invalida.';
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Onde achar a senha de app, para os provedores que exigem uma.
class _Aviso extends StatelessWidget {
  const _Aviso({required this.provedor});

  final ProvedorEmail provedor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final texto = switch (provedor) {
      ProvedorEmail.gmail =>
        'O Gmail recusa a senha normal no IMAP. Gere uma senha de app em '
            'Conta Google > Segurança > Senhas de app — ou use o botao '
            '"Entrar com o Google", que dispensa senha.',
      ProvedorEmail.outlook =>
        'O Outlook recusa a senha normal no IMAP. Gere uma senha de app em '
            'conta.microsoft.com > Segurança > Opçoes avançadas.',
      ProvedorEmail.yahoo =>
        'O Yahoo pede senha de app: Informaçoes da conta > Segurança da conta '
            '> Gerar senha de app.',
      _ =>
        'Este provedor pode exigir uma senha de app em vez da senha normal, '
            'se a conta tiver verificaçao em duas etapas.',
    };

    return Container(
      padding: const EdgeInsets.all(AppTheme.gapMd),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.key_outlined, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppTheme.gapSm),
          Expanded(child: Text(texto, style: theme.textTheme.labelSmall)),
        ],
      ),
    );
  }
}

class _Falha extends StatelessWidget {
  const _Falha({required this.erro});

  final EmailException erro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTheme.gapMd),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 15, color: scheme.error),
          const SizedBox(width: AppTheme.gapSm),
          Expanded(
            child: Text(
              erro.detalhe ?? erro.falha.mensagem,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
