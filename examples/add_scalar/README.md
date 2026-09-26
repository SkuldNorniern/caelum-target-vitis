# add_scalar

Vitis RTL kernel written in Caelum: `dst[i] = src[i] + k` for `i < n`, 32-bit words, one word at a time. Small on purpose, it shows the kernel interface and the flow, not speed.

```text
src/top.cael     the kernel (AddScalar): ap_ctrl_hs control slave + one m_axi port gmem
kernel.xml       kernel name, ports, args and their register offsets
u50.cfg          v++ connectivity (gmem -> HBM[0]) and clock
host/main.cpp    XRT host, checks every word
sim/             same kernel in the Caelum simulator with a fake host and memory, no Vitis needed
```

register map (`s_axi_control`):

| offset | |
|--------|---|
| 0x00 | bit 0 ap_start, 1 ap_done (clears on read), 2 ap_idle, 3 ap_ready |
| 0x04 | GIE |
| 0x08 | IER, bit 0 done, bit 1 ready |
| 0x0c | ISR, write 1 to toggle |
| 0x10 | n |
| 0x18 / 0x1c | src low / high |
| 0x24 / 0x28 | dst low / high |
| 0x30 | k |

```bash
caelum check
cd sim && cargo run --release              # sim, runs anywhere

caelum build --target u50-emu              # xo, xclbin, host (Linux, Vitis + XRT)
caelum run --target u50-emu
caelum build --target u50 --mode hw        # bitstream, hours
```

`vitis` points at this repo (`path = "../.."`), in your own project use the git url.
