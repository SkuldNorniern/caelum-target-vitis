# caelum-target-vitis

Caelum target provider for AMD Vitis RTL kernels (Alveo and other Vitis platforms).

```text
caelum RTL (build/) -> Vivado IP packaging -> kernel.xo -> v++ link -> kernel.xclbin
                                                        -> emconfig.json (hw_emu)
host program (C++, XRT) -> host
```

modes: `hw_emu` (RTL simulation against the platform model, minutes) and `hw` (bitstream, hours).

## use

```toml
[target-dependencies]
vitis = { git = "https://github.com/SkuldNorniern/caelum-target-vitis" }
alveo = { git = "https://github.com/SkuldNorniern/caelum-platform-alveo" }

[target.u50]
provider = "vitis"
platform = "alveo::u50"
host = "host/main.cpp"
kernel-xml = "platform/kernel.xml"    # kernel name, args, AXI ports
config = "platform/u50.cfg"           # connectivity: nk=, sp=kernel_1.in:HBM[0:1] ...
rtl = "platform/rtl"                  # optional extra Verilog (AXI-Lite control block ...)

[target.u50-emu]
inherits = "u50"
mode = "hw_emu"
```

```bash
caelum build --target u50-emu            # xo, xclbin, emconfig.json, host in build/u50-emu/hw_emu/
caelum run --target u50-emu              # host with XCL_EMULATION_MODE=hw_emu
caelum build --target u50 --mode hw      # the real bitstream
caelum build --target u50 --dry-run      # environment and commands only
```

depends on [caelum-target-vivado](https://github.com/SkuldNorniern/caelum-target-vivado) for packaging (RTL collection and reading, the `vivado` tool check). it is downloaded with the rest on the first build; name `vivado` in your own `[target-dependencies]` to pin it.

needs Vitis and XRT on PATH (`source <vitis>/settings64.sh`, `source /opt/xilinx/xrt/setup.sh`). Linux only, like Vitis.

## kernel interface

the Caelum top has to look like a Vitis RTL kernel: `ap_clk`, `ap_rst_n`, an AXI4-Lite `s_axi_control` slave and one AXI4 master per memory port, named like the ports in `kernel.xml`. every port in `kernel.xml` gets associated with `ap_clk`.

working example with register map, host and a simulator test: [examples/add_scalar](examples/add_scalar).

## files

```text
provider.toml        modes, capabilities, tools, steps
scripts/build.sh     package, link, emconfig, host
scripts/run.sh       run the host program
tcl/gen_xo.tcl       IP packaging and package_xo, same flow as the Xilinx RTL kernel examples blueVitis uses
```
