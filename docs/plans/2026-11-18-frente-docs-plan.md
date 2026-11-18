# Frente docs: documentação do modo paralelo (F7 do mapa)

**Status:** Concluído (18/11) · **Frente:** `docs`

Fechado em 18/11: os termos da seção 3 do mapa estão no glossário (`CONTEXT.md`), o ADR 0004 está escrito, os achados P0 estão no protocolo (`fonte/API-INTELBRAS.md`) e o manual (`LEIA-ME.md`) descreve o fluxo paralelo. O mapa não muda aqui: muda na raiz, depois que a frente fecha.

Plano de frente da F7 de `docs/plans/2026-11-cameras-em-paralelo.md`, escrito sobre o `main` em eece536 (frentes `motor`, `orquestrador`, `ui`, `servidor` e `simulacao` fechadas). Roda em paralelo com a frente `ui-paralela` (F6, `docs/plans/2026-11-18-frente-ui-paralela-plan.md`), que só mexe em código. Os textos de tela citados aqui vêm da decisão C4 daquele plano, que vale mesmo antes de a frente fechar. Onde divergir do mapa, vale este plano.

**Goal:** a documentação descreve o painel que sai na 1.3.0: câmeras de fábrica em paralelo no mesmo switch, portão do IP de fábrica, cartões, porta e canal por cartão, decisão por câmera e o modo de reserva de uma câmera por vez.

**Non-Goals:**
- Código: nenhum `.ps1`, nada em `fonte/web/www/`.
- O mapa (muda na raiz, depois que a frente fecha).
- A F8 (câmera real) e a release.

**Touched:**
- `CONTEXT.md` (Task 1);
- `docs/adr/0004-portao-do-ip-de-fabrica.md`, novo (Task 2; documento do repo, não entra no instalador);
- `fonte/API-INTELBRAS.md` (Task 3);
- `LEIA-ME.md` (Task 4);
- este plano (Task 5).

**Safety:**
- Repo público: só valores fictícios. MAC `AA:00:00:00:00:0x`, serial `SIM-x`, câmeras A, B e C, IP de fábrica 192.168.1.108 e IPs de documentação (192.0.2.x) ou os que os docs já usam. Os achados P0 entram sem MAC, serial nem IP da bancada (o mapa já os guarda assim). Antes de cada commit, `git diff --cached` sem dado real.
- Sem painel, rede ou hardware: esta frente só lê código e escreve texto.
- Sem push e sem release.
- Codificação: os `.md` como já estão. Textos em pt-BR, caixa de frase.

**Régua de toda Task:** o bloco "Validação" do `CLAUDE.md` (Motor, Descoberta, Orquestrador, Coordenador, `git diff --check`). Nada de código muda; a régua só confirma. A contagem de testes se lê na saída e não se escreve em doc.

## Estado medido (18/11, na escrita deste plano)

- `CONTEXT.md` tem duas seções (`## Câmeras`, `## Configuração`) e verbetes no formato `**Termo**:` / definição / `_Avoid_: ...`. Não tem Portão do IP de fábrica, Vizinho estático, Conferência em paralelo, Cartão da câmera, Coordenador, fase da câmera, decisão por câmera nem modo de reserva. "Fila", "Posição" e "Vigia" descrevem o modo serial: a Posição não diz quando a câmera é atribuída (D10), e o Vigia não diz que segue com uma câmera em decisão (D6).
- `LEIA-ME.md`:
  - a abertura (`:3-4`) diz "uma por vez, pelo cabo", e a seção Fila (`:90-125`) manda ligar **uma** câmera e diz que, numa falha, "a fila para";
  - Requisitos (`:20`) diz "Wi-Fi não serve", o que contradiz `:55`, o `CONTEXT.md` (Placa escolhida: "Ethernet ou Wi-Fi") e o código (`Motor-Cameras.ps1`: placas físicas Ethernet tipo 6 e Wi-Fi tipo 71);
  - PoE e firewall (UDP 37810) só aparecem na tabela "Se algo der errado";
  - Desenvolvimento (`:249-272`) fixa contagens ("95 provas", "49 provas"), lista só `Testes-Motor` e `Testes-Descoberta` e não cita `Orquestrador-Cameras.ps1`, `Coordenador-Cameras.ps1`, `Testes-Orquestrador.ps1`, `Testes-Coordenador.ps1` nem `fonte/testes/Smoke-Paralelo.ps1`;
  - Pendências tem 8 itens; nenhum fala do modo paralelo sem prova em câmera real.
- `fonte/API-INTELBRAS.md` cobre DHIP, `/OutsideCmd` e RPC2, mas não IP duplicado, ARP nem vizinho estático, e não registra que o firmware antigo no `/RPC2` responde só `{ "NotifyMethod" : "1.2" }`.
- `docs/adr/` tem 0001 a 0003. O 0003 tem título afirmativo, parágrafo de contexto com incidente datado, parágrafo "Decidido: …", `## Considered Options` (bullets "**opção**: motivo da recusa") e `## Consequences`; sem Status nem data no cabeçalho.
- O que a implementação faz hoje (fonte para os textos):
  - fases da câmera `espera|portao|conferindo|decisao|feita|pulada|ignorada` (`Orquestrador-Cameras.ps1`);
  - o portão tem uma vaga; a conferência não tem limite (`Max = 0`);
  - sem DHIP, `Max = 1` e o aviso "O broadcast não responde. Libere a porta UDP 37810 no firewall ou ligue uma câmera por vez." (`Coordenador-Cameras.ps1`); sem Administrador, também `Max = 1` e sem vizinho estático (`Servidor-Painel.ps1`, aviso "Sem administrador: uma câmera por vez.");
  - a conferência parte do IP de destino e não consulta o de fábrica (frente `simulacao`, S1);
  - encerrar o painel espera as câmeras em curso até 180 s; a atualização recusa começar câmera e não instala se uma começou (S4);
  - simulação: `-SimularCameras` (1 a 16, padrão 3), `-SimularEscala` (padrão 1; 0 = sem espera) e `POST /api/simular {ligado, falharEm}` com `falharEm` em texto ou mapa `{ "<n>": "<etapa>|mac-trocado|ja-inicializada" }`.

## Decisões

Valem as do mapa (D1–D11, Q1–Q8) e as das frentes já fechadas. Desta frente:

- **E1. O texto descreve o real.** Na dúvida entre o mapa e o código, vale o código (`Orquestrador-Cameras.ps1`, `Coordenador-Cameras.ps1`, `Servidor-Painel.ps1`). Exemplo: o mapa (D10) diz "porta e canal editáveis até a conferência terminar", mas a decisão do usuário de 18/11 (C2 da `ui-paralela`) estende até a fila fechar.
- **E2. Texto de tela vem da C4 da `ui-paralela`.** Rótulos, palavras de estado e o texto do vigia são citados como lá estão. Texto de tela fora da C4 não é citado entre aspas: descreve-se o comportamento.
- **E3. Nenhum número que muda nos docs:** contagem de testes, versão corrente e "versão da instalação" ficam fora. Versões de firmware validadas (fatos de bancada datados) ficam.
- **E4. "Uma por vez" só onde é verdade:** modo de reserva (sem DHIP, sem Administrador), portão do IP de fábrica e retomada manual pelo IP.

## Task 1: Glossário (`CONTEXT.md`)

**Files:** `CONTEXT.md`

1. Verbetes novos, no formato da casa, na seção `## Configuração`, perto de Fila/Vigia:
   - **Portão do IP de fábrica**: etapa de uma câmera por vez em que a câmera, presa pelo MAC, é inicializada, recebe o encoder e grava a rede, saindo do IP de fábrica para o destino;
   - **Vizinho estático**: entrada ARP fixa `IP de fábrica -> MAC` na placa escolhida, posta pelo portão e removida ao soltar, com rastro (some no reboot);
   - **Conferência em paralelo**: a conferência roda ao mesmo tempo para várias câmeras, cada uma no seu destino, sem tocar o IP de fábrica;
   - **Cartão da câmera**: o bloco da bancada de cada câmera da fila, com posição, modelo, serial, MAC, destino, estado, Porta e Canal (editáveis até a fila fechar, menos em câmera pulada) e, em falha, Tentar de novo / Pular esta posição;
   - **Modo de reserva**: sem resposta do broadcast ou sem Administrador, o painel configura uma câmera por vez e avisa.
2. Revisar:
   - **Fila**: as posições recebem câmeras em paralelo; uma câmera em falha não para as outras;
   - **Posição**: a câmera recebe a próxima posição livre ao entrar no portão, na ordem em que apareceu no broadcast, que não é a ordem do cabo;
   - **Vigia**: observa pelo broadcast (DHIP) na placa escolhida e admite quantas câmeras houver no switch; câmera já inicializada só gera aviso e nunca é tocada; não pausa com câmera em decisão.
3. Fases da câmera: um verbete curto (**Estado da câmera**) com as palavras da C4 ("Na espera", "No portão", "Conferindo", "Falhou", "Instalada", "Pulada", "Já inicializada: não tocada").

**Validation:**
- `git grep -n "Portão do IP de fábrica\|Vizinho estático\|Conferência em paralelo\|Cartão da câmera\|Modo de reserva" CONTEXT.md` acha os cinco verbetes;
- cada verbete novo tem `_Avoid_:`;
- a régua.

## Task 2: ADR 0004, portão do IP de fábrica

**Files:** `docs/adr/0004-portao-do-ip-de-fabrica.md`

1. Título afirmativo: "O IP de fábrica é atravessado por uma câmera por vez, presa pelo MAC".
2. Contexto: N câmeras de fábrica no mesmo switch respondem todas em 192.168.1.108; a câmera que responde é a que venceu o ARP, e ele pode trocar de dono no meio de uma configuração (prints de novembro e P0 de 17/11, sem dado real). Câmeras A, B e C.
3. "Decidido:" o coordenador prende uma câmera por vez no IP de fábrica com vizinho estático pelo MAC; dentro do portão rodam inicialização, encoder e gravação da rede; a conferência roda em paralelo, cada câmera no destino, num pool de jobs com um coordenador único dono da placa, do registro em mescla por MAC e do estado publicado (D2, D4, D5).
4. `## Considered Options`: endereçar pelo IP e detectar a troca depois; inicializar várias câmeras no mesmo IP; mudar o IP pelo MAC via `DHDiscover.setConfig` (não documentado); VLAN por porta (exige switch gerenciado); pedir ao operador uma câmera por vez (o estado anterior).
5. `## Consequences`: DHIP obrigatório no modo paralelo, e sem ele o modo de reserva; sem Administrador não há vizinho estático, então também o modo de reserva; a conferência parte do destino e nunca consulta o IP de fábrica; o vizinho estático entra no rastro da placa e sai no encerrar (ADR 0002); encerrar e atualizar esperam as câmeras em curso.

**Validation:**
- o ADR tem as mesmas seções do 0003 (`## Considered Options`, `## Consequences`);
- `git grep -n "0004" docs/adr` acha o arquivo;
- a régua.

## Task 3: Protocolo (`fonte/API-INTELBRAS.md`)

**Files:** `fonte/API-INTELBRAS.md`

1. Seção nova, depois de "Descoberta DHIP": **Várias câmeras de fábrica no mesmo IP**:
   - todas respondem em 192.168.1.108, com MACs distintos e `Init=1` no DHIP;
   - sem prender, o HTTP vai para quem venceu o ARP, que pode trocar no meio (respostas misturadas ou perdidas);
   - com vizinho estático `IP -> MAC` na placa, as chamadas vão só para aquela câmera: 20 de 20 `Security.getEncryptInfo` anônimas devolveram a mesma chave pública, distinta por câmera (a impressão da chave identifica a câmera sem login);
   - a câmera recém-ligada responde ARP cerca de 1 min antes do DHIP;
   - em cerca de 15 min, nenhuma câmera saiu sozinha do IP de fábrica por conflito;
   - o DHIP só responde com a placa numa faixa da rede de fábrica (em APIPA, voltou vazio).
2. Na seção de endpoints: o firmware antigo (G3, 2.800) responde no `/RPC2` só `{ "NotifyMethod" : "1.2" }`, e `Security.getEncryptInfo` e `DevInit.getStatus` funcionam pelo `/OutsideCmd`.
3. Fonte citada: "prova de bancada de 17/11 (três câmeras de fábrica num switch isolado)", sem MAC, serial nem IP da bancada.

**Validation:**
- `git diff` desta Task sem MAC fora de `AA:00:00:00:00:0x` e sem IP fora de 192.168.1.108 e dos de documentação;
- a régua.

## Task 4: Manual (`LEIA-ME.md`)

**Files:** `LEIA-ME.md`

1. **Abertura (`:3-4`):** o painel leva câmeras de fábrica a instaladas, várias ao mesmo tempo no mesmo switch, sem "uma por vez, pelo cabo".
2. **Requisitos:**
   - a linha da placa passa a dizer o que o código aceita (Ethernet ou Wi-Fi; a Ethernet com cabo vem sugerida em primeiro), acertando a contradição com `:55`;
   - linha nova: switch com PoE (ou injetor, saída P+D) para as câmeras;
   - linha nova: porta UDP 37810 liberada no firewall para o broadcast, e o que acontece sem ela (modo de reserva);
   - Administrador: sem ele, o modo de reserva (uma câmera por vez).
3. **Fila (`:90-125`):** reescrever o fluxo:
   - montar a fila e ligar o vigia; texto do vigia da C4;
   - ligar as câmeras no switch, quantas quiser; cada uma ganha a próxima posição livre na ordem em que aparece no broadcast, que não é a do cabo;
   - cada câmera tem um cartão (C4: estados, Porta e Canal); porta e canal se digitam no cartão pelo serial da etiqueta, até a fila fechar, inclusive depois de "Instalada";
   - uma câmera passa por vez pelo portão (inicialização, encoder e rede); a conferência roda em paralelo, no IP novo;
   - falha numa câmera abre decisão só no cartão dela ("Tentar de novo", "Pular esta posição"); as outras seguem;
   - "Encerrar a fila" para de admitir câmeras e deixa as em curso terminarem;
   - câmera já inicializada aparece como "Já inicializada: não tocada";
   - modo de reserva ("Sem broadcast: uma câmera por vez.");
   - o caminho sem vigia ("Câmera conectada") e a retomada pelo IP continuam, uma câmera por vez.
4. **Versões e atualização:** a atualização espera as câmeras em curso terminarem; fechar o painel também.
5. **Se algo der errado:** linhas para "Duas câmeras respondem em 192.168.1.108." e para o aviso de broadcast sem resposta, com o que fazer.
6. **Pendências:** item novo: o modo paralelo (DHIP, ARP, vizinho estático, conferência em paralelo e o modo sem Administrador) só tem prova em simulação e na bancada de 17/11; falta a rodada com 2 a 3 câmeras reais do começo ao fim (F8). Revisar os itens existentes: "Vigia e contagem do boot não usados em campo" e "DHIP: câmera de fábrica não vista ao vivo" mudam com a P0 (o DHIP viu as 3 de fábrica em 17/11); os demais ficam.
7. **Desenvolvimento:**
   - árvore com `Orquestrador-Cameras.ps1`, `Coordenador-Cameras.ps1`, os 4 arquivos de teste e `fonte/testes/Smoke-Paralelo.ps1` (fora do CI);
   - sem contagem de provas (E3);
   - comando de teste igual à régua do `CLAUDE.md`;
   - simulação: `-SimularCameras`, `-SimularEscala`, `POST /api/simular` com `falharEm` em texto ou mapa por câmera, e os cenários do `Smoke-Paralelo.ps1` (`basico`, `falha-rede-2`, `mac-trocado-2`, `ja-inicializada-3`, `encerrar`).

**Validation:**
- `git grep -n -i "uma por vez"` fora de `docs/plans` só nos lugares da E4 (cada ocorrência listada no corpo do commit, com o porquê);
- `git grep -n "provas do motor\|95 provas\|49 provas"` vazio;
- `git grep -n "Wi-Fi não serve"` vazio;
- os textos entre aspas batem com a C4 da `ui-paralela` (conferido um a um no corpo do commit);
- a régua.

## Task 5: Fechar o plano

**Files:** `docs/plans/2026-11-18-frente-docs-plan.md`

- `**Status:**` passa a `Concluído`, com uma linha: termos da seção 3 do mapa no glossário, ADR 0004 escrito, achados P0 no protocolo, manual no fluxo paralelo. Não editar o mapa: ele muda na raiz, depois que a frente fecha.

**Validation:**
- a régua inteira verde;
- `git grep -n -E "([0-9A-F]{2}[:-]){5}[0-9A-F]{2}" -- "*.md"` só com MACs `AA:00:00:00:00:0x` (e os de exemplo que já existiam antes desta frente, listados no corpo do commit);
- `git diff --check` limpo.
