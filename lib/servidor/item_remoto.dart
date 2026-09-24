/// Um item como o servidor o descreve: pasta ou arquivo, com a data de
/// gravacao que a sincronizacao usa para decidir quem mudou.
///
/// O tipo do pacote de XML fica fora daqui de proposito. A camada de sync so
/// precisa de caminho, tipo e data, e manter isso num tipo nosso permite
/// testar o sincronizador sem forjar um `<D:multistatus>` inteiro.
class ItemRemoto {
  const ItemRemoto({
    required this.caminho,
    required this.ehPasta,
    this.modificadoEm,
    this.tamanho,
    this.etag,
  });

  /// Caminho relativo a raiz do vault, sempre com `/` — nunca `\`, mesmo
  /// falando com o app no Windows. E a mesma chave usada no estado da sync.
  final String caminho;

  final bool ehPasta;
  final DateTime? modificadoEm;
  final int? tamanho;
  final String? etag;

  /// Nome do item, sem a pasta que o contem.
  String get nome {
    final corte = caminho.lastIndexOf('/');
    return corte < 0 ? caminho : caminho.substring(corte + 1);
  }

  @override
  String toString() => '${ehPasta ? 'pasta' : 'arquivo'} $caminho';
}
