import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app_theme.dart';

/// Navegador de diretorios escrito em Dart puro, sem plugin nativo.
///
/// Existe por dois motivos praticos:
///   * o seletor nativo do Android devolve URI `content://` do SAF, e o app
///     precisa de caminho real para ler a pasta replicada pelo sync;
///   * o `file_picker` nao compila com o Kotlin embutido do AGP 9.
///
/// Como o app ja tem acesso total ao armazenamento, percorrer as pastas com
/// `dart:io` funciona igual no Windows e no Android.
Future<String?> showFolderPicker(BuildContext context, {String? startPath}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _FolderPickerDialog(startPath: startPath),
  );
}

class _FolderPickerDialog extends StatefulWidget {
  const _FolderPickerDialog({this.startPath});

  final String? startPath;

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  /// `null` significa a tela de raizes: as unidades no Windows, os volumes de
  /// armazenamento no Android.
  Directory? _current;
  List<Directory> _entries = const [];
  List<Directory> _roots = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _roots = await _findRoots();
    final start = widget.startPath;
    if (start != null && Directory(start).existsSync()) {
      await _enter(Directory(start));
    } else if (_roots.length == 1) {
      await _enter(_roots.first);
    } else {
      setState(() => _loading = false);
    }
  }

  /// No Windows, sonda as letras de unidade — `dart:io` nao lista drives.
  /// No Android, os caminhos usuais de armazenamento interno e cartao SD.
  Future<List<Directory>> _findRoots() async {
    final found = <Directory>[];

    if (Platform.isWindows) {
      for (
        var letter = 'A'.codeUnitAt(0);
        letter <= 'Z'.codeUnitAt(0);
        letter++
      ) {
        final dir = Directory('${String.fromCharCode(letter)}:\\');
        if (dir.existsSync()) found.add(dir);
      }
      return found;
    }

    for (final candidate in const [
      '/storage/emulated/0',
      '/sdcard',
      '/storage',
    ]) {
      final dir = Directory(candidate);
      if (dir.existsSync()) {
        found.add(dir);
        break;
      }
    }
    return found.isEmpty ? [Directory('/')] : found;
  }

  Future<void> _enter(Directory dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final children = <Directory>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory && !p.basename(entity.path).startsWith('.')) {
          children.add(entity);
        }
      }
      children.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _current = dir;
        _entries = children;
        _loading = false;
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        // Pasta de sistema sem permissao: mostra o aviso mas deixa voltar.
        _current = dir;
        _entries = const [];
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _goUp() {
    final current = _current;
    if (current == null) return;
    final parent = current.parent;
    // Ja esta numa raiz: volta para a lista de raizes.
    if (parent.path == current.path ||
        _roots.any((r) => r.path == current.path)) {
      setState(() {
        _current = null;
        _entries = const [];
        _error = null;
      });
      return;
    }
    _enter(parent);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;

    return AlertDialog(
      title: const Text('Escolher a pasta do vault'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Subir um nivel',
                    onPressed: current == null ? null : _goUp,
                  ),
                  Expanded(
                    child: Text(
                      current?.path ?? 'Este dispositivo',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Text(
                  'Sem acesso a esta pasta: $_error',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _list(theme, current),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: current == null
              ? null
              : () => Navigator.pop(context, current.path),
          child: const Text('Usar esta pasta'),
        ),
      ],
    );
  }

  Widget _list(ThemeData theme, Directory? current) {
    if (current == null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
        children: [
          for (final root in _roots)
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              hoverColor: theme.colorScheme.surfaceContainerHigh,
              leading: const Icon(Icons.storage_outlined, size: 17),
              title: Text(root.path, style: theme.textTheme.bodyMedium),
              onTap: () => _enter(root),
            ),
        ],
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Text('Nenhuma subpasta aqui.', style: theme.textTheme.bodySmall),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.gapMd),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final dir = _entries[index];
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          ),
          hoverColor: theme.colorScheme.surfaceContainerHigh,
          leading: const Icon(Icons.folder_outlined, size: 17),
          title: Text(
            p.basename(dir.path),
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.chevron_right,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          onTap: () => _enter(dir),
        );
      },
    );
  }
}
