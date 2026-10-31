#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
# Icarus rejects the upstream trailing concatenation comma accepted by Quartus.
# Normalize syntax in the temporary simulation copy only; preserve pinned source.
python3 - "$build/legacy.sv" <<'PYCODE'
from pathlib import Path
import sys
s=Path('reference/SNES_MiSTer-a922e326-llapi.sv').read_text()
assert s.count(", //R")==1
s=s.replace(", //R", " //R")
s=s.replace("output        IO_LATCH_OUT", "output reg    IO_LATCH_OUT").replace("output        IO_DATA_OUT", "output reg    IO_DATA_OUT")
s=s.replace("state <= (read_byte >= read_length) ? STATE_READ_END : STATE_READ;", "if (read_byte >= read_length) state <= STATE_READ_END; else state <= STATE_READ;")
Path(sys.argv[1]).write_text(s)
PYCODE
iverilog -g2012 -s legacy_wire_tb -o "$build/legacy" "$build/legacy.sv" tests/legacy_wire_tb.sv
vvp "$build/legacy"

# Exercise every nonempty truncated status-packet length, followed by recovery.
for truncated_bytes in 1 2 3 4 5 6 7 8 9 10 11 12; do
  iverilog -g2012 -s enhanced_reset_tb -Penhanced_reset_tb.TRUNCATE_BYTES="$truncated_bytes" -o "$build/enhanced" rtl/llapi_enhanced.sv tests/enhanced_reset_tb.sv
  vvp "$build/enhanced"
done

# Interrupt a bit before, near, and after the receiver's sampling window.
for abort_ticks in 50 160 165 170 220; do
  iverilog -g2012 -s enhanced_reset_tb -Penhanced_reset_tb.ABORT_TICKS="$abort_ticks" -o "$build/enhanced" rtl/llapi_enhanced.sv tests/enhanced_reset_tb.sv
  vvp "$build/enhanced"
done

iverilog -g2012 -s stuck_leadin_tb -o "$build/stuck" rtl/llapi_enhanced.sv tests/stuck_leadin_tb.sv
vvp "$build/stuck"
