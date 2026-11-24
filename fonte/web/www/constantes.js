// Numeros com sentido do painel (direcao.md, secao 7.2). Fora daqui, nenhum literal maior que 2.
// Regex com numero tambem mora aqui: o teste do front le regex literal como codigo.

export const ETAPAS = ['inicializada', 'encoder', 'rede', 'conferida'];

// Ciclo de consulta do estado: mais rapido com o worker ocupado ou configurando.
export const CONSULTA_MS = 1500;
export const CONSULTA_RAPIDA_MS = 600;
// Consulta logo depois de um comando e depois de pedir a atualizacao.
export const CONSULTA_APOS_COMANDO_MS = 150;
export const CONSULTA_APOS_ATUALIZAR_MS = 300;
// Espera do estado publicado: padrao, intervalo entre consultas e as esperas longas.
export const ESPERA_ESTADO_MS = 6000;
export const ESPERA_ESTADO_PASSO_MS = 250;
export const ESPERA_SESSAO_MS = 8000;
export const ESPERA_COMECAR_MS = 60000;

// Tempo maximo da trava dos botoes de um cartao depois de um clique: o
// servidor pode aceitar e nao mudar nada (o motivo chega pelo aviso).
export const TRAVA_DECISAO_MS = 5000;
// Aviso neutro (409, "aguarde") some sozinho.
export const AVISO_NEUTRO_MS = 4000;
// Pausa entre limpar e escrever o anuncio, para o leitor de tela falar de novo.
export const ANUNCIO_ATRASO_MS = 60;

export const HTTP = {
  OK: 200,
  REDIRECIONAMENTO: 300,
  REQUISICAO_INVALIDA: 400,
  CONFLITO: 409,
};

// Log: linhas guardadas, folga (px) para seguir o fim e onde a hora comeca em "yyyy-MM-dd HH:mm:ss".
export const LOG_MAX_LINHAS = 1500;
export const LOG_FOLGA_FIM = 30;
export const LOG_INICIO_HORA = 11;

export const OCTETOS_IP = 4;
export const OCTETO_MAX = 255;
export const MAC_DIGITOS = 12;
export const PORTA_HTTP = 80;
export const FILA_MAX_ENDERECOS = 254;
// Base do parseInt do numero do passo no hash (#inicio/N).
export const BASE_DECIMAL = 10;
// Colunas com IP, MAC e serial (sem tradutor) nas tabelas de Descobrir e Verificar.
export const COLUNAS_MONO_DESCOBRIR = [0, 1, 2, 4];
export const COLUNAS_MONO_VERIFICAR = [0, 1];

// Limites dos campos do encoder e a barra de progresso antes do primeiro dado.
export const FPS_MIN = 1;
export const FPS_MAX = 60;
export const BITRATE_MIN = 64;
export const BITRATE_MAX = 16384;
export const PROGRESSO_MAX = 120;

// Secoes da tela de Opcoes de hoje (legado), na ordem.
export const SECOES_ORDEM = ['senha', 'placa', 'rede', 'fabrica', 'camera', 'fila'];

// Passo a passo (direcao.md, secao 2.2): seis passos, o ultimo e o Conferir.
export const PASSOS = Object.freeze(['senha', 'placa', 'rede', 'camera', 'fila', 'conferir']);
// Etapa que cada passo grava na sessao (o servidor guarda a maior). A 3 era a
// rede e a 4 a faixa de fabrica no passo a passo antigo: Rede grava as duas.
export const ETAPA_DO_PASSO = Object.freeze({ placa: 2, rede: 4, camera: 5, fila: 6 });
// Etapa gravada pelo "Comecar" (POST /api/sessao/concluir).
export const ETAPA_CONCLUIDA = 7;
// Ultimo octeto que a fila aceita (o .255 e o broadcast da rede).
export const OCTETO_MAX_FILA = 254;
// Ultimo octeto do IP do PC na faixa de fabrica quando o campo fica vazio (o servidor usa o mesmo).
export const OCTETO_PC_FABRICA = 220;

// Sem sessao.json ainda: os campos ficam com o que o servidor considera fabrica.
export const SESSAO_PADRAO = {
  Mascara: '255.255.255.0', Gateway: '', Dns1: '8.8.8.8', Dns2: '8.8.4.4', IpPcCameras: '', IpFabrica: '192.168.1.108', IpPcFabrica: '',
  EmailRecuperacao: '',
  Encoder: {
    Principal: { Resolucao: '1920x1080', Fps: 20, BitRate: 1596, Codec: 'H.264' },
    Secundario: { Resolucao: '704x480', Fps: 12, BitRate: 512, Codec: 'H.264' },
  },
  Placa: null, Fila: null, Etapa: 0,
};

// Espaco que nao quebra entre numero e unidade ("20 fps", "1596 kbps").
export const NBSP = String.fromCharCode(160);

export const RE_IP = /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;
// "yyyy-MM-dd HH:mm[:ss]" do servidor (hora local da maquina).
export const RE_DATA_SERVIDOR = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?/;
export const RE_NAO_HEX = /[^0-9a-f]/g;
// E-mail com algo antes e depois do @ e um ponto no dominio (a camera nao confere mais que isso).
export const RE_EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
