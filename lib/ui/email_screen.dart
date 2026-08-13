import 'package:flutter/material.dart';

import '../models/email_account.dart';
import '../models/email_message.dart';
import 'app_theme.dart';
import 'google_login_dialog.dart';
import 'resizable_split.dart';

/// Os jeitos de ligar ou trocar a conta.
enum AcaoConta {
  entrarComGoogle('Entrar com o Google', Icons.login),
  senhaDeApp('Usar senha de app', Icons.key_outlined),
  refazerCadastroGoogle('Refazer o cadastro do Google', Icons.build_outlined);

  const AcaoConta(this.label, this.icone);

  final String label;
  final IconData icone;
}

/// Painel de e-mail: lista de mensagens e leitura.
///
/// So le. Nao envia, nao apaga e nao marca como lida — abrir uma mensagem aqui
/// nao muda nada na caixa de entrada de verdade.
class EmailScreen extends StatefulWidget {
  const EmailScreen({
    super.key,
    required this.conta,
    required this.mensagens,
    required this.carregando,
    required this.erro,
    required this.onRefresh,
    required this.onConta,
    this.entrando = false,
  });

  /// Nula enquanto nao houver conta configurada.
  final EmailAccount? conta;

  final List<EmailMessage> mensagens;
  final bool carregando;
  final EmailException? erro;
  final VoidCallback onRefresh;

  /// Pedido de ligar, trocar ou recadastrar a conta.
  final ValueChanged<AcaoConta> onConta;

  /// O consentimento do Google esta aberto no navegador.
  final bool entrando;

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final _filtroCtrl = TextEditingController();
  String _filtro = '';
  int? _abertaUid;

  @override
  void dispose() {
    _filtroCtrl.dispose();
    super.dispose();
  }

  List<EmailMessage> get _visiveis =>
      widget.mensagens.where((m) => m.combina(_filtro)).toList();

  EmailMessage? get _aberta {
    final uid = _abertaUid;
    if (uid == null) return null;
    for (final m in widget.mensagens) {
      if (m.uid == uid) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.conta == null) {
      // O erro entra aqui tambem: um login recusado deixa a conta nula, e sem
      // isto a tela voltaria ao convite inicial como se nada tivesse
      // acontecido.
      return _SemConta(
        onConta: widget.onConta,
        entrando: widget.entrando,
        erro: widget.erro,
      );
    }

    return Column(
      children: [
        _barra(context),
        const Divider(height: 1),
        Expanded(child: _corpo(context)),
      ],
    );
  }

  Widget _barra(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.gapMd,
        AppTheme.gapSm,
        AppTheme.gapSm,
        AppTheme.gapSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _filtroCtrl,
                style: theme.textTheme.bodySmall,
                decoration: const InputDecoration(
                  hintText: 'Filtrar e-mails',
                  prefixIcon: Icon(Icons.search, size: 16),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filtro = v),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.gapXs),
          PopupMenuButton<AcaoConta>(
            icon: const Icon(Icons.settings_outlined, size: 17),
            tooltip: 'Trocar a conta de e-mail',
            onSelected: widget.onConta,
            itemBuilder: (context) => [
              for (final acao in AcaoConta.values)
                PopupMenuItem(
                  value: acao,
                  height: 38,
                  child: Row(
                    children: [
                      Icon(acao.icone, size: 15),
                      const SizedBox(width: AppTheme.gapMd),
                      Text(acao.label),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Buscar e-mails novos',
            visualDensity: VisualDensity.compact,
            onPressed: widget.carregando ? null : widget.onRefresh,
          ),
        ],
      ),
    );
  }

  Widget _corpo(BuildContext context) {
    if (widget.carregando && widget.mensagens.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final erro = widget.erro;
    if (erro != null && widget.mensagens.isEmpty) {
      return _Erro(erro: erro, onConta: widget.onConta);
    }

    if (widget.mensagens.isEmpty) {
      return const _Aviso(
        icone: Icons.inbox_outlined,
        titulo: 'Caixa de entrada vazia',
        detalhe: 'Nao ha mensagens nesta caixa.',
      );
    }

    final aberta = _aberta;
    final lista = _lista(context);

    if (aberta == null) return lista;

    // Lista em cima, mensagem embaixo: o painel costuma ser estreito, e lado a
    // lado espremeria as duas colunas.
    return ResizableSplit(
      storageKey: 'email_leitura',
      axis: Axis.vertical,
      minFirst: 120,
      minSecond: 140,
      initialFirst: 220,
      first: lista,
      second: _Leitura(
        mensagem: aberta,
        onFechar: () => setState(() => _abertaUid = null),
      ),
    );
  }

  Widget _lista(BuildContext context) {
    final visiveis = _visiveis;
    if (visiveis.isEmpty) {
      return const _Aviso(
        icone: Icons.search_off,
        titulo: 'Nada encontrado',
        detalhe: 'Nenhuma mensagem combina com o filtro.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.gapXs),
      itemCount: visiveis.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 14),
      itemBuilder: (context, i) {
        final m = visiveis[i];
        return _LinhaEmail(
          mensagem: m,
          selecionada: m.uid == _abertaUid,
          onTap: () =>
              setState(() => _abertaUid = m.uid == _abertaUid ? null : m.uid),
        );
      },
    );
  }
}

class _LinhaEmail extends StatelessWidget {
  const _LinhaEmail({
    required this.mensagem,
    required this.selecionada,
    required this.onTap,
  });

  final EmailMessage mensagem;
  final bool selecionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        color: selecionada ? scheme.primaryContainer : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.gapMd,
          vertical: AppTheme.gapSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ponto so nas nao lidas: e a unica informaçao que a linha precisa
            // dar antes de ser aberta.
            Padding(
              padding: const EdgeInsets.only(top: 5, right: AppTheme.gapSm),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mensagem.lida ? Colors.transparent : scheme.primary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mensagem.quem,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: mensagem.lida
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTheme.gapSm),
                      Text(
                        _quando(mensagem.data),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    mensagem.titulo,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (mensagem.previa.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      mensagem.previa,
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data curta: hora no mesmo dia, dia e mes no resto do ano, com o ano so
/// quando ele muda. Data cheia em cada linha roubaria largura do assunto.
String _quando(DateTime data) {
  final agora = DateTime.now();
  String dois(int n) => n.toString().padLeft(2, '0');

  if (data.year == agora.year &&
      data.month == agora.month &&
      data.day == agora.day) {
    return '${dois(data.hour)}:${dois(data.minute)}';
  }
  if (data.year == agora.year) return '${dois(data.day)}/${dois(data.month)}';
  return '${dois(data.day)}/${dois(data.month)}/${data.year}';
}

class _Leitura extends StatelessWidget {
  const _Leitura({required this.mensagem, required this.onFechar});

  final EmailMessage mensagem;
  final VoidCallback onFechar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.gapLg,
              AppTheme.gapMd,
              AppTheme.gapSm,
              AppTheme.gapSm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mensagem.titulo, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${mensagem.quem}  <${mensagem.remetente}>',
                        style: theme.textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Fechar a mensagem',
                  visualDensity: VisualDensity.compact,
                  onPressed: onFechar,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.gapLg),
              child: SelectableText(
                mensagem.corpo.isEmpty
                    ? '(mensagem sem texto)'
                    : mensagem.corpo,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SemConta extends StatelessWidget {
  const _SemConta({
    required this.onConta,
    required this.entrando,
    required this.erro,
  });

  final ValueChanged<AcaoConta> onConta;
  final bool entrando;
  final EmailException? erro;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final falha = erro;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mail_outline,
              size: 34,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppTheme.gapMd),
            Text('Nenhuma conta ligada', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.gapSm),
            Text(
              'Ligue uma conta de e-mail para ver a caixa de entrada aqui '
              'dentro.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (falha != null) ...[
              const SizedBox(height: AppTheme.gapMd),
              Text(
                falha.detalhe ?? falha.falha.mensagem,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppTheme.gapLg),
            BotaoGoogle(
              ocupado: entrando,
              onPressed: () => onConta(AcaoConta.entrarComGoogle),
            ),
            const SizedBox(height: AppTheme.gapSm),
            TextButton(
              onPressed: entrando ? null : () => onConta(AcaoConta.senhaDeApp),
              child: const Text('Outro provedor, com senha de app'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro({required this.erro, required this.onConta});

  final EmailException erro;
  final ValueChanged<AcaoConta> onConta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 30, color: scheme.error),
            const SizedBox(height: AppTheme.gapMd),
            Text(
              erro.falha.mensagem,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            if (erro.detalhe != null) ...[
              const SizedBox(height: AppTheme.gapSm),
              Text(
                erro.detalhe!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: AppTheme.gapLg),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings_outlined, size: 15),
              label: const Text('Rever a conta'),
              onPressed: () => onConta(AcaoConta.entrarComGoogle),
            ),
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icone,
    required this.titulo,
    required this.detalhe,
  });

  final IconData icone;
  final String titulo;
  final String detalhe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 30, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppTheme.gapMd),
            Text(titulo, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppTheme.gapXs),
            Text(
              detalhe,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
