# Frente registro-controle: controle do operador sobre registro, fila e log (1.3.1, 2 de 2)

**Status:** Ativo · **Frente:** `registro-controle`

Frente 2 da onda 2 do mapa `docs/plans/2026-11-26-versao-131-mapa.md`. Depende da frente `responsivo` fechada (as duas tocam `tela-painel.js`, `componentes.css` e `textos.js`). Escopo fechado em grilling (26/11).

**Goal:** o operador decide o que fica no registro e o que sai no CSV, e lê e baixa o log. Toda exclusão é reversível por uma cópia automática.

**Non-Goals:**
- editar campos do registro;
- campo de obra;
- escolher colunas do CSV;
- apagar o log;
- histórico de filas encerradas;
- filtros além da busca de texto.

**Touched:** `fonte/Motor-Cameras.ps1`, `fonte/web/Servidor-Painel.ps1`, `fonte/Testes-Motor.ps1`, `fonte/web/www/` (`tela-painel.js`, `tela-inicio.js`, `tela-ferramentas.js`, `textos.js`, `constantes.js`, `componentes.css`, `telas.css`, `tokens.css`), `CONTEXT.md`, `LEIA-ME.md`, este plano, o mapa.

## Estado de hoje (levantamento, 26/11)

- **Registro.**
  - `registro.json` na pasta de dados (`registro-simulado.json` em simulação): um por PC, sem obra nem sessão.
  - Escrita só por upsert: `Update-RegistroCamera` sob Mutex (`Motor-Cameras.ps1:3712`) e `Set-CameraRegistro` (`:3645`).
  - Nenhuma rota nem botão de remover ou limpar. Rotas: `GET /api/registro` (`Servidor-Painel.ps1:1839`), `GET /api/relatorio.csv` (`:1840`).
  - "Refazer o passo a passo" (`:1071`) não toca o registro.
- **CSV.** `ConvertTo-RelatorioCsv` (`Motor-Cameras.ps1:3811`): registro inteiro, 17 colunas fixas, UTF-8 com BOM, separador `;`.
- **Fila.** Só em memória. `Clear-Fila` (`Servidor-Painel.ps1:628`); "Encerrar a fila" (`POST /api/decisao`). A tabela mostra a fila encerrada até alguém montar outra.
- **Log.**
  - `log.txt` por `Write-Log` (`Motor-Cameras.ps1:66`), `Add-Content` de vários runspaces, sem rotação.
  - Em memória, um ring de 3000 linhas.
  - Ferramentas tem um `<details>` com "Só avisos e erros", sem baixar nem buscar (`tela-ferramentas.js:129-147`).
- **Testes.** Registro e CSV cobertos em `Testes-Motor.ps1`; as rotas do servidor não têm teste unitário (prova por simulação).
- **Dados sensíveis.**
  - Registro e CSV: MAC, IP, serial, local e gateway, sem senha.
  - Log: e-mail de recuperação, gateway e IPs, sem senha.

## Decisões do usuário (grilling, 26/11)

- **G1. Passo a passo novo com registro não vazio.**
  - O painel mostra no início: "O registro tem N câmeras, a última de dd/mm/aaaa."
  - Opções: Manter, Exportar e zerar, Zerar.
  - Abrir o painel ou montar uma fila **nunca** apaga nada sozinho.
- **G2. Cópia automática antes de excluir, zerar ou restaurar.**
  - Antes de qualquer uma dessas ações, o registro inteiro vai para `<PastaDados>\copias-registro\registro-yyyyMMdd-HHmmss-<acao>.json`. Em simulação, `copias-registro-simulado`.
  - Ficam as últimas 10.
  - Ferramentas ganha "Cópias do registro": lista com data, ação e nº de câmeras, e "Restaurar esta cópia".
  - O diálogo de exclusão diz quantas câmeras saem e que a cópia fica em Ferramentas.
- **G3. Busca de texto única** sobre IP, MAC, serial, modelo, local, rack e andar. Filtra na tela, sem rota.
- **G4. Seleção por linha.**
  - Coluna de caixas; a do cabeçalho marca as linhas visíveis, em estado indeterminado quando parcial.
  - Barra: "N selecionadas · Exportar · Excluir · Limpar a seleção".
  - Zerar o registro = marcar todas e excluir; o diálogo diz "todas as N".
  - Vale durante a operação no Painel, não só no passo a passo.
- **G5. Fila aberta.**
  - As câmeras da fila aberta ficam com a caixa desabilitada e "Na fila agora" ao lado; o resto pode ser excluído a qualquer momento.
  - O servidor também recusa esses MACs (defesa dupla).
  - Restaurar uma cópia fica travado com fila aberta, pelo mesmo motivo: o motor regrava o registro.
- **G6. "Limpar a fila".**
  - Botão na fila encerrada ou concluída: a tabela sai e o Painel volta a "Sem fila".
  - O registro não muda, e com a fila aberta o servidor recusa.
- **G7. CSV com colunas fixas.**
  - Linhas: as selecionadas, ou todas se nada estiver marcado.
  - Exportação parcial leva `-selecao` no nome.
  - Vai por `POST` com a lista de MACs e o download sai por Blob no front, para não estourar a URL. O `GET` de hoje fica para o registro inteiro.
- **G8. Log.**
  - Rotação por tamanho (5 MB; mantém `log.1.txt` a `log.3.txt`), na abertura do painel e no laço do servidor. Não roda no `Write-Log`, para não disputar o arquivo com os runspaces paralelos.
  - Falha de rotação é ignorada e registrada.
  - Ferramentas ganha "Baixar o log" (`GET /api/log.txt`) e a mesma busca de texto sobre as linhas, junto do filtro de hoje.
  - Sem apagar.
- **G9. Vocabulário.**
  - `CONTEXT.md`: Registro deixa de ser "a única cópia". Entram "cópia do registro" e "limpar a fila".
  - `LEIA-ME.md`: seções do registro, do backup e de Ferramentas.

**Safety (as duas frentes):**
- Painel só em simulação, do worktree:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1 -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar -SemAtualizacao -PastaDados <scratchpad>\painel-131`
  - Porta ocupada: use 8766 e anote no commit. Encerre o processo que você subiu.
- Câmera com MAC fora de `AA:00:00:00:00:0x` ou serial fora de `SIM-x`: `BLOQUEADO`.
- Capturas em `.playwright-mcp/` (ignorado), nunca no repo.
- Sem push, tag nem release.
- Codificação:
  - `Servidor-Painel.ps1` e o `.iss` em UTF-8 **com BOM**;
  - `Testes-*.ps1` em ASCII, com acento por `[char]`;
  - `www` em UTF-8 sem BOM, com CRLF.
- Textos em pt-BR, em caixa de frase, só em `textos.js`; medidas só em `tokens.css`.

**Régua de toda Task:** o bloco `### Validação` do `CLAUDE.md`, com a saída colada no corpo do commit.

## Task 1: motor (TDD)

**Files:** `fonte/Motor-Cameras.ps1`, `fonte/Testes-Motor.ps1`

**Skills:** `mattpocock-skills:tdd`.

Funções puras e testáveis, todas pelo mesmo Mutex e pela mesma leitura travada de `Update-RegistroCamera` e `Read-RegistroTravado`:
- `Remove-CamerasRegistro -Caminho -Macs`: devolve as removidas; MAC ausente não é erro.
- `Save-CopiaRegistro -Caminho -Pasta -Acao`, que poda para 10.
- `Get-CopiasRegistro -Pasta`: data, ação e nº de câmeras, da mais nova para a mais velha.
- `Restore-CopiaRegistro -Caminho -Pasta -Nome`: salva antes uma cópia do atual e recusa nome fora da pasta (sem path traversal).
- `ConvertTo-RelatorioCsv -Macs` (opcional; sem ele, tudo como hoje).
- `Invoke-RotacaoLog -Caminho -LimiteBytes -Manter`.

Testes com MACs `AA:00:00:00:00:0x`, em pasta temporária.

**Validation:** a régua; o RED de cada função colado.

## Task 2: servidor

**Files:** `fonte/web/Servidor-Painel.ps1` (BOM), `fonte/web/www/textos.js` (a recusa passa pelo `traduzirServidor`)

- Rotas:
  - `POST /api/registro/excluir {macs}`, que faz a cópia antes e recusa os MACs da fila aberta (G5);
  - `GET /api/registro/copias`;
  - `POST /api/registro/restaurar {nome}`, travada com fila aberta;
  - `POST /api/relatorio.csv {macs}`;
  - `POST /api/fila/limpar`, só com a fila encerrada ou concluída;
  - `GET /api/log.txt`.
- Rotação do log na abertura e no laço (G8).

**Validation:** a régua. Em simulação, por `Invoke-WebRequest`: cada rota no caso bom e na recusa (MAC na fila; restaurar e limpar com a fila aberta; nome com `..\`), com as saídas coladas.

## Task 3: Registro no Painel (G3, G4, G5, G7)

**Files:** `tela-painel.js`, `textos.js`, `constantes.js`, `componentes.css`, `telas.css`, `tokens.css`

**Skills:** `design-taste-frontend` (`references/system.md`, tabelas e estados), `web-design-guidelines`, `frontend-design` (escrita).

- Busca, caixas, barra de seleção e diálogo de exclusão (G2), linha travada "Na fila agora" e exportação da seleção.
- A coluna de caixas cabe no layout da frente `responsivo` (`medir-responsivo.js` sem regressão).
- Teclado: Espaço marca a linha, e o foco volta à barra depois de excluir.

**Validation:** a régua. Playwright em simulação:
- buscar, marcar 2, exportar (nome com `-selecao`, 2 linhas);
- excluir 1 e conferir a cópia criada;
- marcar todas e excluir (diálogo "todas as N");
- com fila aberta, a câmera em curso não pode ser marcada;
- medição sem regressão a 1366 e a 900.

## Task 4: passo a passo e fila (G1, G6)

**Files:** `tela-inicio.js`, `tela-painel.js`, `textos.js`, `componentes.css`

- G1 no primeiro passo, só com registro não vazio. "Exportar e zerar" baixa o CSV inteiro e só zera depois do download iniciado.
- G6: botão "Limpar a fila" na fila encerrada ou concluída.

**Validation:** a régua. Playwright:
- refazer o passo a passo com 3 câmeras no registro: aparece o aviso; Manter mantém; Zerar zera e deixa a cópia;
- encerrar a fila e depois Limpar a fila: o Painel volta a "Sem fila", e o registro fica intacto.

## Task 5: Ferramentas (G2, G8)

**Files:** `tela-ferramentas.js`, `textos.js`, `componentes.css`

- "Cópias do registro" com Restaurar, travado com fila aberta e com o motivo dito.
- No log: "Baixar o log" e a busca de texto.

**Validation:** a régua. Playwright: restaurar a cópia da Task 3 devolve a câmera excluída; baixar o log; a busca filtra as linhas.

## Task 6: documentos e verificação

**Files:** `CONTEXT.md`, `LEIA-ME.md`, este plano (`**Status:** Concluído`), o mapa

- G9.
- Roteiro de ponta a ponta nos dois temas: passo a passo com registro antigo, operação com fila aberta excluindo linhas antigas, limpar a fila e restaurar a cópia.
- `medir-responsivo.js` sem regressão.

**Validation:** a régua, com o roteiro colado; `git diff --cached` sem dado real.
