# RPC2 em vez de CGI para falar com as câmeras

O motor fala com as câmeras só por RPC2 (`/RPC2_Login` + `/RPC2`, sessão com login MD5 em desafio), abandonando a CGI com Digest que a primeira versão usava. Em 29/09/2026 uma VIP-1230-D-G3 com firmware 2.800.00IB003.0.T recusou a CGI com HTTP 401 mesmo com a senha correta, enquanto o RPC2 aceitou o mesmo login e leu o `Encode` sem problema. O RPC2 é o protocolo da própria interface web da câmera, então acompanha qualquer firmware que tenha página web.

## Considered Options

- **CGI com RPC2 de reserva**: menor mudança e já validada na VIP-5460-Z-IA, mas mantém dois caminhos de código, e o 401 da CGI não distingue senha errada de CGI desabilitada.
- **RPC2 com CGI de reserva**: mesmo custo de manter dois caminhos, sem ganho real se o RPC2 funcionar em tudo.

## Consequences

- A leitura e a gravação de rede foram reescritas em RPC2 (`configManager.getConfig`/`setConfig Network`) e validadas na VIP-1230-D-G3 em 29/09/2026. Falta revalidar numa VIP-5460-Z-IA.
- A conferência depois da inicialização não pode depender da CGI: foi ela que acusou "falhou" numa inicialização bem-sucedida. Hoje é por login RPC2.
- O CLI em CGI (plano B) saiu do repositório em 30/09/2026 (commit `a638fce` é o último que o contém). Se a 5460 recusar o RPC2, o caminho é recuperá-lo do histórico, não manter dois protocolos.
