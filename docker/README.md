# Servidor do vault

Um container só: um WebDAV (`dufs`) servindo a pasta onde os `.md` moram. O app
sincroniza contra ele; o Google Drive saiu.

## Subir

No servidor, com a pasta `docker/` deste repositório copiada para lá:

```bash
cp .env.exemplo .env
$EDITOR .env          # troque NOTAS_SENHA, confira NOTAS_UID/NOTAS_GID
mkdir -p dados
docker compose up -d
```

Confira que respondeu:

```bash
curl -u notas:SUA_SENHA -X PROPFIND -H 'Depth: 1' http://localhost:5005/
```

De outra máquina, o endereço IPv6 entra entre colchetes:

```bash
curl -u notas:SUA_SENHA -X PROPFIND -H 'Depth: 1' 'http://[2804:...:e044]:5005/'
```

Um `207 Multi-Status` com XML é a resposta certa. `401` é senha errada.

## Ligar o app

No app: ícone de nuvem na barra de cima → **Configurar o servidor**.

| Campo | Valor |
|---|---|
| Endereço | `http://IP-DO-SERVIDOR:5005/` — IPv6 vai entre colchetes: `http://[2804:...:e044]:5005/` |
| | O app aceita os dois; o IPv4 da rede local é o mais estável dos dois. |
| Usuário | o `NOTAS_USUARIO` do `.env` |
| Senha | o `NOTAS_SENHA` do `.env` |

O botão **Testar** faz um PROPFIND real antes de salvar. A senha não fica em
texto puro: é cifrada pelo DPAPI do Windows, amarrada à sua conta.

## Abrir a porta na LAN

O `ports:` do compose só publica a porta no host — o firewall do servidor ainda
precisa deixar passar:

```bash
sudo ufw allow from 192.168.0.0/24 to any port 5005 proto tcp
```

Troque `192.168.0.0/24` pela faixa da sua rede. Liberar para `any` em vez da
faixa local expõe suas notas para quem alcançar o servidor — e sem HTTPS a
senha viaja legível.

## Backup

Tudo que importa está em `NOTAS_DADOS` (por padrão `docker/dados/`). São `.md`
comuns e dois `.json` de metadados. Um `rsync` ou um `tar` da pasta é o backup
completo — não há banco de dados para exportar.

```bash
tar czf notas-$(date +%F).tar.gz -C dados .
```

## Quando quiser expor para fora

Hoje é HTTP puro na LAN: a senha vai em Basic Auth, legível para quem estiver
na rede. Antes de deixar o servidor acessível pela internet, faça as duas
coisas:

1. **Tire a porta do compose.** Troque o bloco `ports:` por uma rede
   compartilhada com o seu proxy reverso, para o container deixar de escutar
   direto.
2. **Ponha TLS no proxy.** Nginx Proxy Manager, Traefik ou Caddy com
   Let's Encrypt. No app, o endereço passa a ser `https://...` — o cliente
   WebDAV não muda em nada.

Alternativa sem abrir porta nenhuma: Tailscale ou WireGuard, prendendo a porta
na interface da VPN — trocando a linha `ports:` do `compose.yml` pelo endereço
dela, como o comentário lá explica.

## Endereço estável

O endereço IPv4 vem do DHCP do roteador, então em tese pode mudar — e quando
mudar, o app para de sincronizar até alguém corrigir o endereço na tela de
configuração. Duas formas de travar, em ordem de preferência:

1. **Reserva no roteador.** Na administração dele, amarrar o MAC
   `34:e6:d7:fb:e0:44` ao endereço atual. É a melhor: o servidor continua
   pegando tudo por DHCP e nunca briga com outra máquina pelo mesmo IP.
2. **Endereço fixo no netplan.** Funciona, mas só é seguro com um endereço
   fora da faixa que o roteador distribui — senão um dia ele entrega o mesmo
   número para outro aparelho e as duas máquinas somem da rede.

O endereço IPv6 é derivado do MAC (EUI-64), então esse não muda enquanto o
prefixo da operadora for o mesmo.

## Notas de operação

- **Sem healthcheck.** A imagem do `dufs` é enxuta e não traz `curl` nem `wget`;
  um healthcheck escrito no chute marcaria o serviço como doente para sempre.
  `docker compose logs -f vault` mostra o que está acontecendo.
- **Log curto de propósito.** O `dufs` não registra senha, mas registra cada
  caminho pedido — ou seja, o nome de todas as suas notas. O compose limita a
  3 arquivos de 5 MB para isso não virar um histórico permanente.
- **Atualizar:** `docker compose pull && docker compose up -d`. A versão está
  fixada (`v0.46.0`) para uma atualização não chegar sem você pedir.
