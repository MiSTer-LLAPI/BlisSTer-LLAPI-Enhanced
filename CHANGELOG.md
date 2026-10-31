# BlisSTer LLAPI Enhanced changelog

## 2026-10-31 — initial foundation

- Added an isolated legacy protocol test; polling, analog status and transition to a digital controller pass simulation.
- Added LLAPI_Enhanced with deterministic reset. Reception passes without forced internal initialization in the testbench.
- Added pending state to publish controller type, buttons and axes together after a complete packet; the test verifies that partial replies do not update the published snapshot.
- Preserved original references and the MIT license. No firmware changes or core integrations have been published.
- Published the initial source, tests and documentation in the public RetroShopPT/BlisSTer-LLAPI-Enhanced repository. All eight files were verified against a public download, and both protocol simulations passed from that download.
- Translated the README and changelog into English; English is the documentation language for this project.
- Added local simulation coverage for all 12 nonempty truncated status replies (1–12 bytes), snapshot preservation and recovery on the next complete reply; all passed. Five additional mid-bit interruption positions (50, 160, 165, 170 and 220 clock cycles into a bit) also pass snapshot preservation and subsequent recovery. Additional stuck-line cases remain pending.
- Recorded the mandatory mutual exclusion of LLAPI and SNAC for future shared integration; no SNAC module is implemented yet.
- Pending: modes, errors, additional stuck-line/reconnection cases, broader timeout coverage, optional transactions, resource measurements, Quartus validation and hardware testing.

### Receive-start recovery

- Initially reproduced a failure with `tests/stuck_leadin_tb.sv` (now included in the regression runner): a device holding both latch and data low before the receive lead-in leaves the driver in READ_START after 2 ms. This is a bounded-recovery test target, not a vendor timing requirement. Added a 1 ms receive-start timeout with neutral controls and a wait-for-release state. The focused test now passes through recovery after both lines are released. This limit requires hardware validation and does not yet cover every receive-state fault.

- Extended the timeout regression to reject release of only one input and a short simultaneous release glitch; complete recovery after stable release passes. No additional RTL change.

- Repository transferred to MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced; the original author attribution and MIT license are preserved.
