# caelum-target-vitis

AMD Vitis RTL kernels for Caelum: Verilog -> kernel.xo -> kernel.xclbin, and a host program with XRT. Modes `hw_emu`, `hw`. Packaging goes through [caelum-target-vivado](https://github.com/SkuldNorniern/caelum-target-vivado), pulled in on its own.

```toml
[target-dependencies]
vitis = { git = "https://github.com/SkuldNorniern/caelum-target-vitis" }
alveo = { git = "https://github.com/SkuldNorniern/caelum-platform-alveo" }

[target.u50]
provider = "vitis"
platform = "alveo::u50"
kernel-xml = "kernel.xml"   # kernel name, ports, arg offsets
config = "u50.cfg"          # v++ connectivity
host = "host/main.cpp"

[target.u50-emu]
inherits = "u50"
mode = "hw_emu"
```

```bash
caelum build --target u50-emu
caelum run --target u50-emu
```

the top must look like a Vitis RTL kernel: `ap_clk`, `ap_rst_n`, an `s_axi_control` AXI4-Lite slave, AXI4 masters named like the ports in kernel.xml. [examples/add_scalar](examples/add_scalar) is a full one with a `caelum test` bench.

needs Vitis and XRT (Linux).
