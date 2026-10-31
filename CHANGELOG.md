# BlisSTer LLAPI Enhanced changelog

## 2026-10-31 — initial foundation

- Added an isolated legacy protocol test; polling, analog status and transition to a digital controller pass simulation.
- Added LLAPI_Enhanced with deterministic reset. Reception passes without forced internal initialization in the testbench.
- Added pending state to publish controller type, buttons and axes together after a complete packet; the test verifies that partial replies do not update the published snapshot.
- Preserved original references and the MIT license. No firmware changes or core integrations have been published.
- Published the initial source, tests and documentation in the public RetroShopPT/BlisSTer-LLAPI-Enhanced repository. All eight files were verified against a public download, and both protocol simulations passed from that download.
- Translated the README and changelog into English; English is the documentation language for this project.
- Pending: modes, errors, truncated replies, reconnection, timeouts, optional transactions, resource measurements, Quartus validation and hardware testing.
