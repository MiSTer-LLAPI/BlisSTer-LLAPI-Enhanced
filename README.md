# BlisSTer LLAPI Enhanced

Projeto de melhoria da integração LLAPI entre cores MiSTer e BlisSTer. O protocolo LLAPI não é exclusivo do BlisSTer; este projeto concentra-se nesse hardware e nas suas duas portas LLAPI. Estado: desenvolvimento experimental, sem integração publicada ou validação física.

## Objetivo e prioridade

Completar e melhorar o driver MiSTer mantendo compatibilidade com o firmware BlisSTer existente e as suas duas portas LLAPI. Só depois avaliar alterações ao firmware e eventual código Gamer-Pro Advanced, conforme disponibilidade, licença e compatibilidade.

## Implementado e verificado em simulação

- Reset determinístico quando ENABLE está desligado: contadores, estado de transmissão/receção e sincronização deixam de depender de inicialização forçada pelo teste.
- Publicação conjunta do tipo de comando, botões e nove bytes analógicos após receção de um pacote de estado completo. A conversão D-pad usa os dados desse mesmo pacote.
- Ajustes de portabilidade SystemVerilog: declaração explícita das saídas procedurais, remoção de vírgula final numa concatenação e seleção de enum por if/else.

A implementação está em `rtl/llapi_enhanced.sv`. Mantém o aviso de copyright e licença MIT de Jamie Dickson (Kitrinx). As referências originais em `reference/` estão preservadas.

## Testes reproduzíveis

Requisitos: Python 3 e Icarus Verilog com suporte SystemVerilog.

```sh
bash tests/run.sh
```

Executar a partir desta pasta. O script cria e elimina um diretório temporário.

1. `legacy_wire_tb.sv`: descodifica comandos nos fios, responde ao poll/status e verifica o pacote analógico completo e a transição para comando digital. Modela explicitamente os valores de arranque dos contadores antigos.
2. `enhanced_reset_tb.sv`: verifica as mesmas entradas sem forçar contadores internos; durante a segunda resposta, confirma que os bytes parciais não alteram o estado anterior publicado. Verifica o estado novo após a resposta completa.

O teste da referência usa uma cópia temporária com três normalizações de sintaxe para Icarus; não altera a referência guardada. Existem avisos herdados de atribuições não bloqueantes em always_comb, ainda por rever. PASS em simulação não é aprovação Quartus nem prova de funcionamento físico.

## Próximos passos

1. Testes de resposta interrompida, desligar/religar e erros de protocolo; verificar limites dos índices de receção.
2. Consulta GET_MODES e recuperação quando não suportada.
3. Timeouts limitados e proteção contra subtração inválida no período de polling.
4. Interface opcional de transações completas com payload/resposta e polling justo.
5. Funcionalidades documentadas, como pressão e parâmetros de rumble, com testes próprios.
6. Medir recursos e tempos de polling; integrar piloto e executar Quartus/timing antes de testes físicos.

Não há ainda ganhos de recursos ou latência medidos. Não se promete controlo independente dos motores através do firmware atual. Escritas persistentes de modos/mapeamentos e funcionalidades não documentadas ficam fora da primeira fase.

## Documentação de referência

- [Protocolo Bliss-Box](https://bliss-box.com/pages/integration)
- [Downloads e firmware Bliss-Box](https://bliss-box.com/pages/downloads)
- [Exemplo público de firmware LLAPI](https://github.com/ulao/Bliss-Box-LLAPI), referência auditada abdb246195d5d089b6fd968ebb98aa86ce3c6a70. É parcial e não inclui o backend dos motores.
- Referência de driver preservada em `reference/SNES_MiSTer-a922e326-llapi.sv`.

## Publicação

Cores LLAPI Enhanced começam em `_LLAPI/_Experimental`, com identificação Enhanced e requisitos de hardware/RAM. O nome não repete Experimental. As versões finais 1943/1944 usam o LLAPI antigo, foram aprovadas pelo utilizador e permanecem finais.

## Acompanhamento

O progresso, os testes e as limitações são registados em [CHANGELOG.md](CHANGELOG.md).
