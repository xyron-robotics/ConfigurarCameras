# O IP de fábrica é atravessado por uma câmera por vez, presa pelo MAC

As câmeras saem de fábrica todas no mesmo IP (192.168.1.108). Até a 1.2.2 o painel falava com a câmera pelo IP e pedia ao operador que ligasse uma por vez. Com duas ou mais de fábrica no mesmo switch, todas respondem ARP para esse endereço, e a câmera que atende é a que venceu o ARP, que pode trocar de dono no meio de uma configuração. Em novembro de 2026 isso apareceu na bancada com as câmeras A e B: a inicialização foi para B enquanto a posição era de A, e a conferência de MAC só pegou a troca depois do DevInit; noutra tela, B, já inicializada, escondeu A, ainda de fábrica, atrás do mesmo IP, e o vigia nunca mais a viu. A prova de bancada de 17/11, com A, B e C de fábrica no mesmo IP, mostrou as duas coisas: sem prender, as respostas iam para a vencedora do ARP, e numa rodada vieram parte de uma, parte de outra e parte de nenhuma; com a câmera presa pelo MAC, 20 de 20 chamadas anônimas devolveram a chave pública dela, distinta para A, B e C.

Decidido: o coordenador prende uma câmera por vez no IP de fábrica com um vizinho estático na placa escolhida (`IP de fábrica -> MAC`, em `ActiveStore`), confere que a entrada pegou e só então fala com ela. Dentro desse portão, que tem uma vaga, rodam a inicialização, o encoder e a gravação da rede; ao gravar a rede, a câmera reinicia no IP de destino, que é único, e o portão a solta e passa à próxima. A conferência roda em paralelo, cada câmera no seu destino. Cada câmera é um job num `RunspacePool`, e um coordenador único é dono da placa (IP temporário, vizinho estático, rastro), do estado publicado e do log em arquivo; o registro é gravado por câmera, sob trava, relido do disco e mesclado pelo MAC (`Update-RegistroCamera`), para dois jobs não apagarem a entrada um do outro. Detalhe nas decisões D2, D4 e D5 de `docs/plans/2026-11-cameras-em-paralelo.md`.

## Considered Options

- **Endereçar pelo IP e detectar a troca depois**: é o que a 1.2.2 fazia. A conferência de MAC vem depois do login, quando o DevInit já foi para a câmera errada e a senha da sessão já está gravada nela.
- **Inicializar várias câmeras ao mesmo tempo no mesmo IP**: cada chamada HTTP vai para quem estiver no ARP naquele instante; é o caso que dividiu as respostas entre A, B e C na prova de bancada.
- **Mudar o IP pelo MAC via `DHDiscover.setConfig`, à moda do ConfigTool**: não está documentado em `fonte/API-INTELBRAS.md`, não foi sondado na bancada e seria engenharia reversa. O vizinho estático é ARP padrão e basta.
- **VLAN por porta**: exige switch gerenciado; a bancada usa switch comum, não gerenciado.
- **Pedir ao operador que ligue uma câmera por vez**: era o estado anterior, que o modo paralelo veio eliminar. Fica só como modo de reserva.

## Consequences

- O broadcast (DHIP, UDP 37810) passa a ser obrigatório no modo paralelo: sem ele, câmeras no mesmo IP não se distinguem pelo MAC. Sem resposta do broadcast, o painel cai no modo de reserva, uma câmera por vez, e avisa para liberar a porta no firewall.
- Sem Administrador não há vizinho estático, e o painel também fica no modo de reserva.
- A conferência parte do IP de destino e nunca consulta o IP de fábrica, onde outra câmera pode estar presa no portão.
- O vizinho estático entra no rastro `placa-sessao.json` e sai ao soltar a câmera, ao encerrar o painel e na partida seguinte, se o painel tiver sido fechado com uma câmera presa (ADR 0002). Em `ActiveStore`, ele some também no reboot.
- Vizinho estático que não confere na tabela de vizinhos não deixa a câmera começar: ela vai para a decisão daquela câmera. Se, dentro do portão, o MAC lido depois do login não for o escolhido, é erro do portão e não da posição: ele solta, a câmera volta à espera e a posição volta a ficar livre, sem decisão.
- A posição é atribuída quando a câmera entra no portão, na ordem em que apareceu no broadcast, que não é a ordem do cabo.
- Encerrar o painel espera as câmeras em curso (até 180 s), e a atualização não começa câmera nova nem instala com uma em curso: abortar no meio da gravação da rede deixa a câmera num estado sem dono.
