# add_scalar

Vitis RTL kernel in Caelum: `dst[i] = src[i] + k`, one 32-bit word at a time. Shows the interface and the flow, not speed.

```bash
caelum test                        # native sim, anywhere
caelum build --target u50-emu      # Linux with Vitis + XRT
caelum run --target u50-emu
```

`s_axi_control` registers:

| offset | |
|--------|---|
| 0x00 | bit 0 ap_start, 1 ap_done (clears on read), 2 ap_idle, 3 ap_ready |
| 0x04 / 0x08 / 0x0c | GIE / IER / ISR (write 1 toggles) |
| 0x10 | n |
| 0x18, 0x24 | src, dst (64-bit, low word first) |
| 0x30 | k |
