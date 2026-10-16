#!/bin/sh
# caelum build --target <t> --mode hw_emu|hw
#
# from caelum:    CAELUM_ROOT CAELUM_RTL_DIR CAELUM_OUT_DIR CAELUM_TOP CAELUM_MODE CAELUM_PROVIDER_DIR
#                 CAELUM_PROVIDER_VIVADO_DIR (provider dependency)
#                 CAELUM_PLATFORM_DIR VITIS_PLATFORM (platform [env]) CAELUM_HOST (target host =)
# target options: kernel-xml (required)   kernel description for package_xo
#                 config                  v++ --config with the connectivity (nk=, sp=), relative to the project
#                 rtl                     extra Verilog folder (AXI-Lite control block ...), relative to the project
#                 jobs                    Vivado jobs, default 8
set -eu

die() { echo "vitis: $*" >&2; exit 1; }
# stage <what> <log> <cmd...>: output stays on screen, a failure names the stage and its log
# (tools are checked by caelum from provider.toml)
stage() {
  what=$1
  log=$2
  shift 2
  "$@" && return 0
  status=$?
  die "$what failed (exit $status), log: $log"
}
# a platform without an installed shell (zynq) brings a recipe for one, built once into build/.platforms
if [ -z "${VITIS_PLATFORM:-}" ] && [ -n "${CAELUM_PLATFORM_DIR:-}" ] && [ -f "$CAELUM_PLATFORM_DIR/build_platform.sh" ]; then
  VITIS_PLATFORM=$(sh "$CAELUM_PLATFORM_DIR/build_platform.sh" "$CAELUM_RTL_DIR/.platforms" | tail -n 1) \
    || die "building the platform failed"
fi
[ -n "${VITIS_PLATFORM:-}" ] || die "no VITIS_PLATFORM: pick a platform (platform = \"alveo::u50\") or set it in [env]"
[ -n "${CAELUM_OPT_KERNEL_XML:-}" ] || die "set kernel-xml = \"<path>\" in the [target] table"

root=$CAELUM_ROOT
out=$CAELUM_OUT_DIR
kxml=$root/$CAELUM_OPT_KERNEL_XML
[ -f "$kxml" ] || die "kernel-xml not found: $kxml"
jobs=${CAELUM_OPT_JOBS:-8}

[ -n "${CAELUM_PROVIDER_VIVADO_DIR:-}" ] || die "no CAELUM_PROVIDER_VIVADO_DIR: vitis depends on caelum-target-vivado, update caelum"
sh "$CAELUM_PROVIDER_VIVADO_DIR/scripts/collect_rtl.sh" "$out/rtl"

echo "vitis: packaging $CAELUM_TOP -> kernel.xo"
stage "kernel packaging (vivado)" "$out/package.log" sh -c 'cd "$1" && shift && exec "$@"' _ "$out" \
    vivado -mode batch -nojournal -log package.log \
    -source "$CAELUM_PROVIDER_DIR/tcl/gen_xo.tcl" \
    -tclargs "$out/kernel.xo" "$CAELUM_TOP" "$kxml" "$out/rtl" "$out/packaged"

cfg=""
if [ -n "${CAELUM_PLATFORM_DIR:-}" ] && [ -f "$CAELUM_PLATFORM_DIR/platform.cfg" ]; then
  cfg="$cfg --config $CAELUM_PLATFORM_DIR/platform.cfg"
fi
if [ -n "${CAELUM_OPT_CONFIG:-}" ]; then
  cfg="$cfg --config $root/$CAELUM_OPT_CONFIG"
fi

echo "vitis: linking kernel.xclbin ($CAELUM_MODE, $VITIS_PLATFORM)"
# shellcheck disable=SC2086
# a platform's [env] VITIS_LINK_OPTS goes on the link line (zynq: --save-temps, to keep the .bit / .hwh)
# run in $out: v++ leaves analyzer_input / xcd.log / .Xil in its working directory
stage "v++ link" "$out/logs" sh -c 'cd "$1" && shift && exec "$@"' _ "$out" \
    v++ -l -t "$CAELUM_MODE" --platform "$VITIS_PLATFORM" $cfg ${VITIS_LINK_OPTS:-} \
    --vivado.param general.maxThreads="$jobs" --vivado.impl.jobs "$jobs" --vivado.synth.jobs "$jobs" \
    --temp_dir "$out/tmp" --log_dir "$out/logs" --report_dir "$out/reports" --report_level 2 \
    "$out/kernel.xo" -o "$out/kernel.xclbin"

if [ "$CAELUM_MODE" = hw_emu ]; then
  stage "emconfigutil" "(its output above)" sh -c 'cd "$1" && shift && exec "$@"' _ "$out" \
      emconfigutil --platform "$VITIS_PLATFORM" --od "$out" --nd 1
fi
if [ -n "${CAELUM_PLATFORM_DIR:-}" ] && [ -f "$CAELUM_PLATFORM_DIR/xrt.ini" ]; then
  cp "$CAELUM_PLATFORM_DIR/xrt.ini" "$out/"
fi

# summary.toml for caelum report: the whole linked design (shell + kernels), placed and routed
imp=$out/reports/link/imp
util=$(ls "$imp"/*_utilization_placed.rpt 2>/dev/null | grep -v full_util | head -n 1)
timing=$(ls "$imp"/*_timing_summary_routed.rpt 2>/dev/null | head -n 1)
if [ -n "$util" ]; then
  sh "$CAELUM_PROVIDER_VIVADO_DIR/scripts/summary.sh" "v++ link" "$util" "${timing:-}" "$out/summary.toml"
fi

# embedded platforms: the bitstream and .hwh out of the link too, what pynq.Overlay loads
# (the link project's, not the platform's copy under vpl/.local, which has no kernel in it)
prj=$out/tmp/link/vivado/vpl/prj
bit=$(ls "$prj"/prj.runs/impl_1/*.bit 2>/dev/null | head -n 1)
hwh=$(ls "$prj"/prj.gen/sources_1/bd/*/hw_handoff/*.hwh 2>/dev/null | head -n 1)
if [ -n "$bit" ] && [ -n "$hwh" ]; then
  cp "$bit" "$out/$CAELUM_TOP.bit"
  cp "$hwh" "$out/$CAELUM_TOP.hwh"
  echo "vitis: $CAELUM_TOP.bit + $CAELUM_TOP.hwh for PYNQ"
fi

# a platform run.sh runs the host on the board, the host doesn't build here
if [ -n "${CAELUM_HOST:-}" ] && [ -n "${CAELUM_PLATFORM_DIR:-}" ] && [ -f "$CAELUM_PLATFORM_DIR/run.sh" ]; then
  echo "vitis: done, $out"
  exit 0
fi
if [ -n "${CAELUM_HOST:-}" ]; then
  [ -n "${XILINX_XRT:-}" ] || die "host program needs XILINX_XRT (source /opt/xilinx/xrt/setup.sh)"
  echo "vitis: host $CAELUM_HOST"
  stage "host compile" "(its output above)" "${CXX:-g++}" -std=c++17 -O2 -g -Wall "$CAELUM_HOST" -I"$XILINX_XRT/include" -L"$XILINX_XRT/lib" \
      -lxrt_coreutil -pthread -o "$out/host"
fi
echo "vitis: done, $out"
