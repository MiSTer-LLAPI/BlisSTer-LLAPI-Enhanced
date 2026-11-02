# BlisSTer LLAPI Enhanced

Improving LLAPI integration between MiSTer cores and BlisSTer. The LLAPI protocol is not exclusive to BlisSTer; this project focuses on that hardware and its two LLAPI ports. Status: experimental. The earlier driver revision is integrated in the published 1944 Enhanced v0.2.0; the storage optimizations below require validation in each target core. Full hardware validation remains pending.

## Versions

Current driver source: [v0.1.0](https://github.com/MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced/releases/tag/v0.1.0). See [all versions and differences](VERSIONS.md) for historical snapshots, exact commits/checksums, validation and core-update impact. Driver versions are independent of arcade/core release numbers.

## What has improved

Enhanced adds a more compact internal implementation, stronger error handling and usable interfaces for functionality that was declared or partially implemented in the preserved original driver. It builds on Kitrinx's existing controller-input support:

- **More compact internal logic:** narrower bounded counters and removal of redundant pending button/axis registers reduce explicit state storage while preserving coherent controller readings. FPGA savings must be measured per core; this is not a claim that Enhanced is smaller than the original driver with fewer features.
- **Extended functionality:** automatic controller-mode queries and an optional atomic interface make pressure and rumble commands available to integrating cores, subject to adapter/controller support. Mode writes remain disabled by default.
- **Consistent controller readings:** buttons and sticks are updated together only after a complete reply has arrived. An incomplete reply cannot overwrite part of the previous reading.
- **Better handling of connection problems:** bounded waits prevent the driver from waiting forever in the tested failure cases. When a connection is lost, controls are cleared to reduce the risk of stuck inputs.
- **Controller changes and reconnection:** the driver queries the controller modes again after reconnecting or detecting a different controller type, instead of keeping stale settings.
- **Pressure and rumble commands:** previously declared functionality is connected to an optional interface that a core can use to request button pressure or send rumble commands, where supported. Each core must still integrate these features.
- **More reliable reply synchronization:** a byte-alignment problem found with slightly slower simulated replies has been corrected. This is not a guarantee of compatibility with every physical device.

These changes use the existing LLAPI protocol and do not introduce a requirement to flash new BlisSTer firmware. Compatibility with real devices still needs physical testing.

The regression runner covers incomplete packets, interrupted command payloads, controller changes, reply timing variation and a prolonged stuck-bus wait. Recovery fixtures that reset the modeled adapter parser do not prove real firmware recovery or motor stop.

The driver now uses bounded counter widths and decodes the receive buffer without redundant pending button/axis registers. Public outputs still update together only after a complete packet. These changes preserve the existing ports, protocol and default settings; they do not promise a universal FPGA saving or lower latency. The PSX Single RAM candidate still exceeds device capacity (4197 LABs required, 4191 available), so it has no accepted Enhanced RBF or final timing result.

1944 Enhanced v0.2.0 was compiled with positive timing using the earlier driver revision. A user-reported player-two problem remains under investigation; this driver update is not a demonstrated fix. 1943's baseline compilation passed, while additional core features remain separate work. Physical pressure/rumble behavior and firmware recovery are still unverified.

## Kitrinx's original driver and Enhanced

Kitrinx's driver already provided the essential controller connection: it read buttons, the D-pad and analog values, identified the controller type, and scheduled regular reads. Enhanced builds on that work.

| Feature | Kitrinx's original driver | Enhanced |
| --- | --- | --- |
| Read buttons and sticks | Already supported. | Keeps this support. |
| Identify the controller | Already reported the controller type. | Keeps it and refreshes mode information when the type changes. |
| Keep readings together | Controller type and controls could update at different points in a reply. | Updates them together after a complete reply. |
| Handle connection problems | Already had basic timeout and input-clearing logic. | Adds safeguards for more failure cases, including a device holding the connection busy. |
| Start from a known state | Cleared controls when disabled, but did not reset all internal counters. | Resets the internal state as well. |
| Read controller modes | Some mode-reading code was present, but the normal reading sequence did not activate it. | Automatically requests modes on connection or controller change, with a fallback if unavailable. |
| Pressure and rumble | Command names were listed, but there was no usable interface for a core to request them. | Adds an optional interface for cores to request pressure readings and send rumble commands. Actual support depends on the controller and adapter. |
| Read replies reliably | Already handled the LLAPI signal and byte timing. | Fixes a reply-alignment issue reproduced with slightly slower simulated replies. |
| Internal storage | Original implementation provides the baseline functionality. | Recent Enhanced revisions narrow bounded counters and remove redundant snapshot storage. Extra features can still make the complete driver larger than the original. |
| Response speed and FPGA footprint | Comparison requires equivalent core features and build settings. | Lower physical input latency has not been demonstrated. Core resource measurements are tracked separately; storage optimization is not a speed claim. |

This comparison refers to the [preserved Kitrinx driver](reference/SNES_MiSTer-a922e326-llapi.sv), not every LLAPI version or core. These driver changes are tested in simulation; each core integration needs its own FPGA timing and hardware validation. Sending a rumble command is not proof that a physical motor works correctly.

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

Enhanced arcade launchers use `_LLAPI Enhanced/_Arcade` and the name `core-LLAPI-SNAC`; core binaries are stored under `_LLAPI Enhanced/cores`. Releases remain experimental until validated. Hardware/RAM requirements must be explicit where applicable. The final 1943/1944 releases use the legacy LLAPI implementation, have been approved through user testing, and remain final.

## Progress tracking

Progress, tests and limitations are recorded in [CHANGELOG.md](CHANGELOG.md). Project documentation is maintained in English.

Additional regression coverage: `PRESSURE_FAULTS=1` tests all12 nonempty incomplete pressure replies. Each must report timeout with no partial reply, preserve ordinary controller inputs, and recover with all13 bytes correct on the next request. This extends test coverage; no driver change or hardware claim.

## Updating integrations

The storage optimization is an optional maintenance update for existing cores, not a mandatory protocol or firmware migration. Keep each release pinned to its exact driver commit. Plan and test updates individually: 1944 Enhanced v0.2.0 and the verified 1943 baseline retain the earlier driver; the PSX candidate already contains these optimizations but does not fit. Existing published PSX Diagnostic/Dual builds remain unchanged. Menus, autofire, SNAC routing, controller guides and pause effects belong to the core integration, not this transport driver. Do not add optional FPGA logic to constrained cores without available capacity and passing timing.

## Disconnect handling: driver and core responsibilities

The transport driver handles polling, complete replies, timeout/error recovery and reported link/controller state. Loss of communication is not proof of physical unplug: adapter reset, firmware behavior, wiring or a transient fault may also cause it. A host-requested transport disable (for example while OSD is open) must not be classified as unplug.

The integrating core owns gameplay policy: neutral controls, clearing the affected player's latched autofire, optional pause on qualified loss, pause reason and user confirmation before resuming. It must preserve the other player's connection. Core logic must not reset the game when rediscovering a controller. Rediscovery/reset is per port and must use the driver's supported interface; it does not imply a hardware reset command was sent to the adapter or gamepad.

SNAC readers must provide their own protocol-specific validity. Do not infer disconnect from no buttons pressed. When a reader cannot reliably distinguish an idle controller from an absent one, automatic disconnect pause is unavailable and manual pause remains necessary.

### Reuse and validation checklist

- Pin driver version, commit and file hash in each core release.
- Validate A-only, B-only and both ports; distinct simultaneous input; disconnect either port while preserving the other; adapter reset; reconnect with a different controller type.
- Test unused ports, transient communication loss, intentional polling suspension/OSD, interface changes and manual pause interaction.
- Clear stale buttons/autofire on loss; qualify loss only after a previously valid connection; do not resume gameplay automatically on reconnection.
- Keep transport recovery, reusable pause policy and game-specific UI/routing separate. Reuse tested modules rather than independent copies with undocumented differences.
- Use the official Main interface only. Validate simulation, per-core Quartus fit/timing/resources and hardware separately.

Current development status (2026-11-02): the 1943 candidate contains a standalone controller-loss pause policy fixture. Its simulated tests pass, but it is NOT yet connected to the core pause path or driver rediscovery. This is not a released driver feature or a completed core feature. The reported physical 1943 port-B failure remains unresolved. Reuse requires integration tests in each core; no previously released core is silently updated.

Development policy: neutralize invalid inputs immediately, but request pause only after 2000 consecutive millisecond loss ticks. Recovery before the threshold cancels pending pause; reconnection after pause requires explicit resume. The standalone policy tests pass; a real millisecond timebase and core integration remain pending.


### v0.2.0-dev telemetry (not yet released)

`STATUS_VALID` qualifies the last complete controller snapshot; `STATUS_UPDATE`
is a one-cycle publication event; `LINK_FAULT` is a one-cycle transport/status
failure event. They do not distinguish a physically removed controller from an
unresponsive adapter. Keep the two-second loss filter and manual-resume policy
in the core. Ignore intentional interface disable and OSD suspension. An
auxiliary-command fault alone must not cause a disconnect pause.

Use ENABLE low for at least one CLK_50M edge to reset only the affected driver
instance, then re-enable it for normal discovery. This does not reset BlisSTer
firmware or guarantee physical motor stop. Same-type reconnect already refreshes
modes after observed link loss. Each port must remain independently instantiated.

No default diagnostic counters were added. Consumers that do not connect the
new outputs can allow synthesis to remove their logic. New resource/timing
measurements are pending; no lower physical latency is claimed.


### Change-recording policy

Every driver code change must be recorded in this GitHub repository with its
source, regression tests, changelog, version identifier and validation limits.
Core releases pin the exact driver revision and hash. Development versions must
remain clearly distinguished from tagged releases and hardware validation.
