import 'package:flutter/material.dart';

import 'ui/app_theme.dart';
import 'ui/ui_prefs.dart';
import 'ui/vault_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // As preferencias de interface sao lidas antes da primeira tela para os
  // paineis ja nascerem no estado escolhido, sem piscar no padrao.
  await UiPrefs.load();
  runApp(const NotasApp());
}

class NotasApp extends StatelessWidget {
  const NotasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notas',
      debugShowCheckedModeBanner: false,
      // Tema unico e escuro: o app e uma superficie de leitura e escrita longa,
      // e manter as duas variantes dobraria o custo de acerto visual sem ganho.
      theme: AppTheme.dark,
      home: const VaultScreen(),
    );
  }
}
