// GERADO por gerar-pacote.ps1 a partir dos modulos desta pasta. Nao edite: edite o modulo e gere de novo.
(function () {
  'use strict';
  const __m = {};

  // ---- dom.js
  __m['dom'] = (function () {
    // Criacao de no sem innerHTML com dado do servidor (direcao.md, secao 7.2).

    // h('button', { class: 'botao', onclick: fn, dados: { acao: 'x' } }, ['texto', outroNo])
    function h(tag, atributos, filhos) {
      const el = document.createElement(tag);
      aplicar(el, atributos || {});
      anexar(el, filhos);
      return el;
    }

    function aplicar(el, atributos) {
      for (const [nome, valor] of Object.entries(atributos)) {
        if (valor === undefined || valor === null || valor === false) continue;
        if (nome.startsWith('on') && typeof valor === 'function') {
          el.addEventListener(nome.slice(2), valor);
        } else if (nome === 'dados') {
          for (const [k, v] of Object.entries(valor)) el.dataset[k] = v;
        } else if (nome === 'class') {
          el.className = Array.isArray(valor) ? valor.filter(Boolean).join(' ') : valor;
        } else if (nome === 'value' || nome === 'checked' || nome === 'open') {
          el[nome] = valor;
        } else if (valor === true) {
          el.setAttribute(nome, '');
        } else {
          el.setAttribute(nome, String(valor));
        }
      }
    }

    function anexar(el, filhos) {
      if (filhos === undefined || filhos === null || filhos === false) return el;
      const lista = Array.isArray(filhos) ? filhos : [filhos];
      for (const f of lista) {
        if (f === undefined || f === null || f === false) continue;
        if (Array.isArray(f)) { anexar(el, f); continue; }
        el.append(f instanceof Node ? f : document.createTextNode(String(f)));
      }
      return el;
    }

    function trocar(el, filhos) {
      el.replaceChildren();
      return anexar(el, filhos);
    }

    function $(seletor, raiz) {
      return (raiz || document).querySelector(seletor);
    }

    function focar(el) {
      if (!el) return;
      if (!el.hasAttribute('tabindex') && !/^(A|BUTTON|INPUT|SELECT|TEXTAREA)$/.test(el.tagName)) {
        el.setAttribute('tabindex', '-1');
      }
      el.focus({ preventScroll: false });
    }

    let contadorId = 0;
    function novoId(prefixo) {
      contadorId += 1;
      return `${prefixo}-${contadorId}`;
    }

    return { h, anexar, trocar, $, focar, novoId };
  })();

  // ---- textos.js
  __m['textos'] = (function () {
    // Toda string de UI do painel (direcao.md, secoes 6 e 7.2). Caixa de frase, pt-BR, plural certo.
    // Chave ausente vira erro no console: o teste de console do prototipo pega texto esquecido.

    const regras = new Intl.PluralRules('pt-BR');
    const pl = (n, um, varios) => `${n} ${regras.select(n) === 'one' ? um : varios}`;

    const NOME_ETAPA = { inicializada: 'inicialização', encoder: 'encoder', rede: 'rede', conferida: 'conferência' };
    const NOME_SECAO = { senha: 'Senha', placa: 'Placa', rede: 'Rede', camera: 'Câmera', fila: 'Fila', painel: 'Painel', conferir: 'Conferir' };

    const TEXTOS = {
      'app.titulo': 'Configurar câmeras',
      'app.abrindo': 'Abrindo o painel…',
      'app.pular': 'Pular para o conteúdo',
      'app.encerrado.titulo': 'Painel encerrado.',
      'app.encerrado.texto': 'Pode fechar esta janela. A placa voltou ao DHCP.',
      'app.anuncio.falha': ({ n }) => `Câmera ${n} pede você.`,
      'marca.alt': 'Grupo SmartSeg',

      'nav.rotulo': 'Seções do painel',
      'nav.painel': 'Painel',
      'nav.sessao': 'Sessão',
      'nav.ferramentas': 'Ferramentas',
      'nav.encerrar': 'Encerrar o painel',
      'nav.irPedeVoce': 'Ir para o que pede você',

      'chip.placa': 'Placa',
      'chip.placaPronta': 'Placa pronta',
      'chip.placaSemCabo': 'Placa sem cabo',
      'chip.placaAusente': 'Placa ausente',
      'chip.placaNaoPreparada': 'Placa não preparada',
      'chip.internet': 'Internet',
      'chip.semInternet': 'Sem internet',
      'chip.simulacao': 'Simulação',
      'chip.detalhe': ({ nome }) => `Detalhe: ${nome}`,
      'popover.placa.titulo': 'Placa escolhida',
      'popover.placa.normal': ({ nome }) => `${nome}. Em simulação a placa não é tocada.`,
      'popover.placa.pronta': ({ nome }) => `${nome}, preparada com as faixas da sessão.`,
      'popover.placa.semCabo': ({ nome }) => `Ligue o cabo na ${nome}.`,
      'popover.placa.ausente': ({ nome }) => `A ${nome} não foi encontrada. Escolha outra placa em Sessão.`,
      'popover.placa.naoPreparada': ({ nome }) => `A ${nome} ainda não tem as faixas da sessão.`,
      'popover.placa.ips': 'Endereços nesta placa',
      'popover.placa.preparar': 'Preparar a placa',
      'popover.placa.restaurar': 'Restaurar o DHCP',
      'popover.internet.titulo': 'Internet',
      'popover.internet.ok': ({ quando }) => `Respondendo. Último teste às ${quando}.`,
      'popover.internet.sem': 'Sem resposta. Veja o Wi-Fi ou o cabo da rede da obra.',
      'popover.internet.naoTestado': 'Ainda não testada.',
      'popover.internet.testar': 'Testar a internet',
      'popover.simulacao.titulo': 'Simulação',
      'popover.simulacao.texto': 'Câmeras fictícias. Nenhuma câmera nem placa real é tocada.',
      'detalhe.tecnico': 'Detalhe técnico',
      'detalhe.ifIndex': ({ n }) => `ifIndex ${n}`,

      'faixa.perdida': 'O painel parou de responder. Veja se a janela do servidor ainda está aberta e recarregue.',
      'faixa.perdida.acao': 'Recarregar a página',
      'faixa.perdida.ultima': ({ hora }) => `Última resposta às ${hora}`,
      'faixa.reserva': 'O broadcast não respondeu: o vigia está no modo de reserva. Ligue uma câmera de fábrica por vez no switch. Para voltar ao modo normal, libere a porta UDP 37810 no firewall do Windows.',
      'faixa.atualizacao': ({ versao }) => `Versão ${versao} disponível.`,
      'faixa.atualizacao.acao': 'Atualizar o painel',

      'inicio.titulo': 'Configurar câmeras',
      'inicio.trilha': 'Passos',
      'inicio.feito': 'feito',
      'inicio.atual': 'atual',
      'inicio.voltar': 'Voltar',
      'inicio.avancar': 'Avançar',
      'inicio.comecar': 'Começar',
      'inicio.comecar.nota': 'Prepara a placa e abre o Painel.',
      'inicio.passo': ({ n, nome }) => `${n} ${nome}`,

      'secao.nome': ({ secao }) => NOME_SECAO[secao] || secao,
      'secao.alterar': ({ secao }) => `Alterar ${({ senha: 'a senha', placa: 'a placa', rede: 'a rede', camera: 'a câmera', fila: 'a fila' })[secao]}`,

      'senha.titulo': 'Senha',
      'senha.lead': 'A senha do admin que o painel grava em cada câmera de fábrica.',
      'senha.campo': 'Senha',
      'senha.repetir': 'Repita a senha',
      'senha.ajuda': 'No mínimo 8 caracteres, com letra e número.',
      'senha.salvar': 'Salvar a senha',
      'senha.salva': 'Senha salva.',
      'senha.trocar': 'Trocar a senha',
      'senha.simulacao': 'Senha não usada em simulação.',
      'senha.definida': 'Senha salva nesta sessão.',
      'senha.erro.curta': 'Use no mínimo 8 caracteres, com letra e número.',
      'senha.erro.diferente': 'As duas senhas não batem. Digite de novo.',

      'placa.titulo': 'Placa',
      'placa.lead': 'A placa de rede ligada ao switch das câmeras.',
      'placa.lista': 'Placas deste PC',
      'placa.sugerida': 'sugerida',
      'placa.semCabo': 'sem cabo',
      'placa.notaInternet': 'Esta placa leva o PC à internet; o painel vai pôr as faixas nela e devolver o DHCP ao encerrar.',
      'placa.ler': 'Ler as placas de novo',
      'placa.lendo': 'Lendo as placas…',

      'rede.titulo': 'Rede',
      'rede.lead': 'A rede definitiva das câmeras, onde elas ficam depois de instaladas.',
      'rede.mascara': 'Máscara',
      'rede.gateway': 'Gateway',
      'rede.dns': 'DNS',
      'rede.ipPc': 'IP do PC na rede das câmeras',
      'rede.fabrica': 'Faixa de fábrica',
      'rede.fabrica.resumo': ({ ipFabrica, ipPc }) => `IP de fábrica ${ipFabrica}, IP do PC ${ipPc}`,
      'rede.ipFabrica': 'IP de fábrica da câmera',
      'rede.ipPcFabrica': 'IP do PC na faixa de fábrica',
      'rede.broadcast': 'Aceitar câmera de fábrica de qualquer faixa',
      'rede.broadcast.risco': 'Ligado, o vigia aceita câmera fora do IP de fábrica. Use só se a câmera veio com outro IP: qualquer câmera ligada no switch pode ser reconfigurada.',
      'rede.exemplo': ({ v }) => `ex.: ${v}`,

      'camera.titulo': 'Câmera',
      'camera.lead': 'E-mail de recuperação e encoder dos dois streams. Vale para todas as câmeras da sessão.',
      'camera.email': 'E-mail de recuperação',
      'camera.email.ajuda': 'Único jeito de recuperar a senha do admin.',
      'camera.principal': 'Stream principal',
      'camera.secundario': 'Stream secundário',
      'camera.resolucao': 'Resolução',
      'camera.bitrate': 'Bitrate (kbps)',
      'camera.bitrate.recomendado': ({ v }) => `${v} (recomendado)`,
      'camera.bitrate.outro': 'Outro valor',
      'camera.bitrate.valor': 'Valor do bitrate (kbps)',
      'camera.fps': 'FPS',
      'camera.codec': 'Codec',
      'camera.porque': 'Por que isso importa',
      'camera.porque.texto': 'O stream principal é o que o NVR grava; o secundário é o da visualização remota. Bitrate alto demais enche o disco do NVR e a câmera pode recusar o valor. O recomendado cabe na câmera e no disco.',

      'fila.titulo': 'Fila',
      'fila.lead': 'A faixa de IPs que as próximas câmeras vão receber, em ordem.',
      'fila.inicio': 'Primeiro IP',
      'fila.fim': 'Último IP',
      'fila.local': 'Local',
      'fila.rack': 'Rack',
      'fila.andar': 'Andar',
      'fila.previa': ({ n }) => `${pl(n, 'posição', 'posições')} na faixa.`,
      'fila.previa.livre': 'Nenhuma no registro.',
      'fila.previa.registro': ({ n }) => `${pl(n, 'já está', 'já estão')} no registro.`,
      'fila.montar': 'Montar a fila',
      'fila.montarOutra': 'Montar outra fila',
      'fila.montada': ({ n, inicio, fim }) => `Fila montada: ${pl(n, 'posição', 'posições')}, de ${inicio} a ${fim}.`,
      'fila.usarSeguinte': ({ inicio, fim }) => `Usar a faixa seguinte: ${inicio} a ${fim}`,
      'fila.conflito.todas': ({ n, inicio, fim }) => `${n === 1 ? 'A posição' : `As ${n} posições`} de ${inicio} a ${fim} já ${n === 1 ? 'está' : 'estão'} no registro.`,
      'fila.conflito.parte': ({ n, total }) => `${n} das ${total} posições já ${n === 1 ? 'está' : 'estão'} no registro; ${n === 1 ? 'ela vai ser pulada' : 'elas vão ser puladas'}.`,
      'fila.erro.ip': 'Digite um IP no formato 192.0.2.10.',
      'fila.erro.ordem': 'O último IP precisa vir depois do primeiro.',

      'conferir.titulo': 'Conferir a sessão',
      'conferir.lead': 'Confira antes de começar. Cada linha abre a seção para alterar.',
      'conferir.rede': ({ gateway, ipPc, mascara }) => `Máscara ${mascara}, gateway ${gateway}, PC em ${ipPc}`,
      'conferir.camera': ({ codec, p, s, email }) => `${codec}, ${p}, ${s}${email ? `, e-mail ${email}` : ''}`,
      'conferir.stream': ({ resolucao, bitrate }) => `${resolucao} ${bitrate} kbps`,
      'conferir.fila': ({ inicio, fim, local, rack, andar }) => `${inicio} a ${fim}, ${local}, rack ${rack}, ${andar}º andar`,
      'conferir.placa': ({ nome }) => `${nome}, cabo ligado`,
      'conferir.vazio': 'Falta preencher.',

      'painel.titulo': 'Painel',
      'painel.fila.titulo': ({ local, rack, andar }) => `Fila ${local}, rack ${rack}, ${andar}º andar`,
      'painel.fila.faixa': ({ inicio, fim }) => `${inicio} a ${fim}`,
      'painel.vigia.ligado': 'Vigia ligado',
      'painel.vigia.desligado': 'Vigia desligado',
      'painel.vigia.ligar': 'Ligar o vigia',
      'painel.vigia.desligar': 'Desligar o vigia',
      'painel.vigia.explica': 'O vigia observa o switch e configura cada câmera de fábrica que aparecer.',
      'painel.fila.encerrar': 'Encerrar a fila',
      'painel.qualquerFaixa': 'Qualquer faixa',
      'painel.vazio.semFila': 'Nenhuma fila montada.',
      'painel.vazio.semFila.texto': 'Monte a fila com a faixa de IPs que as câmeras vão receber.',
      'painel.vazio.desligado': 'Ligue o vigia para configurar cada câmera de fábrica que aparecer no switch.',
      'painel.vazio.sequencial': 'Sem vigia: uma câmera por vez',
      'painel.vazio.esperando': 'Esperando câmeras de fábrica',
      'painel.vazio.esperando.texto': 'Observando 192.168.1.108. A primeira costuma levar cerca de 1 minuto depois de ligada.',
      'painel.concluida': ({ n }) => `Fila concluída: ${pl(n, 'instalada', 'instaladas')}.`,
      'painel.concluida.texto': 'O vigia foi desligado.',
      'painel.encerrada': ({ inst, sem }) => `Fila encerrada: ${pl(inst, 'instalada', 'instaladas')}, ${pl(sem, 'sem câmera', 'sem câmera')}.`,
      'painel.encerrada.texto': 'O vigia foi desligado.',
      'painel.abas': 'Visão da fila',
      'painel.aba.fila': 'Fila agora',
      'painel.aba.registro': 'Registro',

      'fita.resumo': ({ c }) => `Fila: ${pl(c.instalada, 'instalada', 'instaladas')}, ${pl(c.falha, 'pede você', 'pedem você')}, ${c.curso} em curso, ${pl(c.aguardando + c.proxima, 'aguardando', 'aguardando')}.`,
      'fita.instaladas': ({ n }) => pl(n, 'instalada', 'instaladas'),
      'fita.falha': ({ n }) => `${n} ${n === 1 ? 'pede' : 'pedem'} você`,
      'fita.curso': ({ n }) => `${n} em curso`,
      'fita.proxima': 'próxima',
      'fita.aguardando': ({ n }) => `${n} aguardando`,
      'fita.puladas': ({ n }) => pl(n, 'pulada', 'puladas'),
      'fita.casa': ({ n, ip }) => `Ir para a câmera ${n}, ${ip}`,

      'pede.titulo': ({ n }) => `Pede você (${n})`,
      'pede.falhou': ({ n, ip, etapa }) => `Câmera ${n} (${ip}) falhou ${etapa === 'encoder' ? 'no encoder' : `na ${NOME_ETAPA[etapa] || etapa}`}`,
      'pede.recusa': ({ valor }) => `A câmera recusou ${valor ? `o bitrate ${valor}` : 'um valor do encoder'}. Mude o bitrate do stream principal e tente de novo.`,
      'pede.senha': 'A câmera recusou a senha. Repetir a senha recusada bloqueia o admin.',
      'pede.senha.motivo': 'Repetir a senha recusada bloqueia o admin. Troque a senha em Sessão > Senha.',
      'pede.outro': 'Confira o cabo e a energia da câmera e tente de novo.',
      'pede.tentar': 'Tentar de novo',
      'pede.mudarEncoder': 'Mudar o encoder',
      'pede.pular': 'Pular esta posição',
      'pede.pular.titulo': ({ n }) => `Pular a câmera ${n}?`,
      'pede.pular.texto': ({ ip }) => `A posição ${ip} fica registrada como falha e a fila segue para a próxima.`,
      'pede.pular.confirmar': ({ n }) => `Pular a câmera ${n}`,
      'pede.tentando': 'Tentando de novo…',

      'tabela.pos': 'Pos.',
      'tabela.estado': 'Estado',
      'tabela.ip': 'IP de destino',
      'tabela.modelo': 'Modelo',
      'tabela.serial': 'Serial',
      'tabela.mac': 'MAC',
      'tabela.porta': 'Porta do switch',
      'tabela.canal': 'Canal no NVR',
      'tabela.status': 'Status',
      'tabela.data': 'Data',
      'tabela.local': 'Local',
      'tabela.espera': ({ n }) => `Na espera do portão (${n})`,
      'tabela.espera.explica': 'Câmera de fábrica vista no switch, esperando uma posição livre na fila.',

      'estado.instalada': 'Instalada',
      'estado.curso': ({ n, total, etapa }) => `${n} de ${total}: ${NOME_ETAPA[etapa] || etapa}`,
      'estado.falha': ({ etapa }) => `Falhou ${etapa === 'encoder' ? 'no encoder' : `na ${NOME_ETAPA[etapa] || etapa}`}`,
      'estado.proxima': 'Próxima',
      'estado.aguardando': 'Aguardando',
      'estado.pulada': 'Pulada',
      'estado.espera': 'Na espera',

      'registro.lendo': 'Lendo o registro…',
      'registro.erro': 'Não deu para ler o registro.',
      'registro.lerDeNovo': 'Ler o registro de novo',
      'registro.vazio': 'Nenhuma câmera instalada ainda.',
      'registro.exportar': 'Exportar o relatório',
      'registro.status.Instalada': 'Instalada',
      'registro.status.Falhou': 'Falhou',
      'registro.status.Em andamento': 'Em andamento',
      'registro.status.Resetada': 'Resetada',

      'lateral.encoder.titulo': ({ n }) => `Mudar o encoder da câmera ${n}`,
      'lateral.encoder.texto': 'O novo valor vale para a sessão inteira, não só para esta câmera.',
      'lateral.encoder.salvar': 'Salvar e tentar de novo',
      'lateral.fila.titulo': 'Montar outra fila',
      'lateral.fila.texto': 'A fila nova substitui a atual. As câmeras instaladas continuam no registro.',
      'lateral.cancelar': 'Cancelar',
      'lateral.fechar': 'Fechar',

      'dialogo.cancelar': 'Cancelar',
      'dialogo.encerrarFila.titulo': 'Encerrar a fila?',
      'dialogo.encerrarFila.texto': ({ sem }) => `O vigia para de aceitar câmeras. ${sem ? `${pl(sem, 'posição fica', 'posições ficam')} sem câmera.` : ''}`.trim(),
      'dialogo.encerrarFila.confirmar': 'Encerrar a fila',
      'dialogo.encerrarPainel.titulo': 'Encerrar o painel?',
      'dialogo.encerrarPainel.texto': 'O vigia para, a placa volta ao DHCP e o painel fecha. As câmeras instaladas continuam no registro.',
      'dialogo.encerrarPainel.confirmar': 'Encerrar o painel',
      'dialogo.trocarFila.titulo': 'Trocar a fila?',
      'dialogo.trocarFila.texto': 'Há câmeras em curso na fila atual. Elas terminam, mas as posições livres somem.',
      'dialogo.trocarFila.confirmar': 'Trocar a fila',
      'dialogo.restaurar.titulo': 'Restaurar o DHCP?',
      'dialogo.restaurar.texto': 'A placa perde as faixas da sessão e o vigia para de achar câmeras até preparar de novo.',
      'dialogo.restaurar.confirmar': 'Restaurar o DHCP',
      'dialogo.refazer.titulo': 'Refazer o passo a passo?',
      'dialogo.refazer.texto': 'Os valores da sessão ficam como sugestão em cada passo. A fila atual continua.',
      'dialogo.refazer.confirmar': 'Refazer o passo a passo',

      'sessao.titulo': 'Sessão',
      'sessao.lead': 'Os valores que valem para todas as câmeras desta obra.',
      'sessao.menu': 'Seções da sessão',
      'sessao.salvar': 'Salvar alterações',
      'sessao.salvando': 'Salvando…',
      'sessao.salvas': 'Alterações salvas.',
      'sessao.painel.titulo': 'Painel',
      'sessao.painel.lead': 'O que é do painel, não da obra.',
      'sessao.painel.tema': 'Tema',
      'sessao.painel.tema.sistema': 'Sistema',
      'sessao.painel.tema.claro': 'Claro',
      'sessao.painel.tema.escuro': 'Escuro',
      'sessao.painel.versao': ({ v }) => `Versão ${v}`,
      'sessao.painel.procurar': 'Procurar atualização',
      'sessao.painel.semAtualizacao': 'Esta é a versão mais nova.',
      'sessao.painel.refazer': 'Refazer o passo a passo',
      'sessao.painel.sobre': 'Sobre',
      'sessao.painel.sobre.texto': 'Painel de bancada do Grupo SmartSeg para levar câmeras Intelbras de fábrica a câmeras instaladas.',

      'ferr.titulo': 'Ferramentas',
      'ferr.lead': 'Para diagnóstico. Nenhuma delas altera câmera.',
      'ferr.sondar': 'Sondar um IP',
      'ferr.sondar.campo': 'IP para sondar',
      'ferr.sondar.acao': 'Sondar o IP',
      'ferr.sondar.texto': 'Ping, login e dados de uma câmera.',
      'ferr.verificar': 'Verificar o registro',
      'ferr.verificar.texto': 'Faz login em cada câmera instalada e confere IP e MAC.',
      'ferr.procurar': 'Procurar câmeras',
      'ferr.procurar.texto': 'Procura câmeras na rede pelo broadcast e por varredura.',
      'ferr.procurar.motivo': 'Só no uso real: em simulação não há câmera na rede.',
      'ferr.internet': 'Testar a internet',
      'ferr.internet.texto': 'Testa se o PC alcança a internet pela outra placa.',
      'ferr.resultado': 'Resultado',
      'ferr.resultado.vazio': 'Escolha uma ferramenta acima. O resultado aparece aqui.',
      'ferr.sondar.ok': ({ ip, modelo, serial, quando }) => `${ip} responde: ${modelo}, serial ${serial}, login aceito. Sondado às ${quando}.`,
      'ferr.verificar.ok': ({ n, quando }) => `${pl(n, 'câmera conferida', 'câmeras conferidas')}, todas com IP e MAC certos. Verificado às ${quando}.`,
      'ferr.internet.ok': ({ quando }) => `Internet respondendo. Testado às ${quando}.`,
      'ferr.log': 'Log do painel',
      'ferr.log.filtro': 'Só avisos e erros',

      'erro.desconhecido': 'O painel recusou a ação.',
      'erro.semResposta': 'O painel não respondeu. Tente de novo.',
      'erro.campo.obrigatorio': 'Preencha este campo.',
    };

    // Mensagens conhecidas do servidor (sem acento) viram frase do painel; o resto vai para o detalhe.
    const SERVIDOR = [
      [/^Monte a fila antes de ligar o vigia/i, 'Monte a fila antes de ligar o vigia.'],
      [/^Procurar cameras so funciona no uso real/i, 'Só no uso real: em simulação não há câmera na rede.'],
      [/^Aguarde: o painel/i, 'Aguarde: o painel está terminando a operação atual.'],
      [/^Camera nao esta em decisao/i, 'Esta câmera já saiu da decisão.'],
    ];

    function t(chave, dados) {
      const v = TEXTOS[chave];
      if (v === undefined) {
        console.error(`texto ausente: ${chave}`);
        return chave;
      }
      return typeof v === 'function' ? v(dados || {}) : v;
    }

    function traduzirServidor(mensagem) {
      const m = String(mensagem || '');
      for (const [padrao, frase] of SERVIDOR) if (padrao.test(m)) return frase;
      return t('erro.desconhecido');
    }

    function nomeEtapa(etapa) {
      return NOME_ETAPA[etapa] || etapa;
    }

    function valorRecusado(erroCru) {
      const m = /Bitrate\w*=(\d+)/.exec(String(erroCru || ''));
      return m ? m[1] : '';
    }

    return { t, traduzirServidor, nomeEtapa, valorRecusado };
  })();

  // ---- constantes.js
  __m['constantes'] = (function () {
    // Numeros com sentido do painel (direcao.md, secao 7.2). Fora daqui, nenhum literal maior que 2.

    const ETAPAS = ['inicializada', 'encoder', 'rede', 'conferida'];
    const TOTAL_ETAPAS = 4;

    const CONSULTA_MS = 1000;
    const FALHAS_ATE_PERDER_CONEXAO = 3;
    const TRAVA_DECISAO_MS = 1500;

    const HTTP = {
      OK: 200,
      ACEITO: 202,
      REQUISICAO_INVALIDA: 400,
      CONFLITO: 409,
      ERRO_SERVIDOR: 500,
    };

    // Fita: ate este numero de casas, numero embaixo de cada uma; acima, a cada FITA_PASSO_NUMERO.
    const FITA_MAX_NUMEROS = 24;
    const FITA_PASSO_NUMERO = 5;

    const OCTETOS_IP = 4;
    const OCTETO_MAX = 255;

    const SECOES = ['senha', 'placa', 'rede', 'camera', 'fila'];
    const PASSOS = ['senha', 'placa', 'rede', 'camera', 'fila', 'conferir'];
    const SECOES_SESSAO = ['senha', 'placa', 'rede', 'camera', 'fila', 'painel'];

    const TEMAS = ['sistema', 'claro', 'escuro'];


    const SENHA_MIN = 8;

    return { ETAPAS, TOTAL_ETAPAS, CONSULTA_MS, FALHAS_ATE_PERDER_CONEXAO, TRAVA_DECISAO_MS, HTTP, FITA_MAX_NUMEROS, FITA_PASSO_NUMERO, OCTETOS_IP, OCTETO_MAX, SECOES, PASSOS, SECOES_SESSAO, TEMAS, SENHA_MIN };
  })();

  // ---- formato.js
  __m['formato'] = (function () {
    const { OCTETOS_IP, OCTETO_MAX } = __m['constantes'];
    // Formatacao de dado de maquina (direcao.md, secao 7.2).

    const LOCALE = 'pt-BR';
    const numero = new Intl.NumberFormat(LOCALE);
    const relogio = new Intl.DateTimeFormat(LOCALE, { hour: '2-digit', minute: '2-digit', second: '2-digit' });

    function ip(texto) {
      return String(texto || '').trim();
    }

    function ipParaNumero(texto) {
      const partes = ip(texto).split('.').map(Number);
      if (partes.length !== OCTETOS_IP || partes.some((p) => !Number.isInteger(p) || p < 0 || p > OCTETO_MAX)) return null;
      return partes.reduce((acc, p) => acc * (OCTETO_MAX + 1) + p, 0);
    }

    function numeroParaIp(n) {
      const partes = [];
      let resto = n;
      for (let i = 0; i < OCTETOS_IP; i += 1) {
        partes.unshift(resto % (OCTETO_MAX + 1));
        resto = Math.floor(resto / (OCTETO_MAX + 1));
      }
      return partes.join('.');
    }

    function mac(texto) {
      const limpo = String(texto || '').replace(/[^0-9a-f]/gi, '').toUpperCase();
      return limpo.match(/.{1,2}/g)?.join(':') || '';
    }

    function hora(data) {
      return relogio.format(data instanceof Date ? data : new Date(data));
    }

    function inteiro(n) {
      return numero.format(n);
    }

    return { ip, ipParaNumero, numeroParaIp, mac, hora, inteiro };
  })();

  // ---- api.js
  __m['api'] = (function () {
    const { HTTP } = __m['constantes'];
    // Costura com o servidor (direcao.md, secao 7.2). Unico modulo que fala com o transporte.
    // Dois adaptadores: transporteFetch (produto) e criarTransporteFalso (prototipo, api-falsa.js).

    // Erro normalizado: { ok: false, codigo, mensagem, detalhe, semResposta }.
    function criarApi(transporte) {
      async function chamar(metodo, caminho, corpo) {
        try {
          const r = await transporte(metodo, caminho, corpo);
          if (r.status >= HTTP.OK && r.status < HTTP.REQUISICAO_INVALIDA) return { ok: true, dados: r.corpo };
          return { ok: false, codigo: r.status, mensagem: (r.corpo && r.corpo.erro) || '', detalhe: r.corpo, semResposta: false };
        } catch (e) {
          return { ok: false, codigo: 0, mensagem: '', detalhe: String(e && e.message ? e.message : e), semResposta: true };
        }
      }
      return {
        estado: () => chamar('GET', '/api/estado'),
        registro: () => chamar('GET', '/api/registro'),
        sessao: () => chamar('GET', '/api/sessao'),
        placas: () => chamar('GET', '/api/placas'),
        salvarSessao: (parcial) => chamar('PUT', '/api/sessao', parcial),
        tema: (tema) => chamar('PUT', '/api/tema', { tema }),
        comando: (rota, corpo) => chamar('POST', rota, corpo || {}),
      };
    }

    // Adaptador do produto. O prototipo nunca o chama (abre por file://, sem servidor).
    function transporteFetch() {
      return async (metodo, caminho, corpo) => {
        const opcoes = { method: metodo };
        if (corpo !== undefined) {
          opcoes.headers = { 'content-type': 'application/json' };
          opcoes.body = JSON.stringify(corpo);
        }
        const r = await fetch(caminho, opcoes);
        const texto = await r.text();
        return { status: r.status, corpo: texto ? JSON.parse(texto) : null };
      };
    }

    return { criarApi, transporteFetch };
  })();

  // ---- estado.js
  __m['estado'] = (function () {
    const { ETAPAS, TOTAL_ETAPAS, FALHAS_ATE_PERDER_CONEXAO } = __m['constantes'];
    const { ipParaNumero, numeroParaIp, mac: formatarMac } = __m['formato'];
    // Modulo profundo do painel (direcao.md, secao 7.2): do estado bruto do servidor ao modelo que as
    // telas desenham. Funcao pura: contagens, posicao da falha, etapa real, placa, vigia, reserva,
    // conexao perdida e conflito da fila com o registro. Telas nao leem o estado bruto.

    const EM_CURSO = ['portao', 'conferindo'];

    function derivar(bruto, extras) {
      const x = extras || {};
      const e = (bruto && bruto.estado) || {};
      const sessaoServidor = e.sessao || {};
      const sessaoValores = (x.sessao && x.sessao.sessao) || {};
      const conexao = x.conexao || { falhas: 0, ultima: null };

      const modelo = {
        conexaoPerdida: conexao.falhas >= FALHAS_ATE_PERDER_CONEXAO,
        ultimaResposta: conexao.ultima,
        simular: !!e.simular,
        senhaDefinida: !!e.senhaDefinida,
        sessaoExiste: !!sessaoServidor.existe,
        sessaoCompleta: !!sessaoServidor.completa,
        sessao: sessaoValores,
        catalogo: (x.sessao && x.sessao.catalogo) || null,
        placas: x.placas || null,
        versao: (bruto && bruto.versao) || '',
        atualizacao: (bruto && bruto.atualizacao) || { estado: 'nenhuma' },
        fase: e.fase || 'ocioso',
        ultimo: e.ultimo || '',
        log: (bruto && bruto.log) || [],
        ferramenta: e.ferramenta || null,
        placa: derivarPlaca(e),
        internet: derivarInternet(e),
        vigia: derivarVigia(e),
        fila: null,
        espera: [],
        pedeVoce: [],
        registro: x.registro || null,
        registroErro: !!x.registroErro,
        conflito: null,
      };

      const cameras = Array.isArray(e.cameras) ? e.cameras : [];
      modelo.espera = cameras.filter((c) => c.fase === 'espera' || (c.posicao === 0 && c.fase !== 'ignorada'))
        .map((c) => ({ mac: formatarMac(c.mac), serial: c.serial, modelo: c.modelo }));

      if (e.fila && Array.isArray(e.fila.itens)) modelo.fila = derivarFila(e, cameras);
      if (modelo.fila) {
        modelo.pedeVoce = modelo.fila.posicoes.filter((p) => p.estado === 'falha').map((p) => ({
          posicao: p.posicao, ip: p.ip, mac: p.camera.mac, etapa: p.falha.etapa,
          tipo: p.falha.tipo, erroCru: p.falha.erro, bloqueiaTentar: p.falha.bloqueiaTentar,
        }));
      }
      modelo.conflito = derivarConflito(sessaoValores.Fila, x.registro);
      return modelo;
    }

    function derivarPlaca(e) {
      const r = e.rede || {};
      const placa = r.placa || {};
      const base = { nome: placa.nome || '', ips: r.ips || [], ifIndex: placa.ifIndex, preparada: !!r.preparada };
      if (e.simular || !(e.sessao && e.sessao.completa)) return { ...base, nivel: 'neutro', motivo: 'normal' };
      if (placa.presente === false) return { ...base, nivel: 'alarme', motivo: 'ausente' };
      if (placa.cabo === false) return { ...base, nivel: 'alarme', motivo: 'sem-cabo' };
      if (!r.ok || !r.preparada) return { ...base, nivel: 'alarme', motivo: 'nao-preparada' };
      return { ...base, nivel: 'pronta', motivo: 'pronta' };
    }

    function derivarInternet(e) {
      const i = e.internet || {};
      return { nivel: i.agora === 'sem' ? 'alarme' : 'neutro', agora: i.agora || 'nao-testado', quando: i.quando || '' };
    }

    function derivarVigia(e) {
      const v = e.vigia || {};
      const p = e.paralelo || {};
      return { ligado: !!v.ligado, reserva: !!v.ligado && p.dhip === 'sem-resposta', broadcast: !!v.broadcast, motivo: v.motivo || '' };
    }

    function tipoFalha(f) {
      if (f.loginRecusado || f.bloqueada) return 'senha';
      if (f.recusa) return 'recusa';
      return 'outro';
    }

    function derivarFila(e, cameras) {
      const f = e.fila;
      const porMac = new Map(cameras.map((c) => [c.mac, c]));
      const admitindo = !e.paralelo || e.paralelo.admitindo !== false;
      let proximaMarcada = false;

      const posicoes = f.itens.map((item) => {
        const cam = item.Mac ? porMac.get(item.Mac) : cameras.find((c) => c.indice === item.Posicao - 1);
        const p = { posicao: item.Posicao, ip: item.Ip, estado: 'aguardando', fase: '', etapa: '', etapaN: 0, camera: null, falha: null, motivo: item.Motivo || '' };
        if (cam) p.camera = { mac: formatarMac(cam.mac), macBruto: cam.mac, serial: cam.serial, modelo: cam.modelo, porta: cam.porta, canal: cam.canal };
        if (item.Estado === 'feita') {
          p.estado = 'instalada';
        } else if (item.Estado === 'pulada') {
          p.estado = 'pulada';
        } else if (item.Estado === 'reservada' && cam) {
          if (cam.fase === 'decisao' && cam.falha) {
            p.estado = 'falha';
            p.falha = { etapa: cam.falha.etapa || cam.etapa, erro: cam.falha.erro || '', tipo: tipoFalha(cam.falha), bloqueiaTentar: !!(cam.falha.loginRecusado || cam.falha.bloqueada) };
          } else if (EM_CURSO.includes(cam.fase)) {
            p.estado = 'curso';
            p.fase = cam.fase;
            p.etapa = cam.etapa;
            p.etapaN = cam.progresso && cam.progresso.atual ? cam.progresso.atual : ETAPAS.indexOf(cam.etapa) + 1;
          }
        } else if (item.Estado === 'pendente' && admitindo && !proximaMarcada) {
          p.estado = 'proxima';
          proximaMarcada = true;
        }
        return p;
      });

      const contagem = { instalada: 0, falha: 0, curso: 0, proxima: 0, aguardando: 0, pulada: 0 };
      for (const p of posicoes) contagem[p.estado] += 1;

      return {
        local: f.local || '', rack: f.rack || '', andar: f.andar || '', inicio: f.inicio, fim: f.fim,
        total: posicoes.length, totalEtapas: TOTAL_ETAPAS, posicoes, contagem,
        concluida: e.fase === 'concluida',
        encerrada: e.fase === 'encerrada' || !admitindo,
        semCamera: contagem.aguardando + contagem.proxima,
      };
    }

    function derivarConflito(filaSessao, registro) {
      if (!filaSessao || !filaSessao.inicio || !filaSessao.fim || !Array.isArray(registro)) return null;
      const a = ipParaNumero(filaSessao.inicio);
      const b = ipParaNumero(filaSessao.fim);
      if (a === null || b === null || b < a) return null;
      const instaladosIp = new Set(registro.filter((r) => r.Status === 'Instalada').map((r) => r.Ip));
      let instaladas = 0;
      for (let n = a; n <= b; n += 1) if (instaladosIp.has(numeroParaIp(n))) instaladas += 1;
      const total = b - a + 1;
      if (instaladas === 0) return { instaladas, total, todas: false, seguinte: null };
      return { instaladas, total, todas: instaladas === total, seguinte: { inicio: numeroParaIp(b + 1), fim: numeroParaIp(b + total) } };
    }

    return { derivar };
  })();

  // ---- rotas.js
  __m['rotas'] = (function () {
    // Rotas por hash (direcao.md, secao 7.2): #/inicio/<passo>, #/conferir, #/painel,
    // #/painel/registro, #/sessao/<secao>, #/ferramentas. Sem servidor: funciona em file://.

    function lerRota() {
      const partes = (location.hash || '').replace(/^#\/?/, '').split('/').filter(Boolean);
      return { tela: partes[0] || '', parte: partes[1] || '' };
    }

    function ir(rota) {
      if (location.hash === rota) window.dispatchEvent(new HashChangeEvent('hashchange'));
      else location.hash = rota;
    }

    function aoMudarRota(funcao) {
      window.addEventListener('hashchange', () => funcao(lerRota()));
    }

    return { lerRota, ir, aoMudarRota };
  })();

  // ---- icones.js
  __m['icones'] = (function () {
    // Icones (direcao.md, secao 4.5). Caminhos do Lucide, https://lucide.dev
    // Lucide: ISC License. Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022
    // as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022.

    const NS = 'http://www.w3.org/2000/svg';

    const CAMINHOS = {
      concluido: '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
      falha: '<circle cx="12" cy="12" r="10"/><path d="m15 9-6 6"/><path d="m9 9 6 6"/>',
      atencao: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
      informacao: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
      espera: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
      agora: '<circle cx="12" cy="12" r="5" class="icone-cheio"/>',
      placa: '<path d="m15 20 3-3h2a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h2l3 3z"/><path d="M6 8v1"/><path d="M10 8v1"/><path d="M14 8v1"/><path d="M18 8v1"/>',
      internet: '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
      simulacao: '<path d="M14 2v6a2 2 0 0 0 .245.96l5.51 10.08A2 2 0 0 1 18 22H6a2 2 0 0 1-1.755-2.96l5.51-10.08A2 2 0 0 0 10 8V2"/><path d="M6.453 15h11.094"/><path d="M8.5 2h7"/>',
      fechar: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
      abrir: '<path d="m6 9 6 6 6-6"/>',
      pulada: '<path d="M5 12h14"/>',
      mais: '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
    };

    // Icone decorativo: o significado vem sempre da palavra ao lado (aria-hidden).
    function icone(nome, tamanho) {
      const svg = document.createElementNS(NS, 'svg');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.setAttribute('aria-hidden', 'true');
      svg.setAttribute('focusable', 'false');
      svg.setAttribute('class', `icone icone-${tamanho || 'p'} icone-${nome}`);
      svg.innerHTML = CAMINHOS[nome] || '';
      return svg;
    }

    return { icone };
  })();

  // ---- componentes.js
  __m['componentes'] = (function () {
    const { h, novoId, focar } = __m['dom'];
    const { icone } = __m['icones'];
    const { t } = __m['textos'];
    // Componentes da direcao.md, secao 5. So tokens semanticos no CSS; aqui so estrutura e estado.

    // tipo: 'primario' | 'secundario' | 'discreto' | 'perigo'
    function botao(rotulo, aoClicar, opcoes) {
      const o = opcoes || {};
      return h('button', {
        type: o.submit ? 'submit' : 'button',
        class: ['botao', `botao-${o.tipo || 'secundario'}`, o.classe],
        onclick: aoClicar || undefined,
        disabled: !!o.desabilitado,
        'aria-describedby': o.motivoId,
        dados: o.dados,
        popovertarget: o.popover,
      }, [o.icone ? icone(o.icone) : null, h('span', { class: 'botao-rotulo' }, rotulo)]);
    }

    // Ocupado: mesmo verbo, aria-busy. Devolve a funcao que restaura.
    function ocupar(btn, rotuloOcupado) {
      const rotulo = btn.querySelector('.botao-rotulo');
      const antes = rotulo.textContent;
      btn.setAttribute('aria-busy', 'true');
      btn.disabled = true;
      rotulo.textContent = rotuloOcupado;
      return () => { btn.removeAttribute('aria-busy'); btn.disabled = false; rotulo.textContent = antes; };
    }

    // nivel: 'neutro' | 'pronta' | 'alarme' | 'atencao' | 'agora'
    function chip(rotulo, nivel, nomeIcone) {
      return h('span', { class: ['chip', `chip-${nivel || 'neutro'}`] }, [nomeIcone ? icone(nomeIcone) : null, h('span', null, rotulo)]);
    }

    // Aviso junto do controle que o gerou. tipo: 'sucesso' | 'erro' | 'atencao' | 'info'
    function aviso(tipo, texto, detalheCru) {
      const nomeIcone = { sucesso: 'concluido', erro: 'falha', atencao: 'atencao', info: 'informacao' }[tipo];
      return h('div', { class: ['aviso', `aviso-${tipo}`], role: tipo === 'erro' ? 'alert' : 'status' }, [
        icone(nomeIcone),
        h('div', { class: 'aviso-corpo' }, [
          h('p', null, texto),
          detalheCru ? detalhe(detalheCru) : null,
        ]),
      ]);
    }

    function detalhe(cru) {
      return h('details', { class: 'detalhe' }, [
        h('summary', null, t('detalhe.tecnico')),
        h('pre', { class: 'mono detalhe-cru' }, cru),
      ]);
    }

    // Lugar fixo para o aviso de uma acao: troca o conteudo, nunca some sozinho.
    function lugarAviso() {
      const el = h('div', { class: 'lugar-aviso', 'aria-live': 'polite' });
      return {
        el,
        mostrar(tipo, texto, cru) { el.replaceChildren(aviso(tipo, texto, cru)); },
        limpar() { el.replaceChildren(); },
      };
    }

    // Campo com rotulo visivel acima, ajuda embaixo e erro com o conserto (secao 5.2).
    function campo(o) {
      const id = o.id || novoId('campo');
      const ajudaId = `${id}-ajuda`;
      const erroId = `${id}-erro`;
      const atributos = {
        id, name: o.nome || id, type: o.tipo || 'text', value: o.valor === undefined ? '' : String(o.valor),
        class: ['campo-entrada', o.mono ? 'mono' : null, o.curto ? 'campo-curto' : null],
        autocomplete: o.autocomplete || 'off', inputmode: o.inputmode, placeholder: o.exemplo ? t('rede.exemplo', { v: o.exemplo }) : undefined,
        'aria-describedby': o.ajuda ? ajudaId : undefined, spellcheck: o.mono ? 'false' : undefined,
      };
      const entrada = o.opcoes ? selecao(atributos, o.opcoes, o.valor) : h('input', atributos);
      const erro = h('p', { class: 'campo-erro', id: erroId, hidden: true });
      const el = h('div', { class: ['campo', o.classe] }, [
        h('label', { class: 'campo-rotulo', for: id }, o.rotulo),
        entrada,
        o.ajuda ? h('p', { class: 'campo-ajuda', id: ajudaId }, o.ajuda) : null,
        erro,
      ]);
      return {
        el, entrada,
        valor: () => entrada.value.trim(),
        mostrarErro(texto) {
          erro.replaceChildren(icone('falha'), h('span', null, texto));
          erro.hidden = false;
          entrada.setAttribute('aria-invalid', 'true');
          entrada.setAttribute('aria-describedby', [o.ajuda ? ajudaId : null, erroId].filter(Boolean).join(' '));
        },
        limparErro() {
          erro.hidden = true;
          entrada.removeAttribute('aria-invalid');
          if (o.ajuda) entrada.setAttribute('aria-describedby', ajudaId); else entrada.removeAttribute('aria-describedby');
        },
      };
    }

    function selecao(atributos, opcoes, valor) {
      const { type, value, placeholder, inputmode, spellcheck, autocomplete, ...resto } = atributos;
      return h('select', resto, opcoes.map((op) => h('option', { value: String(op.valor), selected: String(op.valor) === String(valor) }, op.rotulo)));
    }

    // Dialogo de confirmacao (secao 5.8): <dialog> nativo, titulo com o verbo do botao, foco em Cancelar.
    let dialogoAtual = null;
    function confirmar(o) {
      return new Promise((resolver) => {
        if (dialogoAtual) dialogoAtual.remove();
        const tituloId = novoId('dialogo-titulo');
        const cancelar = botao(t('dialogo.cancelar'), () => fechar(false), { tipo: 'secundario' });
        const ok = botao(o.confirmar, () => fechar(true), { tipo: o.perigo ? 'perigo' : 'primario' });
        const d = h('dialog', { class: 'dialogo', 'aria-labelledby': tituloId }, [
          h('h2', { id: tituloId, class: 'dialogo-titulo' }, o.titulo),
          h('p', { class: 'dialogo-texto' }, o.texto),
          h('div', { class: 'dialogo-acoes' }, [cancelar, ok]),
        ]);
        function fechar(v) { d.close(); d.remove(); dialogoAtual = null; resolver(v); }
        d.addEventListener('cancel', (ev) => { ev.preventDefault(); fechar(false); });
        document.body.append(d);
        dialogoAtual = d;
        d.showModal();
        focar(o.perigo ? cancelar : ok);
      });
    }

    // Painel lateral (secao 3.3): <dialog> modal a direita, conteudo atras inerte. Esc fecha.
    function lateral(o) {
      const tituloId = novoId('lateral-titulo');
      const d = h('dialog', { class: 'lateral', 'aria-labelledby': tituloId });
      const fecharBtn = h('button', { type: 'button', class: 'botao botao-icone', 'aria-label': t('lateral.fechar'), onclick: () => fechar() }, icone('fechar', 'm'));
      function fechar() { d.close(); d.remove(); if (o.aoFechar) o.aoFechar(); }
      d.append(
        h('div', { class: 'lateral-cabeca' }, [h('h2', { id: tituloId }, o.titulo), fecharBtn]),
        o.texto ? h('p', { class: 'lateral-texto' }, o.texto) : null,
        h('div', { class: 'lateral-corpo' }, o.conteudo(fechar)),
      );
      d.addEventListener('cancel', (ev) => { ev.preventDefault(); fechar(); });
      document.body.append(d);
      d.showModal();
      return { fechar };
    }

    // Faixa do painel inteiro (secao 5.7). tipo: 'alarme' | 'atencao' | 'info'
    function faixa(tipo, texto, acao, extra) {
      const nomeIcone = { alarme: 'falha', atencao: 'atencao', info: 'informacao' }[tipo];
      return h('div', { class: ['faixa', `faixa-${tipo}`], role: tipo === 'alarme' ? 'alert' : 'status' }, [
        h('div', { class: 'faixa-conteudo' }, [
          icone(nomeIcone, 'm'),
          h('p', { class: 'faixa-texto' }, texto),
          acao || null,
          extra ? h('span', { class: 'faixa-extra apoio' }, extra) : null,
        ]),
      ]);
    }

    // Estado da posicao: sempre icone mais palavra (secao 5.3).
    function selo(estado, texto) {
      const nomeIcone = { instalada: 'concluido', curso: 'agora', falha: 'falha', proxima: 'abrir', aguardando: null, pulada: 'pulada', espera: 'espera' }[estado];
      return h('span', { class: ['selo', `selo-${estado}`] }, [nomeIcone ? icone(nomeIcone) : null, h('span', null, texto)]);
    }

    function barraEtapas(n, total) {
      const el = h('span', { class: 'barra-etapas', 'aria-hidden': 'true' });
      for (let i = 1; i <= total; i += 1) el.append(h('span', { class: ['barra-etapa', i < n ? 'barra-etapa-feita' : null, i === n ? 'barra-etapa-atual' : null] }));
      return el;
    }

    return { botao, ocupar, chip, aviso, detalhe, lugarAviso, campo, confirmar, lateral, faixa, selo, barraEtapas };
  })();

  // ---- marca.js
  __m['marca'] = (function () {
    const { h } = __m['dom'];
    const { t } = __m['textos'];
    // Marca Grupo SmartSeg (direcao.md, secao 4.6). Logo inteira nas telas de abertura, passo a passo,
    // Conferir, Encerrado e Sessao > Painel > Sobre; simbolo no topo. No escuro a logo oficial vai
    // sobre a placa clara (--logo-placa): logo-escuro.png espera o aceite da SmartSeg.

    function logo() {
      return h('img', { class: 'logo', src: 'logo.png', alt: t('marca.alt'), width: '336', height: '172' });
    }

    function simbolo() {
      return h('img', { class: 'simbolo', src: 'simbolo.png', alt: '', width: '64', height: '64' });
    }

    return { logo, simbolo };
  })();

  // ---- topo.js
  __m['topo'] = (function () {
    const { h } = __m['dom'];
    const { t, traduzirServidor } = __m['textos'];
    const { botao, chip, confirmar, detalhe } = __m['componentes'];
    const { simbolo } = __m['marca'];
    // Topo fixo do console (direcao.md, secoes 2.1 e 5.9): simbolo, nome, tres abas, chips com
    // popover e "Encerrar o painel". Os chips so se redesenham quando o estado deles muda.

    const ABAS = ['painel', 'sessao', 'ferramentas'];

    const CHIP_PLACA = {
      normal: ['chip.placa', 'neutro', 'placa', 'popover.placa.normal'],
      pronta: ['chip.placaPronta', 'pronta', 'concluido', 'popover.placa.pronta'],
      'sem-cabo': ['chip.placaSemCabo', 'alarme', 'falha', 'popover.placa.semCabo'],
      ausente: ['chip.placaAusente', 'alarme', 'falha', 'popover.placa.ausente'],
      'nao-preparada': ['chip.placaNaoPreparada', 'alarme', 'falha', 'popover.placa.naoPreparada'],
    };

    function criarTopo(ctx) {
      const links = ABAS.map((aba) => h('a', { class: 'topo-aba', href: `#/${aba}`, dados: { aba } }, t(`nav.${aba}`)));
      const chips = h('div', { class: 'topo-chips' });
      const encerrar = botao(t('nav.encerrar'), async () => {
        const sim = await confirmar({ titulo: t('dialogo.encerrarPainel.titulo'), texto: t('dialogo.encerrarPainel.texto'), confirmar: t('dialogo.encerrarPainel.confirmar'), perigo: true });
        if (!sim) return;
        const r = await ctx.api.comando('/api/encerrar');
        if (r.ok || r.semResposta) ctx.encerrar();
      }, { tipo: 'secundario' });
      const el = h('header', { class: 'topo' }, h('div', { class: 'topo-conteudo' }, [
        h('a', { class: 'topo-marca', href: '#/painel' }, [simbolo(), h('span', { class: 'topo-nome' }, t('app.titulo'))]),
        h('nav', { class: 'topo-nav', 'aria-label': t('nav.rotulo') }, links),
        h('span'),
        chips,
        encerrar,
      ]));

      let assinatura = '';

      function popover(id, titulo, corpo) {
        return h('div', { id, popover: 'auto', class: 'popover' }, [h('h2', { class: 'popover-titulo' }, titulo), corpo]);
      }

      function chipBotao(id, rotulo, nivel, nomeIcone) {
        return h('button', { type: 'button', class: 'chip-botao', popovertarget: id, 'aria-label': t('chip.detalhe', { nome: rotulo }) }, chip(rotulo, nivel, nomeIcone));
      }

      function acaoRede(rota, rotulo, pergunta) {
        return botao(rotulo, async () => {
          if (pergunta && !(await confirmar(pergunta))) return;
          const r = await ctx.api.comando(rota);
          if (!r.ok) ctx.anunciar(traduzirServidor(r.mensagem));
          ctx.recarregar();
        }, { tipo: 'secundario' });
      }

      function desenharChips(m) {
        const [rotulo, nivel, nomeIcone, frase] = CHIP_PLACA[m.placa.motivo] || CHIP_PLACA.normal;
        const nomePlaca = m.placa.nome || (m.sessao.Placa && m.sessao.Placa.nome) || '';
        const popPlaca = popover('popover-placa', t('popover.placa.titulo'), [
          h('p', null, t(frase, { nome: nomePlaca })),
          m.placa.ips.length ? h('div', { class: 'popover-lista' }, [
            h('span', { class: 'campo-rotulo' }, t('popover.placa.ips')),
            m.placa.ips.map((ip) => h('span', { class: 'mono' }, ip)),
          ]) : null,
          m.simular ? null : h('div', { class: 'popover-acoes' }, [
            acaoRede('/api/rede/preparar', t('popover.placa.preparar')),
            acaoRede('/api/rede/restaurar', t('popover.placa.restaurar'), { titulo: t('dialogo.restaurar.titulo'), texto: t('dialogo.restaurar.texto'), confirmar: t('dialogo.restaurar.confirmar'), perigo: true }),
          ]),
          m.placa.ifIndex ? detalhe(t('detalhe.ifIndex', { n: m.placa.ifIndex })) : null,
        ]);
        const i = m.internet;
        const fraseInternet = i.agora === 'ok' ? t('popover.internet.ok', { quando: i.quando }) : i.agora === 'sem' ? t('popover.internet.sem') : t('popover.internet.naoTestado');
        const popInternet = popover('popover-internet', t('popover.internet.titulo'), [
          h('p', null, fraseInternet),
          h('div', { class: 'popover-acoes' }, acaoRede('/api/internet/testar', t('popover.internet.testar'))),
        ]);
        const lista = [
          chipBotao('popover-placa', t(rotulo), nivel, nomeIcone), popPlaca,
          chipBotao('popover-internet', i.nivel === 'alarme' ? t('chip.semInternet') : t('chip.internet'), i.nivel, i.nivel === 'alarme' ? 'falha' : 'internet'), popInternet,
        ];
        if (m.simular) {
          lista.push(
            chipBotao('popover-simulacao', t('chip.simulacao'), 'neutro', 'simulacao'),
            popover('popover-simulacao', t('popover.simulacao.titulo'), h('p', null, t('popover.simulacao.texto'))),
          );
        }
        chips.replaceChildren(...lista);
      }

      return {
        el,
        atualizar(m, tela) {
          for (const a of links) {
            if (a.dataset.aba === tela) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
          }
          const nova = JSON.stringify([m.placa, m.internet, m.simular]);
          if (nova === assinatura) return;
          assinatura = nova;
          desenharChips(m);
        },
      };
    }

    return { criarTopo };
  })();

  // ---- formularios.js
  __m['formularios'] = (function () {
    const { h, novoId } = __m['dom'];
    const { campo } = __m['componentes'];
    const { icone } = __m['icones'];
    const { t } = __m['textos'];
    const { ipParaNumero, numeroParaIp } = __m['formato'];
    const { SENHA_MIN } = __m['constantes'];
    // Uma definicao por secao da sessao (direcao.md, secao 7.2; UX-37): a mesma no passo a passo,
    // em Sessao e no painel lateral. montarFormulario devolve { el, coletar }; coletar valida e
    // devolve { ok, parcial } com a secao pronta para PUT /api/sessao.

    const OUTRO = 'outro';

    function validarIp(c) {
      if (ipParaNumero(c.valor()) === null) { c.mostrarErro(t('fila.erro.ip')); return false; }
      c.limparErro();
      return true;
    }

    function obrigatorio(c) {
      if (!c.valor()) { c.mostrarErro(t('erro.campo.obrigatorio')); return false; }
      c.limparErro();
      return true;
    }

    function senha(modelo) {
      if (modelo.simular) {
        return { el: h('p', { class: 'nota-neutra' }, [icone('simulacao'), h('span', null, t('senha.simulacao'))]), coletar: () => ({ ok: true, parcial: null }) };
      }
      const a = campo({ rotulo: t('senha.campo'), tipo: 'password', ajuda: t('senha.ajuda'), autocomplete: 'new-password' });
      const b = campo({ rotulo: t('senha.repetir'), tipo: 'password', autocomplete: 'new-password' });
      const el = h('div', { class: 'form-grade' }, [a.el, b.el]);
      return {
        el,
        coletar() {
          const v = a.valor();
          if (v.length < SENHA_MIN || !/[a-z]/i.test(v) || !/\d/.test(v)) { a.mostrarErro(t('senha.erro.curta')); a.entrada.focus(); return { ok: false }; }
          a.limparErro();
          if (v !== b.valor()) { b.mostrarErro(t('senha.erro.diferente')); b.entrada.focus(); return { ok: false }; }
          b.limparErro();
          return { ok: true, senha: v, parcial: null };
        },
      };
    }

    function placa(modelo) {
      const atual = (modelo.sessao.Placa && modelo.sessao.Placa.ifIndex) || null;
      const placas = modelo.placas || [];
      if (!placas.length) return { el: h('p', { class: 'apoio' }, t('placa.lendo')), coletar: () => ({ ok: false }) };
      const nome = novoId('placa');
      const linhas = placas.map((p) => {
        const id = novoId('placa-op');
        const marcada = atual ? p.ifIndex === atual : p.sugerida;
        const nota = h('p', { class: 'placa-nota', hidden: !(marcada && p.rotaPadrao) }, [icone('informacao'), h('span', null, t('placa.notaInternet'))]);
        const radio = h('input', { type: 'radio', id, name: nome, value: String(p.ifIndex), checked: marcada, class: 'placa-radio' });
        return { p, radio, nota, el: h('div', { class: 'placa-linha' }, [
          radio,
          h('label', { for: id, class: 'placa-rotulo' }, [
            h('span', { class: 'placa-nome' }, p.nome),
            h('span', { class: 'placa-desc apoio' }, [p.descricao, p.velocidade ? `, ${p.velocidade}` : '']),
            p.sugerida ? h('span', { class: 'chip chip-neutro' }, t('placa.sugerida')) : null,
            !p.cabo ? h('span', { class: 'chip chip-atencao' }, [icone('atencao'), h('span', null, t('placa.semCabo'))]) : null,
          ]),
          nota,
        ]) };
      });
      const grupo = h('fieldset', { class: 'placa-lista' }, [h('legend', { class: 'campo-rotulo' }, t('placa.lista')), linhas.map((l) => l.el)]);
      grupo.addEventListener('change', () => { for (const l of linhas) l.nota.hidden = !(l.radio.checked && l.p.rotaPadrao); });
      return {
        el: grupo,
        coletar() {
          const l = linhas.find((x) => x.radio.checked);
          if (!l) return { ok: false };
          return { ok: true, parcial: { Placa: { nome: l.p.nome, ifIndex: l.p.ifIndex } } };
        },
      };
    }

    function rede(modelo, opcoes) {
      const r = modelo.sessao.Rede || {};
      const f = modelo.sessao.Fabrica || {};
      const mascara = campo({ rotulo: t('rede.mascara'), valor: r.mascara, mono: true, exemplo: '255.255.255.0' });
      const gateway = campo({ rotulo: t('rede.gateway'), valor: r.gateway, mono: true, exemplo: '192.0.2.1' });
      const dns = campo({ rotulo: t('rede.dns'), valor: r.dns, mono: true, exemplo: '192.0.2.1' });
      const ipPc = campo({ rotulo: t('rede.ipPc'), valor: r.ipPc, mono: true, exemplo: '192.0.2.250' });
      const ipFab = campo({ rotulo: t('rede.ipFabrica'), valor: f.ipFabrica, mono: true, exemplo: '192.168.1.108' });
      const ipPcFab = campo({ rotulo: t('rede.ipPcFabrica'), valor: f.ipPc, mono: true, exemplo: '192.168.1.220' });
      const idBroadcast = novoId('broadcast');
      const broadcast = h('input', { type: 'checkbox', id: idBroadcast, checked: !!modelo.sessao.Broadcast, 'aria-describedby': `${idBroadcast}-risco` });
      const el = h('div', { class: 'form' }, [
        h('div', { class: 'form-grade' }, [mascara.el, gateway.el, dns.el, ipPc.el]),
        h('details', { class: 'recolhido' }, [
          h('summary', null, [h('span', { class: 'recolhido-titulo' }, t('rede.fabrica')), h('span', { class: 'apoio' }, t('rede.fabrica.resumo', { ipFabrica: f.ipFabrica, ipPc: f.ipPc }))]),
          h('div', { class: 'form-grade' }, [ipFab.el, ipPcFab.el]),
        ]),
        opcoes && opcoes.comBroadcast ? h('div', { class: 'caixa' }, [
          broadcast,
          h('div', null, [
            h('label', { for: idBroadcast, class: 'caixa-rotulo' }, t('rede.broadcast')),
            h('p', { class: 'campo-ajuda', id: `${idBroadcast}-risco` }, t('rede.broadcast.risco')),
          ]),
        ]) : null,
      ]);
      return {
        el,
        coletar() {
          const todos = [mascara, gateway, dns, ipPc, ipFab, ipPcFab];
          const oks = todos.map(validarIp);
          if (oks.includes(false)) { todos[oks.indexOf(false)].entrada.focus(); return { ok: false }; }
          const parcial = {
            Rede: { mascara: mascara.valor(), gateway: gateway.valor(), dns: dns.valor(), ipPc: ipPc.valor() },
            Fabrica: { ipFabrica: ipFab.valor(), ipPc: ipPcFab.valor() },
          };
          if (opcoes && opcoes.comBroadcast) parcial.Broadcast = broadcast.checked;
          return { ok: true, parcial };
        },
      };
    }

    function stream(chave, valores, cat) {
      const v = valores || {};
      const opcoesBitrate = (resolucao) => {
        const rec = cat.recomendado[resolucao];
        return [
          ...cat.bitrates.map((b) => ({ valor: b, rotulo: b === rec ? t('camera.bitrate.recomendado', { v: b }) : String(b) })),
          { valor: OUTRO, rotulo: t('camera.bitrate.outro') },
        ];
      };
      const forado = v.bitrate && !cat.bitrates.includes(Number(v.bitrate));
      const resolucao = campo({ rotulo: t('camera.resolucao'), valor: v.resolucao, opcoes: cat.resolucoes.map((r) => ({ valor: r, rotulo: r })) });
      const bitrate = campo({ rotulo: t('camera.bitrate'), valor: forado ? OUTRO : v.bitrate, opcoes: opcoesBitrate(v.resolucao || cat.resolucoes[0]) });
      const outro = campo({ rotulo: t('camera.bitrate.valor'), valor: forado ? v.bitrate : '', inputmode: 'numeric', classe: 'campo-outro' });
      outro.el.hidden = !forado;
      const fps = campo({ rotulo: t('camera.fps'), valor: v.fps, opcoes: cat.fpsLista.map((n) => ({ valor: n, rotulo: String(n) })), classe: 'campo-curto' });
      const codec = campo({ rotulo: t('camera.codec'), valor: v.codec, opcoes: cat.codecs.map((c) => ({ valor: c, rotulo: c })), classe: 'campo-curto' });
      bitrate.entrada.addEventListener('change', () => { outro.el.hidden = bitrate.valor() !== OUTRO; if (!outro.el.hidden) outro.entrada.focus(); });
      resolucao.entrada.addEventListener('change', () => {
        const rec = cat.recomendado[resolucao.valor()];
        bitrate.entrada.replaceChildren(...opcoesBitrate(resolucao.valor()).map((op) => h('option', { value: String(op.valor), selected: op.valor === rec }, op.rotulo)));
        outro.el.hidden = true;
      });
      const el = h('fieldset', { class: 'stream' }, [
        h('legend', { class: 'stream-titulo' }, t(`camera.${chave}`)),
        resolucao.el, bitrate.el, outro.el, h('div', { class: 'stream-par' }, [fps.el, codec.el]),
      ]);
      return {
        el, bitrate,
        focarBitrate: () => bitrate.entrada.focus(),
        coletar() {
          let b = bitrate.valor();
          if (b === OUTRO) {
            if (!/^\d+$/.test(outro.valor())) { outro.mostrarErro(t('erro.campo.obrigatorio')); outro.entrada.focus(); return null; }
            outro.limparErro();
            b = outro.valor();
          }
          return { resolucao: resolucao.valor(), bitrate: Number(b), fps: Number(fps.valor()), codec: codec.valor() };
        },
      };
    }

    function camera(modelo, opcoes) {
      const c = modelo.sessao.Camera || {};
      const cat = modelo.catalogo;
      const email = campo({ rotulo: t('camera.email'), tipo: 'email', valor: c.email, ajuda: t('camera.email.ajuda'), autocomplete: 'email', exemplo: 'tecnico@exemplo.example' });
      const p = stream('principal', c.principal, { ...cat.principal, codecs: cat.codecs, fpsLista: cat.fps });
      const s = stream('secundario', c.secundario, { ...cat.secundario, codecs: cat.codecs, fpsLista: cat.fps });
      const soEncoder = opcoes && opcoes.soEncoder;
      const el = h('div', { class: 'form' }, [
        soEncoder ? null : email.el,
        h('div', { class: ['form-streams', soEncoder ? 'form-streams-coluna' : null] }, [p.el, s.el]),
        soEncoder ? null : h('details', { class: 'recolhido' }, [
          h('summary', null, h('span', { class: 'recolhido-titulo' }, t('camera.porque'))),
          h('p', { class: 'apoio' }, t('camera.porque.texto')),
        ]),
      ]);
      return {
        el,
        focarBitrate: p.focarBitrate,
        coletar() {
          if (!soEncoder && !obrigatorio(email)) { email.entrada.focus(); return { ok: false }; }
          const vp = p.coletar();
          const vs = vp && s.coletar();
          if (!vp || !vs) return { ok: false };
          return { ok: true, parcial: { Camera: { email: soEncoder ? c.email : email.valor(), principal: vp, secundario: vs } } };
        },
      };
    }

    function fila(modelo) {
      const f = modelo.sessao.Fila || {};
      const inicio = campo({ rotulo: t('fila.inicio'), valor: f.inicio, mono: true, exemplo: '192.0.2.10' });
      const fim = campo({ rotulo: t('fila.fim'), valor: f.fim, mono: true, exemplo: '192.0.2.12' });
      const local = campo({ rotulo: t('fila.local'), valor: f.local, exemplo: 'Obra exemplo' });
      const rack = campo({ rotulo: t('fila.rack'), valor: f.rack, classe: 'campo-curto' });
      const andar = campo({ rotulo: t('fila.andar'), valor: f.andar, classe: 'campo-curto' });
      const previa = h('p', { class: 'previa', 'aria-live': 'polite' });
      const instalados = new Set((modelo.registro || []).filter((r) => r.Status === 'Instalada').map((r) => r.Ip));
      function atualizarPrevia() {
        const a = ipParaNumero(inicio.valor());
        const b = ipParaNumero(fim.valor());
        if (a === null || b === null || b < a) { previa.replaceChildren(); return; }
        let noRegistro = 0;
        for (let n = a; n <= b; n += 1) {
          const ip = numeroParaIp(n);
          if (instalados.has(ip)) noRegistro += 1;
        }
        previa.replaceChildren(icone(noRegistro ? 'atencao' : 'informacao'), h('span', null, `${t('fila.previa', { n: b - a + 1 })} ${noRegistro ? t('fila.previa.registro', { n: noRegistro }) : t('fila.previa.livre')}`));
        previa.className = ['previa', noRegistro ? 'previa-atencao' : null].filter(Boolean).join(' ');
      }
      inicio.entrada.addEventListener('input', atualizarPrevia);
      fim.entrada.addEventListener('input', atualizarPrevia);
      atualizarPrevia();
      const el = h('div', { class: 'form' }, [
        h('div', { class: 'form-grade' }, [inicio.el, fim.el]),
        previa,
        h('div', { class: 'form-grade form-grade-local' }, [local.el, rack.el, andar.el]),
      ]);
      return {
        el,
        coletar() {
          if (!validarIp(inicio)) { inicio.entrada.focus(); return { ok: false }; }
          if (!validarIp(fim)) { fim.entrada.focus(); return { ok: false }; }
          if (ipParaNumero(fim.valor()) < ipParaNumero(inicio.valor())) { fim.mostrarErro(t('fila.erro.ordem')); fim.entrada.focus(); return { ok: false }; }
          if (!obrigatorio(local)) { local.entrada.focus(); return { ok: false }; }
          return { ok: true, parcial: { Fila: { inicio: inicio.valor(), fim: fim.valor(), local: local.valor(), rack: rack.valor(), andar: andar.valor() } } };
        },
      };
    }

    const FORMULARIOS = { senha, placa, rede, camera, fila };

    function montarFormulario(secao, modelo, opcoes) {
      return FORMULARIOS[secao](modelo, opcoes || {});
    }

    return { FORMULARIOS, montarFormulario };
  })();

  // ---- tela-inicio.js
  __m['tela-inicio'] = (function () {
    const { h } = __m['dom'];
    const { icone } = __m['icones'];
    const { t, traduzirServidor } = __m['textos'];
    const { PASSOS } = __m['constantes'];
    const { botao, ocupar, lugarAviso, chip, aviso, campo } = __m['componentes'];
    const { montarFormulario } = __m['formularios'];
    const { logo } = __m['marca'];
    // Passo a passo e Conferir (direcao.md, secoes 2.2 e 3.1). Coluna de 720 px sob a logo,
    // trilha com numero, palavra e icone, rodape fixo com Voltar e Avancar ou Comecar.

    function trilha(atual) {
      const iAtual = PASSOS.indexOf(atual);
      const itens = PASSOS.map((passo, i) => {
        const feito = i < iAtual;
        const corrente = i === iAtual;
        const conteudo = [
          h('span', { class: 'trilha-numero' }, feito ? icone('concluido') : String(i + 1)),
          h('span', null, t('secao.nome', { secao: passo })),
          feito ? h('span', { class: 'visualmente-oculto' }, `, ${t('inicio.feito')}`) : null,
          corrente ? h('span', { class: 'visualmente-oculto' }, `, ${t('inicio.atual')}`) : null,
        ];
        return h('li', { class: ['trilha-passo', feito ? 'trilha-feito' : null, corrente ? 'trilha-atual' : null], 'aria-current': corrente ? 'step' : null },
          feito ? h('a', { class: 'trilha-link', href: rotaDoPasso(passo) }, conteudo) : conteudo);
      });
      return h('nav', { class: 'inicio-trilha', 'aria-label': t('inicio.trilha') }, h('ol', { class: 'trilha-lista' }, itens));
    }

    function rotaDoPasso(passo) {
      return passo === 'conferir' ? '#/conferir' : `#/inicio/${passo}`;
    }

    function cabeca(modelo) {
      return h('header', { class: 'inicio-cabeca' }, [
        logo(),
        modelo.simular ? chip(t('chip.simulacao'), 'neutro', 'simulacao') : null,
      ]);
    }

    // Rodape fixo; estreito alinha os botoes com a coluna do formulario (passo a passo).
    function rodape(esquerda, direita, estreito) {
      return h('footer', { class: 'rodape' }, h('div', { class: 'rodape-conteudo' }, h('div', { class: ['rodape-linha', estreito ? 'rodape-estreito' : null] }, [esquerda, h('div', { class: 'rodape-fim' }, direita)])));
    }

    function telaPasso(ctx, passoPedido) {
      const passo = PASSOS.includes(passoPedido) && passoPedido !== 'conferir' ? passoPedido : PASSOS[0];
      const modelo = ctx.modelo();
      const i = PASSOS.indexOf(passo);
      const form = montarFormulario(passo, modelo, { comBroadcast: false });
      const resposta = lugarAviso();
      const titulo = h('h2', { class: 'inicio-secao-titulo' }, t(`${passo}.titulo`));

      async function avancar(ev) {
        ev.preventDefault();
        const r = form.coletar();
        if (!r.ok) return;
        const restaurar = ocupar(btnAvancar, t('sessao.salvando'));
        let res = { ok: true };
        if (passo === 'senha' && r.senha) res = await ctx.api.comando('/api/senha', { senha: r.senha });
        else if (r.parcial) res = await ctx.api.salvarSessao(r.parcial);
        restaurar();
        if (!res.ok) {
          resposta.mostrar('erro', res.semResposta ? t('erro.semResposta') : traduzirServidor(res.mensagem), res.mensagem);
          return;
        }
        await ctx.recarregarSessao();
        ctx.ir(rotaDoPasso(PASSOS[i + 1]));
      }

      const btnAvancar = botao(t('inicio.avancar'), null, { tipo: 'primario', submit: true });
      btnAvancar.setAttribute('form', 'form-passo');
      const voltar = i > 0 ? botao(t('inicio.voltar'), () => ctx.ir(rotaDoPasso(PASSOS[i - 1])), { tipo: 'secundario' }) : h('span');

      const el = h('div', { class: 'inicio' }, [
        cabeca(modelo),
        h('main', { class: 'inicio-corpo', id: 'conteudo' }, [
          h('h1', { class: 'inicio-titulo' }, t('inicio.titulo')),
          trilha(passo),
          h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t(`${passo}.lead`))]),
          h('form', { id: 'form-passo', class: 'form', novalidate: true, onsubmit: avancar }, form.el),
          resposta.el,
        ]),
        rodape(voltar, btnAvancar, true),
      ]);
      return { el, foco: titulo };
    }

    function valorConferir(secao, modelo) {
      const s = modelo.sessao;
      if (secao === 'placa') return s.Placa && s.Placa.nome ? t('conferir.placa', { nome: s.Placa.nome }) : '';
      if (secao === 'rede') return s.Rede && s.Rede.gateway ? t('conferir.rede', s.Rede) : '';
      if (secao === 'camera') {
        const c = s.Camera;
        if (!c || !c.principal) return '';
        return t('conferir.camera', { codec: c.principal.codec, p: t('conferir.stream', c.principal), s: t('conferir.stream', c.secundario), email: c.email });
      }
      if (secao === 'fila') return s.Fila && s.Fila.inicio ? t('conferir.fila', s.Fila) : '';
      return '';
    }

    function telaConferir(ctx) {
      const modelo = ctx.modelo();
      const resposta = lugarAviso();
      const titulo = h('h1', { class: 'inicio-titulo' }, t('conferir.titulo'));

      function linhaSenha() {
        if (modelo.simular) return [h('span', { class: 'apoio' }, t('senha.simulacao')), h('span')];
        if (modelo.senhaDefinida) return [h('span', null, t('senha.definida')), h('a', { class: 'botao botao-discreto', href: '#/inicio/senha' }, t('secao.alterar', { secao: 'senha' }))];
        const c = campo({ rotulo: t('senha.campo'), tipo: 'password', autocomplete: 'new-password', ajuda: t('senha.ajuda') });
        const salvar = botao(t('senha.salvar'), async () => {
          const r = await ctx.api.comando('/api/senha', { senha: c.valor() });
          if (r.ok) ctx.recarregar(); else c.mostrarErro(traduzirServidor(r.mensagem));
        }, { tipo: 'secundario' });
        return [h('div', { class: 'ferramenta-sondar' }, [c.el, salvar]), h('span')];
      }

      function linhaFila() {
        const valor = valorConferir('fila', modelo);
        const partes = [valor ? h('span', null, valor) : falta()];
        const cf = modelo.conflito;
        if (cf && cf.instaladas) {
          const f = modelo.sessao.Fila;
          partes.push(aviso('atencao', cf.todas ? t('fila.conflito.todas', { n: cf.total, inicio: f.inicio, fim: f.fim }) : t('fila.conflito.parte', { n: cf.instaladas, total: cf.total })));
          if (cf.todas && cf.seguinte) {
            partes.push(botao(t('fila.usarSeguinte', cf.seguinte), async () => {
              const r = await ctx.api.salvarSessao({ Fila: { ...f, inicio: cf.seguinte.inicio, fim: cf.seguinte.fim } });
              if (!r.ok) { resposta.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem); return; }
              await ctx.recarregarSessao();
              ctx.ir('#/conferir');
            }, { tipo: 'secundario' }));
          }
        }
        return partes;
      }

      const falta = () => h('span', { class: 'conferir-falta' }, [icone('atencao'), h('span', null, t('conferir.vazio'))]);
      const alterar = (secao) => h('a', { class: 'botao botao-discreto', href: `#/inicio/${secao}` }, t('secao.alterar', { secao }));

      const [senhaValor, senhaAcao] = linhaSenha();
      const linhas = [
        h('div', { class: 'conferir-linha' }, [h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao: 'senha' })), h('div', { class: 'conferir-valor' }, senhaValor), h('div', { class: 'conferir-acao' }, senhaAcao)]),
        ...['placa', 'rede', 'camera'].map((secao) => {
          const v = valorConferir(secao, modelo);
          return h('div', { class: 'conferir-linha' }, [
            h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao })),
            h('div', { class: 'conferir-valor' }, v ? h('span', null, v) : falta()),
            h('div', { class: 'conferir-acao' }, alterar(secao)),
          ]);
        }),
        h('div', { class: 'conferir-linha' }, [h('div', { class: 'conferir-rotulo' }, t('secao.nome', { secao: 'fila' })), h('div', { class: 'conferir-valor' }, linhaFila()), h('div', { class: 'conferir-acao' }, alterar('fila'))]),
      ];

      const comecar = botao(t('inicio.comecar'), async () => {
        const restaurar = ocupar(comecar, t('inicio.comecar'));
        const r = await ctx.api.comando('/api/sessao/concluir', { montarFila: true });
        restaurar();
        if (!r.ok) { resposta.mostrar('erro', r.semResposta ? t('erro.semResposta') : traduzirServidor(r.mensagem), r.mensagem); return; }
        await ctx.recarregar();
        ctx.ir('#/painel');
      }, { tipo: 'primario' });
      const nota = h('span', { class: 'apoio' }, t('inicio.comecar.nota'));
      const voltar = modelo.sessaoCompleta ? h('span') : botao(t('inicio.voltar'), () => ctx.ir('#/inicio/fila'), { tipo: 'secundario' });

      const el = h('div', { class: 'inicio' }, [
        cabeca(modelo),
        h('main', { class: ['inicio-corpo', 'inicio-conferir'], id: 'conteudo' }, [
          h('div', { class: 'inicio-secao' }, [titulo, h('p', { class: 'lead' }, t('conferir.lead'))]),
          h('div', { class: 'conferir-lista' }, linhas),
          resposta.el,
        ]),
        rodape(voltar, [nota, comecar]),
      ]);
      return { el, foco: titulo };
    }

    return { telaPasso, telaConferir };
  })();

  // ---- tela-painel.js
  __m['tela-painel'] = (function () {
    const { h, focar } = __m['dom'];
    const { icone } = __m['icones'];
    const { t, traduzirServidor, valorRecusado } = __m['textos'];
    const { FITA_MAX_NUMEROS, FITA_PASSO_NUMERO, TRAVA_DECISAO_MS } = __m['constantes'];
    const { botao, ocupar, chip, lugarAviso, detalhe, confirmar, lateral, selo, barraEtapas } = __m['componentes'];
    const { montarFormulario } = __m['formularios'];
    const { mac: formatarMac } = __m['formato'];
    // Painel (direcao.md, secoes 3.2, 3.3 e 3.6): cabecalho da fila com a fita, "Pede voce",
    // tabela Fila agora / Registro e o grupo "Na espera do portao". Redesenha so quando o
    // modelo muda, e devolve o foco ao mesmo controle (o operador pode estar digitando porta).

    const LEGENDA = ['instalada', 'falha', 'curso', 'proxima', 'aguardando', 'pulada'];

    function textoEstado(p, totalEtapas) {
      if (p.estado === 'curso') return t('estado.curso', { n: p.etapaN, total: totalEtapas, etapa: p.etapa });
      if (p.estado === 'falha') return t('estado.falha', { etapa: p.falha.etapa });
      return t(`estado.${p.estado}`);
    }

    function textoLegenda(estado, c) {
      if (estado === 'instalada') return t('fita.instaladas', { n: c.instalada });
      if (estado === 'falha') return t('fita.falha', { n: c.falha });
      if (estado === 'curso') return t('fita.curso', { n: c.curso });
      if (estado === 'proxima') return t('fita.proxima');
      if (estado === 'aguardando') return t('fita.aguardando', { n: c.aguardando });
      return t('fita.puladas', { n: c.pulada });
    }

    function telaPainel(ctx, parte) {
      const raiz = h('main', { class: 'conteudo', id: 'conteudo' });
      const respostaFila = lugarAviso();
      const vistos = new Map();
      let aba = parte === 'registro' ? 'registro' : 'fila';
      let assinatura = '';
      let falhasAntes = null;

      function abrirFila(modelo) {
        const form = montarFormulario('fila', modelo);
        const resposta = lugarAviso();
        lateral({
          titulo: t('lateral.fila.titulo'),
          texto: t('lateral.fila.texto'),
          conteudo: (fechar) => {
            const salvar = botao(t('fila.montar'), async () => {
              const r = form.coletar();
              if (!r.ok) return;
              const m = ctx.modelo();
              if (m.fila && m.fila.contagem.curso > 0) {
                const sim = await confirmar({ titulo: t('dialogo.trocarFila.titulo'), texto: t('dialogo.trocarFila.texto'), confirmar: t('dialogo.trocarFila.confirmar'), perigo: true });
                if (!sim) return;
              }
              const restaurar = ocupar(salvar, t('sessao.salvando'));
              const res = await ctx.api.comando('/api/fila', r.parcial.Fila);
              restaurar();
              if (!res.ok) { resposta.mostrar('erro', traduzirServidor(res.mensagem), res.mensagem); return; }
              fechar();
              const f = r.parcial.Fila;
              await ctx.recarregarSessao();
              await ctx.recarregar();
              const n = ctx.modelo().fila ? ctx.modelo().fila.total : 0;
              respostaFila.mostrar('sucesso', t('fila.montada', { n, inicio: f.inicio, fim: f.fim }));
            }, { tipo: 'primario' });
            return [form.el, resposta.el, h('div', { class: 'lateral-acoes' }, [botao(t('lateral.cancelar'), () => fechar(), { tipo: 'secundario' }), salvar])];
          },
        });
      }

      function abrirEncoder(modelo, item, mac) {
        const form = montarFormulario('camera', modelo, { soEncoder: true });
        const resposta = lugarAviso();
        lateral({
          titulo: t('lateral.encoder.titulo', { n: item.posicao }),
          texto: t('lateral.encoder.texto'),
          conteudo: (fechar) => {
            const salvar = botao(t('lateral.encoder.salvar'), async () => {
              const r = form.coletar();
              if (!r.ok) return;
              const restaurar = ocupar(salvar, t('sessao.salvando'));
              const s = await ctx.api.salvarSessao(r.parcial);
              const d = s.ok ? await ctx.api.comando('/api/decisao', { mac, acao: 'tentar' }) : s;
              restaurar();
              if (!d.ok) { resposta.mostrar('erro', d.semResposta ? t('erro.semResposta') : traduzirServidor(d.mensagem), d.mensagem); return; }
              fechar();
              await ctx.recarregarSessao();
              await ctx.recarregar();
            }, { tipo: 'primario' });
            return [form.el, resposta.el, h('div', { class: 'lateral-acoes' }, [botao(t('lateral.cancelar'), () => fechar(), { tipo: 'secundario' }), salvar])];
          },
        });
        form.focarBitrate();
      }

      async function decidir(btn, mac, acao, resposta) {
        const restaurar = ocupar(btn, acao === 'tentar' ? t('pede.tentando') : btn.textContent);
        const r = await ctx.api.comando('/api/decisao', { mac, acao });
        restaurar();
        if (!r.ok) { resposta.mostrar('erro', r.semResposta ? t('erro.semResposta') : traduzirServidor(r.mensagem), r.mensagem); return; }
        ctx.recarregar();
      }

      function cabecalho(m) {
        const f = m.fila;
        const fechada = f.concluida || f.encerrada;
        const vigia = m.vigia.ligado ? chip(t('painel.vigia.ligado'), 'agora', 'agora') : chip(t('painel.vigia.desligado'), 'neutro');
        const alternar = botao(m.vigia.ligado ? t('painel.vigia.desligar') : t('painel.vigia.ligar'), async () => {
          const r = await ctx.api.comando('/api/vigia', { ligado: !m.vigia.ligado, broadcast: m.vigia.broadcast });
          if (!r.ok) respostaFila.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem); else respostaFila.limpar();
          ctx.recarregar();
        }, { tipo: m.vigia.ligado ? 'secundario' : 'primario', dados: { foco: 'vigia' } });
        const encerrar = botao(t('painel.fila.encerrar'), async () => {
          const sim = await confirmar({ titulo: t('dialogo.encerrarFila.titulo'), texto: t('dialogo.encerrarFila.texto', { sem: f.semCamera }), confirmar: t('dialogo.encerrarFila.confirmar'), perigo: true });
          if (!sim) return;
          const r = await ctx.api.comando('/api/decisao', { acao: 'encerrar' });
          if (!r.ok) respostaFila.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem);
          ctx.recarregar();
        }, { tipo: 'discreto', dados: { foco: 'encerrar-fila' } });
        return h('div', { class: 'fila-cabeca' }, [
          h('div', { class: 'fila-nome' }, [
            h('h1', null, t('painel.fila.titulo', f)),
            h('div', { class: 'fila-faixa' }, [
              h('span', { class: 'mono apoio' }, t('painel.fila.faixa', f)),
              m.vigia.broadcast ? chip(t('painel.qualquerFaixa'), 'atencao', 'atencao') : null,
            ]),
          ]),
          h('div', { class: 'fila-acoes' }, [
            fechada ? null : vigia,
            fechada ? null : alternar,
            botao(t('fila.montarOutra'), () => abrirFila(ctx.modelo()), { tipo: fechada ? 'primario' : 'secundario', dados: { foco: 'montar' } }),
            fechada ? null : encerrar,
          ]),
        ]);
      }

      function irParaLinha(posicao) {
        if (aba !== 'fila') { aba = 'fila'; assinatura = ''; atualizar(ctx.modelo()); }
        const linha = raiz.querySelector(`[data-linha="${posicao}"]`);
        if (!linha) return;
        for (const l of raiz.querySelectorAll('.linha-alvo')) l.classList.remove('linha-alvo');
        linha.classList.add('linha-alvo');
        linha.scrollIntoView({ block: 'nearest' });
      }

      function fita(m) {
        const f = m.fila;
        const comNumeros = f.total <= FITA_MAX_NUMEROS;
        const casas = f.posicoes.map((p) => {
          const casa = h('span', { class: ['fita-casa', `fita-${p.estado}`], onclick: () => irParaLinha(p.posicao) }, p.estado === 'falha' ? '!' : null);
          if (p.estado === 'curso') casa.style.setProperty('--fracao', String((p.etapaN - 1) / f.totalEtapas));
          return casa;
        });
        const numeros = f.posicoes.map((p) => h('span', { class: 'fita-numero' }, comNumeros || p.posicao === 1 || p.posicao % FITA_PASSO_NUMERO === 0 ? String(p.posicao) : ''));
        const legenda = LEGENDA.filter((e) => f.contagem[e] > 0 || e === 'instalada').map((e) => h('span', { class: 'legenda-item' }, [
          h('span', { class: ['legenda-amostra', `legenda-${e}`] }), h('span', null, textoLegenda(e, f.contagem)),
        ]));
        return h('div', { class: 'fita-bloco' }, [
          h('p', { class: 'visualmente-oculto' }, t('fita.resumo', { c: f.contagem })),
          h('div', { class: 'fita', 'aria-hidden': 'true' }, casas),
          h('div', { class: 'fita-numeros', 'aria-hidden': 'true' }, numeros),
          h('div', { class: 'fita-legenda', 'aria-hidden': 'true' }, legenda),
        ]);
      }

      function estadoDaFila(m) {
        const f = m.fila;
        if (f.concluida) {
          return h('section', { class: ['bloco', 'bloco-sucesso'] }, [
            h('h2', { class: 'bloco-titulo' }, [icone('concluido', 'm'), h('span', null, t('painel.concluida', { n: f.contagem.instalada }))]),
            h('p', { class: 'apoio' }, t('painel.concluida.texto')),
          ]);
        }
        if (f.encerrada) {
          return h('section', { class: 'bloco' }, [
            h('h2', { class: 'bloco-titulo' }, t('painel.encerrada', { inst: f.contagem.instalada, sem: f.semCamera })),
            h('p', { class: 'apoio' }, t('painel.encerrada.texto')),
          ]);
        }
        const parada = f.contagem.curso === 0 && f.contagem.falha === 0;
        if (!m.vigia.ligado && parada) {
          return h('section', { class: 'bloco' }, [
            h('h2', { class: 'bloco-titulo' }, t('painel.vigia.desligado')),
            h('p', null, t('painel.vazio.desligado')),
            h('p', { class: 'apoio' }, t('painel.vazio.sequencial')),
          ]);
        }
        if (m.vigia.ligado && parada && f.contagem.instalada === 0) {
          return h('section', { class: 'bloco' }, [
            h('h2', { class: 'bloco-titulo' }, [icone('espera', 'm'), h('span', null, t('painel.vazio.esperando'))]),
            h('p', { class: 'apoio' }, t('painel.vazio.esperando.texto')),
          ]);
        }
        return null;
      }

      function pedeVoce(m) {
        if (!m.pedeVoce.length) return null;
        const agora = Date.now();
        const itens = m.pedeVoce.map((item) => {
          const pos = m.fila.posicoes.find((p) => p.posicao === item.posicao);
          const mac = pos.camera.macBruto;
          if (!vistos.has(mac)) vistos.set(mac, agora);
          const travado = agora - vistos.get(mac) < TRAVA_DECISAO_MS;
          const resposta = lugarAviso();
          const explica = item.tipo === 'recusa' ? t('pede.recusa', { valor: valorRecusado(item.erroCru) }) : item.tipo === 'senha' ? t('pede.senha') : t('pede.outro');
          const motivoId = `motivo-${item.posicao}`;
          const tentar = botao(t('pede.tentar'), (ev) => decidir(ev.currentTarget, mac, 'tentar', resposta), {
            tipo: item.etapa === 'encoder' ? 'secundario' : 'primario', desabilitado: item.bloqueiaTentar || travado,
            motivoId: item.bloqueiaTentar ? motivoId : undefined, dados: { foco: `tentar-${mac}`, trava: item.bloqueiaTentar ? '' : 'sim' },
          });
          const encoder = item.etapa === 'encoder'
            ? botao(t('pede.mudarEncoder'), () => abrirEncoder(ctx.modelo(), item, mac), { tipo: 'primario', desabilitado: travado, dados: { foco: `encoder-${mac}`, trava: 'sim' } })
            : null;
          const pular = botao(t('pede.pular'), async (ev) => {
            const btn = ev.currentTarget;
            const sim = await confirmar({ titulo: t('pede.pular.titulo', { n: item.posicao }), texto: t('pede.pular.texto', { ip: item.ip }), confirmar: t('pede.pular.confirmar', { n: item.posicao }), perigo: true });
            if (sim) decidir(btn, mac, 'pular', resposta);
          }, { tipo: 'discreto', desabilitado: travado, dados: { foco: `pular-${mac}`, trava: 'sim' } });
          return h('div', { class: 'pede-item' }, [
            h('h3', { class: 'pede-titulo' }, [icone('falha', 'm'), h('span', null, t('pede.falhou', { n: item.posicao, ip: item.ip, etapa: item.etapa }))]),
            h('p', null, explica),
            h('div', { class: 'pede-acoes' }, [encoder, tentar, pular, item.erroCru ? detalhe(item.erroCru) : null]),
            item.bloqueiaTentar ? h('p', { class: 'motivo', id: motivoId }, [icone('informacao'), h('span', null, t('pede.senha.motivo'))]) : null,
            resposta.el,
          ]);
        });
        const espera = Math.max(0, ...[...vistos.values()].map((v) => v + TRAVA_DECISAO_MS - agora));
        if (espera > 0) {
          setTimeout(() => { for (const b of raiz.querySelectorAll('[data-trava="sim"]')) b.disabled = false; }, espera);
        }
        return h('section', { class: 'pede', id: 'pede-voce', 'aria-labelledby': 'pede-titulo' }, [
          h('h2', { id: 'pede-titulo' }, t('pede.titulo', { n: m.pedeVoce.length })),
          itens,
        ]);
      }

      // Nome do campo vem do cabecalho da coluna e da celula Pos., os dois visiveis.
      function entradaTabela(p, campoNome) {
        const cam = p.camera;
        const entrada = h('input', {
          class: 'entrada-tabela', type: 'text', inputmode: 'numeric', value: cam[campoNome] || '',
          'aria-labelledby': `col-${campoNome} pos-${p.posicao}`, dados: { foco: `${campoNome}-${p.posicao}` },
          onchange: async () => {
            const linha = entrada.closest('tr');
            const porta = linha.querySelector('[data-campo="porta"]').value.trim();
            const canal = linha.querySelector('[data-campo="canal"]').value.trim();
            const r = await ctx.api.comando('/api/camera', { mac: cam.macBruto, porta, canal });
            if (!r.ok) respostaFila.mostrar('erro', traduzirServidor(r.mensagem), r.mensagem);
            ctx.recarregar();
          },
        });
        entrada.dataset.campo = campoNome;
        return entrada;
      }

      function tabelaFila(m) {
        const f = m.fila;
        const cab = ['pos', 'estado', 'ip', 'modelo', 'serial', 'mac', 'porta', 'canal'];
        const linhas = f.posicoes.map((p) => {
          const c = p.camera;
          const comCampos = c && (p.estado === 'instalada' || p.estado === 'curso' || p.estado === 'falha');
          return h('tr', { class: p.estado === 'falha' ? 'linha-falha' : null, dados: { linha: p.posicao } }, [
            h('td', { class: 'coluna-pos', id: `pos-${p.posicao}` }, String(p.posicao)),
            h('td', { class: 'coluna-estado' }, h('span', { class: 'selo-linha' }, [selo(p.estado, textoEstado(p, f.totalEtapas)), p.estado === 'curso' ? [' ', barraEtapas(p.etapaN, f.totalEtapas)] : null])),
            h('td', { class: 'mono' }, p.ip),
            h('td', null, c ? c.modelo : ''),
            h('td', { class: 'mono' }, c ? c.serial : ''),
            h('td', { class: 'mono' }, c ? c.mac : ''),
            h('td', null, comCampos ? entradaTabela(p, 'porta') : ''),
            h('td', null, comCampos ? entradaTabela(p, 'canal') : ''),
          ]);
        });
        return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
          h('thead', null, h('tr', null, cab.map((k) => h('th', { scope: 'col', id: `col-${k}` }, t(`tabela.${k}`))))),
          h('tbody', null, linhas),
        ]));
      }

      function tabelaRegistro(m) {
        if (m.registroErro) {
          return h('div', { class: 'tabela-vazio' }, [h('p', null, t('registro.erro')), botao(t('registro.lerDeNovo'), () => ctx.recarregarRegistro(), { tipo: 'secundario' })]);
        }
        if (!m.registro) return h('div', { class: 'tabela-vazio' }, h('p', null, t('registro.lendo')));
        if (!m.registro.length) return h('div', { class: 'tabela-vazio' }, h('p', null, t('registro.vazio')));
        const cab = ['data', 'ip', 'modelo', 'serial', 'mac', 'status', 'local', 'porta', 'canal'];
        const estadoStatus = { Instalada: 'instalada', Falhou: 'falha', 'Em andamento': 'curso', Resetada: 'pulada' };
        const linhas = m.registro.map((r) => h('tr', null, [
          h('td', { class: 'numeros' }, r.Data),
          h('td', { class: 'mono' }, r.Ip),
          h('td', null, r.Modelo),
          h('td', { class: 'mono' }, r.Serial),
          h('td', { class: 'mono' }, formatarMac(r.Mac)),
          h('td', null, selo(estadoStatus[r.Status] || 'aguardando', t(`registro.status.${r.Status}`))),
          h('td', null, r.Local),
          h('td', { class: 'numeros' }, r.Porta),
          h('td', { class: 'numeros' }, r.Canal),
        ]));
        return h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
          h('thead', null, h('tr', null, cab.map((k) => h('th', { scope: 'col' }, t(`tabela.${k}`))))),
          h('tbody', null, linhas),
        ]));
      }

      function vista(m) {
        const ids = { fila: 'aba-fila', registro: 'aba-registro' };
        const botoes = ['fila', 'registro'].map((nome) => h('button', {
          type: 'button', role: 'tab', class: 'aba', id: ids[nome], 'aria-selected': String(aba === nome), 'aria-controls': 'painel-vista',
          tabindex: aba === nome ? '0' : '-1', dados: { foco: `aba-${nome}` },
          onclick: () => trocarAba(nome),
          onkeydown: (ev) => {
            if (ev.key === 'ArrowRight' || ev.key === 'ArrowLeft') { ev.preventDefault(); trocarAba(nome === 'fila' ? 'registro' : 'fila', true); }
          },
        }, t(`painel.aba.${nome}`)));
        return h('section', { class: 'vista' }, [
          h('div', { class: 'abas', role: 'tablist', 'aria-label': t('painel.abas') }, botoes),
          h('div', { role: 'tabpanel', id: 'painel-vista', 'aria-labelledby': ids[aba] }, aba === 'fila' ? tabelaFila(m) : tabelaRegistro(m)),
        ]);
      }

      function trocarAba(nome, focarAba) {
        aba = nome;
        history.replaceState(null, '', nome === 'registro' ? '#/painel/registro' : '#/painel');
        if (nome === 'registro') ctx.recarregarRegistro();
        assinatura = '';
        atualizar(ctx.modelo());
        if (focarAba) focar(raiz.querySelector(`[data-foco="aba-${nome}"]`));
      }

      function espera(m) {
        if (!m.espera.length) return null;
        return h('section', { class: 'espera', 'aria-labelledby': 'espera-titulo' }, [
          h('h2', { id: 'espera-titulo' }, t('tabela.espera', { n: m.espera.length })),
          h('p', { class: 'apoio' }, t('tabela.espera.explica')),
          h('div', { class: 'tabela-rolagem' }, h('table', { class: 'tabela' }, [
            h('thead', null, h('tr', null, ['estado', 'modelo', 'serial', 'mac'].map((k) => h('th', { scope: 'col' }, t(`tabela.${k}`))))),
            h('tbody', null, m.espera.map((c) => h('tr', null, [
              h('td', { class: 'coluna-estado' }, selo('espera', t('estado.espera'))),
              h('td', null, c.modelo), h('td', { class: 'mono' }, c.serial), h('td', { class: 'mono' }, c.mac),
            ]))),
          ])),
        ]);
      }

      function semFila() {
        return [
          h('h1', null, t('painel.titulo')),
          h('section', { class: 'bloco' }, [
            h('h2', { class: 'bloco-titulo' }, t('painel.vazio.semFila')),
            h('p', null, t('painel.vazio.semFila.texto')),
            botao(t('fila.montar'), () => abrirFila(ctx.modelo()), { tipo: 'primario', dados: { foco: 'montar' } }),
          ]),
        ];
      }

      function desenhar(m) {
        if (!m.fila) { raiz.replaceChildren(...semFila(), respostaFila.el); return; }
        const atalho = m.pedeVoce.length
          ? h('a', { class: 'botao botao-discreto', href: '#/painel', dados: { foco: 'atalho' }, onclick: (ev) => { ev.preventDefault(); focar(raiz.querySelector('.pede h2')); } }, t('nav.irPedeVoce'))
          : null;
        raiz.replaceChildren(
          h('section', { class: 'painel-topo', 'aria-label': t('painel.titulo') }, [cabecalho(m), fita(m), atalho, respostaFila.el]),
          estadoDaFila(m) || '',
          pedeVoce(m) || '',
          vista(m),
          espera(m) || '',
        );
      }

      function anunciarFalhas(m) {
        const agora = new Set(m.pedeVoce.map((p) => p.posicao));
        if (falhasAntes) for (const n of agora) if (!falhasAntes.has(n)) ctx.anunciar(t('app.anuncio.falha', { n }));
        falhasAntes = agora;
      }

      function atualizar(m) {
        anunciarFalhas(m);
        const nova = JSON.stringify([m.fila, m.pedeVoce, m.espera, m.vigia, m.registro, m.registroErro, aba]);
        if (nova === assinatura) return;
        assinatura = nova;
        const ativo = document.activeElement;
        const chave = ativo && raiz.contains(ativo) ? ativo.dataset.foco : null;
        const valor = chave && ativo.tagName === 'INPUT' ? ativo.value : null;
        desenhar(m);
        if (chave) {
          const alvo = raiz.querySelector(`[data-foco="${chave}"]`);
          if (alvo) { if (valor !== null) alvo.value = valor; alvo.focus({ preventScroll: true }); }
        }
      }

      atualizar(ctx.modelo());
      return { el: raiz, foco: () => raiz.querySelector('h1'), atualizar };
    }

    return { telaPainel };
  })();

  // ---- tela-sessao.js
  __m['tela-sessao'] = (function () {
    const { h } = __m['dom'];
    const { t, traduzirServidor } = __m['textos'];
    const { SECOES_SESSAO, TEMAS } = __m['constantes'];
    const { botao, ocupar, lugarAviso, confirmar } = __m['componentes'];
    const { montarFormulario } = __m['formularios'];
    const { logo } = __m['marca'];
    // Sessao, antes "Opcoes" (direcao.md, secao 3.5): menu de secoes a esquerda, uma secao por tela,
    // o mesmo formulario do passo a passo e "Salvar alteracoes" com o aviso junto do botao.

    function secaoPainel(ctx, modelo) {
      const nome = 'tema-painel';
      const opcoes = TEMAS.map((tema) => {
        const id = `tema-${tema}`;
        return h('span', { class: 'caixa' }, [
          h('input', { type: 'radio', id, name: nome, value: tema, checked: ctx.temaAtual() === tema, onchange: () => ctx.definirTema(tema) }),
          h('label', { for: id }, t(`sessao.painel.tema.${tema}`)),
        ]);
      });
      const avisoVersao = lugarAviso();
      return [
        h('fieldset', { class: 'temas' }, [h('legend', { class: 'campo-rotulo' }, t('sessao.painel.tema')), opcoes]),
        h('div', { class: 'sessao-bloco' }, [
          h('h3', null, t('sessao.painel.versao', { v: modelo.versao })),
          botao(t('sessao.painel.procurar'), () => avisoVersao.mostrar('sucesso', t('sessao.painel.semAtualizacao')), { tipo: 'secundario' }),
          avisoVersao.el,
        ]),
        h('div', { class: 'sessao-bloco' }, [
          h('h3', null, t('sessao.painel.refazer')),
          h('p', { class: 'apoio' }, t('dialogo.refazer.texto')),
          botao(t('sessao.painel.refazer'), async () => {
            const sim = await confirmar({ titulo: t('dialogo.refazer.titulo'), texto: t('dialogo.refazer.texto'), confirmar: t('dialogo.refazer.confirmar') });
            if (!sim) return;
            await ctx.api.comando('/api/sessao/refazer');
            await ctx.recarregar();
            ctx.ir('#/inicio/senha');
          }, { tipo: 'secundario' }),
        ]),
        h('div', { class: 'sessao-bloco' }, [
          h('h3', null, t('sessao.painel.sobre')),
          logo(),
          h('p', null, t('sessao.painel.sobre.texto')),
        ]),
      ];
    }

    function telaSessao(ctx, parte) {
      const secao = SECOES_SESSAO.includes(parte) ? parte : SECOES_SESSAO[0];
      const modelo = ctx.modelo();
      const titulo = h('h1', null, t('sessao.titulo'));
      const menu = h('nav', { class: 'sessao-menu', 'aria-label': t('sessao.menu') }, SECOES_SESSAO.flatMap((s) => [
        s === 'painel' ? h('span', { class: 'sessao-separador', 'aria-hidden': 'true' }) : null,
        h('a', { class: 'sessao-item', href: `#/sessao/${s}`, 'aria-current': s === secao ? 'page' : null }, t('secao.nome', { secao: s })),
      ]));

      let corpo;
      if (secao === 'painel') {
        corpo = secaoPainel(ctx, modelo);
      } else {
        const form = montarFormulario(secao, modelo, { comBroadcast: true });
        const resposta = lugarAviso();
        const rotulo = secao === 'senha' ? t('senha.salvar') : t('sessao.salvar');
        const salvar = botao(rotulo, null, { tipo: 'primario', submit: true });
        const enviar = async (ev) => {
          ev.preventDefault();
          const r = form.coletar();
          if (!r.ok) return;
          if (!r.parcial && !r.senha) { resposta.mostrar('info', t('senha.simulacao')); return; }
          const restaurar = ocupar(salvar, t('sessao.salvando'));
          const res = r.senha ? await ctx.api.comando('/api/senha', { senha: r.senha }) : await ctx.api.salvarSessao(r.parcial);
          restaurar();
          if (!res.ok) { resposta.mostrar('erro', res.semResposta ? t('erro.semResposta') : traduzirServidor(res.mensagem), res.mensagem); return; }
          await ctx.recarregarSessao();
          resposta.mostrar('sucesso', r.senha ? t('senha.salva') : t('sessao.salvas'));
        };
        corpo = [
          h('form', { class: 'form', novalidate: true, onsubmit: enviar }, [
            form.el,
            h('div', { class: 'sessao-acoes' }, modelo.simular && secao === 'senha' ? null : salvar),
            resposta.el,
          ]),
        ];
      }

      const leadChave = secao === 'painel' ? 'sessao.painel.lead' : `${secao}.lead`;
      const el = h('main', { class: 'conteudo', id: 'conteudo' }, [
        h('div', { class: 'cabeca-tela' }, [titulo, h('p', { class: 'lead' }, t('sessao.lead'))]),
        h('div', { class: 'sessao-grade' }, [
          menu,
          h('section', { class: 'sessao-secao', 'aria-labelledby': 'sessao-secao-titulo' }, [
            h('div', { class: 'cabeca-tela' }, [h('h2', { id: 'sessao-secao-titulo' }, t('secao.nome', { secao })), h('p', { class: 'apoio' }, t(leadChave))]),
            corpo,
          ]),
        ]),
      ]);
      return { el, foco: titulo };
    }

    return { telaSessao };
  })();

  // ---- tela-ferramentas.js
  __m['tela-ferramentas'] = (function () {
    const { h, novoId } = __m['dom'];
    const { t, traduzirServidor } = __m['textos'];
    const { botao, ocupar, campo, aviso, lugarAviso } = __m['componentes'];
    const { ipParaNumero } = __m['formato'];
    // Ferramentas (direcao.md, secao 3.4): uma linha por ferramenta, um Resultado so e o log
    // recolhido. Ferramenta indisponivel fica desabilitada com o motivo escrito ao lado.

    const COR_LOG = { Yellow: 'log-aviso', Red: 'log-erro', Green: 'log-sucesso' };

    function telaFerramentas(ctx) {
      const titulo = h('h1', null, t('ferr.titulo'));
      const resultado = h('div', { class: 'resultado-corpo', 'aria-live': 'polite' });
      const erroAcao = lugarAviso();
      const log = h('div', { class: 'log' });
      let ultima = null;
      let assinatura = '';
      let soAvisos = false;

      async function rodar(btn, rota, corpo, tipo) {
        const restaurar = ocupar(btn, btn.textContent);
        const r = await ctx.api.comando(rota, corpo);
        restaurar();
        if (!r.ok) {
          erroAcao.mostrar('erro', r.semResposta ? t('erro.semResposta') : traduzirServidor(r.mensagem), r.mensagem);
          return;
        }
        erroAcao.limpar();
        ultima = tipo;
        await ctx.recarregar();
        assinatura = '';
        atualizar(ctx.modelo());
      }

      const ip = campo({ rotulo: t('ferr.sondar.campo'), valor: '192.0.2.10', mono: true, exemplo: '192.0.2.10' });
      const sondar = botao(t('ferr.sondar.acao'), (ev) => {
        if (ipParaNumero(ip.valor()) === null) { ip.mostrarErro(t('fila.erro.ip')); ip.entrada.focus(); return; }
        ip.limparErro();
        rodar(ev.currentTarget, '/api/sondar', { ip: ip.valor() }, 'sondar');
      }, { tipo: 'secundario' });
      const verificar = botao(t('ferr.verificar'), (ev) => rodar(ev.currentTarget, '/api/verificar', {}, 'verificar'), { tipo: 'secundario' });
      const motivoId = novoId('motivo-procurar');
      const modelo = ctx.modelo();
      const procurar = botao(t('ferr.procurar'), (ev) => rodar(ev.currentTarget, '/api/descobrir', {}, 'procurar'), { tipo: 'secundario', desabilitado: modelo.simular, motivoId: modelo.simular ? motivoId : undefined });
      const internet = botao(t('ferr.internet'), (ev) => rodar(ev.currentTarget, '/api/internet/testar', {}, 'internet'), { tipo: 'secundario' });

      const linha = (nome, texto, acao, extra) => h('div', { class: 'ferramenta' }, [
        h('h2', null, nome),
        h('div', { class: 'ferramenta-corpo' }, [texto ? h('p', { class: 'apoio' }, texto) : null, extra || null]),
        acao,
      ]);

      const filtro = h('input', { type: 'checkbox', id: 'filtro-log', onchange: (ev) => { soAvisos = ev.currentTarget.checked; desenharLog(ctx.modelo()); } });

      const el = h('main', { class: 'conteudo', id: 'conteudo' }, [
        h('div', { class: 'cabeca-tela' }, [titulo, h('p', { class: 'lead' }, t('ferr.lead'))]),
        h('div', { class: 'ferramentas' }, [
          linha(t('ferr.sondar'), t('ferr.sondar.texto'), h('div', { class: 'ferramenta-sondar' }, [ip.el, sondar])),
          linha(t('ferr.verificar'), t('ferr.verificar.texto'), verificar),
          linha(t('ferr.procurar'), t('ferr.procurar.texto'), procurar, modelo.simular ? h('p', { class: 'motivo', id: motivoId }, t('ferr.procurar.motivo')) : null),
          linha(t('ferr.internet'), t('ferr.internet.texto'), internet),
        ]),
        erroAcao.el,
        h('section', { class: 'resultado', 'aria-labelledby': 'ferr-resultado' }, [h('h2', { id: 'ferr-resultado' }, t('ferr.resultado')), resultado]),
        h('details', { class: 'recolhido' }, [
          h('summary', null, h('span', { class: 'recolhido-titulo' }, t('ferr.log'))),
          h('div', { class: 'resultado' }, [
            h('span', { class: 'caixa' }, [filtro, h('label', { for: 'filtro-log' }, t('ferr.log.filtro'))]),
            log,
          ]),
        ]),
      ]);

      function desenharResultado(m) {
        const f = m.ferramenta;
        if (ultima === 'internet') {
          resultado.replaceChildren(aviso('sucesso', t('ferr.internet.ok', { quando: m.internet.quando })));
        } else if (f && f.tipo === 'sondar') {
          resultado.replaceChildren(aviso('sucesso', t('ferr.sondar.ok', f)));
        } else if (f && f.tipo === 'verificar') {
          resultado.replaceChildren(aviso('sucesso', t('ferr.verificar.ok', { n: f.itens.length, quando: f.quando })));
        } else {
          resultado.replaceChildren(h('p', { class: 'apoio' }, t('ferr.resultado.vazio')));
        }
      }

      function desenharLog(m) {
        const linhas = m.log.filter((l) => !soAvisos || l.cor === 'Yellow' || l.cor === 'Red');
        log.replaceChildren(...linhas.map((l) => h('p', { class: ['log-linha', 'mono', COR_LOG[l.cor]] }, [h('span', { class: 'apoio' }, l.ts), h('span', null, l.msg)])));
      }

      function atualizar(m) {
        const nova = JSON.stringify([m.ferramenta, m.internet, m.log.length, ultima]);
        if (nova === assinatura) return;
        assinatura = nova;
        desenharResultado(m);
        desenharLog(m);
      }

      atualizar(modelo);
      return { el, foco: titulo, atualizar };
    }

    return { telaFerramentas };
  })();

  // ---- api-falsa.js
  __m['api-falsa'] = (function () {
    const { ipParaNumero, numeroParaIp } = __m['formato'];
    // PROTOTIPO. Transporte falso que imita o Servidor-Painel.ps1 sem rede (direcao.md, secao 7.2).
    // So existe no prototipo: a fase B usa o transporteFetch de api.js. Dados todos ficticios
    // (IPs 192.0.2.x e 192.168.1.108, MACs AA:00:00:00:00:0x, seriais SIM-x, "Obra exemplo").
    // Formato do estado conferido contra o servidor: fonte/web/Servidor-Painel.ps1 (Publicar, rotas)
    // e fonte/Coordenador-Cameras.ps1 (cameras[], fila.itens, paralelo).
    // Este arquivo fica fora das regras de numero solto: e dado de cenario, nao codigo do painel.


    const CENARIOS = [
      { id: 'primeira', rota: '#/inicio/senha' },
      { id: 'sessao-salva', rota: '#/conferir' },
      { id: 'vazio', rota: '#/painel' },
      { id: 'painel', rota: '#/painel' },
      { id: 'falha', rota: '#/painel' },
      { id: 'concluida', rota: '#/painel' },
      { id: 'dezesseis', rota: '#/painel' },
      { id: 'reserva', rota: '#/painel' },
      { id: 'perdida', rota: '#/painel' },
    ];

    const MODELO = 'VIP 3230 B';
    const ETAPAS = ['inicializada', 'encoder', 'rede', 'conferida'];

    function macFicticio(n) {
      return `AA:00:00:00:00:${n.toString(16).toUpperCase().padStart(2, '0')}`;
    }

    function sessaoPadrao() {
      return {
        Senha: { definida: true },
        Placa: { nome: 'Ethernet 2', ifIndex: 12 },
        Rede: { mascara: '255.255.255.0', gateway: '192.0.2.1', dns: '192.0.2.1', ipPc: '192.0.2.250' },
        Fabrica: { ipFabrica: '192.168.1.108', ipPc: '192.168.1.220' },
        Camera: {
          email: 'tecnico@exemplo.example',
          principal: { resolucao: '1080p', bitrate: 4096, fps: 15, codec: 'H.265' },
          secundario: { resolucao: 'D1', bitrate: 512, fps: 15, codec: 'H.265' },
        },
        Fila: { inicio: '192.0.2.10', fim: '192.0.2.12', local: 'Obra exemplo', rack: '2', andar: '2' },
        Broadcast: false,
      };
    }

    const CATALOGO = {
      principal: { resolucoes: ['1080p', '720p'], bitrates: [1024, 2048, 3072, 4096, 6144, 8192], recomendado: { '1080p': 4096, '720p': 2048 } },
      secundario: { resolucoes: ['D1', 'VGA', 'CIF'], bitrates: [256, 384, 512, 768, 1024], recomendado: { D1: 512, VGA: 384, CIF: 256 } },
      codecs: ['H.265', 'H.264'],
      fps: [10, 12, 15, 20, 25, 30],
    };

    const PLACAS = [
      { nome: 'Ethernet 2', ifIndex: 12, tipo: 'Ethernet', cabo: true, rotaPadrao: false, sugerida: true, descricao: 'Adaptador USB 3.0 Gigabit', velocidade: '1 Gbps' },
      { nome: 'Wi-Fi', ifIndex: 7, tipo: 'Wi-Fi', cabo: true, rotaPadrao: true, sugerida: false, descricao: 'Wi-Fi interno', velocidade: '300 Mbps' },
      { nome: 'Ethernet', ifIndex: 4, tipo: 'Ethernet', cabo: false, rotaPadrao: false, sugerida: false, descricao: 'Ethernet da placa-mae', velocidade: '' },
    ];

    function montarItens(inicio, fim) {
      const a = ipParaNumero(inicio);
      const b = ipParaNumero(fim);
      const itens = [];
      for (let n = a, p = 1; n <= b; n += 1, p += 1) itens.push({ Posicao: p, Ip: numeroParaIp(n), Estado: 'pendente', Motivo: '', Mac: '' });
      return itens;
    }

    function novaCamera(n, item, fase, etapa) {
      return {
        mac: macFicticio(n), serial: `SIM-${n}`, modelo: MODELO, ipOrigem: '192.168.1.108',
        indice: item ? item.Posicao - 1 : -1, posicao: item ? item.Posicao : 0, destino: item ? item.Ip : '',
        porta: '', canal: '', fase, etapa: etapa || '', progresso: null, trabalho: '', aviso: '', falha: null,
      };
    }

    function linhaRegistro(cam, quando) {
      return {
        Mac: cam.mac.replace(/:/g, '').toLowerCase(), Ip: cam.destino, Modelo: cam.modelo, Serial: cam.serial, Firmware: '2.800.0000000.1.R',
        Etapa: 'conferida', Status: 'Instalada', Erro: '', Data: `2026-11-19 ${quando}`, Local: 'Obra exemplo', Rack: '2', Andar: '2',
        Porta: cam.porta, Canal: cam.canal, Observacao: '', Aplicado: '', Encoder: null,
      };
    }

    function estadoBase() {
      return {
        senhaDefinida: true, senhaGeracao: 1, simular: true, falharEm: '', falharEmCameras: null,
        fase: 'ocioso', trabalho: '', etapa: '', progresso: null,
        fila: null, atual: -1, camera: null, falha: null, cameras: [], portao: null, paralelo: null,
        ferramenta: null, aviso: '', avisoOrigem: '', avisoN: 0, ultimo: '',
        rede: {
          ok: true, semSessao: false, faltando: [], ips: ['192.0.2.250/24', '192.168.1.220/24'], gateway: '192.0.2.1',
          placa: { nome: 'Ethernet 2', ifIndex: 12, tipo: 'Ethernet', presente: true, cabo: true },
          preparada: true, placaPreparada: true, mexida: true, temporarios: [], rotas: [],
        },
        ocupado: false, admin: true,
        internet: { agora: 'ok', antes: 'ok', quando: '14:02:10' },
        sessao: { existe: true, completa: true, iniciada: true, etapa: 6, geracao: 3, placa: { nome: 'Ethernet 2', ifIndex: 12, mac: '', tipo: 'Ethernet' }, fila: null, quando: '2026-11-19 13:58' },
        vigia: { ligado: false, porta: '', canal: '', motivo: '', broadcast: false },
        pastaDados: '', pastaDadosAlternativa: false,
      };
    }

    function montarCenario(id) {
      const s = estadoBase();
      const sessao = sessaoPadrao();
      let registro = [];
      let semResposta = false;
      const comFila = (inicio, fim) => {
        s.fila = { itens: montarItens(inicio, fim), local: 'Obra exemplo', rack: '2', andar: '2', inicio, fim };
        s.paralelo = { max: 4, admitindo: true, dhip: 'ok', emCurso: 0 };
        s.fase = 'fila';
        sessao.Fila = { inicio, fim, local: 'Obra exemplo', rack: '2', andar: '2' };
        s.sessao.fila = { ...sessao.Fila, quando: '2026-11-19 13:58' };
      };
      const instalar = (item, n, quando, porta, canal) => {
        const cam = novaCamera(n, item, 'feita', 'conferida');
        cam.porta = porta; cam.canal = canal;
        item.Estado = 'feita'; item.Mac = cam.mac;
        s.cameras.push(cam);
        registro.push(linhaRegistro(cam, quando));
      };
      const emCurso = (item, n, fase, etapa) => {
        const cam = novaCamera(n, item, fase, etapa);
        const i = ETAPAS.indexOf(etapa);
        cam.progresso = { atual: i + 1, total: ETAPAS.length };
        item.Estado = 'reservada'; item.Mac = cam.mac;
        s.cameras.push(cam);
        return cam;
      };
      const falhar = (cam, etapa, erro, extra) => {
        cam.fase = 'decisao'; cam.etapa = etapa;
        cam.falha = { etapa, erro, recusa: false, loginRecusado: false, bloqueada: false, geracao: 1, ...extra };
        s.fase = 'decisao';
      };

      switch (id) {
        case 'primeira':
          s.senhaDefinida = false;
          s.sessao = { existe: false, completa: false, iniciada: false, etapa: 0, geracao: 0, placa: null, fila: null, quando: '' };
          s.rede = { ok: false, semSessao: true, faltando: ['conclua o passo a passo'], ips: [], gateway: '', placa: null, preparada: false, placaPreparada: false, mexida: false, temporarios: [], rotas: [] };
          sessao.Camera.email = '';
          sessao.Fila = { inicio: '', fim: '', local: '', rack: '', andar: '' };
          sessao.Senha.definida = false;
          break;
        case 'sessao-salva':
          s.senhaDefinida = false;
          sessao.Senha.definida = false;
          sessao.Fila = { inicio: '192.0.2.10', fim: '192.0.2.12', local: 'Obra exemplo', rack: '2', andar: '2' };
          s.sessao.fila = { ...sessao.Fila, quando: '2026-11-18 17:40' };
          registro = ['10', '11', '12'].map((final, i) => linhaRegistro(novaCamera(i + 1, { Posicao: i + 1, Ip: `192.0.2.${final}` }, 'feita'), `0${i + 8}:1${i}`));
          break;
        case 'vazio':
          comFila('192.0.2.13', '192.0.2.15');
          break;
        case 'painel':
        case 'reserva':
        case 'perdida':
          comFila('192.0.2.10', '192.0.2.12');
          instalar(s.fila.itens[0], 1, '14:05', '3', '1');
          emCurso(s.fila.itens[1], 2, 'portao', 'encoder');
          emCurso(s.fila.itens[2], 3, 'conferindo', 'conferida');
          s.vigia.ligado = true; s.fase = 'configurando'; s.paralelo.emCurso = 2;
          if (id === 'reserva') s.paralelo.dhip = 'sem-resposta';
          if (id === 'perdida') semResposta = true;
          break;
        case 'falha': {
          comFila('192.0.2.10', '192.0.2.12');
          instalar(s.fila.itens[0], 1, '14:05', '3', '1');
          const c2 = emCurso(s.fila.itens[1], 2, 'portao', 'encoder');
          emCurso(s.fila.itens[2], 3, 'conferindo', 'conferida');
          falhar(c2, 'encoder', 'valor recusado pela camera: BitratePrincipal=4096', { recusa: true });
          s.vigia.ligado = true; s.paralelo.emCurso = 2;
          break;
        }
        case 'concluida':
          comFila('192.0.2.10', '192.0.2.12');
          instalar(s.fila.itens[0], 1, '14:05', '3', '1');
          instalar(s.fila.itens[1], 2, '14:07', '4', '2');
          instalar(s.fila.itens[2], 3, '14:08', '5', '3');
          s.fase = 'concluida'; s.vigia.motivo = 'fila concluida';
          s.ultimo = 'Camera instalada em 192.0.2.12 (MAC AA:00:00:00:00:03).';
          break;
        case 'dezesseis': {
          comFila('192.0.2.10', '192.0.2.25');
          for (let i = 0; i < 7; i += 1) instalar(s.fila.itens[i], i + 1, `14:${10 + i}`, String(3 + i), String(1 + i));
          emCurso(s.fila.itens[7], 8, 'portao', 'encoder');
          const c9 = emCurso(s.fila.itens[8], 9, 'portao', 'encoder');
          falhar(c9, 'encoder', 'valor recusado pela camera: BitratePrincipal=4096', { recusa: true });
          emCurso(s.fila.itens[9], 10, 'conferindo', 'conferida');
          emCurso(s.fila.itens[10], 11, 'portao', 'rede');
          s.cameras.push(novaCamera(17, null, 'espera', ''));
          s.vigia.ligado = true; s.paralelo.emCurso = 3;
          break;
        }
        default:
          break;
      }
      return { s, sessao, registro, semResposta };
    }

    // Transporte: (metodo, caminho, corpo) -> Promise<{ status, corpo }>, igual ao transporteFetch.
    function criarTransporteFalso(cenarioId) {
      const m = montarCenario(cenarioId);
      let tema = 'sistema';
      let encerrado = false;
      let proximoMac = 20;
      let consultas = 0;
      const log = [
        { n: 1, ts: '2026-11-19 13:58:02', msg: 'Painel aberto em simulacao.', cor: 'Gray' },
        { n: 2, ts: '2026-11-19 14:02:10', msg: 'Internet ok pela Wi-Fi.', cor: 'Gray' },
      ];

      const ok = (corpo) => ({ status: 202, corpo: corpo || { ok: true } });
      const erro = (status, texto) => ({ status, corpo: { erro: texto } });
      const escrever = (msg, cor) => log.push({ n: log.length + 1, ts: `2026-11-19 ${new Date().toTimeString().slice(0, 8)}`, msg, cor: cor || 'Gray' });

      function recalcularFase() {
        const s = m.s;
        if (!s.fila) { s.fase = 'ocioso'; return; }
        if (s.paralelo && !s.paralelo.admitindo) { s.fase = 'encerrada'; return; }
        if (s.cameras.some((c) => c.fase === 'decisao')) { s.fase = 'decisao'; return; }
        if (s.cameras.some((c) => c.fase === 'portao' || c.fase === 'conferindo')) { s.fase = 'configurando'; return; }
        if (!s.fila.itens.some((i) => i.Estado === 'pendente' || i.Estado === 'reservada')) {
          s.fase = 'concluida';
          if (s.vigia.ligado) { s.vigia.ligado = false; s.vigia.motivo = 'fila concluida'; }
          return;
        }
        s.fase = 'fila';
      }

      // Um passo do tempo: cada camera em curso avanca uma etapa; o vigia admite a proxima posicao.
      function avancar() {
        const s = m.s;
        if (!s.fila) return;
        for (const cam of s.cameras) {
          if (cam.fase === 'portao') {
            const i = ETAPAS.indexOf(cam.etapa);
            if (i + 1 >= ETAPAS.length - 1) { cam.fase = 'conferindo'; cam.etapa = 'conferida'; } else { cam.etapa = ETAPAS[i + 1]; }
            cam.progresso = { atual: ETAPAS.indexOf(cam.etapa) + 1, total: ETAPAS.length };
          } else if (cam.fase === 'conferindo') {
            cam.fase = 'feita'; cam.progresso = null;
            const item = s.fila.itens[cam.indice];
            item.Estado = 'feita';
            m.registro.push(linhaRegistro(cam, new Date().toTimeString().slice(0, 5)));
            s.ultimo = `Camera instalada em ${cam.destino} (MAC ${cam.mac}).`;
            escrever(s.ultimo, 'Green');
          }
        }
        const emCurso = s.cameras.filter((c) => c.fase === 'portao' || c.fase === 'conferindo' || c.fase === 'decisao').length;
        if (s.vigia.ligado && s.paralelo.admitindo && emCurso < s.paralelo.max) {
          const item = s.fila.itens.find((i) => i.Estado === 'pendente');
          if (item) {
            proximoMac += 1;
            const cam = novaCamera(proximoMac, item, 'portao', 'inicializada');
            cam.progresso = { atual: 1, total: ETAPAS.length };
            item.Estado = 'reservada'; item.Mac = cam.mac;
            s.cameras.push(cam);
          }
        }
        s.paralelo.emCurso = s.cameras.filter((c) => c.fase === 'portao' || c.fase === 'conferindo').length;
        recalcularFase();
      }

      const rotas = {
        'GET /api/estado': () => ok({ estado: m.s, log, cursor: log.length, comandos: 0, versao: '1.3.0', atualizacao: { estado: 'nenhuma' } }),
        'GET /api/registro': () => ok({ cameras: m.registro, simulado: true }),
        'GET /api/sessao': () => ok({ sessao: m.sessao, existe: m.s.sessao.existe, completa: m.s.sessao.completa, etapa: m.s.sessao.etapa, catalogo: CATALOGO }),
        'GET /api/placas': () => ok({ placas: PLACAS, sugerida: 12 }),
        'PUT /api/tema': (c) => { tema = c.tema; return ok({ tema }); },
        'POST /api/senha': () => { m.s.senhaDefinida = true; m.sessao.Senha.definida = true; return ok(); },
        'PUT /api/sessao': (c) => {
          for (const [secao, valores] of Object.entries(c)) {
            m.sessao[secao] = typeof valores === 'object' && valores !== null ? { ...m.sessao[secao], ...valores } : valores;
          }
          m.s.sessao.existe = true;
          return ok({ ok: true, aplicarRede: false, etapa: m.s.sessao.etapa });
        },
        'POST /api/sessao/concluir': (c) => {
          m.s.sessao = { ...m.s.sessao, existe: true, completa: true, iniciada: true, etapa: 6 };
          m.s.rede = { ...estadoBase().rede };
          if (c.montarFila) {
            const f = m.sessao.Fila;
            m.s.fila = { itens: montarItens(f.inicio, f.fim), local: f.local, rack: f.rack, andar: f.andar, inicio: f.inicio, fim: f.fim };
            m.s.paralelo = { max: 4, admitindo: true, dhip: 'ok', emCurso: 0 };
            m.s.vigia.motivo = '';
          }
          recalcularFase();
          return ok();
        },
        'POST /api/sessao/refazer': () => { m.s.sessao = { ...m.s.sessao, completa: false, etapa: 0 }; return ok(); },
        'POST /api/vigia': (c) => {
          if (c.ligado && !m.s.fila) return erro(409, 'Monte a fila antes de ligar o vigia.');
          m.s.vigia.ligado = !!c.ligado; m.s.vigia.motivo = '';
          if (c.ligado) avancar();
          return ok();
        },
        'POST /api/fila': (c) => {
          m.s.fila = { itens: montarItens(c.inicio, c.fim), local: c.local, rack: c.rack, andar: c.andar, inicio: c.inicio, fim: c.fim };
          m.s.cameras = m.s.cameras.filter((x) => x.fase === 'espera');
          m.s.paralelo = { max: 4, admitindo: true, dhip: m.s.paralelo ? m.s.paralelo.dhip : 'ok', emCurso: 0 };
          m.sessao.Fila = { ...c };
          m.s.vigia.motivo = '';
          recalcularFase();
          return ok();
        },
        'POST /api/decisao': (c) => {
          if (c.acao === 'encerrar') {
            m.s.paralelo.admitindo = false; m.s.vigia.ligado = false; m.s.vigia.motivo = 'fila encerrada';
            recalcularFase();
            return ok();
          }
          const cam = m.s.cameras.find((x) => x.mac === c.mac);
          if (!cam || cam.fase !== 'decisao') return erro(409, 'Camera nao esta em decisao.');
          if (c.acao === 'tentar') {
            cam.fase = 'portao'; cam.etapa = cam.falha.etapa; cam.falha = null;
            cam.progresso = { atual: ETAPAS.indexOf(cam.etapa) + 1, total: ETAPAS.length };
          } else if (c.acao === 'pular') {
            cam.fase = 'pulada'; cam.falha = null;
            m.s.fila.itens[cam.indice].Estado = 'pulada';
            m.s.fila.itens[cam.indice].Motivo = 'pulada pelo operador';
          }
          recalcularFase();
          return ok();
        },
        'POST /api/camera': (c) => {
          const cam = m.s.cameras.find((x) => x.mac === c.mac);
          if (cam) { cam.porta = c.porta; cam.canal = c.canal; }
          return ok();
        },
        'POST /api/rede/preparar': () => { m.s.rede.preparada = true; m.s.rede.ok = true; return ok(); },
        'POST /api/rede/restaurar': () => { m.s.rede.preparada = false; m.s.rede.ok = false; return ok(); },
        'POST /api/internet/testar': () => { m.s.internet = { agora: 'ok', antes: 'ok', quando: new Date().toTimeString().slice(0, 8) }; return ok(); },
        'POST /api/sondar': (c) => {
          m.s.ferramenta = { tipo: 'sondar', ip: c.ip, quando: new Date().toTimeString().slice(0, 8), ping: true, init: true, fabrica: false, login: true, modelo: MODELO, serial: 'SIM-1', firmware: '2.800.0000000.1.R', mac: macFicticio(1) };
          return ok();
        },
        'POST /api/verificar': () => {
          m.s.ferramenta = { tipo: 'verificar', quando: new Date().toTimeString().slice(0, 8), itens: m.registro.map((r) => ({ ip: r.Ip, mac: r.Mac, ping: true, login: true, ok: true, detalhe: '' })) };
          return ok();
        },
        'POST /api/descobrir': () => erro(409, 'Procurar cameras so funciona no uso real.'),
        'POST /api/encerrar': () => { encerrado = true; return ok({ ok: true, restaurando: true }); },
      };

      const transporte = async (metodo, caminho, corpo) => {
        // "perdida": a primeira consulta responde; as seguintes nao.
        if (caminho === '/api/estado') consultas += 1;
        if (encerrado || (m.semResposta && caminho === '/api/estado' && consultas > 1)) throw new Error('sem resposta do servidor');
        const rota = rotas[`${metodo} ${caminho}`];
        if (!rota) return erro(404, `rota desconhecida: ${metodo} ${caminho}`);
        const r = rota(corpo || {});
        return JSON.parse(JSON.stringify(r));
      };
      transporte.avancar = avancar;
      return transporte;
    }

    return { CENARIOS, criarTransporteFalso };
  })();

  // ---- prototipo-barra.js
  __m['prototipo-barra'] = (function () {
    const { h } = __m['dom'];
    const { CENARIOS } = __m['api-falsa'];
    const { TEMAS } = __m['constantes'];
    // PROTOTIPO. Barra discreta de cenario e tema (skill prototype, ramo UI): fixa embaixo, troca
    // o cenario por ?cenario= e o tema por ?tema=. Setas esquerda e direita trocam o cenario
    // quando o foco nao esta num campo. A fase B nao leva este arquivo; os textos daqui sao do
    // prototipo e por isso nao moram em textos.js.

    const NOMES = {
      primeira: 'Primeira configuração',
      'sessao-salva': 'Sessão salva: Conferir',
      vazio: 'Fila montada, vigia desligado',
      painel: 'Painel com 3 câmeras',
      falha: 'Falha com decisão',
      concluida: 'Fila concluída',
      dezesseis: 'Fila de 16 posições',
      reserva: 'Modo de reserva',
      perdida: 'Conexão perdida',
    };
    const NOMES_TEMA = { sistema: 'Sistema', claro: 'Claro', escuro: 'Escuro' };

    function lerParametros() {
      const p = new URLSearchParams(location.search);
      const cenario = CENARIOS.some((c) => c.id === p.get('cenario')) ? p.get('cenario') : CENARIOS[0].id;
      const tema = TEMAS.includes(p.get('tema')) ? p.get('tema') : 'sistema';
      return { cenario, tema };
    }

    function irPara(cenario, tema) {
      const destino = CENARIOS.find((c) => c.id === cenario);
      location.href = `?cenario=${encodeURIComponent(cenario)}&tema=${encodeURIComponent(tema)}${destino.rota}`;
    }

    function montarBarra(o) {
      const { cenario, tema } = lerParametros();
      const seletor = h('select', { id: 'prototipo-cenario', onchange: (ev) => irPara(ev.currentTarget.value, o.temaAtual()) },
        CENARIOS.map((c) => h('option', { value: c.id, selected: c.id === cenario }, NOMES[c.id])));
      const temas = h('select', { id: 'prototipo-tema', onchange: (ev) => o.aoTema(ev.currentTarget.value) },
        TEMAS.map((t) => h('option', { value: t, selected: t === tema }, NOMES_TEMA[t])));
      const barra = h('aside', { class: 'prototipo', 'aria-label': 'Controles do protótipo' }, [
        h('span', { class: 'prototipo-marca' }, 'Protótipo'),
        h('span', { class: 'prototipo-campo' }, [h('label', { for: 'prototipo-cenario' }, 'Cenário'), seletor]),
        h('span', { class: 'prototipo-campo' }, [h('label', { for: 'prototipo-tema' }, 'Tema'), temas]),
        h('button', { type: 'button', onclick: o.aoAvancar }, 'Avançar o tempo'),
        h('span', { class: 'prototipo-dica' }, 'Setas ← → trocam o cenário'),
      ]);

      document.addEventListener('keydown', (ev) => {
        if (ev.key !== 'ArrowLeft' && ev.key !== 'ArrowRight') return;
        if (ev.target.closest && ev.target.closest('input, select, textarea, [role="tab"], dialog')) return;
        if (document.querySelector('dialog[open]')) return;
        const i = CENARIOS.findIndex((c) => c.id === cenario);
        const passo = ev.key === 'ArrowRight' ? 1 : -1;
        const proximo = CENARIOS[(i + passo + CENARIOS.length) % CENARIOS.length];
        irPara(proximo.id, o.temaAtual());
      });

      return { el: barra, sincronizarTema: (t) => { temas.value = t; } };
    }

    return { lerParametros, montarBarra };
  })();

  // ---- app.js
  __m['app'] = (function () {
    const { h, focar } = __m['dom'];
    const { t } = __m['textos'];
    const { CONSULTA_MS } = __m['constantes'];
    const { hora } = __m['formato'];
    const { criarApi } = __m['api'];
    const { derivar } = __m['estado'];
    const { lerRota, ir, aoMudarRota } = __m['rotas'];
    const { botao, faixa } = __m['componentes'];
    const { logo } = __m['marca'];
    const { criarTopo } = __m['topo'];
    const { telaPasso, telaConferir } = __m['tela-inicio'];
    const { telaPainel } = __m['tela-painel'];
    const { telaSessao } = __m['tela-sessao'];
    const { telaFerramentas } = __m['tela-ferramentas'];
    const { CENARIOS, criarTransporteFalso } = __m['api-falsa'];
    const { montarBarra, lerParametros } = __m['prototipo-barra'];
    // Entrada do painel (direcao.md, secao 7.2): liga api, ciclo de consulta, rotas, telas e tema.
    // No prototipo o transporte e o falso (api-falsa.js), escolhido por ?cenario=; na fase B troca
    // por transporteFetch() e a barra do prototipo sai.

    const TELAS_CONSOLE = { painel: telaPainel, sessao: telaSessao, ferramentas: telaFerramentas };

    function iniciar() {
      const raiz = document.querySelector('[data-raiz]');
      const anuncio = h('p', { class: 'visualmente-oculto', 'aria-live': 'assertive' });
      const params = lerParametros();
      const transporte = criarTransporteFalso(params.cenario);
      const api = criarApi(transporte);

      let tema = params.tema;
      let bruto = null;
      let extras = { registro: null, registroErro: false, sessao: null, placas: null, conexao: { falhas: 0, ultima: null } };
      let modelo = derivar(null, extras);
      let tela = null;
      let nomeTela = '';
      let topo = null;
      let faixas = null;
      let relogio = null;
      let primeiraRota = true;
      let instaladasAntes = -1;

      function aplicarTema(valor) {
        if (valor === 'sistema') document.documentElement.removeAttribute('data-tema');
        else document.documentElement.setAttribute('data-tema', valor);
      }

      const ctx = {
        api,
        ir,
        modelo: () => modelo,
        temaAtual: () => tema,
        async recarregar() { await consultar(); },
        async recarregarSessao() {
          const r = await api.sessao();
          if (r.ok) extras = { ...extras, sessao: r.dados };
          rederivar();
        },
        async recarregarRegistro() {
          const r = await api.registro();
          extras = { ...extras, registro: r.ok ? r.dados.cameras : extras.registro, registroErro: !r.ok };
          rederivar();
        },
        anunciar(texto) {
          anuncio.textContent = '';
          setTimeout(() => { anuncio.textContent = texto; }, 0);
        },
        definirTema(valor) {
          tema = valor;
          aplicarTema(valor);
          api.tema(valor);
          barra.sincronizarTema(valor);
          const p = new URLSearchParams(location.search);
          p.set('tema', valor);
          history.replaceState(null, '', `?${p.toString()}${location.hash}`);
        },
        encerrar() {
          clearInterval(relogio);
          raiz.replaceChildren(h('main', { class: 'fim', id: 'conteudo' }, [
            logo(),
            h('h1', null, t('app.encerrado.titulo')),
            h('p', { class: 'apoio' }, t('app.encerrado.texto')),
          ]));
          nomeTela = 'encerrado';
          tela = null;
        },
      };

      const barra = montarBarra({
        temaAtual: () => tema,
        aoTema: (valor) => ctx.definirTema(valor),
        aoAvancar: async () => { transporte.avancar(); await consultar(); },
      });

      function desenharFaixas() {
        if (!faixas) return;
        let nova = null;
        if (modelo.conexaoPerdida) {
          nova = faixa('alarme', t('faixa.perdida'), botao(t('faixa.perdida.acao'), () => location.reload(), { tipo: 'secundario' }),
            modelo.ultimaResposta ? t('faixa.perdida.ultima', { hora: hora(modelo.ultimaResposta) }) : null);
        } else if (modelo.vigia.reserva) {
          nova = faixa('atencao', t('faixa.reserva'));
        } else if (modelo.atualizacao.estado === 'disponivel') {
          nova = faixa('info', t('faixa.atualizacao', { versao: modelo.atualizacao.versao }), botao(t('faixa.atualizacao.acao'), null, { tipo: 'secundario' }));
        }
        const chave = nova ? nova.className + nova.textContent : '';
        if (faixas.dataset.chave === chave) return;
        faixas.dataset.chave = chave;
        faixas.replaceChildren(nova || '');
        const inerte = modelo.conexaoPerdida;
        for (const el of raiz.querySelectorAll('[data-inerte]')) el.inert = inerte;
      }

      function rederivar() {
        modelo = derivar(bruto, extras);
        if (topo) topo.atualizar(modelo, nomeTela);
        desenharFaixas();
        if (tela && tela.atualizar) tela.atualizar(modelo);
      }

      async function consultar() {
        const r = await api.estado();
        if (r.ok) {
          bruto = r.dados;
          extras = { ...extras, conexao: { falhas: 0, ultima: new Date() } };
        } else {
          extras = { ...extras, conexao: { ...extras.conexao, falhas: extras.conexao.falhas + 1 } };
        }
        const instaladas = bruto && bruto.estado.fila ? bruto.estado.fila.itens.filter((i) => i.Estado === 'feita').length : 0;
        if (r.ok && instaladas !== instaladasAntes) {
          instaladasAntes = instaladas;
          const reg = await api.registro();
          extras = { ...extras, registro: reg.ok ? reg.dados.cameras : extras.registro, registroErro: !reg.ok };
        }
        rederivar();
      }

      function desenhar(rota) {
        const fabrica = TELAS_CONSOLE[rota.tela];
        if (rota.tela === 'inicio' || rota.tela === 'conferir') {
          topo = null;
          faixas = null;
          tela = rota.tela === 'inicio' ? telaPasso(ctx, rota.parte) : telaConferir(ctx);
          nomeTela = rota.tela;
          raiz.replaceChildren(tela.el);
        } else if (fabrica) {
          topo = criarTopo(ctx);
          faixas = h('div', { class: 'faixas' });
          nomeTela = rota.tela;
          tela = fabrica(ctx, rota.parte);
          topo.el.dataset.inerte = '';
          tela.el.dataset.inerte = '';
          const pular = h('a', { class: 'pular', href: '#/painel', onclick: (ev) => { ev.preventDefault(); focar(tela.el); } }, t('app.pular'));
          raiz.replaceChildren(pular, topo.el, faixas, tela.el);
          topo.atualizar(modelo, nomeTela);
          desenharFaixas();
        } else {
          const destino = CENARIOS.find((c) => c.id === params.cenario);
          ir(destino.rota);
          return;
        }
        document.title = fabrica ? `${t(`nav.${rota.tela}`)} - ${t('app.titulo')}` : t('app.titulo');
        if (!primeiraRota) {
          const alvo = typeof tela.foco === 'function' ? tela.foco() : tela.foco;
          focar(alvo);
        }
        primeiraRota = false;
      }

      aplicarTema(tema);
      document.body.append(anuncio, barra.el);
      raiz.replaceChildren(h('main', { class: 'fim', id: 'conteudo' }, [logo(), h('h1', null, t('app.abrindo'))]));

      (async () => {
        const [s, p] = await Promise.all([api.sessao(), api.placas()]);
        extras = { ...extras, sessao: s.ok ? s.dados : null, placas: p.ok ? p.dados.placas : null };
        await consultar();
        aoMudarRota(desenhar);
        desenhar(lerRota());
        relogio = setInterval(consultar, CONSULTA_MS);
      })();
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar);
    else iniciar();

    return {  };
  })();
})();
