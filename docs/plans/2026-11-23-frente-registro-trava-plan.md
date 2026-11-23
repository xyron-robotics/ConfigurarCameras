# Frente registro-trava: leitura do registro sob o Mutex (conserta o Testes-Coordenador intermitente)

**Status:** Ativo · **Frente:** `registro-trava`

**Goal:** toda leitura do registro de câmeras (`registro.json`) passa pelo mesmo Mutex que a gravação. Com isso, a conferência de uma câmera não lê o registro no meio do `File.Replace` de outra. O `Testes-Coordenador` fica estável e a release 1.3.0 não cai no CI.

**Non-Goals:** mexer na sessão, no rastro da placa ou em outros JSON (`Save-JsonAtomico` continua como está), no front, no redesenho (fase B) ou em timeouts de teste. Release, push e tag ficam de fora.

**Touched:** `fonte/Motor-Cameras.ps1`, `fonte/Coordenador-Cameras.ps1`, `fonte/web/Servidor-Painel.ps1` (UTF-8 **com BOM**: preservar), `fonte/Testes-Motor.ps1`, este plano.

## Context

O CI da release roda o `Testes-Coordenador`, que falha de vez em quando nos testes "pool". Reproduzido em 19/11 na `main` `7193319`: **3 falhas em 6 rodadas**, sempre no cenário das 5 câmeras. Uma câmera termina em `decisao`, o registro dela fica em `Em andamento` e a linha do modo some do log da conferência.

**Causa medida:**
- A conferência lê o registro **sem o Mutex** (`Motor-Cameras.ps1:3999`), enquanto outro job grava sob Mutex com `File.Replace` (`Update-RegistroCamera`, `:3675`; `Save-JsonAtomico`, `:3481`).
- No meio do Replace, `Read-JsonArquivo` (`:3501`) vê duas coisas: o arquivo ausente, e então devolve um registro vazio; ou um erro de leitura, que ele engole antes de cair no `.bak`, que é a versão anterior.
- Daí sai "o MAC não está no registro" ou "parou na etapa X" (`:4010`, `:4012`). A conferência recusa antes da linha do modo (`:4019`), e o `Instalada` nunca é gravado.
- Prova da janela nesta máquina: em 7,5 s, um leitor sem trava competindo com um escritor por Replace achou 162 vezes o arquivo ausente e teve 4545 exceções; em 4321 delas leu o `.bak`.

**Isto é defeito do produto, não só do teste.** O painel real roda o pool em paralelo com câmeras de verdade e tem as mesmas leituras sem trava:
- `Coordenador-Cameras.ps1:901` (`Sync-PortaCanalRegistro`) é ler, mudar e gravar. Uma leitura velha do `.bak` grava a entrada antiga por cima, e o `Instalada` pode voltar para `Em andamento`.
- `Servidor-Painel.ps1:691, 786, 936, 1232` e `Read-RegistroAtual` (`:1702`): um registro vazio por um instante faz a fila da faixa (`:936`) sugerir de novo câmeras já instaladas. O retry por `IOException` em `:1706` nunca dispara, porque `Read-JsonArquivo` engole a exceção.

Todas as **gravações** do registro já passam por `Update-RegistroCamera`, sob o Mutex. Falta só travar as leituras.

## Decisões técnicas

- **Leitura travada em vez de retry.** Retry só diminui a janela; o Mutex fecha a janela. O Mutex já existe (`Get-NomeMutexRegistro`, `:3660`) e é nomeado na sessão do Windows, então vale entre runspaces e para o servidor.
- **Um só ajudante de Mutex.** Extrair de `Update-RegistroCamera` uma função interna, por exemplo `Invoke-SobMutexRegistro -Caminho -Bloco -EsperaMs`, com o `WaitOne`, o `AbandonedMutexException` e o throw "ocupado". Ela serve a `Update-RegistroCamera` e à nova `Read-RegistroTravado -Caminho`. `Read-Registro` cru continua existindo e só é chamado sob o Mutex: dentro de `Update` e de `Read-RegistroTravado`.
- **`Sync-PortaCanalRegistro`** passa a usar `Read-RegistroTravado`. A janela entre ler e gravar continua, mas é inofensiva: a câmera já está `feita` e nenhum job dela grava ao mesmo tempo. Registrar isso no comentário da função.
- **Servidor:** `Read-RegistroAtual` vira um invólucro de `Read-RegistroTravado` sem o retry morto, e as 4 chamadas diretas passam a chamá-lo.
- **Guarda contra regressão:** um teste no `Testes-Motor` varre os `.ps1` de produção de `fonte/` (sem `Testes-*`) e falha se `Read-Registro` for chamado fora de `Update-RegistroCamera`/`Read-RegistroTravado`.
- Sem arquivo de teste novo, então `release.yml` e `Gerar-Instalador.ps1` não mudam.

## Task 1: testes vermelhos (corrida e guarda)

Em `fonte/Testes-Motor.ps1`, uma seção "Registro sob Mutex":
- **Teste de corrida.** Um runspace grava em laço por `Update-RegistroCamera` a câmera `AA:00:00:00:00:01`, com um contador crescente (por exemplo, em `Porta`) e uma segunda câmera fixa `AA:00:00:00:00:02`, por cerca de 2 s. Ao mesmo tempo, o teste lê em laço com o leitor sob prova.
- **O que o teste exige:** em toda leitura as duas câmeras estão presentes, o contador nunca cai e não há exceção.
- **O leitor é injetável** (scriptblock). Primeiro roda com `Read-Registro` cru para provar o vermelho, e esse vermelho é colado no commit. Depois fica com `Read-RegistroTravado`, que ainda não existe e por isso falha.
- **Teste de guarda,** como em Decisões: hoje ele lista `Motor:3999`, `Coordenador:901` e `Servidor:691/786/936/1232/1706-1708`.
- **Validation:** os 2 testes novos falham pelo motivo esperado e o resto do `Testes-Motor` fica verde. Commit só dos testes, com a saída vermelha no corpo.

## Task 2: leitura travada no motor

- Em `fonte/Motor-Cameras.ps1`: `Invoke-SobMutexRegistro` e `Read-RegistroTravado`, e `Update-RegistroCamera` reescrita sobre o ajudante, com o mesmo comportamento e a mesma mensagem.
- A linha `:3999` passa a usar `Read-RegistroTravado`.
- **Validation:** o teste de corrida fica verde. O de guarda ainda aponta só Coordenador e Servidor. Régua do Motor, Descoberta e Orquestrador verde.

## Task 3: coordenador e servidor

- `Sync-PortaCanalRegistro` e as leituras do `Servidor-Painel.ps1` passam a ler pelo caminho travado, como em Decisões.
- Conferir o BOM do servidor: o teste de BOM existente precisa passar.
- **Validation:** teste de guarda verde e régua inteira verde.

## Task 4: prova de estabilidade e fecho

- Rodar o `Testes-Coordenador` **10 vezes seguidas** e colar o placar no commit. A meta é 10/10 em 75/0, contra 3/6 com falha antes. Repetir uma vez com carga paralela (Motor e Descoberta rodando junto). Se algum "pool" ainda falhar, a Task volta VERMELHO com o motivo da `decisao`. Não aumentar timeout.
- Painel em `-Simular`, porta livre, rodando 5 câmeras em paralelo: todas terminam Instalada.
- Este plano passa a `**Status:** Concluído (<data>)`.
- **Validation:** régua inteira e `git diff --check`.

## Riscos

- **Leitura bloqueia atrás de uma gravação.** A gravação leva milissegundos, e o teto é o `EsperaMs` de 30 s, que já existe e lança "ocupado". O servidor HTTP pode esperar alguns ms por requisição, o que é aceitável.
- **Reentrância:** `Read-RegistroTravado` nunca é chamado dentro de `Update-RegistroCamera`, que continua usando `Read-Registro` cru. De todo modo, o Mutex do .NET é reentrante na mesma thread.
- **BOM do `Servidor-Painel.ps1`:** editar sem perder o BOM; o teste existente pega.
- **Mudança de comportamento:** nenhuma no caminho feliz. Só some o registro vazio ou velho lido por engano.

## Verificação ponta a ponta

1. Régua do `CLAUDE.md` (4 suítes + `git diff --check`), colada no commit de cada Task.
2. `Testes-Coordenador` 10× seguidas com 10/10 verde, e 1× sob carga paralela.
3. Painel em simulação com 5 câmeras em paralelo, todas Instalada no registro.
4. `git diff --cached` sem dado real (MACs `AA:00:00:00:00:0x`).

## Depois desta frente

Ativar a fase B, começando por `docs/plans/2026-11-20-frente-redesenho-1-arquitetura-plan.md`, que hoje está em Draft. Antes, corrigir o achado menor do plano da frente 3: as mensagens do servidor que ainda citam "Opções".
