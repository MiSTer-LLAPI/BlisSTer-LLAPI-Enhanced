# BlisSTer LLAPI Enhanced

Improving LLAPI integration between MiSTer cores and BlisSTer. The LLAPI protocol is not exclusive to BlisSTer; this project focuses on that hardware and its two LLAPI ports. Status: experimental development, with no published core integration or hardware validation yet.

## Goal and priorities

Complete and improve the MiSTer driver while preserving compatibility with existing BlisSTer firmware and its two LLAPI ports. Firmware changes and potential reuse of Gamer-Pro Advanced code will only be considered afterward, subject to availability, licensing and compatibility.

## Implemented and verified in simulation

- Deterministic reset while ENABLE is low: counters, transmit/receive state and synchronization no longer depend on initialization forced by the testbench.
- Atomic publication of controller type, buttons and all nine analog payload bytes after receiving a complete status packet. D-pad conversion uses data from the same packet.
- SystemVerilog portability adjustments: explicit procedural output declarations, removal of a trailing concatenation comma, and if/else selection of enum values.

The implementation is in `rtl/llapi_enhanced.sv`. It retains Jamie Dickson's (Kitrinx) copyright notice and MIT license. Original references are preserved in `reference/`.

## Reproducible tests

Requirements: Python 3 and Icarus Verilog with SystemVerilog support.

```sh
bash tests/run.sh
```

Run from this directory. The script creates and removes a temporary directory.

1. `legacy_wire_tb.sv`: decodes commands on the wire, responds to poll/status requests, and checks the complete analog packet and transition to a digital controller. It explicitly models the legacy counters' power-up values.
2. `enhanced_reset_tb.sv`: checks the same inputs without forcing internal counters; during the second response, it verifies that partial bytes do not change the previously published state. It checks the new state after the complete response.

The reference test uses a temporary copy with three syntax normalizations for Icarus; the stored reference remains unchanged. Inherited warnings about nonblocking assignments in always_comb remain to be reviewed. Passing simulation does not establish Quartus timing closure or hardware operation.

## Next steps

1. Test interrupted replies, disconnection/reconnection and protocol errors; verify receive index bounds.
2. Query GET_MODES and recover when unsupported.
3. Add bounded timeouts and protect polling-period calculations against subtraction underflow.
4. Add an optional interface for complete transactions with payloads/replies and fair polling.
5. Implement documented features, such as pressure and rumble parameters, with dedicated tests.
6. Measure resource usage and polling times; integrate a pilot core and run Quartus/timing checks before hardware tests.

No resource or latency improvements have been measured yet. Independent motor control through current firmware is not promised. Persistent mode/mapping writes and undocumented features are outside the first phase.

## Reference documentation

- [Bliss-Box protocol](https://bliss-box.com/pages/integration)
- [Bliss-Box downloads and firmware](https://bliss-box.com/pages/downloads)
- [Public LLAPI firmware example](https://github.com/ulao/Bliss-Box-LLAPI), audited reference abdb246195d5d089b6fd968ebb98aa86ce3c6a70. This is partial and does not include the motor backend.
- Preserved driver reference: `reference/SNES_MiSTer-a922e326-llapi.sv`.

## Distribution

LLAPI Enhanced cores initially belong in `_LLAPI/_Experimental`, with Enhanced identification and hardware/RAM requirements in their names. Filenames do not repeat Experimental. The final 1943/1944 releases use the legacy LLAPI implementation, have been approved through user testing, and remain final.

## Progress tracking

Progress, tests and limitations are recorded in [CHANGELOG.md](CHANGELOG.md). Project documentation is maintained in English.
