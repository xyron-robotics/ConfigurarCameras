// Modulo profundo do painel (direcao.md, secao 7.2): do estado bruto do GET
// /api/estado, mais a sessao, as placas e o registro que o app.js carrega, ao
// modelo que as telas novas desenham (decisao N1). Funcao pura: nao busca, nao
// guarda e nao toca no DOM. As regras de placa, internet, simulacao, passo do
// passo a passo e conflito da fila com o registro moram so aqui; as telas leem o
// modelo. Cresce com o uso (decisao N2): a frente 4 trouxe a fila por posicao
// (estado, etapa, falha e camera de cada linha), as cameras sem posicao e o registro.
import { ETAPAS, PASSOS, ETAPA_DO_PASSO, SESSAO_PADRAO, FILA_MAX_ENDERECOS, OCTETO_MAX, OCTETO_MAX_FILA, RE_IP } from './constantes.js';
import { ipParaNumero, numeroParaIp, mac as formatarMac } from './formato.js';

// extras (do app.js): { sessao: dados do GET /api/sessao, placas: { dados, erro, lendo },
// registro: cameras do GET /api/registro, registroLeitura: { lendo, erro, simulado } }.
// Sem extras, o modelo sai sem essas partes.
export function derivar(bruto, extras) {
  const e = (bruto && bruto.estado) || {};
  const sessao = e.sessao || {};
  const x = extras || {};
  const carregado = !!e.fase;
  const senhaOk = !!(e.senhaDefinida || e.simular);
  const etapa = Number(sessao.etapa) || 0;
  const passoMax = passoMaximo(senhaOk, !!sessao.completa, etapa);
  const dadosSessao = x.sessao || null;
  const valores = (dadosSessao && dadosSessao.sessao) || JSON.parse(JSON.stringify(SESSAO_PADRAO));
  const instaladas = (x.registro || []).filter((c) => c.Status === 'Instalada').map((c) => c.Ip);
  const faixa = valores.Fila;
  const cams = listaCameras(e);
  const fila = derivarFila(e, cams);
  const vigia = derivarVigia(e, valores, x);
  const modelo = {
    carregado,
    simular: !!e.simular,
    // Etapa onde a simulacao forca a falha (texto do servidor); vazio fora da simulacao.
    falhaForcada: e.simular && e.falharEm ? e.falharEm : '',
    // Na simulacao a senha nao faz falta: as cameras sao de mentira.
    senhaOk,
    senhaDefinida: !!e.senhaDefinida,
    sessaoCompleta: !!sessao.completa,
    sessaoIniciada: !!sessao.iniciada,
    // Sobe a cada gravacao da sessao pelo worker: quem salvou espera por ela.
    geracao: Number(sessao.geracao) || 0,
    etapa,
    // O passo a passo fica na tela enquanto faltar senha, sessao completa ou o "comecar".
    inicio: carregado && (!senhaOk || !sessao.completa || !sessao.iniciada),
    // Passo mais adiante que a trilha deixa abrir, e onde o passo a passo abre.
    passoMax,
    passoSugerido: e.simular && !sessao.completa && etapa < 1 ? PASSOS[0] : passoMax,
    sessaoCarregada: !!dadosSessao,
    sessao: valores,
    catalogo: dadosSessao ? {
      resolucoes: dadosSessao.resolucoes || [],
      resolucoesSecundario: dadosSessao.resolucoesSecundario || [],
      codecs: dadosSessao.codecs || [],
      ...(dadosSessao.catalogo || {}),
    } : null,
    placas: derivarPlacas(x.placas),
    registroCarregado: Array.isArray(x.registro),
    instaladas,
    conflito: faixa ? conflitoDaFaixa(faixa.Inicio, faixa.Fim, instaladas) : null,
    fase: e.fase || '',
    // Comando na fila do servidor ainda nao virou "ocupado": ja conta como ocupado.
    ocupado: !!e.ocupado || !!(bruto && bruto.comandos > 0),
    versao: (bruto && bruto.versao) || '',
    pastaAlternativa: e.pastaDadosAlternativa ? (e.pastaDados || '') : '',
    placa: derivarPlaca(e),
    internet: derivarInternet(e),
    // Fila na memoria do servidor (null sem fila): a Sessao pergunta antes de troca-la;
    // o Painel desenha uma linha por posicao.
    fila,
    vigia,
    ...derivarSemPosicao(fila, cams),
    registro: derivarRegistro(x.registro, x.registroLeitura),
    // Ultimo aviso do servidor; n sobe a cada aviso novo (quem mandou o comando compara).
    aviso: { texto: e.aviso || '', n: Number(e.avisoN) || 0, origem: e.avisoOrigem || '' },
    // Ultima ferramenta (Sondar, Verificar, Procurar) como o servidor publica, e o
    // trabalho em curso dela (texto e { atual, total }): Ferramentas desenha.
    ferramenta: e.ferramenta || null,
    trabalho: e.trabalho || '',
    progresso: e.progresso && e.progresso.total ? e.progresso : null,
    atualizacao: derivarAtualizacao(bruto && bruto.atualizacao),
  };
  modelo.painel = estadoDoPainel(modelo);
  return modelo;
}

// Vigia (GET /api/estado: vigia e paralelo.dhip). qualquerFaixa: com o vigia
// ligado vale o que o servidor usa; desligado, a escolha da Sessao (extras),
// que vai junto no proximo Ligar. reserva: o broadcast nao respondeu e o vigia
// so olha o IP de fabrica, uma camera por vez (direcao 3.6 e 5.7). desde: quando
// o app.js viu o vigia ligar (o servidor nao publica a hora).
function derivarVigia(e, valores, x) {
  const v = e.vigia || {};
  const ligado = !!v.ligado;
  const escolha = typeof x.qualquerFaixa === 'boolean' ? x.qualquerFaixa : !!v.broadcast;
  return {
    ligado,
    motivo: v.motivo || '',
    porta: String(v.porta ?? '').trim(),
    canal: String(v.canal ?? '').trim(),
    broadcast: !!v.broadcast,
    qualquerFaixa: ligado ? !!v.broadcast : escolha,
    reserva: ligado && !!(e.paralelo && e.paralelo.dhip === 'sem-resposta'),
    ipFabrica: (valores && valores.IpFabrica) || '',
    desde: (ligado && x.vigiaDesde) || null,
  };
}

// Estado vazio do Painel (direcao 3.6), um so por vez; null quando ha camera
// para mostrar. Parada = nada em curso, em falha nem na espera do portao.
function estadoDoPainel(m) {
  const f = m.fila;
  if (!f) return 'semFila';
  if (f.concluida) return 'concluida';
  if (f.encerrada) return 'encerrada';
  const c = f.contagem;
  const parada = c.curso === 0 && c.falha === 0 && m.espera.length === 0;
  if (!parada) return null;
  if (!m.vigia.ligado) return 'vigiaDesligado';
  if (c.instalada === 0) return 'esperando';
  return null;
}

function listaCameras(e) {
  const c = e.cameras;
  return Array.isArray(c) ? c.filter(Boolean) : (c ? [c] : []);
}

function chaveMac(m) {
  return formatarMac(m);
}

// Camera de cameras[] como a tabela mostra (MAC formatado, porta e canal publicados).
function derivarCamera(c) {
  return {
    mac: formatarMac(c.mac),
    macBruto: String(c.mac || ''),
    serial: c.serial || '',
    modelo: c.modelo || '',
    ipOrigem: c.ipOrigem || '',
    fase: String(c.fase || ''),
    porta: String(c.porta ?? '').trim(),
    canal: String(c.canal ?? '').trim(),
    aviso: c.aviso || '',
  };
}

// Falha de uma camera (ou da retomada manual): "Tentar de novo" fica travado
// enquanto a senha recusada for a mesma da sessao (o servidor tambem recusa;
// repetir gastaria o lockout da camera).
function derivarFalha(f, senhaGeracao) {
  const x = f || {};
  return {
    etapa: x.etapa || '',
    erro: x.erro || '',
    recusa: !!x.recusa,
    loginRecusado: !!x.loginRecusado,
    bloqueada: !!x.bloqueada,
    bloqueiaTentar: !!x.loginRecusado && x.geracao === senhaGeracao,
  };
}

// Etapa em curso: a do motor (Write-Progresso vem antes do passo); conferindo
// sem etapa publicada e a conferencia. etapaN 0 = no portao, antes da primeira.
function etapaEmCurso(etapa, fase) {
  const nome = etapa || (fase === 'conferindo' ? ETAPAS[ETAPAS.length - 1] : '');
  return { etapa: nome, etapaN: ETAPAS.indexOf(nome) + 1 };
}

// Posicao que pode receber camera (CONTEXT.md, Posicao): as puladas na
// montagem (gateway, rede/broadcast, fora da rede, ja no registro) ficam de
// fora; as puladas depois, pelo operador ou porque o IP ja responde, eram
// lugar de camera e continuam numeradas. Mesma regra do "N de M" legado.
function posicaoUsavel(item) {
  return item.Estado !== 'pulada' || /operador|responde/.test(item.Motivo || '');
}

// Estado de cada posicao da fila (direcao 5.3), com a camera dela. A camera
// vem pelo indice (base 0 em fila.itens) ou pelo MAC gravado na posicao; sem
// camera, a retomada manual pelo IP (e.atual) explica a posicao em curso.
// numero: a ordem entre as posicoes usaveis, a mesma na fita e na tabela.
function derivarPosicao(item, idx, numero, cam, e, livre) {
  const fase = cam ? cam.fase : '';
  const manual = !cam && idx === e.atual;
  const base = { posicao: numero, ip: item.Ip || '', motivo: item.Motivo || '', etapa: '', etapaN: 0, falha: null };
  if (item.Estado === 'feita' || fase === 'feita') return { ...base, estado: 'instalada' };
  if (item.Estado === 'pulada' || fase === 'pulada') return { ...base, estado: 'pulada' };
  if (fase === 'decisao') return { ...base, estado: 'falha', falha: derivarFalha(cam.falha, e.senhaGeracao) };
  if (fase === 'portao' || fase === 'conferindo') return { ...base, estado: 'curso', ...etapaEmCurso(cam.etapa, fase) };
  if (manual && e.fase === 'decisao' && e.falha) return { ...base, estado: 'falha', falha: derivarFalha(e.falha, e.senhaGeracao) };
  if (manual && e.fase === 'configurando') return { ...base, estado: 'curso', ...etapaEmCurso(e.etapa, '') };
  if (livre) return { ...base, estado: 'proxima' };
  return { ...base, estado: 'aguardando' };
}

// Fila na memoria do servidor (null sem fila): posicoes com estado e camera,
// contagem por estado e a faixa. As cameras sem posicao ficam fora (espera e
// ignoradas, em derivarSemPosicao).
function derivarFila(e, cams) {
  const f = e.fila;
  const itens = (f && f.itens) || [];
  if (!itens.length) return null;
  const aberta = !['concluida', 'encerrada'].includes(e.fase) && !(e.paralelo && e.paralelo.admitindo === false);
  const porIndice = new Map(cams.filter((c) => c.indice >= 0).map((c) => [c.indice, c]));
  const porMac = new Map(cams.filter((c) => c.mac).map((c) => [chaveMac(c.mac), c]));
  let proximaDada = false;
  // O indice da camera e o e.atual apontam para fila.itens: o idx original
  // fica, so as usaveis viram posicao (sem linha, casa, contagem nem total).
  const usaveis = itens.map((item, idx) => ({ item, idx })).filter((x) => posicaoUsavel(x.item));
  const posicoes = usaveis.map(({ item, idx }, i) => {
    const c = porIndice.get(idx) || (item.Mac ? porMac.get(chaveMac(item.Mac)) : null) || null;
    // Proxima: a primeira pendente sem camera, com a fila aberta.
    const livre = aberta && !proximaDada && !c && item.Estado === 'pendente' && idx !== e.atual;
    if (livre) proximaDada = true;
    // Etapa e falha vem da camera crua; a tabela recebe a camera ja formatada.
    const camera = c ? derivarCamera(c) : null;
    return { ...derivarPosicao(item, idx, i + 1, c, e, livre), camera };
  });
  const contagem = { instalada: 0, falha: 0, curso: 0, proxima: 0, aguardando: 0, pulada: 0 };
  for (const p of posicoes) contagem[p.estado] += 1;
  return {
    total: posicoes.length,
    pendentes: itens.filter((i) => i.Estado === 'pendente').length,
    inicio: f.inicio || '',
    fim: f.fim || '',
    local: f.local || '',
    rack: f.rack || '',
    andar: f.andar || '',
    aberta,
    concluida: e.fase === 'concluida',
    encerrada: e.fase === 'encerrada',
    // Primeira posicao livre (a que o vigia ou o Configurar pega agora).
    proxima: proximaDe(posicoes),
    totalEtapas: ETAPAS.length,
    posicoes,
    // Bloco "Pede voce" (direcao 3.2): so a falha que espera decisao, a mais
    // grave primeiro (direcao, tabela de fontes: Genetec). O estado nao traz a
    // hora da falha; no empate vale a ordem da fila.
    pedeVoce: posicoes.filter((p) => p.estado === 'falha').sort((a, b) => gravidade(b.falha) - gravidade(a.falha)),
    contagem,
    // Posicoes que ficam sem camera se a fila for encerrada agora.
    semCamera: contagem.aguardando + contagem.proxima,
  };
}

// Senha recusada (repetir bloqueia o admin) antes de valor recusado, antes do resto.
function gravidade(f) {
  if (f.loginRecusado) return 2;
  return f.recusa ? 1 : 0;
}

function proximaDe(posicoes) {
  const p = posicoes.find((x) => x.estado === 'proxima');
  return p ? { posicao: p.posicao, ip: p.ip } : null;
}

// Cameras sem posicao na fila: na espera do portao e as ja inicializadas que o
// vigia nao toca (a tabela oferece "Retomar esta camera" pelo IP de agora).
function derivarSemPosicao(fila, cams) {
  const comPosicao = new Set(fila ? fila.posicoes.filter((p) => p.camera).map((p) => p.camera.mac) : []);
  const soltas = cams.map(derivarCamera).filter((c) => !comPosicao.has(c.mac));
  return {
    espera: soltas.filter((c) => !['ignorada', 'feita', 'pulada'].includes(c.fase)),
    ignoradas: soltas.filter((c) => c.fase === 'ignorada'),
  };
}

// Registro (GET /api/registro) ordenado por IP. lendo/erro vem do app.js: com
// erro, a tela mostra so o erro, nunca a lista velha.
function derivarRegistro(lista, leitura) {
  const l = leitura || {};
  return {
    lendo: !!l.lendo,
    erro: l.erro || '',
    simulado: !!l.simulado,
    lista: Array.isArray(lista) ? lista.slice().sort((a, b) => ipParaNumero(a.Ip) - ipParaNumero(b.Ip)) : null,
  };
}

// Procura automatica de versao nova (o servidor procura uma vez por dia).
function derivarAtualizacao(a) {
  const x = a || {};
  return { estado: x.estado || 'nenhuma', versao: x.versao || '', ultimaChecagem: x.ultimaChecagem || '' };
}

// Sessao completa: o Conferir (a senha que faltar entra na linha dele). Sem
// senha, so o passo da senha. Antes disso, o passo seguinte ao ultimo salvo.
function passoMaximo(senhaOk, completa, etapa) {
  if (completa) return 'conferir';
  if (!senhaOk) return 'senha';
  const salvos = Object.keys(ETAPA_DO_PASSO).filter((p) => etapa >= ETAPA_DO_PASSO[p]);
  const ultimo = salvos.length ? PASSOS.indexOf(salvos[salvos.length - 1]) : 0;
  return PASSOS[ultimo + 1];
}

function derivarPlacas(p) {
  const d = (p && p.dados) || null;
  return {
    lista: (d && d.placas) || [],
    sugerida: (d && d.sugerida) || null,
    erro: (p && p.erro) || '',
    lendo: !!(p && p.lendo),
    carregadas: !!d,
  };
}

// Quantas posicoes da faixa ja estao no registro como instaladas e a faixa
// seguinte do mesmo tamanho (so se couber na mesma rede /24, sem o .255).
// IP invalido, faixa invertida ou grande demais: null.
export function conflitoDaFaixa(inicio, fim, instaladas) {
  if (!RE_IP.test(String(inicio || '')) || !RE_IP.test(String(fim || ''))) return null;
  const a = ipParaNumero(inicio);
  const b = ipParaNumero(fim);
  const total = b - a + 1;
  if (total < 1 || total > FILA_MAX_ENDERECOS) return null;
  const ocupados = new Set((instaladas || []).map(ipParaNumero));
  let n = 0;
  for (let ip = a; ip <= b; ip += 1) if (ocupados.has(ip)) n += 1;
  const bloco = OCTETO_MAX + 1;
  const fim2 = b + total;
  const cabe = Math.floor(fim2 / bloco) === Math.floor(a / bloco) && fim2 % bloco <= OCTETO_MAX_FILA;
  return {
    total,
    instaladas: n,
    todas: n === total,
    seguinte: cabe ? { inicio: numeroParaIp(b + 1), fim: numeroParaIp(fim2) } : null,
  };
}

// Chip da placa (direcao 5.9): neutro na simulacao e sem sessao concluida;
// alarme so quando pede acao (sem as faixas, ausente, sem cabo); pronta so
// preparada pelo painel e com as faixas.
function derivarPlaca(e) {
  const r = e.rede || {};
  const placa = r.placa || {};
  const sessao = e.sessao || {};
  const base = {
    nome: placa.nome || '',
    ifIndex: placa.ifIndex || '',
    ips: r.ips || [],
    faltando: r.faltando || [],
    temporarios: (r.temporarios || []).map((x) => ({ ip: x.ip, camera: x.camera || '' })),
    rotas: (r.rotas || []).map((x) => x.destino),
    preparada: !!r.preparada,
    // Preparar so faz sentido fora da simulacao, com sessao e sem as faixas.
    podePreparar: !e.simular && !r.semSessao && !r.ok,
    podeRestaurar: !e.simular && !r.semSessao,
  };
  if (e.simular) return { ...base, nivel: 'neutro', motivo: 'simulacao' };
  if (r.semSessao || !sessao.completa || !sessao.iniciada) return { ...base, nivel: 'neutro', motivo: 'sem-sessao' };
  if (placa.presente === false) return { ...base, nivel: 'alarme', motivo: 'ausente' };
  if (placa.cabo === false) return { ...base, nivel: 'alarme', motivo: 'sem-cabo' };
  if (!r.ok) return { ...base, nivel: 'alarme', motivo: 'nao-preparada' };
  if (r.preparada) return { ...base, nivel: 'pronta', motivo: 'pronta' };
  return { ...base, nivel: 'neutro', motivo: 'com-faixas' };
}

// Chip da internet: alarme so quando caiu depois de o painel preparar a placa
// (culpa do painel, pede Restaurar o DHCP); "ja estava sem" e so informacao.
function derivarInternet(e) {
  const i = e.internet || {};
  const r = e.rede || {};
  const agora = i.agora || 'nao-testado';
  let motivo = agora === 'ok' ? 'ok' : 'nao-testado';
  if (agora === 'sem') {
    if (i.antes === 'ok' && r.preparada) motivo = 'caiu';
    else motivo = i.antes === 'sem' ? 'ja-sem' : 'sem';
  }
  return { nivel: motivo === 'caiu' ? 'alarme' : 'neutro', semResposta: agora === 'sem', motivo, quando: i.quando || '' };
}
