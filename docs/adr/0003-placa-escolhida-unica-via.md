# A placa escolhida na sessão é a única via até as câmeras

Até a 1.1.1 o painel olhava para todas as placas do PC ao decidir se a placa estava pronta, se uma câmera era alcançável e por onde mandar o broadcast. Em 01/10/2026 isso falhou na bancada: a câmera `10.16.251.208` estava num switch isolado ligado à Ethernet, mas o IP dela caía na faixa do Wi-Fi do PC (`10.16.251.207/22`). O painel viu "um IP local na mesma faixa", declarou a placa pronta e a câmera alcançável, não pôs IP temporário, e o Windows roteou tudo pelo Wi-Fi: a câmera nunca respondeu. O contorno manual que funcionou foi um IP `/32` mais uma rota de host `10.16.251.208/32` on-link na Ethernet.

Decidido: o operador escolhe a placa no passo a passo (Ethernet ou Wi-Fi; a Ethernet com cabo é sugerida) e ela fica na sessão por `ifIndex`, MAC e nome. Só ela conta: placa pronta, alcance, broadcast, IP temporário e preparo olham para o `ifIndex` dela. Câmera cujo IP cai na faixa de outra placa do PC recebe, além do IP temporário, uma rota de host `/32` on-link na placa escolhida, registrada no rastro e removida ao devolver a placa.

## Considered Options

- **Continuar olhando todas as placas e só avisar quando duas tiverem a mesma faixa**: não resolve o caso da bancada (o aviso não faz o tráfego sair pela Ethernet) e mantém o "pronta" mentiroso.
- **Deduzir a placa pela rota padrão (a que não leva a internet é a das câmeras)**: é o que a heurística antiga fazia e falha com uma Ethernet só, com dock + USB, e com Wi-Fi sem cabo nenhum. Virou só a sugestão do passo 2.
- **Rota de host sempre, para toda câmera descoberta**: simples, mas polui a tabela de rotas e esconde o caso raro em que a rota é mesmo necessária. Fica só quando a faixa é de outra placa.

## Consequences

- Sondar e Procurar não enxergam mais uma câmera que só está na rede do Wi-Fi quando a placa escolhida é a Ethernet. É intencional: o log diz "fora das faixas da placa escolhida".
- Placa que some (USB desconectado) ou é renumerada pelo Windows: a sessão casa por `ifIndex`, depois MAC, depois nome; não achando, a barra avisa e Opções pede outra.
- Trocar a placa ou as faixas em Opções com a placa preparada devolve a placa com a sessão antiga, grava a nova e prepara de novo; a fila fica se ainda cabe na rede nova.
- A rota de host vive em `ActiveStore` (some no reboot) e no rastro `placa-sessao.json`; sem rastro, ao devolver a placa o painel varre as `/32` on-link criadas por `NetMgmt` nela.
- `Get-IpsLocais`, `Get-FaixasDaPlaca`, `Get-InterfacesBroadcast` e `Find-CamerasNaRede` continuam aceitando `-IfIndex 0` (todas as placas) para os testes e para diagnóstico; o painel nunca chama assim.
