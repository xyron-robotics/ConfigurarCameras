// Todo texto de interface do painel (direcao.md, secao 7.2), em pt-BR e com a
// letra de hoje. Chave = tela.elemento; valor = texto ou funcao dos dados.
// t('chave', dados) devolve o texto; chave ausente avisa no console.
import { NBSP } from './constantes.js';

const TEXTOS = {
  // ---------------------------------------------------------------- marcacao (legado-marcacao.js)
  'topo.pular': 'Pular para o conteúdo',
  'topo.atualizacao-notas': 'o que mudou',
  'topo.btn-atualizar': 'Atualizar o painel',
  'marca.alt': 'Grupo SmartSeg',
  'painel.painel-sem-fila.titulo': 'Sem fila montada',
  'painel.painel-sem-fila.apoio': 'A fila é a sequência de IPs que as câmeras vão receber.',
  'painel.painel-sem-fila.link': 'Monte uma em Sessão, seção Fila.',
  'painel.fita-titulo': 'Fila',
  'painel.btn-encerrar-fila': 'Encerrar a fila',
  'painel.fita.rotulo-leitor': 'Posições da fila',
  'painel.vigia.titulo': 'Vigia',
  'painel.vigia-estado': 'desligado',
  'painel.vigia-dhip': 'Sem broadcast: uma câmera por vez.',
  'painel.campo-broadcast.dica': 'Broadcast DHIP (UDP 37810): acha câmera de fábrica mesmo fora do IP de fábrica; a placa recebe um IP temporário na rede dela. Na rede do escritório, só com a bancada isolada.',
  'painel.campo-broadcast': 'Aceitar câmera de fábrica em qualquer faixa (broadcast)',
  'painel.btn-vigia': 'Ligar vigia',
  'painel.cartoes.rotulo-leitor': 'Câmeras em curso',
  'painel.bancada-destino.rotulo': 'Destino',
  'painel.bancada-apoio': 'Ligue uma câmera só no cabo e confirme. A câmera de fábrica é encontrada sozinha, em qualquer faixa de IP.',
  'painel.campo-porta': 'Porta do switch',
  'painel.campo-canal': 'Canal no NVR',
  'painel.btn-conectada': 'Câmera conectada',
  'painel.retomar.abrir': 'Retomar câmera já inicializada',
  'painel.retomar.nota': 'Só para uma câmera que já recebeu a senha desta sessão, como depois de uma falha ou com o painel fechado no meio. Informe o IP em que ela responde agora. Com o campo vazio, o painel procura uma câmera de fábrica.',
  'painel.campo-ip': 'IP atual da câmera',
  'painel.etapa-inicializada': 'Inicialização',
  'painel.etapa-encoder': 'Encoder',
  'painel.etapa-rede': 'Rede',
  'painel.etapa-conferida': 'Conferência',
  'painel.decisao-apoio': 'O que foi concluído fica registrado. Tentar de novo continua da etapa que falhou.',
  'painel.decisao-tentar': 'Tentar de novo',
  'painel.decisao-pular': 'Pular esta posição',
  'painel.bancada-fim.link': 'Montar outra fila',
  'painel.registro-titulo': 'Registro',
  'painel.btn-registro-atualizar': 'Atualizar registro',
  'painel.btn-exportar': 'Exportar relatório',
  'painel.registro-bloco.coluna': 'IP',
  'painel.registro-bloco.coluna.2': 'MAC',
  'painel.registro-bloco.coluna.3': 'Modelo',
  'painel.registro-bloco.coluna.4': 'Situação',
  'painel.registro-bloco.coluna.5': 'Encoder',
  'painel.registro-bloco.coluna.6': 'Local',
  'painel.registro-bloco.coluna.7': 'Rack / porta',
  'painel.registro-bloco.coluna.8': 'Data',
  'painel.registro-vazio': 'Nenhuma câmera registrada ainda.',
  'ferramentas.titulo': 'Ferramentas',
  'ferramentas.apoio': 'Tudo aqui só lê a rede e as câmeras, pela placa escolhida. Nada é alterado. Para voltar uma câmera de fábrica, use a tela dela ou o botão físico de reset.',
  'ferramentas.form-sondar.titulo': 'Sondar uma câmera',
  'ferramentas.form-sondar.apoio': 'Lê uma câmera pelo IP. Sem senha na sessão, mostra apenas se está de fábrica.',
  'ferramentas.campo-ip': 'IP',
  'ferramentas.form-sondar.botao': 'Sondar câmera',
  'ferramentas.form-sondar.nota': 'Desligado em simulação: lê a rede de verdade.',
  'ferramentas.descobrir.titulo': 'Procurar câmeras na rede',
  'ferramentas.descobrir.apoio': 'Broadcast',
  'ferramentas.descobrir.termo': 'DHIP',
  'ferramentas.descobrir.apoio.2': 'pela placa escolhida (responde de qualquer faixa, com modelo, serial e firmware) e, se nada vier, varredura por ping. Lista câmeras de fábrica, já inicializadas, NVRs e controladores.',
  'ferramentas.btn-descobrir': 'Procurar câmeras',
  'ferramentas.descobrir.nota': 'Desligado em simulação: lê a rede de verdade.',
  'ferramentas.verificar.titulo': 'Verificar câmeras instaladas',
  'ferramentas.verificar.apoio': 'Faz login em cada câmera do registro e confere IP e MAC. Para na primeira senha recusada.',
  'ferramentas.btn-verificar': 'Verificar câmeras',
  'log.abrir': 'Log',
  // Nome acessivel do icone da linha do log (a mensagem nem sempre traz a palavra do estado).
  'log.falha': 'Falha',
  'log.sucesso': 'Concluído',
  'log.atencao': 'Atenção',
  'fim.encerrado-texto': 'Painel encerrado. Pode fechar esta janela.',
  'fim.atualizando-texto': 'Atualizando o painel… ele fecha e reabre sozinho em instantes. Pode fechar esta janela.',

  // ---------------------------------------------------------------- geral
  'erro.http': ({ codigo }) => 'HTTP ' + codigo,
  'geral.progresso': 'Progresso',
  'geral.trabalhando': 'Trabalhando…',
  'geral.separador': ' · ',
  'campo.ip-invalido': 'Use quatro números de 0 a 255, como 192.168.1.108.',
  'formato.vezes': ' × ',
  'unidade.fps': 'fps',
  'unidade.kbps': 'kbps',

  // ---------------------------------------------------------------- casca (app.js, topo.js, componentes.js)
  'app.titulo': 'Configurar câmeras',
  'app.tituloTela': ({ tela }) => tela + ' - Configurar câmeras',
  'topo.prefixo-simulacao': '[Simulação] ',
  'nav.rotulo': 'Seções do painel',
  'nav.painel': 'Painel',
  'nav.sessao': 'Sessão',
  'nav.ferramentas': 'Ferramentas',
  'nav.encerrar': 'Encerrar o painel',

  'chip.detalhe': ({ nome }) => nome + ': ver detalhes',
  'chip.placa': 'Placa de rede',
  'chip.placaPronta': 'Placa pronta',
  'chip.placaSemCabo': 'Placa sem cabo',
  'chip.placaAusente': 'Placa ausente',
  'chip.placaNaoPreparada': 'Placa sem as faixas',
  'chip.internet': 'Internet',
  'chip.semInternet': 'Sem internet',
  'chip.simulacao': 'Simulação',

  'popover.placa.titulo': 'Placa de rede',
  'popover.placa.semNome': 'escolhida',
  'popover.placa.simulacao': 'Na simulação o painel não mexe na placa de rede.',
  'popover.placa.semSessao': 'A placa é escolhida no passo a passo da sessão.',
  'popover.placa.comFaixas': ({ nome }) => 'A placa ' + nome + ' já tem as faixas de câmera.',
  'popover.placa.pronta': ({ nome }) => 'A placa ' + nome + ' está pronta: o painel colocou as faixas de câmera nela.',
  'popover.placa.semCabo': ({ nome }) => 'A placa ' + nome + ' está sem cabo. Ligue o cabo do switch das câmeras.',
  'popover.placa.ausente': ({ nome }) => 'A placa ' + nome + ' não está mais neste PC. Escolha outra em Sessão.',
  'popover.placa.naoPreparada': ({ nome }) => 'A placa ' + nome + ' ainda não tem as faixas de câmera. Prepare a placa para alcançar as câmeras.',
  'popover.placa.ips': 'Endereços',
  'popover.placa.faltando': 'Faltam',
  'popover.placa.temporarios': 'IP temporário',
  'popover.placa.temporario': ({ ip, camera }) => ip + ' (câmera em ' + camera + ')',
  'popover.placa.rotas': 'Rotas de host',
  'popover.placa.voltaDhcp': 'Ao encerrar o painel, a placa volta ao DHCP sozinha.',
  'popover.placa.pasta': ({ pasta }) => 'Dados em ' + pasta + ', porque não há permissão de escrita em ProgramData.',
  'popover.placa.preparar': 'Preparar a placa',
  'popover.placa.preparando': 'Preparando a placa…',
  'popover.placa.restaurar': 'Restaurar o DHCP',
  'popover.placa.restaurando': 'Restaurando o DHCP…',

  'popover.internet.titulo': 'Internet deste PC',
  'popover.internet.ok': ({ quando }) => 'A internet responde' + (quando ? ' (teste às ' + quando + ').' : '.'),
  'popover.internet.caiu': 'A internet caiu depois que o painel preparou a placa. Se precisar dela agora, restaure o DHCP no chip da placa.',
  'popover.internet.jaSem': 'Sem internet, e já estava assim quando o painel abriu. O painel não precisa dela para configurar câmeras.',
  'popover.internet.sem': 'Sem internet. O painel não precisa dela para configurar câmeras; só para se atualizar.',
  'popover.internet.naoTestado': 'A internet ainda não foi testada. O teste roda ao abrir e depois de preparar a placa.',
  'popover.internet.testar': 'Testar a internet',
  'popover.internet.testando': 'Testando a internet…',

  'popover.simulacao.titulo': 'Simulação',
  'popover.simulacao.texto': 'Nada é enviado para câmera nem para a placa de rede: as câmeras são de mentira.',
  'popover.simulacao.falha': ({ etapa }) => 'Falha forçada na etapa ' + etapa + '.',

  'detalhe.tecnico': 'Detalhe técnico',
  'detalhe.ifIndex': ({ n }) => 'ifIndex ' + n,
  'campo.exemplo': ({ v }) => 'ex.: ' + v,
  'erro.semResposta': 'O painel não respondeu. Confira se ele ainda está aberto e tente de novo.',

  'dialogo.cancelar': 'Cancelar',
  'dialogo.encerrarPainel.titulo': 'Encerrar o painel?',
  'dialogo.encerrarPainel.texto': ({ situacao, dhcp }) => ({
    configurando: 'Há uma câmera sendo configurada agora. Encerrar no meio pode deixá-la sem o IP definitivo, e ela vai ' +
      'precisar ser retomada depois.',
    ocupado: 'Há uma operação em andamento e ela será interrompida. A fila em memória se perde; o registro fica salvo.',
  }[situacao] || 'A fila em memória se perde; o registro e a sessão ficam salvos.') + (dhcp ? ' A placa de rede volta ao DHCP sozinha.' : ''),
  'dialogo.encerrarPainel.confirmar': 'Encerrar o painel',
  'dialogo.restaurar.titulo': 'Restaurar o DHCP?',
  'dialogo.restaurar.texto': 'Os endereços das faixas de câmera e as rotas de host saem da placa e o DHCP volta. Para ' +
    'alcançar as câmeras de novo, prepare a placa.',
  'dialogo.restaurar.confirmar': 'Restaurar o DHCP',

  'anuncio.fila-concluida': 'Fila concluída.',
  'anuncio.fila-encerrada': 'Fila encerrada.',

  // ---------------------------------------------------------------- atualizacao
  'atualizacao.motivo-ocupado': 'Aguarde: o painel está terminando a operação atual.',
  'atualizacao.motivo-em-curso': 'Espere as câmeras em curso terminarem antes de atualizar.',
  'atualizacao.motivo-vigia': 'Desligue o vigia antes de atualizar.',
  'atualizacao.motivo-admin': 'Atualizar exige o painel aberto como Administrador.',
  'atualizacao.disponivel': ({ versao, atual }) => 'Versão ' + versao + ' disponível (esta é a ' + atual + ').',
  'atualizacao.erro': ({ versao, erro }) => 'A atualização para a ' + versao + ' falhou: ' + erro + '. Nada foi instalado.',
  'atualizacao.erro-generico': 'erro',
  'atualizacao.tentar': 'Tentar de novo',
  'atualizacao.baixando': ({ versao }) => 'Baixando a versão ' + versao + '…',
  'atualizacao.verificando': 'Conferindo o instalador (SHA-256)…',
  'atualizacao.instalando': ({ versao }) => 'Instalando a versão ' + versao + '…',
  'atualizacao.em-andamento': 'Em andamento.',

  // ---------------------------------------------------------------- passo a passo (tela-inicio.js, formularios.js)
  'inicio.titulo': 'Configurar câmeras',
  'inicio.trilha': 'Passos',
  'inicio.feito': ', feito',
  'inicio.voltar': 'Voltar',
  'inicio.avancar': 'Avançar',
  'inicio.salvando': 'Salvando…',
  'inicio.comecar': 'Começar',
  'inicio.comecando': 'Começando…',
  'inicio.comecar.nota': ({ simular }) => (simular ? 'Começar monta a fila e abre o Painel.'
    : 'Começar prepara a placa, monta a fila e abre o Painel.'),
  'inicio.comecar.demorou': 'O painel ainda está preparando a placa. Espere um instante e clique em Começar de novo.',
  'inicio.carregando': 'Carregando a sessão…',
  'inicio.demorou': 'O painel ainda não confirmou. Espere um instante e tente de novo.',
  'secao.nome': ({ secao }) => ({ senha: 'Senha', placa: 'Placa', rede: 'Rede', camera: 'Câmera', fila: 'Fila', conferir: 'Conferir', painel: 'Painel' })[secao] || secao,
  'secao.alterar': ({ secao }) => ({ senha: 'Alterar a senha', placa: 'Alterar a placa', rede: 'Alterar a rede', camera: 'Alterar a câmera', fila: 'Alterar a fila' })[secao] || 'Alterar',

  'senha.titulo': 'Senha das câmeras',
  'senha.lead': 'Vira a senha do admin de cada câmera configurada nesta sessão. Fica só na memória do painel e é pedida de novo a cada abertura.',
  'senha.campo': 'Senha do admin',
  'senha.ajuda': 'Confira antes de seguir: senha digitada errada fica gravada nas câmeras.',
  'senha.repetir': 'Repita a senha',
  'senha.salvar': 'Salvar a senha',
  'senha.salvando': 'Salvando a senha…',
  'senha.salvaTrocar': 'Senha salva nesta abertura. Para trocar, digite a nova nos dois campos; vazios, fica a atual.',
  'senha.erro.diferente': 'As duas senhas estão diferentes. Digite a mesma nos dois campos.',
  'senha.salva': 'Salva nesta abertura do painel.',
  'senha.simulacao': 'Senha não usada em simulação.',

  'placa.titulo': 'Placa de rede',
  'placa.lead': 'A placa deste PC ligada à bancada ou ao switch das câmeras. Ao começar, ela ganha dois endereços a mais; ao encerrar o painel, volta ao que era.',
  'placa.lista': 'Placas de rede deste PC',
  'placa.ler': 'Ler as placas de novo',
  'placa.lendo': 'Lendo as placas de rede…',
  'placa.nenhuma': 'Nenhuma placa de rede física encontrada. Conecte um adaptador (USB-Ethernet serve) e clique em Ler as placas de novo.',
  'placa.erroLeitura': 'Não deu para ler as placas. Clique em Ler as placas de novo.',
  'placa.notaInternet': 'Esta placa leva o PC à internet: ao começar, a rede pisca por alguns segundos e o painel testa a internet depois.',

  'rede.titulo': 'Rede das câmeras',
  'rede.lead': 'A rede em que as câmeras ficam depois de configuradas, a mesma do NVR. Máscara, gateway e DNS vão para cada câmera.',
  'rede.mascara': 'Máscara',
  'rede.gateway': 'Gateway',
  'rede.dns1': 'DNS 1',
  'rede.dns2': 'DNS 2',
  'rede.ipPc': 'IP do PC nesta rede',
  'rede.ipPc.ajuda': 'Vazio: o painel escolhe um entre .200 e .249.',
  'rede.fabrica': 'Faixa de fábrica',
  'rede.fabrica.ip': 'IP de fábrica',
  'rede.fabrica.pc': 'IP do PC',
  'rede.alterar': 'Alterar',
  'rede.ipFabrica': 'IP de fábrica da câmera',
  'rede.ipPcFabrica': 'IP do PC na faixa de fábrica',
  'rede.ipPcFabrica.ajuda': 'Vazio: o painel usa o .220.',
  'rede.confirmar.titulo': 'Trocar a rede com a fila montada?',
  'rede.confirmar.botao': 'Trocar a rede',

  'camera.titulo': 'Câmera',
  'camera.lead': 'O que vai para toda câmera: o e-mail de recuperação da senha e o vídeo dos dois streams.',
  'camera.email': 'E-mail de recuperação',
  'camera.email.ajuda': 'Única forma de recuperar a senha do admin. Use um e-mail da empresa, não o pessoal.',
  'camera.porque': 'Por que isso importa',
  'camera.porque.texto': 'O intervalo de quadro-chave (GOP) é sempre o dobro dos quadros por segundo. H.264 e H.265 foram testados em câmera real; antes de usar H.265, confira se o NVR aceita.',
  'camera.principal': 'Stream principal',
  'camera.secundario': 'Stream secundário',
  'camera.resolucao': 'Resolução',
  'camera.codec': 'Codec',
  'camera.fps': 'Quadros por segundo',
  'camera.bitrate': 'Bitrate',
  'camera.bitrate.valor': 'Bitrate em kbps',
  'camera.bitrate.limites': ({ min, max }) => 'De ' + min + ' a ' + max + ' kbps.',
  'erro.email': 'Digite um e-mail completo, como cameras@empresa.example.',
  'erro.bitrate': ({ min, max }) => 'Digite um número de ' + min + ' a ' + max + '.',
  'erro.obrigatorio': 'Preencha este campo.',

  'fila.titulo': 'Fila',
  'fila.lead': 'Os IPs que as câmeras vão receber, um por câmera, dentro da rede das câmeras. Local, rack e andar vão para o registro.',
  'fila.inicio': 'Primeiro IP',
  'fila.fim': 'Último IP',
  'fila.local': 'Local',
  'fila.local.exemplo': 'Obra exemplo',
  'fila.rack': 'Rack',
  'fila.andar': 'Andar',
  'fila.posicoes': ({ n }) => (n === 1 ? '1 posição.' : n + ' posições.'),
  'fila.noRegistro': ({ n, total }) => (n === total ? 'Todas já estão no registro como instaladas.'
    : n + ' de ' + total + ' já estão no registro como instaladas.'),
  'fila.livre': 'Nenhuma no registro.',
  'fila.erro.ordem': 'O último IP vem antes do primeiro. Troque os dois.',
  'fila.usarSeguinte': ({ inicio, fim }) => 'Usar a faixa seguinte (' + inicio + ' a ' + fim + ')',
  'fila.trocandoFaixa': 'Trocando a faixa…',
  'fila.conflito.todas': ({ n }) => (n === 1 ? 'A posição já está no registro como instalada.'
    : 'As ' + n + ' posições já estão no registro como instaladas.'),
  'fila.conflito.parte': ({ n, total }) => n + ' de ' + total + ' posições já estão no registro como instaladas. Confira a faixa antes de começar.',

  'conferir.titulo': 'Conferir a sessão',
  'conferir.lead': 'O que vale nesta sessão. Tudo pode ser mudado depois na aba Sessão.',
  'conferir.falta': 'Falta preencher.',
  'conferir.senhaPede': 'A senha não fica guardada entre aberturas: digite a do admin das câmeras.',
  'conferir.virgula': ', ',
  'conferir.automatico': 'automático',
  'conferir.mascara': 'máscara',
  'conferir.dns': 'DNS',
  'conferir.e': ' e ',
  'conferir.ipPc': 'IP do PC',
  'conferir.ate': ' a ',
  'conferir.rack': ({ v }) => 'rack ' + v,
  'conferir.andar': ({ v }) => 'andar ' + v,
  'conferir.streams': ({ principal, secundario }) => 'Stream principal: ' + principal + '; secundário: ' + secundario,

  // ---------------------------------------------------------------- formularios
  'senha.digite': 'Digite a senha.',
  'form.nada-salvo': ({ marcados }) => 'Nada foi salvo: corrija ' +
    (marcados === 1 ? 'o campo marcado' : 'os ' + marcados + ' campos marcados') + '.',

  'encoder.gop': ({ gop }) => 'GOP ' + gop,
  'encoder.recusado-na': ({ modelo }) => ' (recusado na ' + modelo + ')',
  'encoder.testado': ' (testado)',
  'encoder.nao-testado': ' (não testado em câmera)',
  'encoder.recomendado': ({ v }) => v + ' (recomendado)',
  'encoder.outro-valor': 'Outro valor…',

  'placas.escolha': 'Escolha uma placa de rede da lista.',
  'placas.wifi': 'Wi-Fi',
  'placas.ethernet': 'Ethernet',
  'placas.desconectada': 'desconectada',
  'placas.sem-cabo': 'sem cabo',
  'placas.sem-ip': 'sem IP',
  'placas.dhcp': 'DHCP',
  'placas.ip-fixo': 'IP fixo',
  'placas.selo-sugerida': 'sugerida',
  'placas.so-wifi': 'Só há Wi-Fi neste PC. Dá para usar, mas a bancada precisa estar na mesma rede do Wi-Fi; um adaptador ' +
    'USB-Ethernet é mais simples.',

  'fila.previa-invertida': 'O primeiro IP vem depois do último: troque os dois.',
  'fila.previa-acima': ({ n }) => n + ' endereços: acima do máximo de 254. Divida em faixas menores.',

  // ---------------------------------------------------------------- painel
  'fita.instalada': 'instalada',
  'fita.falhou': 'falhou',
  'fita.pulada': 'pulada',
  'fita.agora': 'agora',
  'fita.proxima': 'próxima',
  'fita.camera': ({ n }) => 'câmera ' + n,
  'fita.titulo': ({ inicio, fim }) => 'Fila ' + inicio + ' a ' + fim,
  'fita.resumo': ({ feitas, pendentes }) => feitas + ' instalada(s), ' + pendentes + ' pendente(s)',
  'bancada.ordinal': ({ n, total }) => 'Câmera ' + n + ' de ' + total,
  'bancada.trabalho-titulo': ({ ordinal, ip }) => ordinal + ' → ' + ip,
  'bancada.decisao-titulo': ({ etapa, ip }) => 'Falhou na etapa ' + etapa + (ip ? ' (' + ip + ')' : ''),
  'bancada.fila-encerrada': 'Fila encerrada',
  'bancada.fila-concluida': 'Fila concluída',
  'bancada.fim-texto': 'O registro abaixo tem cada câmera; Exportar relatório gera o CSV.',
  'bancada.fim-vigia': ({ motivo }) => ' O vigia foi desligado: ' + motivo + '.',
  'bancada.conecte': ({ n, total }) => 'Conecte a câmera ' + n + ' de ' + total,
  'bancada.apoio-vigia': 'O vigia configura sozinho. Câmera conectada fica para retomar uma câmera já inicializada, pelo bloco abaixo.',
  'bancada.apoio-cabo': 'Ligue uma câmera só no cabo e confirme. A câmera de fábrica é encontrada sozinha pela placa escolhida.',

  'cartao.fase-espera': 'Na espera',
  'cartao.fase-portao': 'No portão',
  'cartao.fase-conferindo': 'Conferindo',
  'cartao.fase-decisao': 'Falhou',
  'cartao.fase-feita': 'Instalada',
  'cartao.fase-pulada': 'Pulada',
  'cartao.fase-ignorada': 'Já inicializada: não tocada',
  'cartao.serial': 'Serial ',
  'cartao.mac': 'MAC ',
  'cartao.tentar': 'Tentar de novo',
  'cartao.pular': 'Pular esta posição',
  'cartao.porta': 'Porta',
  'cartao.canal': 'Canal',
  'cartao.confirmar-pular': ({ numero, serial, mac }) => 'Pular ' + (numero ? 'a câmera ' + numero : 'esta câmera') +
    (serial ? ' (serial ' + serial + ')' : (mac ? ' (MAC ' + mac + ')' : '')) +
    '? Ela fica como está agora, registrada como Falhou e fora das instaladas. As outras seguem.',
  'cartao.titulo': ({ n }) => 'Câmera ' + n,
  'cartao.sem-posicao': 'Sem posição',
  'cartao.etapa': ({ i, total, nome }) => 'Etapa ' + i + ' de ' + total + ': ' + nome,
  'cartao.falhou-etapa': ({ etapa }) => 'Falhou na etapa ' + etapa,
  'cartao.etapa-desconhecida': 'desconhecida',
  'cartao.salvo': 'Salvo',

  'falha.bloqueada': 'A câmera bloqueou o admin por senhas erradas. Espere alguns minutos, confirme a senha certa em Opções e só ' +
    'então tente de novo.',
  'falha.senha-recusada': 'A câmera recusou a senha da sessão. Troque a senha (Opções, seção Senha) antes de tentar de novo: ' +
    'cada tentativa com a senha errada conta para o bloqueio da câmera.',
  'falha.recusa': 'A câmera recusou um valor. Confira a seção Câmera em Opções antes de tentar de novo; o que já foi concluído ' +
    'fica registrado.',
  'falha.o-destino': 'o destino',
  'falha.inicializada': 'A câmera pode ter ficado com o admin já criado. Tentar de novo confere o estado dela: se continuar de ' +
    'fábrica, recomeça; se já tiver a senha desta sessão, segue para o encoder.',
  'falha.encoder': 'A câmera já está inicializada com a senha desta sessão e continua no IP de origem. Tentar de novo faz login ' +
    'e refaz o encoder.',
  'falha.rede': ({ destino }) => 'A câmera já tem a senha e o encoder. Tentar de novo grava a rede; se ela já tiver mudado para ' +
    destino + ', só confere.',
  'falha.conferida': ({ destino }) => 'A rede já foi gravada: a câmera deve estar reiniciando em ' + destino + '. Tentar de novo ' +
    'espera ela responder lá e confere. Se ela não voltar, confira o cabo e a máscara e o gateway da sessão (Opções).',
  'falha.outra': 'O que foi concluído fica registrado. Tentar de novo continua da etapa que falhou.',

  'vigia.ip-generico': 'o IP de fábrica',
  'vigia.ligado': 'ligado',
  'vigia.desligado': 'desligado',
  'vigia.desligar': 'Desligar vigia',
  'vigia.ligar': 'Ligar vigia',
  'vigia.motivo': ({ motivo }) => 'Desligado: ' + motivo + '. ',
  'vigia.texto-desligado': ({ ip }) => 'Ligado, o painel observa ' + ip + ' e configura sozinho cada câmera de fábrica que ' +
    'aparecer, na próxima posição livre. Com a caixa marcada, aceita também câmera de fábrica em qualquer faixa (broadcast): só ' +
    'com a bancada isolada da rede do escritório.',
  'vigia.texto-ligado': ({ ip }) => 'Observando ' + ip + ' por broadcast. Ligue quantas câmeras quiser no switch: cada uma ' +
    'entra na próxima posição livre. Digite porta e canal no cartão de cada câmera, pelo serial da etiqueta.',

  'registro.titulo-simulacao': 'Registro da simulação',
  'registro.concluiu': ({ etapa }) => 'concluiu: ' + etapa,
  'registro.principal': ({ texto }) => 'Principal: ' + texto,
  'registro.secundario': ({ texto }) => 'Secundário: ' + texto,

  // ---------------------------------------------------------------- sessao (tela-sessao.js)
  'sessao.titulo': 'Sessão',
  'sessao.lead': 'Os valores que valem para as câmeras desta obra. O que for salvo vale a partir da próxima câmera.',
  'sessao.menu': 'Seções da sessão',
  'sessao.salvar': 'Salvar alterações',
  'sessao.salvando': 'Salvando…',
  'sessao.salvas': 'Alterações salvas.',
  'sessao.senhaContinua': 'Nada mudou: a senha atual continua.',
  'sessao.fila.nota': 'Salvar alterações só guarda a faixa. Montar a fila troca agora a fila da bancada e também guarda a faixa.',
  'sessao.fila.montar': 'Montar a fila',
  'sessao.fila.montando': 'Montando a fila…',
  'sessao.fila.montada': ({ n, inicio, fim }) => 'Fila montada: ' + (n === 1 ? '1 posição, ' + inicio : n + ' posições, de ' + inicio + ' a ' + fim) + '.',
  'sessao.fila.trocar.titulo': 'Trocar a fila?',
  'sessao.fila.trocar.texto': ({ inicio, fim, total, pend }) => 'A fila atual (' + inicio + ' a ' + fim + ') sai da memória com ' +
    (total === 1 ? '1 posição' : total + ' posições') + ', ' + (pend === 1 ? '1 pendente' : pend + ' pendentes') +
    '. As câmeras já instaladas continuam no registro.',
  'sessao.fila.trocar.botao': 'Trocar a fila',
  'sessao.painel.lead': 'O que é do painel, não da obra.',
  'sessao.painel.tema': 'Tema',
  'sessao.painel.tema.sistema': 'Sistema',
  'sessao.painel.tema.claro': 'Claro',
  'sessao.painel.tema.escuro': 'Escuro',
  'sessao.painel.temaErro': ({ erro }) => 'O tema não foi guardado: ' + erro + '. Escolha de novo.',
  'sessao.painel.versao': ({ v }) => 'Versão ' + v,
  'sessao.painel.procura.nenhuma': ({ quando }) => 'Última procura automática em ' + quando + ': nenhuma versão nova.',
  'sessao.painel.procura.nunca': 'O painel procura versão nova sozinho uma vez por dia. A primeira procura desta abertura ainda não terminou.',
  'sessao.painel.procura.desligada': 'A procura automática de versão nova está desligada nesta abertura do painel.',
  'sessao.painel.procura.disponivel': ({ versao, quando }) => 'Versão ' + versao + ' disponível' +
    (quando ? ', vista na procura automática em ' + quando : '') + '. Para instalar, use “Atualizar o painel” na faixa do topo.',
  'sessao.painel.procura.andamento': ({ versao }) => 'A atualização para a versão ' + versao + ' está em andamento: acompanhe na faixa do topo.',
  'sessao.painel.procura.erro': ({ versao }) => 'A atualização para a versão ' + versao + ' falhou. O motivo e o “Tentar de novo” estão na faixa do topo.',
  'sessao.painel.passo': 'Passo a passo',
  'sessao.painel.passo.apoio': 'Volta às telas iniciais com tudo preenchido, para conferir a sessão passo a passo.',
  'sessao.painel.refazer': 'Refazer o passo a passo',
  'sessao.painel.refazendo': 'Abrindo o passo a passo…',
  'sessao.refazer.titulo': 'Refazer o passo a passo?',
  'sessao.refazer.texto': ({ temFila }) => 'As telas iniciais voltam com tudo preenchido; a senha continua na memória.' +
    (temFila ? ' A fila atual fica na memória e volta ao terminar.' : ''),
  'sessao.painel.sobre': 'Sobre',
  'sessao.painel.sobre.texto': 'Painel de bancada do Grupo SmartSeg que leva câmeras Intelbras e Dahua de fábrica a câmeras instaladas: senha, rede, encoder e registro, uma fila por vez.',

  // ---------------------------------------------------------------- confirmacoes
  'decisao.confirmar-pular': 'Pular esta posição? A câmera fica como está agora, registrada como Falhou e fora das ' +
    'instaladas. A fila segue para a próxima posição.',
  'confirmar.encerrar-fila': ({ pend }) => 'Encerrar a fila? As câmeras em curso terminam antes; as pendentes ficam sem câmera.' +
    (pend === 0 ? ' Não há posições pendentes.' : (pend === 1 ? ' Há 1 posição pendente.' : ' Há ' + pend + ' posições pendentes.')),
  'confirmar.atualizar': ({ temFila }) => 'Atualizar o painel agora? Ele baixa o instalador do GitHub, confere o SHA-256, ' +
    'fecha e reabre sozinho na versão nova.' +
    (temFila ? '\n\nA fila em memória se perde; o registro e a sessão ficam.' : '\n\nO registro e a sessão ficam.'),
  'fim.encerrado-restaurando': 'Painel encerrado. A placa de rede está voltando ao DHCP (leva alguns segundos). Pode fechar ' +
    'esta janela.',

  // ---------------------------------------------------------------- ferramentas
  'ferramenta.sondando': ({ ip }) => 'Sondando ' + ip + '…',
  'ferramenta.procurando': 'Procurando câmeras na rede…',
  'ferramenta.verificando': 'Verificando câmeras instaladas…',
  'ferramenta.sondagem': ({ ip }) => 'Sondagem de ' + ip,
  'ferramenta.encontradas': 'Câmeras encontradas',
  'ferramenta.verificacao': 'Verificação',
  'ferramenta.titulo-as': ({ titulo, quando }) => titulo + ' às ' + quando,
  'sondar.ping': 'Ping',
  'sondar.responde': 'responde',
  'sondar.nao-responde': 'não responde',
  'sondar.estado': 'Estado',
  'sondar.de-fabrica': 'de fábrica',
  'sondar.nao-respondeu': 'não respondeu',
  'sondar.inicializada': 'inicializada',
  'sondar.modelo': 'Modelo',
  'sondar.serial': 'Serial',
  'sondar.firmware': 'Firmware',
  'sondar.mac': 'MAC',
  'sondar.rede': 'Rede',
  'sondar.stream-principal': 'Stream principal',
  'sondar.stream-secundario': 'Stream secundário',
  'sondar.erro': 'Erro',
  'descobrir.nada': 'Nada encontrado. Nenhum aparelho respondeu ao broadcast DHIP (UDP 37810) nem ao ping nas faixas da placa ' +
    'escolhida. Confira o cabo e o PoE; um firewall que barra UDP de entrada também silencia o broadcast.',
  'descobrir.resumo': ({ broadcast, varredura }) => broadcast + ' pelo broadcast, ' + varredura + ' pela varredura. Estado ' +
    '“de fábrica” só é certeza quando confirmado por HTTP; fora das faixas da placa é o que a câmera anunciou.',
  'descobrir.colunas': ['IP', 'Máscara', 'MAC', 'Modelo', 'Serial', 'Firmware', 'Estado'],
  'descobrir.de-fabrica': 'de fábrica',
  'descobrir.desconhecido': 'desconhecido',
  'descobrir.inicializada': 'inicializada',
  'descobrir.fora-das-faixas': ', fora das faixas da placa',
  'descobrir.nao-confirmado': ', não confirmado por HTTP',
  'descobrir.nao-lido': 'não lido',
  'verificar.nenhuma': 'Nenhuma câmera instalada no registro.',
  'verificar.colunas': ['IP', 'MAC', 'Resultado', 'Detalhe'],
  'verificar.ok': 'ok',
  'verificar.divergente': 'divergente',
  'verificar.login-falhou': 'login falhou',
  'verificar.sem-ping': 'sem ping',
};

// Nome de cada etapa no meio de uma frase ("Falhou na etapa encoder").
const NOME_ETAPA = { inicializada: 'inicialização', encoder: 'encoder', rede: 'rede', conferida: 'conferência' };

// Motivos que o servidor publica ao desligar o vigia sozinho.
const MOTIVO_VIGIA = {
  'fila concluida': 'fila concluída', 'fila encerrada': 'fila encerrada', 'fila nova': 'fila nova', 'sem fila': 'sem fila',
  'senha da sessao apagada': 'senha da sessão apagada', 'erro interno': 'erro interno (veja o log)',
  '5 tentativas sem configurar': '5 tentativas seguidas sem configurar; resolva o aviso e ligue de novo',
  'rede da sessao alterada': 'a rede da sessão mudou', 'sessao incompleta': 'sessão incompleta',
  'passo a passo reaberto': 'passo a passo reaberto',
};

export function t(chave, dados) {
  const v = TEXTOS[chave];
  if (v === undefined) {
    console.error('texto ausente: ' + chave);
    return chave;
  }
  return typeof v === 'function' ? v(dados || {}) : v;
}

export function nomeEtapa(etapa) {
  return NOME_ETAPA[etapa];
}

export function motivoVigia(motivo) {
  return MOTIVO_VIGIA[motivo] || motivo;
}
