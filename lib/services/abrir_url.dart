import 'dart:io';

/// Abre uma URL no navegador padrao do sistema.
///
/// Via `rundll32` de proposito, e nao pelo `url_launcher`: o plugin traria
/// codigo nativo para compilar, e aqui uma chamada do proprio Windows resolve.
Future<void> abrirNoNavegador(Uri url) async {
  if (!Platform.isWindows) return;
  await Process.run('rundll32', ['url.dll,FileProtocolHandler', '$url']);
}
