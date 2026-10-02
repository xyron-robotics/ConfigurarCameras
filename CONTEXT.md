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
Conjunto montado no passo a passo ao abrir o painel e editado em Opções: a placa escolhida, a rede das câmeras (máscara, gateway, DNS, IP do PC), a faixa de fábrica (IP de fábrica, IP do PC), a câmera (e-mail de recuperação, encoder dos dois streams) e a última fila. A última sessão fica guardada e volta como sugestão na próxima abertura. A senha nunca faz parte dela.
_Avoid_: padrões, padrões da instalação, perfil, template, configuração do painel

**Passo a passo**:
Sequência de telas, uma depois da outra, que o painel mostra ao abrir até a sessão estar completa e o operador mandar começar: senha, placa de rede, rede das câmeras, faixa de fábrica, câmera, fila (opcional) e resumo. Com uma sessão guardada, oferece usá-la ou revisá-la tela a tela.
_Avoid_: onboarding, wizard, assistente, setup inicial

**Opções**:
Tela, atrás da engrenagem, com as mesmas seções do passo a passo para mudar qualquer coisa no meio da sessão, mais Restaurar DHCP, Refazer o passo a passo e Encerrar.
_Avoid_: configurações, padrões, ajustes, engrenagem (é só o ícone)

**Placa escolhida**:
A placa de rede do PC, Ethernet ou Wi-Fi, escolhida no passo a passo. É a única via do painel até as câmeras: só ela conta como placa pronta, só ela define o que é alcançável, só por ela sai o broadcast e só ela recebe IP temporário. Endereço igual noutra placa do PC não vale.
_Avoid_: placa das câmeras, placa de rede do PC (há mais de uma), NomePlaca

**Preparo da placa**:
Ação do painel que acrescenta à placa escolhida um endereço na faixa de fábrica e um na rede das câmeras, sem tirar nenhum, para alcançar a câmera antes e depois da troca de IP. O painel guarda o rastro do que fez e desfaz tudo ao encerrar ou em Restaurar DHCP, devolvendo a placa ao estado de antes; a internet do PC é testada antes e depois.
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
Etapa obrigatória da configuração que grava resolução, quadros por segundo e bitrate no stream principal e no stream secundário, em todas as entradas de cada stream, e deriva o intervalo de quadro-chave (GOP) como o dobro dos quadros por segundo; o resto do encoder fica como veio.
_Avoid_: configurar vídeo, alterar qualidade

**Fila**:
Sequência de IPs de destino montada a partir de uma faixa início–fim antes de começar; cada posição recebe uma câmera. Uma faixa sem nenhuma posição livre não vira fila. A faixa montada fica na sessão e volta preenchida na próxima abertura, só como sugestão. Montar é no passo a passo ou em Opções.
_Avoid_: plano, lote, lista

**Posição**:
Um IP de destino da fila. As que podem receber câmera são numeradas "câmera N" (câmera 1, câmera 2…), no mesmo número na fita e na bancada; as deixadas de fora na montagem (gateway, fora da rede, já no registro) não recebem número.
_Avoid_: slot, item, vaga

**Vigia**:
Modo da fila, desligado por padrão, em que o painel observa o IP de fábrica e configura sozinho, na próxima posição livre, cada câmera de fábrica que aparece. Com a chave "qualquer faixa" ligada, observa também pela descoberta, aceitando câmera de fábrica fora do IP de fábrica. Câmera já inicializada só gera aviso; retomar é sempre ação do operador.
_Avoid_: automático, auto-detecção, watcher, polling

**Descoberta**:
Busca de câmeras feita pelo painel só pela placa escolhida, em três passos: o broadcast (a câmera responde de qualquer faixa, com modelo, serial, firmware e se está de fábrica), o IP de fábrica e, só se nada foi achado, a varredura por ping das faixas da placa. O estado anunciado no broadcast é pista; o painel só age depois de confirmar pelo HTTP.
_Avoid_: scan, varredura (é só o último passo), procurar (é o botão)

**IP temporário**:
Endereço que a placa escolhida recebe, na rede de uma câmera de fábrica achada fora das faixas dela, só para configurá-la. Entra no rastro do preparo da placa e sai com ele; vem acompanhado de uma rota de host quando a faixa é de outra placa do PC.
_Avoid_: IP extra, alias, segundo IP
