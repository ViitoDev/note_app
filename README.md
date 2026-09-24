# Notas

Aplicativo de notas em Markdown para desktop, escrito em Flutter. O vault é uma
pasta comum de arquivos `.md` no disco — os arquivos são a fonte da verdade, e
calendário, quadro kanban, grafo e painel são apenas leituras deles.

Não há banco de dados, índice persistido nem estado paralelo. Apagar uma linha
de uma nota apaga o evento; limpar um campo do frontmatter tira o card do
quadro. Suas notas continuam legíveis e editáveis em qualquer outro editor de
Markdown, hoje e depois que este app deixar de existir.

## Funcionalidades

**Editor e vault**

- Árvore de pastas e arquivos `.md`, com criar, renomear, mover e excluir.
- Editor com preview lado a lado, divisor arrastável e frontmatter YAML.
- Salvamento seguro: grava num temporário, faz backup do original e só então
  renomeia — uma queda no meio da escrita não corrompe a nota.
- Ordem manual da árvore por arrasto, persistida por pasta.
- Wikilinks `[[nome da nota]]`, com sugestões enquanto se digita e links
  navegáveis no preview. O arquivo continua guardando o texto `[[...]]`.
- Ficha de propriedades no topo do preview, que expõe os campos que o app
  entende sem exigir que você decore a sintaxe do frontmatter.
- Tabelas desenhadas como grade editável nos dois lados da tela, em vez de
  barras verticais no texto.
- Quadros de fluxograma: caixas, losangos de decisão, elipses e flechas com
  rótulo, desenhados dentro da nota e editáveis em tela cheia. Ficam num bloco
  ` ```quadro ` do próprio `.md` — sem anexo ao lado do arquivo.

**Desenho**

- Caneta, reta, seta solta, escrita solta e borracha na tela cheia do quadro,
  com seis cores e quatro grossuras. O traço à mão livre entra no mesmo bloco
  ` ```quadro `, uma linha por traço — mover uma caixa continua mudando uma
  linha do arquivo.
- **Escrever solto** (tecla `T`, ou duplo clique na área vazia): o cursor abre
  onde se apontou, sem caixa em volta. A área da anotação acompanha o que for
  escrito, então nunca se pensa em tamanho; anotação que ficou sem texto não
  fica no quadro.
- Tudo é desenhado com o traço levemente fora de esquadro de quem desenhou à
  mão: uma passada só por contorno, com a aresta reta saindo reta e a curva
  saindo curva. Um interruptor na barra devolve a régua, e a escolha fica
  gravada na nota (`"mao":false`). O texto dentro das caixas usa uma humanista
  (Candara), não uma manuscrita — quem desenha é a forma; o texto só precisa
  acompanhar sem disputar.
- Desfazer e refazer (Ctrl+Z, Ctrl+Shift+Z) dentro da tela cheia.
- **Notas que são telas**: um arquivo `nome.quadro.md` abre como área de desenho
  sem fim, ocupando o editor inteiro em vez de texto com preview. Continua sendo
  um `.md` comum do vault — sincroniza, renomeia e vai para a lixeira como
  qualquer nota. Escolha "Tela" ao criar a nota.
- Uma caixa cujo texto é só um `[[wikilink]]` vira atalho para aquela nota: sai
  desenhada com cara de link, e duplo clique abre a nota. O grafo continua vendo
  a ligação, porque o arquivo guarda o `[[...]]` de sempre.

**Excalidraw**

- Copie no excalidraw.com e cole no quadro com Ctrl+V: caixas, losangos,
  elipses, textos, rabiscos e setas atravessam. Seta presa em duas caixas vira
  ligação daqui; seta solta vira traço.
- Ctrl+C leva o quadro de volta para o excalidraw.com, com as flechas ainda
  presas às caixas.
- Arquivos `.excalidraw` guardados no vault aparecem na árvore e abrem
  desenhados, **só para leitura** — regravá-los daqui apagaria deles o que este
  app não entende (rotação, tracejado, imagens). Um botão copia o desenho como
  bloco de quadro, para colar numa nota e dali em diante mexer à vontade.

**Sincronização**

- Servidor privado próprio, em um container Docker que vive em
  [docker/](docker/) — WebDAV, uma imagem só, sem banco de dados.
- O vault local continua sendo o que o app lê e escreve. Editar sem rede
  funciona igual; o que mudou sobe três segundos depois da última gravação, e o
  que outra máquina escreveu desce a cada cinco minutos.
- Exclusão feita aqui sobe; exclusão feita no servidor traz a nota para
  `.trash/` dentro do vault, nunca para o nada.
- Ordem manual da árvore e histórico de escrita viajam junto das notas.

**O que fiz hoje**

O painel fecha com um diário do dia: as notas que nasceram ou mudaram hoje,
cada uma com o resumo do que ganhou. O resumo é **tirado da nota**, nunca
inventado — os títulos de seção são os assuntos, as caixas `- [x]` são o que
foi riscado, as tags são a matéria. Não há sumarização nem modelo de
linguagem: se o texto não disser, o painel não diz.

Nada é gravado para isso funcionar. Uma nota entra no dia pela data de
gravação do próprio `.md` — então editar a nota no Obsidian, ou em qualquer
outro editor, aparece aqui do mesmo jeito — e a etiqueta "nova" vem do
`criado_em:` do frontmatter.

**Painéis**

Seis painéis — Arquivos, Painel, Calendário, Grafo, Quadro e E-mail — acopláveis
por arrasto nas barras laterais esquerda e direita. Tamanhos, posições e painéis
ocultos persistem entre execuções. O editor é o centro fixo da tela.

| Painel | O que faz |
|---|---|
| **Painel** | Tela inicial: eventos do dia, cards, tarefas em aberto, tags e o diario de hoje, tudo de uma passada pelo vault. Marcar uma tarefa aqui reescreve a linha no arquivo. |
| **Calendário** | Visão mensal dos compromissos que vivem dentro das notas. |
| **Grafo** | Notas e tags como nós, wikilinks como arestas, com simulação de forças. |
| **Quadro** | Kanban de quatro colunas. Arrastar um card reescreve `status:` na nota. |
| **E-mail** | Leitura da caixa de entrada por IMAP, com descoberta automática de servidor. |

## Como uma nota vira dado

O que o app entende do frontmatter YAML no topo do arquivo:

| Campo | Efeito |
|---|---|
| `tipo: evento` | A nota inteira vira um compromisso no calendário. |
| `data: 2026-08-20` | Dia do evento. |
| `hora: 14:30` | Horário. Sem ele, o evento é "o dia todo". |
| `status: fazendo` | A nota vira um card na coluna correspondente do quadro. |
| `tags: [estudo, flutter]` | Nós de tag no grafo e filtro no painel. |
| `criado_em: 2026-09-09` | Dia em que a nota nasceu; é o que a marca como "nova" no diário do painel. O app escreve este campo ao criar a nota. |

E o nome do arquivo também diz uma coisa: `mapa.quadro.md` abre como tela de
desenho em vez de como texto, e `diagrama.excalidraw` abre como desenho de fora,
só para leitura.

E no corpo do texto:

| Marcação | Efeito |
|---|---|
| `📅2026-08-20 14:30` | Compromisso avulso, sem transformar a nota inteira em evento. |
| `- [ ] tarefa` | Tarefa em aberto; aparece no painel e pode ser marcada de lá. |
| `[[outra nota]]` | Link interno; vira aresta no grafo. |

O campo `status:` aceita sinônimos — `todo`, `backlog` e `a-fazer` caem todos na
coluna "Pronto para fazer", `doing` e `wip` em "Fazendo", `done` e `concluído`
em "Pronto". A escrita no frontmatter é cirúrgica: só a linha do campo muda,
preservando comentários, ordem, aspas e estilo de lista do seu arquivo.

## Requisitos

- Flutter com Dart SDK 3.12.2 ou superior.
- Windows com Visual Studio e a carga de trabalho "Desenvolvimento para desktop
  com C++", necessária para compilar o runner nativo.
- Para sincronizar entre máquinas: uma máquina com Docker para rodar o servidor
  do vault. É opcional — sem ele o app funciona inteiro sobre a pasta local.

## Como rodar

```powershell
flutter pub get
flutter run -d windows
```

Na primeira execução o app pede a pasta do vault. Qualquer pasta com arquivos
`.md` serve, inclusive uma já existente de outro editor.

## Desenvolvimento

```powershell
flutter analyze
flutter test
```

São 763 casos de teste em 47 arquivos, cobrindo os serviços que leem o vault e
as telas. Os testes de widget não tocam o disco: as telas recebem os dados já
extraídos, e a leitura de arquivos fica isolada nos serviços.

## Estrutura

```
lib/
  models/        Nota, evento, card, tarefa, grafo — dados e regras puras
  services/      Leitura do vault, calendário, kanban, grafo, e-mail, segredos
  repositories/  Contratos que a interface consome
  servidor/      Cliente WebDAV e sincronização com o servidor privado
  ui/            Telas, painéis e sistema de design
docker/          O servidor do vault, em um container
test/            Testes de unidade e de widget
```

## Decisões de arquitetura

**Nada de índice.** Calendário, quadro, grafo e painel releem o vault a cada
abertura. Para um vault pessoal isso custa milissegundos e evita o pior defeito
de um cache: mostrar um evento que já foi apagado do arquivo.

**A interface não lê arquivos.** As telas recebem dados prontos dos serviços.
É o que permite testá-las sem disco e o que mantém a leitura do vault num lugar
só.

**Seletor de pastas próprio.** Escrito em Dart puro, em vez do `file_picker`:
o plugin não compila com o Kotlin embutido do AGP 9, e no Android o seletor
nativo devolve URI `content://` do SAF, enquanto o app precisa de caminho real
para ler uma pasta replicada por sync.

**O servidor não é a fonte da verdade.** A pasta local é. O app lê e grava no
disco e só depois conversa com o servidor, que é uma cópia mantida igual — por
isso editar sem rede funciona igual a editar com ela, e um servidor fora do ar
é um ícone cinza na barra, não um app que não abre.

**WebDAV, não uma API própria.** Os ids do vault já são caminhos de arquivo, e
o WebDAV fala em caminhos — o mapeamento é direto, sem um segundo modelo de
dados para manter sincronizado com o primeiro. De quebra, a mesma pasta abre no
Obsidian, no Explorer do Windows e em qualquer cliente de celular. Se este app
sumir, as notas continuam acessíveis.

**Conflito não se resolve sozinho.** Quando a mesma nota mudou nos dois lados,
a versão do servidor é guardada ao lado com outro nome e a daqui continua sendo
a nota. Escolher entre duas versões de um texto é decisão de quem escreveu o
texto. A sincronização compara o conteúdo antes de declarar conflito, então
duas gravações que produziram o mesmo texto não geram cópia nenhuma.

**Tema escuro único.** O app é uma superfície de leitura e escrita longa;
manter duas variantes dobraria o custo de acerto visual sem ganho.

**Segredos fora do repositório.** A senha de e-mail é cifrada pelo DPAPI do
Windows antes de encostar no disco — a chave fica amarrada à conta do Windows,
e o arquivo copiado para outra máquina não abre. Nenhuma credencial vive no
código.

## Estado atual

O app funciona sobre uma pasta local e, quando um servidor está configurado,
mantém essa pasta igual à do servidor nos dois sentidos.

O Google Drive saiu. A camada de OAuth e as operações sobre a pasta do app no
Drive foram removidas junto — ficaram no histórico do Git, se um dia fizerem
falta.

Próximos passos, em ordem:

1. Lixeira própria para exclusões locais. Hoje apagar uma nota é definitivo dos
   dois lados; só o backup do servidor traz de volta.
2. Alarmes para os compromissos do calendário.
3. Plataforma Android — o repositório traz apenas o runner do Windows.
