import 'package:flutter_test/flutter_test.dart';
import 'package:notas_app/models/vault_entry.dart';
import 'package:notas_app/models/vault_order.dart';

const _a = VaultFile(id: r'C:\v\A.md', name: 'A.md');
const _b = VaultFile(id: r'C:\v\B.md', name: 'B.md');
const _c = VaultFile(id: r'C:\v\C.md', name: 'C.md');

List<String> _nomes(List<VaultEntry> entradas) =>
    entradas.map((e) => e.name).toList();

void main() {
  group('ordenar', () {
    test('sem ordem guardada devolve a lista como veio', () {
      expect(_nomes(VaultOrder.vazia.ordenar('', [_a, _b, _c])), [
        'A.md',
        'B.md',
        'C.md',
      ]);
    });

    test('respeita a ordem escolhida', () {
      final ordem = VaultOrder.vazia.comOrdem('', ['C.md', 'A.md', 'B.md']);
      expect(_nomes(ordem.ordenar('', [_a, _b, _c])), ['C.md', 'A.md', 'B.md']);
    });

    test('quem nao esta na lista vai depois, na ordem que veio', () {
      // Uma nota criada fora do app precisa aparecer sem exigir que a ordem
      // inteira seja reescrita.
      final ordem = VaultOrder.vazia.comOrdem('', ['C.md']);
      expect(_nomes(ordem.ordenar('', [_a, _b, _c])), ['C.md', 'A.md', 'B.md']);
    });

    test('nome guardado que nao existe mais e ignorado', () {
      final ordem = VaultOrder.vazia.comOrdem('', [
        'Apagada.md',
        'B.md',
        'A.md',
      ]);
      expect(_nomes(ordem.ordenar('', [_a, _b])), ['B.md', 'A.md']);
    });

    test('nome repetido na lista nao duplica a entrada', () {
      final ordem = VaultOrder.vazia.comOrdem('', ['A.md', 'A.md', 'B.md']);
      expect(_nomes(ordem.ordenar('', [_a, _b])), ['A.md', 'B.md']);
    });

    test('a ordem de uma pasta nao vale para outra', () {
      final ordem = VaultOrder.vazia.comOrdem('Estudos', ['C.md', 'A.md']);
      expect(_nomes(ordem.ordenar('', [_a, _c])), ['A.md', 'C.md']);
    });
  });

  group('aplicar na arvore', () {
    test('reordena a raiz e cada subpasta pela sua propria chave', () {
      const sub = VaultFolder(
        id: r'C:\v\Estudos',
        name: 'Estudos',
        children: [
          VaultFile(id: r'C:\v\Estudos\X.md', name: 'X.md'),
          VaultFile(id: r'C:\v\Estudos\Y.md', name: 'Y.md'),
        ],
      );
      const raiz = VaultFolder(id: r'C:\v', name: 'v', children: [sub, _a, _b]);

      final ordem = VaultOrder.vazia.comOrdem('', ['B.md', 'Estudos']).comOrdem(
        'Estudos',
        ['Y.md'],
      );

      final resultado = ordem.aplicar(raiz);

      expect(_nomes(resultado.children), ['B.md', 'Estudos', 'A.md']);
      final estudos = resultado.children[1] as VaultFolder;
      expect(_nomes(estudos.children), ['Y.md', 'X.md']);
    });

    test('a chave de uma subpasta usa barra normal', () {
      expect(
        VaultOrder.chaveDe(r'C:\v\Estudos\Flutter', r'C:\v'),
        'Estudos/Flutter',
      );
    });

    test('a chave da raiz e vazia', () {
      expect(VaultOrder.chaveDe(r'C:\v', r'C:\v'), '');
    });
  });

  group('persistencia', () {
    test('a ordem sobrevive a ida e volta do texto guardado', () {
      final ordem = VaultOrder.vazia.comOrdem('', ['B.md', 'A.md']).comOrdem(
        'Estudos',
        ['Y.md'],
      );

      expect(VaultOrder.decode(ordem.encode()), ordem);
    });

    test('sem arquivo guardado a ordem e vazia', () {
      expect(VaultOrder.decode(null), VaultOrder.vazia);
      expect(VaultOrder.decode('  '), VaultOrder.vazia);
    });

    test('JSON quebrado nao derruba o vault', () {
      // Perder a ordem manual e aceitavel; nao abrir o vault nao e.
      expect(VaultOrder.decode('{isso nao e json'), VaultOrder.vazia);
      expect(
        VaultOrder.decode('["lista", "no", "lugar", "errado"]'),
        VaultOrder.vazia,
      );
    });

    test('entrada com tipo errado e descartada sem levar o resto junto', () {
      final ordem = VaultOrder.decode('{"": ["A.md", 7, "B.md"], "x": 3}');

      expect(ordem.of(''), ['A.md', 'B.md']);
      expect(ordem.of('x'), isEmpty);
    });

    test('lista vazia apaga a entrada em vez de guardar lixo', () {
      final ordem = VaultOrder.vazia
          .comOrdem('', ['A.md'])
          .comOrdem('', const []);

      expect(ordem.isEmpty, isTrue);
    });
  });
}
