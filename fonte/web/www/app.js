// Entrada do painel (<script type="module" src="/app.js">). Escolhe o
// adaptador da api.js (fetch, este servidor), monta a marcacao em #app e liga
// o codigo de transicao dos legado-*.js, que as frentes 3 a 5 substituem.
import { criarApi, transporteFetch } from './api.js';
import { montarMarcacao } from './legado-marcacao.js';
import { usarApi } from './legado-estado.js';
import { carregarSessao } from './legado-formularios.js';
import { iniciar, ciclo } from './legado-navegacao.js';
import { ligar, ligarTema } from './legado-ligacoes.js';

usarApi(criarApi(transporteFetch()));
document.getElementById('app').replaceChildren(...montarMarcacao());
iniciar();
ligar();
ligarTema();
carregarSessao();
ciclo();
