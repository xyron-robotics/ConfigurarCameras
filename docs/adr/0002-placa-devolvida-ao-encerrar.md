# A placa de rede volta sozinha ao estado de antes, com rastro em arquivo

Ao preparar a placa, o Windows tira a placa do DHCP assim que recebe um endereço fixo (`New-NetIPAddress`), e o PC perde a internet e as unidades de rede quando a única placa com cabo é a que leva à rede do escritório. Desde o início o motor copiava o que o DHCP dava (IP, gateway, DNS) como estático para a rede não cair, mas deixava para o operador lembrar de clicar em **Restaurar DHCP**, não testava se a internet continuava e, ao restaurar, não removia a rota padrão que ele mesmo tinha criado (sobrava `0.0.0.0/0` com métrica 256 na placa). Em 30/09/2026 o usuário pediu que o acesso à internet fosse garantido.

Decidido: o painel grava em `placa-sessao.json` tudo o que fez na placa (foto de antes, endereços acrescentados com a finalidade de cada um, o que foi devolvido como estático, a rota com a métrica original, o DNS) e desfaz isso sozinho no encerramento, no thread principal, depois de parar o worker; **Restaurar DHCP** faz o mesmo antes. A internet é testada na subida (baseline) e depois do preparo, pelo endereço NCSI do Windows, e a barra diz se ela caiu por causa do painel.

## Considered Options

- **Só avisar e deixar o Restaurar DHCP manual** (como era): mais simples, mas o operador esquece, e o PC sai da obra com a placa estática e sem internet.
- **Nunca copiar o DHCP como estático e aceitar perder a internet durante o trabalho**: evita o rastro, mas o painel fica inútil para quem precisa do e-mail ou do NVR na nuvem enquanto configura.
- **Restaurar pelo que está na placa, sem arquivo** (heurística: tudo o que é manual nas faixas de câmera): não distingue o IP fixo que o operador já tinha do que o painel pôs, e não sabe se a placa era DHCP antes. Fica como reserva só quando o arquivo não existe.

## Consequences

- O rastro vive em disco porque o fechamento no X não roda o `finally`; o próximo painel avisa e devolve ao encerrar. Preparar duas vezes (ou um IP temporário da descoberta) junta na mesma sessão, nunca cria uma segunda.
- Placa que já era estática antes do painel não tem o DHCP religado: só sai o que o painel pôs. Placa em APIPA (cabo direto na câmera) não tem lease para devolver nem renovar.
- A rota devolvida leva a métrica fotografada; a remoção é pelo `NextHop` da sessão, não "qualquer rota padrão da placa", exceto no caminho sem arquivo.
- O teste de internet usa `curl.exe`, que ignora o proxy WinINET: numa rede só com proxy ele diz "sem" com o navegador navegando. O painel avisa, não bloqueia.
- A espera pelo worker no encerramento subiu de 5 para 30 s, porque devolver a placa no meio de uma gravação na câmera deixaria a câmera pela metade.
