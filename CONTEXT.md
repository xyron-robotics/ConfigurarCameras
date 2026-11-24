# ConfigurarCameras

Ferramenta de campo que coloca câmeras IP Intelbras (base Dahua) em serviço: inicializa, grava rede e ajusta encoder, registrando cada câmera no inventário.

## Câmeras

**Câmera de fábrica**:
Câmera ainda não inicializada (sem usuário `admin`), que recusa toda chamada autenticada.
_Avoid_: câmera nova, câmera virgem, câmera zerada

**Câmera instalada**:
Câmera cuja configuração terminou e foi conferida no IP definitivo. Antes da conferência, uma falha é retomada da etapa que falhou.
_Avoid_: câmera configurada, câmera em produção

**Inicialização**:
Criação do `admin` e gravação da recuperação de senha apenas por e-mail numa câmera de fábrica. Só um reset de fábrica desfaz.
_Avoid_: ativação, setup

**Reset de fábrica**:
Ação, pela tela da própria câmera ou pelo botão físico, que apaga toda a configuração dela (senha, rede, encoder). A câmera volta a ser câmera de fábrica; quando reaparece, a entrada dela no registro é substituída pela nova configuração e o IP antigo volta a ser uma posição livre. O painel não faz reset: o firmware só oferece o reset parcial (mantém senha e rede), que não é reset de fábrica.
_Avoid_: reset pelo painel, restaurar, formatar, zerar

## Configuração

**Configuração**:
Passada única que leva uma câmera de fábrica a câmera instalada. Nunca é refeita numa câmera instalada; para configurar de novo, a câmera passa por um reset de fábrica e volta a ser câmera de fábrica.
_Avoid_: reconfiguração, ajuste posterior

**Sessão**:
Conjunto montado no passo a passo ao abrir o painel e editado na tela Sessão: a placa escolhida, a rede das câmeras (máscara, gateway, DNS, IP do PC), a faixa de fábrica (IP de fábrica, IP do PC), a câmera (e-mail de recuperação, encoder dos dois streams) e a última fila. A última sessão fica guardada e volta como sugestão na próxima abertura. A senha nunca faz parte dela.
_Avoid_: padrões, padrões da instalação, perfil, template, configuração do painel

**Passo a passo**:
Sequência de seis passos, um depois do outro, que o painel mostra ao abrir até a sessão estar completa e o operador mandar começar: senha, placa de rede, rede das câmeras (com a faixa de fábrica recolhida), câmera, fila e Conferir. Com uma sessão guardada, abre direto em Conferir, com a senha no topo.
_Avoid_: onboarding, wizard, assistente, setup inicial

**Conferir**:
Último passo do passo a passo: uma linha por seção da sessão, cada uma com "Alterar", e o botão Começar. Confere a fila contra o registro e, se todas as posições já estão instaladas, oferece a faixa seguinte.
_Avoid_: resumo, revisão

**Sessão (tela)**:
Aba do topo, antes chamada Opções, que edita a sessão uma seção por vez (senha, placa, rede, câmera, fila), cada uma com "Salvar alterações", mais a seção Painel, que não é da sessão: tema, versão e Refazer o passo a passo. Encerrar o painel fica no topo, não nela.
_Avoid_: configurações, padrões, ajustes, engrenagem

**Placa escolhida**:
A placa de rede do PC, Ethernet ou Wi-Fi, escolhida no passo a passo. É a única via do painel até as câmeras: só ela conta como placa pronta, só ela define o que é alcançável, só por ela sai o broadcast e só ela recebe IP temporário. Endereço igual noutra placa do PC não vale.
_Avoid_: placa das câmeras, placa de rede do PC (há mais de uma), NomePlaca

**Preparo da placa**:
Ação do painel que acrescenta à placa escolhida um endereço na faixa de fábrica e um na rede das câmeras, sem tirar nenhum, para alcançar a câmera antes e depois da troca de IP. O painel guarda o rastro do que fez e desfaz tudo ao encerrar ou em Restaurar o DHCP (no chip da placa), devolvendo a placa ao estado de antes; a internet do PC é testada antes e depois.
_Avoid_: configurar a rede do PC, mexer na placa, setup de rede

**IP do PC**:
Endereço que a placa escolhida recebe no preparo, um por faixa. Vazio na sessão significa automático (.220 na faixa de fábrica; .200 a .249 na rede das câmeras, derivado do MAC); preenchido, o painel usa exatamente aquele.
_Avoid_: IP local, IP da máquina, IP de conferência

**Rota de host**:
Rota para um único endereço (/32), posta pelo painel na placa escolhida quando a câmera de fábrica está numa faixa que outra placa do PC também tem (bancada num switch isolado com IP da faixa do Wi-Fi). Sem ela o Windows mandaria o tráfego pela outra placa. Entra no rastro do preparo e sai com ele; não sobrevive ao reboot.
_Avoid_: rota estática, rota fixa, rota /32 (é a forma, não o nome)

**Stream principal**:
Primeiro fluxo de vídeo da câmera (stream 1).
_Avoid_: main stream, MainFormat

**Stream secundário**:
Segundo fluxo de vídeo da câmera (stream 2), de menor qualidade.
_Avoid_: sub stream, extra stream, ExtraFormat

**Painel**:
Console web local onde a operação é controlada e onde vive o registro das câmeras; é a fonte de verdade. Também é o nome da tela principal, com a fila, a bancada e o registro.
_Avoid_: dashboard, interface, sistema

**Registro**:
Lista, guardada pelo painel neste PC, de cada câmera que passou pela configuração: uma entrada por câmera (pelo MAC), com o IP definitivo, a etapa concluída e o estado (em andamento, instalada, falhou). É a única cópia do que foi feito. Fica na tela Painel, embaixo da fila.
_Avoid_: inventário, banco, histórico, cameras.csv

**Relatório**:
Planilha exportada do painel sob demanda para constatar o que foi feito. Nunca é lida de volta como entrada.
_Avoid_: inventário, plano, planilha de entrada

**Retomada**:
Nova tentativa numa câmera cuja configuração falhou antes da conferência: o painel olha onde a câmera está (de fábrica, inicializada, já no destino) e continua da etapa que faltava, sem refazer o que está registrado.
_Avoid_: reconfiguração, tentar do zero, reprocessar

**Simulação**:
Modo do painel, ligado só por parâmetro ao abrir, em que nada é enviado à câmera nem à placa de rede e o registro usado é um arquivo separado; serve para ensaiar a fila inteira sem câmera e para os testes. Não tem tela.
_Avoid_: modo teste, dry run, sandbox

**Ajuste de encoder**:
Etapa obrigatória da configuração que grava resolução, quadros por segundo e bitrate no stream principal e no stream secundário, em todas as entradas completas de cada stream (entrada que o firmware traz incompleta fica como veio), e deriva o intervalo de quadro-chave (GOP) como o dobro dos quadros por segundo; o resto do encoder fica como veio.
_Avoid_: configurar vídeo, alterar qualidade

**Fila**:
Sequência de IPs de destino montada a partir de uma faixa início–fim antes de começar; cada posição recebe uma câmera. As posições recebem câmeras em paralelo: uma câmera em falha espera a decisão no cartão dela e não para as outras. Uma faixa sem nenhuma posição livre não vira fila. A faixa montada fica na sessão e volta preenchida na próxima abertura, só como sugestão. Montar é no passo a passo ou na tela Sessão, seção Fila.
_Avoid_: plano, lote, lista

**Posição**:
Um IP de destino da fila. As que podem receber câmera são numeradas "câmera N" (câmera 1, câmera 2…), no mesmo número na fita e na bancada; as deixadas de fora na montagem (gateway, fora da rede, já no registro) não recebem número. A câmera recebe a próxima posição livre ao entrar no portão do IP de fábrica, na ordem em que apareceu no broadcast, que não é a ordem do cabo; por isso porta e canal se digitam no cartão da câmera.
_Avoid_: slot, item, vaga

**Vigia**:
Modo da fila, desligado por padrão, em que o painel observa pelo broadcast (DHIP) na placa escolhida e admite, cada uma na próxima posição livre, quantas câmeras de fábrica houver no switch. Com a chave de qualquer faixa desligada, só conta a câmera que responde no IP de fábrica; ligada, aceita também câmera de fábrica fora dele. Câmera já inicializada só gera aviso e nunca é tocada; retomar é sempre ação do operador. Não pausa com câmera em decisão: as outras seguem. Sem resposta do broadcast, cai no modo de reserva.
_Avoid_: automático, auto-detecção, watcher, polling

**Portão do IP de fábrica**:
Etapa, uma câmera por vez, em que a câmera de fábrica, presa pelo MAC num vizinho estático, é inicializada, recebe o encoder e grava a rede, saindo do IP de fábrica para o destino. Enquanto o portão está ocupado, as outras câmeras de fábrica ficam na espera; ao sair dele, a câmera segue para a conferência em paralelo.
_Avoid_: trava, lock, semáforo, fila de fábrica

**Vizinho estático**:
Entrada fixa `IP de fábrica -> MAC` na tabela ARP da placa escolhida, posta quando a câmera entra no portão e tirada quando sai, para que, com várias câmeras de fábrica no mesmo IP, o tráfego vá só para a do portão. Entra no rastro do preparo e sai com ele; não sobrevive ao reboot. Sem Administrador não é posto.
_Avoid_: ARP estático, entrada ARP, NetNeighbor

**Conferência em paralelo**:
Conferência de várias câmeras ao mesmo tempo, sem limite de quantas, cada uma no seu IP de destino. Não toca o IP de fábrica, por isso não espera o portão.
_Avoid_: conferência simultânea, verificação em lote

**Cartão da câmera**:
Bloco da bancada de cada câmera da fila, com posição, modelo, serial, MAC, destino, estado da câmera, Porta e Canal e, em falha, os botões Tentar de novo e Pular esta posição. Porta e Canal ficam editáveis até a fila fechar, inclusive com a câmera instalada, menos em câmera pulada ou já inicializada.
_Avoid_: linha, item, card, ficha

**Estado da câmera**:
Palavra que o cartão mostra para a fase da câmera: "Na espera", "No portão", "Conferindo", "Falhou" (espera a decisão do operador), "Instalada", "Pulada" e "Já inicializada: não tocada".
_Avoid_: status, fase (é o nome no código), situação

**Modo de reserva**:
Sem resposta do broadcast (em geral, a porta UDP 37810 fechada no firewall) ou sem Administrador, o painel configura uma câmera por vez e avisa. Sem Administrador também não há vizinho estático.
_Avoid_: modo serial, modo de segurança, fallback

**Descoberta**:
Busca de câmeras feita pelo painel só pela placa escolhida, em três passos: o broadcast (a câmera responde de qualquer faixa, com modelo, serial, firmware e se está de fábrica), o IP de fábrica e, só se nada foi achado, a varredura por ping das faixas da placa. O estado anunciado no broadcast é pista; o painel só age depois de confirmar pelo HTTP.
_Avoid_: scan, varredura (é só o último passo), procurar (é o botão)

**IP temporário**:
Endereço que a placa escolhida recebe, na rede de uma câmera de fábrica achada fora das faixas dela, só para configurá-la. Entra no rastro do preparo da placa e sai com ele; vem acompanhado de uma rota de host quando a faixa é de outra placa do PC.
_Avoid_: IP extra, alias, segundo IP
