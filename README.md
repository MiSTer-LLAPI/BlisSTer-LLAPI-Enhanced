# BlisSTer LLAPI Enhanced

Improving LLAPI integration between MiSTer cores and BlisSTer. The LLAPI protocol is not exclusive to BlisSTer; this project focuses on that hardware and its two LLAPI ports. Status: experimental development, with no published core integration or hardware validation yet.

## What has improved, in plain English

Enhanced improves the communication between MiSTer cores and BlisSTer:

- **Consistent controller readings:** buttons and sticks are updated together only after a complete reply has arrived. An incomplete reply cannot overwrite part of the previous reading.
- **Better handling of connection problems:** bounded waits prevent the driver from waiting forever in the tested failure cases. When a connection is lost, controls are cleared to reduce the risk of stuck inputs.
- **Controller changes and reconnection:** the driver queries the controller modes again after reconnecting or detecting a different controller type, instead of keeping stale settings.
- **Pressure and rumble commands:** previously declared functionality is connected to an optional interface that a core can use to request button pressure or send rumble commands, where supported. Each core must still integrate these features.
- **More reliable reply synchronization:** a byte-alignment problem found with slightly slower simulated replies has been corrected. This is not a guarantee of compatibility with every physical device.

These changes use the existing LLAPI protocol and do not introduce a requirement to flash new BlisSTer firmware. Compatibility with real devices still needs physical testing.

The completed simulation runs passed: 30 regression configurations and four additional focused timing/payload configurations were run separately, not as one combined 34-configuration run. The affected two-port I/O Tester integration simulations also passed. Simulation does not prove FPGA timing or real controller behavior.

**Still to do:** complete FPGA compilation and timing/resource checks, validate the 1942 integration, and test real BlisSTer hardware and controllers. 1942 is the first game pilot for digital inputs and reconnection; it cannot validate analog input, pressure or rumble. No reduction in latency or resource use has been demonstrated. Real motor behavior and independent motor control remain unverified.

## Credits

- **Jamie Dickson (Kitrinx):** original MiSTer LLAPI driver and the foundation this work builds on. The original copyright notice and MIT license are preserved.
- **UltimateMiSTer:** Enhanced project development, integration work, regression testing and documentation.
- **Bliss-Box / ulao:** existing LLAPI protocol documentation and public transport-parser reference. The public firmware example is partial; it is not a complete motor-control firmware source.

## Goal and priorities

Complete and improve the MiSTer driver while preserving compatibility with existing BlisSTer firmware and its two LLAPI ports. Firmware changes and potential reuse of Gamer-Pro Advanced code will only be considered afterward, subject to availability, licensing and compatibility.

## Implemented and verified in simulation

- Deterministic reset while ENABLE is low: counters, transmit/receive state and synchronization no longer depend on initialization forced by the testbench.
- Atomic publication of controller type, buttons and all nine analog payload bytes after receiving a complete status packet. D-pad conversion uses data from the same packet.
- Bounded receive-start wait: after 1 ms without a valid lead-in, the driver disconnects, clears buttons, centers axes and releases its outputs. It waits for both input lines to be released for the settling interval before resuming polling. The 1 ms limit is an engineering choice that still requires hardware validation.
- Automatic GET_MODES after a valid connection/controller-type change, with explicit validity and fallback when unsupported or silent.
- Optional atomic command interface for pressure, mode queries, opt-in mode writes and the declared rumble commands. Payloads cannot be interleaved with polling; [TRANSACTIONS.md](TRANSACTIONS.md) documents integration and completion/error semantics.
- Bounded transaction waits, receive-index guard, abort priority, complete neutral values on disconnect and saturating/guarded polling calculations.
- SystemVerilog portability adjustments: explicit procedural output declarations, removal of a trailing concatenation comma, and if/else selection of enum values.

The implementation is in `rtl/llapi_enhanced.sv`. It retains Jamie Dickson's (Kitrinx) copyright notice and MIT license. Original references are preserved in `reference/`.

## Reproducible tests

Requirements: Python 3 and Icarus Verilog with SystemVerilog support.

```sh
bash tests/run.sh
```

Run from this directory. The script creates and removes a temporary directory.

1. `legacy_wire_tb.sv`: decodes commands on the wire, responds to poll/status requests, and checks the complete analog packet and transition to a digital controller. It explicitly models the legacy counters' power-up values.
2. `enhanced_reset_tb.sv`: checks the same inputs without forcing internal counters; during the second response, it verifies that partial bytes do not change the previously published state. It checks the new state after the complete response. The runner also tests all 12 nonempty truncated packet lengths (1–12 bytes), verifies that the incomplete reply does not replace the published snapshot, and checks recovery on a subsequent complete reply.

The reference test uses a temporary copy with three syntax normalizations for Icarus; the stored reference remains unchanged. The legacy reference still emits inherited always_comb warnings; the Enhanced output combinational block uses blocking assignments. Passing simulation does not establish Quartus timing closure or hardware operation.

A dedicated `stuck_leadin_tb.sv` test covers a device holding latch and data low, timeout, neutral controls, no transmissions while blocked, rejection of one-line-only releases and short release glitches, and successful reception after a stable release. This does not establish recovery from every possible stuck-line condition.

## Reference documentation

- [Bliss-Box protocol](https://bliss-box.com/pages/integration)
- [Bliss-Box downloads and firmware](https://bliss-box.com/pages/downloads)
- [Public LLAPI firmware example](https://github.com/ulao/Bliss-Box-LLAPI), audited reference abdb246195d5d089b6fd968ebb98aa86ce3c6a70. This is partial and does not include the motor backend.
- Preserved driver reference: `reference/SNES_MiSTer-a922e326-llapi.sv`.

## Future shared LLAPI/SNAC integration

LLAPI and SNAC must never operate simultaneously. A future shared integration module must select one mode, release the previous interface before enabling the next, and prevent both interfaces from driving the pins together. This is a design requirement, not an implemented SNAC feature of the current driver.

Each core must expose only SNAC controller types with enough buttons and the capabilities required by the game, including Start, credits, player count and peripherals. A six-button game must not offer NES or three-button Mega Drive controllers.

## Distribution

LLAPI Enhanced cores initially belong in `_LLAPI/_Experimental`, with Enhanced identification and hardware/RAM requirements in their names. Filenames do not repeat Experimental. The final 1943/1944 releases use the legacy LLAPI implementation, have been approved through user testing, and remain final.

## Progress tracking

Progress, tests and limitations are recorded in [CHANGELOG.md](CHANGELOG.md). Project documentation is maintained in English.

Local additional coverage: `PRESSURE_FAULTS=1` tests all12 nonempty incomplete pressure replies. Each must report timeout with no partial reply, preserve ordinary controller inputs, and recover with all13 bytes correct on the next request. This extends test coverage; no driver change or hardware claim.
