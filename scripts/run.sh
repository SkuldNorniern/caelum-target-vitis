#!/bin/sh
# caelum run --target <t> --mode hw_emu|hw: the host program with the xclbin.
# target option args: extra arguments for the host program.
set -eu
out=$CAELUM_OUT_DIR
[ -x "$out/host" ] || { echo "vitis: no host program in $out, set host = \"...\" and run caelum build --target first" >&2; exit 1; }
[ -f "$out/kernel.xclbin" ] || { echo "vitis: no kernel.xclbin in $out, run caelum build --target first" >&2; exit 1; }
cd "$out"
if [ "$CAELUM_MODE" = hw_emu ]; then
  export XCL_EMULATION_MODE=hw_emu
fi
# shellcheck disable=SC2086
exec ./host "$out/kernel.xclbin" ${CAELUM_OPT_ARGS:-}
