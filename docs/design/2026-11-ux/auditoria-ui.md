# Auditoria de UI e marca do painel

Frente `ux`, Task 3. Diagnóstico visual do painel v1.2.3: cor, tipo, espaço, componentes, estados e a marca SmartSeg. A experiência do operador (fluxo, escrita, recuperação) é da `auditoria-ux.md` (Task 2). Quando um achado visual reforça um achado de UX, ele cita o `UX-nn` e não repete a análise. A solução fica para a direção (Task 4).

## Método

**Fontes.** Código em `fonte/web/www/app.css` (C), `fonte/web/www/index.html` (H) e `fonte/web/www/app.js` (J), citado como `C:linha`. Capturas da Task 1 e desta Task em `capturas/`. Medição ao vivo no painel em simulação, a 1366×768, na porta 8766 (a 8765 estava ocupada por um processo do sistema), com dados só fictícios.

**Skills aplicadas e o que ficou de fora:**

| Skill | Aplicado | Descartado, e por quê |
|---|---|---|
| `web-design-guidelines` | As regras do `command.md` do repositório da Vercel, baixadas em texto cru, contra C, H e J. Achados em `arquivo:linha`. | Regras de React, hidratação, virtualização de lista e imagem responsiva: o painel é HTML e JS puros, sem imagem de conteúdo e sem lista longa. |
| `design-taste-frontend` | `system.md` (checklist "One system", teclado e cabeçalho), `motion.md`, `cards.md`; `consistency.mjs --widths 1366 --quick` e `perf.mjs --runs 3`, os dois com `--profile` no scratchpad. | As regras de casa e as seções de página (uma seção por tela, foto, hero, momento sorteado, efeito): valem para site de empresa, e o painel é ferramenta de bancada. `gate.mjs` e `start.mjs` não rodaram, por regra do plano. Os testes de marketing do checker estão na tabela abaixo. |
| `frontend-design` | A lista de sinais de UI gerada ("tells"), "Visual structure is information", motion e escrita. | O processo de construção em duas passadas e a orientação de hero: esta Task não constrói nada. |

**Severidade:**

| Nota | Significado |
|---|---|
| alta | Quebra a leitura do estado, a identidade ou um critério medido; a direção precisa resolver |
| média | Inconsistência que pesa na tela inteira ou atrasa a leitura; entra no redesenho |
| baixa | Detalhe local; corrigir quando o arquivo for mexido |

## Checkers da Taste Skill

### `consistency.mjs` a 1366 px

Saída: 7 FAIL, 8 WARN, o resto PASS (código de saída 1). Leitura de cada um:

| Teste | Resultado | Leitura |
|---|---|---|
| `text-only` (#inicio) | FAIL | Descartado: regra de página de marketing (pede imagem por seção). |
| `links` (6) | FAIL | 5 falsos positivos: `#painel`, `#ferramentas`, `#opcoes` e `#opcoes/fila` são rotas por hash da própria página. 1 real: `#atualizacao-notas` com `href="#"` (UI-17). |
| `copy-headline`, `effects-fit`, `page-meta`, `share-meta` | WARN | Descartados: título de venda, efeito, metatags de compartilhamento. Não se aplicam a ferramenta local. |
| `copy-buttons` | WARN | Quase todo falso positivo: os blocos da trilha ("Senha", "Câmera") são navegação, não ação. Os botões de ação já têm verbo. |
| `body-size` | WARN | Descartado em parte: o checker pede 16 px, e o plano fixa o corpo entre 14 e 15 px a 1366×768. O texto corrido mede 15 px. |
| `label-centre` | WARN | Real: o rótulo da trilha de passos fica fora do centro do bloco (UI-10). |
| `skip-link` | WARN | Falso positivo: o "Pular para o conteúdo" existe (H:16), em português. |
| `contrast`, `text-contrast`, `button-styles`, `button-shape`, `card-family`, `nesting`, `heading-scale`, `a11y-name`, `field-label`, `heading-order`, `tabindex`, `focus-ring`, `focus-visible`, `focus-hidden`, `link-styles` | PASS | O piso técnico está bom: contraste de texto, foco visível, rótulo de campo, nome acessível e ordem de títulos passam. |

### `perf.mjs`, 3 rodadas

1 FAIL: **layout shift de 0,360 a 1440 px** na abertura (0,000 a 390 px). O resto passa: 179,4 KiB transferidos, 7 requisições, TBT 14 ms, FCP 108 ms, LCP 152 ms (o `p.explica`), 441 nós no DOM. Ver UI-06.

## Checklist "One system" (`system.md`, `cards.md`, `motion.md`)

| Item | Estado | Evidência |
|---|---|---|
| Uma paleta em tokens | Passa | Toda cor vem de `:root` (C:8-54), com `light-dark()`; nenhum hex solto fora dele. |
| Escala tipográfica em tokens | Falha | Nenhum token de tamanho. 11 tamanhos em uso: 12,5, 13, 13,5, 14, 15, 16, 17, 18, 20, 21 e 24 px, mais `0.92em` (C:69). 13 px aparece 17 vezes, 14 px 16 vezes. UI-04. |
| Espaçamento em tokens | Falha | Existem `--s-1` a `--s-6`, mas só 32 usos contra 152 valores em `rem` literais fora de `:root`. UI-05. |
| Um raio por nível de hierarquia | Falha | Só `--r-sm` 4 px e `--r-md` 8 px, os mesmos em cartão, campo, botão, seção e selo. O selo usa 999 px numa regra e `--r-sm` na outra (UI-13). |
| Um estilo de selo | Falha | `.selo` declarado duas vezes, com forma e fundo diferentes (C:315 e C:401). UI-13. |
| Cartão no máximo em dois níveis | No limite | Bancada (caixa com listra) > cartão (caixa) > campo. O vigia e os cartões moram dentro da bancada. UI-03. |
| Uma linguagem de borda lateral | Falha | Listra à esquerda de 3 px (menu ativo, C:146-153), 4 px (`.aviso` C:257, `.ultimo` C:458) e 6 px (`.passo` C:284, `.painel-sem-fila` C:329, `.bancada` C:362). UI-03. |
| Desabilitado com uma cara só | Falha | A regra diz "sem opacidade" (C:239-247), e a trilha usa `opacity: 0.7` (C:278). UI-14. |
| Motion em tokens | Passa | `--m-in` 150 ms, `--m-out` 120 ms, `--m-press` 90 ms e `--ease`. Botão desce 1 px e encolhe a 0,985 no clique (C:218-247). Nenhum `transition: all`. |
| Movimento reduzido respeitado | Passa | O pulso da etapa só roda com `prefers-reduced-motion: no-preference` (C:443-455). |
| Motion só com informação | Falha leve | O pulso de brilho da etapa atual repete o que o número e a cor já dizem. UI-15. |

**Teclado e cabeçalho:**

| Item | Estado | Evidência |
|---|---|---|
| Pular para o conteúdo | Passa | H:16, `.pular` em C:86-91. |
| Foco visível | Passa | Contorno na cor do texto e halo âmbar (C:83), nos dois temas. O halo âmbar é mais um papel do âmbar (UI-01). |
| Ordem de tabulação | Passa | No passo 1: pular, trilha ("Senha"; os outros passos ficam desabilitados), Usar, Revisar, Trocar a senha, Log. |
| Foco levado ao mudar de tela | Passa | J:320, J:374, J:458, J:903, J:1242; Opções rola e foca o 1º campo (J:257). |
| Alvo de clique | Aceito | `--controle` de 38 px, abaixo de 44 px. Painel de notebook, com mouse; mobile está fora do escopo. |
| Dica só por `title` | Falha | H:36 e H:158. UI-11. |
| `color-scheme` e `theme-color` | Passa | `theme-color` por tema (H:9-10), `color-scheme` no `:root`. |
| Opções ao alcance | Falha | `margin-top: auto` (C:154) empurra Opções para o fim da coluna do menu, fora da tela a 768 px. É o UX-12. |

## Web Interface Guidelines (`arquivo:linha`)

```
index.html:25   - link sem destino: href="#" até o JS preencher (UI-17)
index.html:36   - explicação só em title, inacessível por teclado e toque (UI-09, UI-11)
index.html:158  - explicação do broadcast DHIP só em title (UI-11)
index.html:321  - placeholder sem reticências ("vazio = .200 a .249, pelo MAC") (UI-18)
index.html:339  - placeholder sem reticências ("vazio = 192.168.1.220") (UI-18)
index.html:395  - placeholder com rede 10.70.20.x, fora do conjunto fictício do repositório (UI-18)
index.html:396  - idem
index.html:48   - glifo ⚙ como ícone; aria-hidden correto, desenho depende da fonte (UI-16)
app.css:278     - disabled por opacity, contra a regra de C:239 (UI-14)
app.css:315     - .selo declarado duas vezes; a 2ª (C:401) anula a 1ª (UI-13)
app.css:325     - fonte mono em valor que não é dado ("Obra exemplo") (UI-07)
app.css:117     - faixa listrada sticky de 38 px em toda tela (UI-08)
app.js:147      - aviso neutro some sozinho em 4 s (UI-19)
app.js:770      - confirm() nativo; aceito por decisão do plano para ação destrutiva
```

Passam: `Intl` para número e data (J:36-39), `text-wrap: balance` nos títulos (C:105), `font-variant-numeric: tabular-nums` em tabela, fita e IPs (C:104), `prefers-reduced-motion`, `:focus-visible`, `touch-action`, log com `aria-live` desligado e rolagem que só segue quando o operador está no fim (J:407-412), `beforeunload` só com alteração pendente (J:1616), sem `transition: all`.

## Sinais de UI gerada (`frontend-design`)

| Sinal | Onde | Leitura |
|---|---|---|
| Listra colorida na borda esquerda | `.passo`, `.bancada`, `.painel-sem-fila` (6 px), `.aviso`, `.ultimo` (4 px), menu ativo (3 px) | O sinal mais visível do painel. A listra não codifica nada estável: é âmbar no passo e na bancada, cinza sem fila, vermelha no aviso. |
| Kit de cartões iguais | Resumo (6 caixas cinza com "Alterar"), `.secao`, `.ferramenta`, `.cartao` | Tudo é caixa de borda fina e raio 4 a 8 px. A hierarquia vem da caixa, não do tipo nem do espaço. |
| Um raio em tudo | `--r-sm` e `--r-md` em botão, campo, cartão, selo e seção | Nenhuma diferença de forma entre o que se clica e o que se lê. |
| Mono em rótulo pequeno | `.resumo-secao dd` (C:325), `.fita li` (C:340), contadores (C:277, C:440) | Mono deveria marcar só valor de máquina (IP, MAC, serial). Aqui marca também "câmera 1 agora" e "Obra exemplo". |
| Numeração de sequência | Trilha de passos e etapas da câmera | **Legítimo:** as duas são sequência de verdade. O problema é só o número em mono. |
| Acento que não quer dizer nada | Âmbar em 6 papéis | É o UX-15, visto pelo lado da cor. UI-01. |
| Faixa de perigo listrada | `.faixa-simular` (C:117-125) | Estampa de obra para um modo de teste. |
| Título genérico sem marca | `h1.marca` "Configurar câmeras" (H:29, C:134) | Nada diz quem fez o painel. UI-02. |
| Glifo unicode como ícone | ⚙ em Opções (H:48) | Desenho e alinhamento variam com a fonte. |
| Pulso decorativo | Etapa atual (C:443-446) | Movimento sem informação nova. |

Os outros sinais da lista (creme com serifa, preto com verde-ácido, jornal, eyebrow em caixa alta, "A · B · C", seta "→" no botão) **não** aparecem.

## Crítica visual por eixo

Capturas citadas: `t1-painel-cartoes-claro`, `t1-painel-decisao-escuro`, `t1-painel-concluida-claro`, `t1-resumo-claro`, `t1-passo-rede-claro` (Task 1) e `t3-passo-camera-escuro` (desta Task).

- **Hierarquia.** Nenhuma tela tem um ponto focal. Em `t1-painel-cartoes-claro`, a barra vermelha do topo, a faixa listrada, a fita com dois blocos âmbar, a listra âmbar da bancada e o botão âmbar disputam o olho no mesmo nível. O `h1` (24 px) e o `h2` (21 px) estão a uma razão de 1,14 e se confundem. O título da tela não é maior que a marca do topo.
- **Densidade.** O passo Câmera (`t3-passo-camera-escuro`) abre com cinco linhas de explicação antes do primeiro campo, e o 2º stream fica abaixo da dobra. Os cartões de câmera (`t1-painel-cartoes-claro`) mostram Porta e Canal sempre abertos, e cada cartão ocupa quase meia tela (UX-22). O Resumo (`t1-resumo-claro`) gasta seis caixas para 15 valores.
- **Tipografia.** Segoe UI Variable e Cascadia Mono, sem fonte baixada; a escolha é boa para Windows. Faltam a escala e os pesos: 11 tamanhos, quase todos entre 13 e 15 px, sem degrau claro entre rótulo, corpo e título. O mono aparece demais. Medida do texto corrido: 15 px em 518 px, cerca de 70 caracteres, que está bom.
- **Cor.** A paleta é neutra e bem feita em tokens, e o contraste passa no checker. O problema é o âmbar, que é a única cor de destaque e serve para tudo (UI-01), e o vermelho do topo, que é alarme permanente (UX-01). A paleta não tem relação com a marca SmartSeg (azul e grafite).
- **Consistência de componente.** Dois selos (UI-13), três larguras de listra lateral (UI-03), dois jeitos de mostrar desabilitado (UI-14). Três jeitos de dizer "agora": bloco âmbar cheio na fita (C:354), contorno âmbar no "próxima" (C:359) e etapa âmbar pulsando (C:443).
- **Alinhamento.** A coluna de conteúdo é centrada com margem igual dos dois lados a 1366 px. O rótulo da trilha fica fora do centro do bloco (`label-centre`) e quebra em duas linhas ("Placa de / rede", "Faixa de / fábrica" em `t3-passo-camera-escuro`). Os pares de campos do encoder alinham pela base, mas "Codec" desce uma linha porque o campo ao lado tem dois controles empilhados (`t3-passo-camera-escuro`).
- **Estados.** Feito, falhou e pulado na fita têm cor, borda e texto, e isso é bom. Na trilha de passos, concluído e pendente diferem só pela cor da borda de cima (verde, âmbar, cinza) e pelo cinza do texto. O tema escuro (`t1-painel-decisao-escuro`, `t3-passo-camera-escuro`) é coerente com o claro. O foco do campo vira um anel âmbar grosso, igual ao "agora".

## Achados

Cada achado: id, severidade, evidência, código e o `UX-nn` relacionado.

**UI-01. O âmbar faz seis papéis.** Severidade alta.
- Evidência: em `t1-painel-cartoes-claro`, o âmbar marca o modo simulação, a câmera atual, a próxima, a bancada, o botão principal e o foco ao mesmo tempo.
- Código: `--acento` (C:19) em `.faixa-simular` (C:117-125), `.fita li.atual` (C:354), `.fita li.proxima` (C:359), listra de `.passo` e `.bancada` (C:284, C:362), `.btn.acento` (C:236), halo do foco (C:83), etapa atual (C:443-446).
- Relação: é o UX-15 pelo lado da cor. Além disso, o âmbar não pertence à marca SmartSeg e, como texto sobre branco, mede 2,25:1, de modo que só serve como fundo.

**UI-02. O painel não tem marca.** Severidade alta.
- Evidência: em todas as capturas, o topo diz "Configurar câmeras" em texto puro. Não há logo, e nenhuma cor vem da SmartSeg.
- Código: `h1.marca` (H:29, C:134). O servidor não serve PNG, nem subpasta de `www\`, então a logo não entra sem decisão técnica (ver Marca).
- Relação: o pedido da frente é redesenho com a marca SmartSeg.

**UI-03. A hierarquia é feita de caixa e listra, não de tipo e espaço.** Severidade alta.
- Evidência: caixas com listra lateral em três larguras. O vigia e os cartões ficam dentro da bancada listrada (`t1-painel-cartoes-claro`), e "Fila concluída" fica dentro da mesma caixa (`t1-painel-concluida-claro`). O Resumo são seis caixas iguais (`t1-resumo-claro`).
- Código: C:146-153, C:257, C:284, C:329, C:362, C:458; `.cartao` C:388-431; `.secao` C:487-492.
- Relação: o UX-22 (cartões não escalam) e o UX-24 (log aberto) pesam mais por causa disso. É o "kit de cartões" da lista de sinais.

**UI-04. Escala tipográfica sem tokens nem degraus.** Severidade média.
- Evidência: 11 tamanhos de fonte. `h1` de 24 px contra `h2` de 21 px (razão 1,14); os rótulos de 13 px e o corpo de 15 px ficam perto demais para separar papéis.
- Código: nenhum token de tamanho em `:root` (C:8-54); `0.92em` em C:69, 13,5 px em C:325, 12,5 px no log (C:515).
- Relação: a direção define a escala (a decisão do plano fixa o corpo em 14 a 15 px e o piso em 13 px).

**UI-05. Espaçamento fora do sistema.** Severidade média.
- Evidência: 152 valores em `rem` literais fora de `:root` contra 32 usos de `--s-1` a `--s-6`. Padding, gap e margem variam de 0,05 a 1,5 rem sem degrau fixo.
- Código: espalhado em C; exemplos em C:117-125 (`0.45rem 1.25rem`) e C:146 (`1rem 0.5rem`).

**UI-06. A página salta ao abrir.** Severidade média.
- Evidência: `perf.mjs` mede layout shift de 0,360 a 1440 px (o limite bom é 0,1).
- Código: a faixa de simulação (H:18), o menu e o passo nascem `hidden` e aparecem depois do primeiro `/api/estado`, empurrando o conteúdo já pintado.
- Relação: um clique feito no primeiro meio segundo cai no lugar errado.

**UI-07. Mono fora de dado de máquina.** Severidade média.
- Evidência: em `t1-resumo-claro`, todos os valores estão em mono, inclusive "Obra exemplo" e "não precisa em simulação". Na fita, "câmera 1 agora" também está em mono.
- Código: C:325 (`.resumo-secao dd`), C:340 (`.fita li`), C:379 (`.decisao-erro`), C:483 (`.resultado dd`), contadores C:277 e C:440.
- Relação: o mono deveria ser o sinal de "isto é IP, MAC ou serial". Usado em tudo, ele deixa de servir de sinal.

**UI-08. A faixa de simulação grita mais que qualquer estado real.** Severidade média.
- Evidência: faixa sticky listrada em âmbar no topo de toda tela (todas as capturas). Ela ocupa 38 de 768 px e é o elemento de maior contraste da página.
- Código: C:117-125, H:18-20.
- Relação: só aparece em simulação, mas é a tela de todas as demonstrações e de todos os testes de UI. Ela reforça o UI-01.

**UI-09. Estado da placa em texto técnico vermelho.** Severidade média.
- Evidência: "Placa Ethernet sem as faixas: 192.168.1.x (camera de fabrica em 192.168.1.108); 192.0.2.0/24 (conferencia no IP definitivo)", numa linha só, sem acento, com ponto vermelho (`t3-passo-camera-escuro`).
- Código: H:33-36, montado em J:484 a partir do servidor.
- Relação: o UX-01 (vermelho sem ação) e o UX-40 (sem acento). Pelo lado visual, falta um formato de estado (ícone, rótulo curto, detalhe sob demanda) no lugar de uma frase.

**UI-10. A trilha de passos quebra o rótulo e diz o estado só pela cor.** Severidade média.
- Evidência: 7 blocos de 57 px de altura. "Placa de / rede", "Rede das / câmeras" e "Faixa de / fábrica" quebram em duas linhas. O número está em mono. Feito e pendente diferem pela cor da borda de cima (`t3-passo-camera-escuro`). O checker acusa `label-centre`.
- Código: C:272-280.

**UI-11. Explicação só em `title`.** Severidade média.
- Evidência: o que é o broadcast DHIP e o que significa "internet ok" só aparece ao parar o mouse em cima. Por teclado e por toque não aparece nunca.
- Código: H:36, H:158.

**UI-12. Explicação longa antes do primeiro campo.** Severidade média.
- Evidência: o passo Câmera abre com cinco linhas antes do e-mail (`t3-passo-camera-escuro`), e o passo Rede segue o mesmo padrão (`t1-passo-rede-claro`).
- Código: `p.explica` em H:68-118.
- Relação: o UX-09 (jargão). A direção decide o que vira ajuda sob demanda.

**UI-13. Dois estilos de selo, o segundo anulando o primeiro.** Severidade baixa.
- Código: `.selo` em C:315 (pílula de 999 px, fundo `--acento-fraco`) e em C:401-405 (`--r-sm`, fundo `--sup-2`). Pela cascata, vale o segundo onde os dois se sobrepõem, e a pílula nunca aparece.

**UI-14. Desabilitado com duas caras.** Severidade baixa.
- Código: a regra geral (C:239-247) usa a cor de apoio sem opacidade, e `.passo-botao:disabled` usa `opacity: 0.7` (C:278).

**UI-15. Pulso decorativo na etapa atual.** Severidade baixa.
- Código: animação de brilho em C:443-446. O movimento reduzido é respeitado (C:449-455), mas o pulso não diz nada que o número e a cor já não digam.

**UI-16. Glifo ⚙ como ícone.** Severidade baixa.
- Código: H:48. O desenho e a linha de base mudam com a fonte do sistema; não há conjunto de ícones.

**UI-17. Link com `href="#"`.** Severidade baixa.
- Código: `#atualizacao-notas` (H:25) fica com `href="#"` até o JS preencher. Ele está `hidden`, mas o checker de links acusa.

**UI-18. Placeholders inconsistentes.** Severidade baixa.
- Código: H:321 e H:339 sem reticências, ao contrário de H:395-399. H:395-396 usam a rede 10.70.20.x, que não está no conjunto fictício do repositório (192.0.2.x e 192.168.1.108).

**UI-19. Aviso neutro some em 4 s.** Severidade baixa.
- Código: J:147. Uma mensagem com duas frases não dá para ler em 4 s com a atenção na câmera.

## Marca

### Arquivos em `marca/`

| Arquivo | O que é |
|---|---|
| `logo-smartseg.png` | Logo oficial, baixada de `http://gruposmartseg.com.br/wp-content/uploads/2023/09/Logo-Smartseg-Vetor.png` em 19/11/2026. PNG RGBA de 2302×1175 px, com fundo transparente e 125.144 bytes. SHA-256 `205ca1618fd04422b4e501b40437e314be53cec81d76602840d2d3868f334634`. |
| `logo-smartseg-escuro.png` | **Variante derivada, não oficial**, para o tema escuro. O grafite `#565758` foi trocado pelo `--texto` escuro `#E4E7E9` e o cinza `#848688` pelo `--apoio` escuro `#9AA3A9`. Os azuis e o alfa ficaram como estavam. Cada pixel foi trocado pela cor de destino da cor de origem mais próxima. Precisa do aval da SmartSeg antes de ir para o produto. |

**Decisão do usuário:** não há arquivo vetorial; a base é o PNG de 2302 px do site.

**Como a logo lê** (prova em `.playwright-mcp/`, fora do repositório):
- No tema escuro, a logo oficial quase some: o grafite mede 2,36:1 contra `#191C1E`. A variante clara lê bem.
- A 120 px de largura, o traço fino de "Grupo" fica apagado. No topo do painel, a logo precisa de **160 px de largura, no mínimo**.

**A logo não é servida hoje.** O servidor só entrega arquivos diretos de `www\`, e `$tipos` só tem html, js, css e svg (`Servidor-Painel.ps1:1614-1617`). Há três caminhos para a fase B:
1. Pôr `png` em `$tipos`. É uma mudança de tipo de arquivo estático, permitida pelas decisões do plano.
2. Embutir a logo reduzida como `data:` (a CSP permite `img-src data:`).
3. Redesenhar em SVG, o que não parte de vetorial oficial.

Cada arquivo novo em `www` também precisa de `Source:` no `instalador/ConfigurarCameras.iss`.

### Cores medidas

Histograma dos pixels opacos da logo oficial:

| Cor | Papel na logo | Fatia |
|---|---|---|
| `#565758` | Grafite: "SmartSeg" | 55,4% |
| `#5489A1` | Azul claro | 25,7% |
| `#407A94` | Azul escuro | 12,9% |
| `#848688` | Cinza: "Grupo" | 6,0% |

Os quatro valores batem com os que o plano trazia.

### Contraste WCAG

Razão de contraste (luminância relativa, WCAG 2.x). Fundos: branco, `--fundo` claro `#E9ECEE`, `--sup-2` claro `#F4F6F7`, `--fundo` escuro `#191C1E`, `--sup` escuro `#23272A`, e `--texto` claro `#262B2E` (texto escuro sobre a cor).

| Cor | Branco `#FFFFFF` | Fundo claro `#E9ECEE` | Sup-2 claro `#F4F6F7` | Fundo escuro `#191C1E` | Sup escuro `#23272A` | Texto escuro `#262B2E` |
|---|---|---|---|---|---|---|
| `#407A94` | **4,74** | 4,00 | 4,37 | 3,61 | 3,17 | 3,02 |
| `#5489A1` | 3,84 | 3,24 | 3,54 | 4,46 | 3,92 | 3,73 |
| `#565758` | 7,24 | 6,10 | 6,68 | 2,36 | 2,08 | 1,98 |
| `#848688` | 3,65 | 3,08 | 3,37 | 4,69 | 4,12 | 3,92 |
| `#E0A21B` (âmbar atual) | 2,25 | 1,89 | 2,07 | 7,63 | 6,70 | 6,37 |

Limites: 4,5 para texto normal, 3 para texto grande (24 px, ou 18,66 px em negrito) e para componente de UI e foco (WCAG 1.4.11).

**Usos que cada cor aguenta:**

| Cor | Pode | Não pode |
|---|---|---|
| `#407A94` | Botão cheio com texto branco (4,74, margem curta). Texto e link sobre superfície branca (4,74). Borda, ícone e anel de foco nos dois temas (3 ou mais em todos os fundos). | Texto normal sobre o fundo claro `#E9ECEE` (4,00). Texto escuro sobre ela (3,02). Texto normal no tema escuro (3,61). |
| `#5489A1` | Componente de UI e texto grande nos dois temas. Texto branco só em tamanho grande (3,84). | Botão com rótulo branco de 14 px. Texto normal no claro (3,24). Link no escuro: 4,46 fica logo abaixo de 4,5, então pede um tom mais claro. |
| `#565758` | Texto e título no tema claro (6,10 ou mais). | Qualquer uso no tema escuro (2,36); por isso existe a variante clara da logo. |
| `#848688` | Texto no tema escuro (4,69). Borda no claro (3,08). | Texto normal no tema claro (3,65 sobre branco). |

**Consequência para a direção (Task 4):**
- No tema claro, `#407A94` serve de cor de ação com texto branco.
- No tema escuro, o botão cheio `#407A94` com texto branco continua valendo (4,74 no rótulo, 3,17 contra a superfície). Texto e link azuis precisam de um tom mais claro, a definir, com 4,5 ou mais contra `#23272A`.
- Nenhum dos dois azuis carrega texto escuro por cima.
- O âmbar, se ficar, só serve como fundo com texto escuro, ou como texto no tema escuro.
