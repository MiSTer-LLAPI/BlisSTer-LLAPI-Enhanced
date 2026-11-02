# BlisSTer LLAPI Enhanced changelog

## 2026-11-02 — storage optimization and expanded regression

- Narrow the serial count to its reachable range and size the saturating transaction timer from its timeout limits. Saturation is retained during prolonged WAIT_RELEASE; no wrapping timer is introduced.
- Decode pending buttons/axes directly from the stable receive buffer, retaining the atomic public-output commit after packet completion.
- Publish companion fault, payload and timing tests, including a wait longer than the former 21-bit timer range followed by recovery.
- Preserve API, polling policy, default automatic mode queries, default-disabled command interface/mode writes, MIT license and original credits. No firmware change required.
- Optional update for existing integrations; verify fit/timing and behavior per core. PSX Single RAM still fails fit at 4197/4191 LABs; no accepted Enhanced RBF or hardware result is claimed.
- Core-specific menu/autofire/SNAC fixes are not included in this driver. The reported 1944 P2 issue is not claimed fixed.

## 2026-10-31 — initial foundation

- Added an isolated legacy protocol test; polling, analog status and transition to a digital controller pass simulation.
- Added LLAPI_Enhanced with deterministic reset. Reception passes without forced internal initialization in the testbench.
- Added pending state to publish controller type, buttons and axes together after a complete packet; the test verifies that partial replies do not update the published snapshot.
- Preserved original references and the MIT license. No firmware changes or core integrations have been published.
- Published the initial source, tests and documentation in the public RetroShopPT/BlisSTer-LLAPI-Enhanced repository. All eight files were verified against a public download, and both protocol simulations passed from that download.
- Translated the README and changelog into English; English is the documentation language for this project.
- Added local simulation coverage for all 12 nonempty truncated status replies (1–12 bytes), snapshot preservation and recovery on the next complete reply; all passed. Five additional mid-bit interruption positions (50, 160, 165, 170 and 220 clock cycles into a bit) also pass snapshot preservation and subsequent recovery. Additional stuck-line cases remain pending.
- Recorded the mandatory mutual exclusion of LLAPI and SNAC for future shared integration; no SNAC module is implemented yet.
- Remaining validation: additional stuck-line/reconnection cases, resource measurements, Quartus and physical hardware.

### Receive-start recovery

- Initially reproduced a failure with `tests/stuck_leadin_tb.sv` (now included in the regression runner): a device holding both latch and data low before the receive lead-in leaves the driver in READ_START after 2 ms. This is a bounded-recovery test target, not a vendor timing requirement. Added a 1 ms receive-start timeout with neutral controls and a wait-for-release state. The focused test now passes through recovery after both lines are released. This limit requires hardware validation and does not yet cover every receive-state fault.

- Extended the timeout regression to reject release of only one input and a short simultaneous release glitch; complete recovery after stable release passes. No additional RTL change.

- Repository transferred to MiSTer-LLAPI/BlisSTer-LLAPI-Enhanced; the original author attribution and MIT license are preserved.

### Connected features and robustness

- Connected GET_MODES to the normal status sequence, once per connection/controller type, with validity and unsupported/silent fallback. Analog-to-direction conversion uses only valid modes belonging to the same controller type.
- Added an opt-in atomic request interface for pressure, mode queries, gated mode writes, and all declared rumble opcodes. Captures parameters and sends separate frames without interleaved polling; duration precedes level for rumble. One optional transaction per successful status prevents command starvation of inputs.
- Added adapter error replies and transport timeout/rejection results. Write completion does not claim device acknowledgement or physical effect.
- Guarded receive bounds and abort priority, polling subtraction/counter overflow, and full-width neutral disconnect state. Transaction deadlines use engineering limits requiring hardware validation.
- Added wire-level feature regression configurations and English integration documentation. No firmware, core RBF, independent-motor or hardware-success claim.

## Local follow-up — pressure response faults

- Added all12 incomplete pressure payload lengths, with ordinary input preservation and complete next-reply recovery checks.
- Fault suite and default feature regression pass. Driver unchanged; tests/docs not yet published.
- Priority: Enhanced robustness first, then I/O Tester; MT32-Pi deferred and SNAC optional afterward.

## Local follow-up — interrupted rumble parameter writes

- Added two blocked-bus cases between outgoing parameter frames, with single-error completion and no transmissions while blocked.
- Added nine ENABLE cancellations during opcode/duration/level frames and verified no stale replay.
- Explicit modeled adapter reset is required by recovery fixtures; physical parser recovery and motor behavior are not established.
- Driver RTL unchanged. New tests/docs remain local pending publication.

### Local controller mode lifecycle test

TYPE_RECONNECT checks query-once behavior, invalidation on controller replacement, a valid zero modes bitmap, and rediscovery after reconnecting the same controller type. Focused test and default feature regression pass; no RTL change or hardware proof.

### Receive byte synchronization

- Reproduced cumulative byte misalignment with simulated bit times 228 instead of224 clocks. Extended the inter-byte fallback wait and excluded early final-data-bit edges so the real synchronization edge can align each byte.
- Candidate passed all30 existing regression configurations, plus focused feature and 256-value payload probes at220 and228 clocks per bit. The runner now includes these four probes. These engineering variations do not establish vendor timing tolerance or physical hardware success.
- RTL published in commit `a318d7ea34d9c618c6780effc04d2faffd75015f`; the public download matches the tested source byte for byte. Companion expanded tests and documentation are awaiting publication.
- No transmit timing, firmware, or wire command changes. The local I/O Tester copy matches the corrected driver; both affected integration simulations passed, covering dual-driver snapshots, disconnect/reconnect isolation, enable/reset and pin release. Quartus, physical CDC and hardware validation remain pending.
