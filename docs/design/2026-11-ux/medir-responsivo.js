// medir-responsivo.js: mede o layout do painel na largura da janela atual.
// Prova da frente responsivo (docs/plans/2026-11-26-frente-responsivo-plan.md,
// Task 1); versao versionada do medir-pagina.js da auditoria de 26/11. Fica fora
// do www e do instalador.
//
// window.__medirResponsivo() devolve um objeto (JSON puro):
//   largura           clientWidth do documento
//   rota              location.hash
//   tema              data-tema do <html> (ou 'claro')
//   scrollHorizontal  null, ou { scrollWidth, clientWidth } quando a pagina rola na horizontal
//   cortados[]        texto com scrollWidth > clientWidth e sem text-overflow: ellipsis
//                     (tipo 'corta' se o overflow recorta, 'vaza' se o texto passa por cima),
//                     e campo (select/input) cujo texto passa da area util (tipo 'campo')
//   foraDaTela[]      elemento visivel fora da janela, sem ancestral que role ou recorte
//                     (so o mais externo de cada ramo)
//   rolagens[]        container que rola na horizontal por dentro (ex.: .tabela-rolagem)
//
// Como rodar pelo Playwright MCP. A CSP do painel barra script de fora da origem;
// por isso este arquivo entra por addInitScript, antes da pagina carregar.
//   1. Painel em simulacao, do worktree (Safety do plano):
//        powershell.exe -NoProfile -ExecutionPolicy Bypass -File fonte\web\Servidor-Painel.ps1
//          -Simular -SimularCameras 3 -SimularEscala 1 -Porta 8765 -SemNavegador -SemElevar
//          -SemAtualizacao -PastaDados <scratchpad>\painel-131
//      Com a pasta de dados vazia, toda rota cai em #/inicio/senha: a sessao tem de
//      chegar ao Conferir (passos feitos pela tela, ou um sessao.json ficticio).
//   2. Um runner em .playwright-mcp\ (ignorado; e a pasta que o MCP deixa ler), rodado
//      por browser_run_code_unsafe com filename: '.playwright-mcp/<runner>.js':
//        async (page) => {
//          const MEDIR = <o texto deste arquivo, como string JSON>;
//          await page.addInitScript(MEDIR);
//          ... para cada rota e largura: page.setViewportSize({ width, height: 900 }),
//              page.goto(rota), page.reload() (troca so de hash nao recarrega e o
//              script nao entra), espera, page.evaluate(() => window.__medirResponsivo())
//        }
//      addInitScript({ path }) nao serve: o processo do MCP nao chega ao arquivo.
//   3. Ordem: o passo a passo (#/inicio/<passo>) antes de Comecar no Conferir; depois
//      de Comecar ele vai para #/painel. Painel, Registro, Sessao e Ferramentas depois.
// Rotas: #/inicio/camera, #/painel, #/painel/registro, #/sessao/camera, #/ferramentas.
// Larguras da auditoria: 1920 1600 1440 1366 1280 1152 1024 900 800.
window.__medirResponsivo = () => {
  const de = document.documentElement;
  const vw = de.clientWidth;
  const TEXTO_MAX = 40;
  const CAMPOS = ['input', 'select', 'textarea'];
  const TIPOS_TEXTO = ['', 'text', 'email', 'search', 'tel', 'url', 'number', 'password'];
  const SEM_TEXTO = ['svg', 'img', 'progress', 'canvas', 'video'];
  const SETA_SELECT = 20;

  const desc = (el) => {
    let s = el.tagName.toLowerCase();
    if (el.classList.length) s += '.' + [...el.classList].slice(0, 3).join('.');
    const t = (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, TEXTO_MAX);
    return t ? s + ' "' + t + '"' : s;
  };
  const ignora = (el) => el.closest('.so-leitor, .ferramenta-campo .campo-rotulo, [hidden], .pular, svg');
  const visivel = (el) => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return false;
    const b = el.getBoundingClientRect();
    return b.width > 0 && b.height > 0;
  };
  const temTextoProprio = (el) => [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
  const contido = (el) => {
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
      const o = getComputedStyle(p).overflowX;
      if (o === 'auto' || o === 'scroll' || o === 'hidden' || o === 'clip') return true;
    }
    return false;
  };
  const fora = (el) => {
    const b = el.getBoundingClientRect();
    return b.right > vw + 1 || b.left < -1;
  };

  const res = {
    largura: vw,
    rota: location.hash,
    tema: de.getAttribute('data-tema') || 'claro',
    scrollHorizontal: de.scrollWidth > de.clientWidth ? { scrollWidth: de.scrollWidth, clientWidth: de.clientWidth } : null,
    cortados: [],
    foraDaTela: [],
    rolagens: [],
  };

  const cv = document.createElement('canvas').getContext('2d');
  for (const el of document.querySelectorAll('body *')) {
    if (ignora(el) || !visivel(el)) continue;
    const tag = el.tagName.toLowerCase();
    const cs = getComputedStyle(el);
    const b = el.getBoundingClientRect();

    if (CAMPOS.includes(tag)) {
      // Caixa, radio, botao e afins nao mostram o value como texto.
      if (tag === 'input' && !TIPOS_TEXTO.includes((el.getAttribute('type') || '').toLowerCase())) continue;
      cv.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily;
      const txt = tag === 'select' ? (el.selectedOptions[0] || {}).text || '' : el.value || el.placeholder || '';
      const util = el.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) - (tag === 'select' ? SETA_SELECT : 0);
      const largura = cv.measureText(txt).width;
      if (largura > util + 1) {
        res.cortados.push({ tipo: 'campo', el: tag + '[' + (el.name || el.id || '') + ']', texto: txt.slice(0, TEXTO_MAX),
          precisa: Math.round(largura), cabe: Math.round(util) });
      }
    } else if (!SEM_TEXTO.includes(tag) && el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1) {
      const ox = cs.overflowX;
      if (ox === 'auto' || ox === 'scroll') {
        res.rolagens.push({ el: desc(el), scrollWidth: el.scrollWidth, clientWidth: el.clientWidth });
      } else if (temTextoProprio(el) && cs.textOverflow !== 'ellipsis' && cs.display !== 'inline' && cs.display !== 'contents') {
        res.cortados.push({ tipo: ox === 'hidden' || ox === 'clip' ? 'corta' : 'vaza', el: desc(el),
          precisa: el.scrollWidth, cabe: el.clientWidth });
      }
    }

    if (fora(el) && !contido(el) && !(el.parentElement && fora(el.parentElement))) {
      res.foraDaTela.push({ el: desc(el), esquerda: Math.round(b.left), direita: Math.round(b.right) });
    }
  }
  return res;
};
