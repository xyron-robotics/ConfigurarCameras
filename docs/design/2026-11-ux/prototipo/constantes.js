// Numeros com sentido do painel (direcao.md, secao 7.2). Fora daqui, nenhum literal maior que 2.

export const ETAPAS = ['inicializada', 'encoder', 'rede', 'conferida'];
export const TOTAL_ETAPAS = 4;

export const CONSULTA_MS = 1000;
export const FALHAS_ATE_PERDER_CONEXAO = 3;
export const TRAVA_DECISAO_MS = 1500;

export const HTTP = {
  OK: 200,
  ACEITO: 202,
  REQUISICAO_INVALIDA: 400,
  CONFLITO: 409,
  ERRO_SERVIDOR: 500,
};

// Fita: ate este numero de casas, numero embaixo de cada uma; acima, a cada FITA_PASSO_NUMERO.
export const FITA_MAX_NUMEROS = 24;
export const FITA_PASSO_NUMERO = 5;

export const OCTETOS_IP = 4;
export const OCTETO_MAX = 255;

export const SECOES = ['senha', 'placa', 'rede', 'camera', 'fila'];
export const PASSOS = ['senha', 'placa', 'rede', 'camera', 'fila', 'conferir'];
export const SECOES_SESSAO = ['senha', 'placa', 'rede', 'camera', 'fila', 'painel'];

export const TEMAS = ['sistema', 'claro', 'escuro'];


export const SENHA_MIN = 8;
