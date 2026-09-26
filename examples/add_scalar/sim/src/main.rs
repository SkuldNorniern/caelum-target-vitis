// AddScalar in the Caelum simulator, against an XRT-like host and a one-word-at-a-time memory.
// cargo run --release
use std::collections::HashMap;

use caelum::interp::Sim;

type Io = HashMap<String, u64>;

struct Tb<'m> {
    sim: Sim<'m>,
    ins: Io,
    mem: HashMap<u64, u32>,
    // memory side
    rd_pending: Option<u64>,
    wr_addr: Option<u64>,
    wr_data: Option<u32>,
    b_pending: bool,
    cycles: u64,
}

impl<'m> Tb<'m> {
    fn set(&mut self, k: &str, v: u64) {
        self.ins.insert(k.to_string(), v);
    }

    /// One clock: comb outputs before the edge, then the edge. Returns the pre-edge outputs.
    fn tick(&mut self) -> Io {
        // memory drives its side from its own state
        self.set("gmem_arready", self.rd_pending.is_none() as u64);
        self.set("gmem_rvalid", self.rd_pending.is_some() as u64);
        let rdata = self.rd_pending.map(|a| *self.mem.get(&a).unwrap_or(&0)).unwrap_or(0);
        self.set("gmem_rdata", rdata as u64);
        self.set("gmem_rlast", 1);
        self.set("gmem_awready", self.wr_addr.is_none() as u64);
        self.set("gmem_wready", self.wr_data.is_none() as u64);
        self.set("gmem_bvalid", self.b_pending as u64);

        let mut pre_in = self.ins.clone();
        pre_in.insert("ap_clk".into(), 0);
        let o = self.sim.step(&pre_in);
        let mut clk_in = self.ins.clone();
        clk_in.insert("ap_clk".into(), 1);
        self.sim.step(&clk_in);
        self.cycles += 1;

        // memory handshakes seen at this edge
        if self.rd_pending.is_some() && o["gmem_rready"] == 1 {
            self.rd_pending = None;
        } else if self.rd_pending.is_none() && o["gmem_arvalid"] == 1 {
            assert_eq!(o["gmem_arlen"], 0);
            self.rd_pending = Some(o["gmem_araddr"]);
        }
        if self.b_pending && o["gmem_bready"] == 1 {
            self.b_pending = false;
        }
        if self.wr_addr.is_none() && o["gmem_awvalid"] == 1 {
            self.wr_addr = Some(o["gmem_awaddr"]);
        }
        if self.wr_data.is_none() && o["gmem_wvalid"] == 1 {
            assert_eq!(o["gmem_wlast"], 1);
            assert_eq!(o["gmem_wstrb"], 0xf);
            self.wr_data = Some(o["gmem_wdata"] as u32);
        }
        if let (Some(a), Some(d)) = (self.wr_addr, self.wr_data) {
            if !self.b_pending {
                self.mem.insert(a, d);
                self.wr_addr = None;
                self.wr_data = None;
                self.b_pending = true;
            }
        }
        o
    }

    fn write(&mut self, addr: u64, data: u32) {
        self.set("s_axi_control_awvalid", 1);
        self.set("s_axi_control_awaddr", addr);
        self.set("s_axi_control_wvalid", 1);
        self.set("s_axi_control_wdata", data as u64);
        self.set("s_axi_control_wstrb", 0xf);
        loop {
            let o = self.tick();
            if o["s_axi_control_awready"] == 1 {
                assert_eq!(o["s_axi_control_wready"], 1);
                break;
            }
        }
        self.set("s_axi_control_awvalid", 0);
        self.set("s_axi_control_wvalid", 0);
        self.set("s_axi_control_bready", 1);
        loop {
            let o = self.tick();
            if o["s_axi_control_bvalid"] == 1 {
                assert_eq!(o["s_axi_control_bresp"], 0);
                break;
            }
        }
        self.set("s_axi_control_bready", 0);
    }

    fn read(&mut self, addr: u64) -> u32 {
        self.set("s_axi_control_arvalid", 1);
        self.set("s_axi_control_araddr", addr);
        loop {
            if self.tick()["s_axi_control_arready"] == 1 {
                break;
            }
        }
        self.set("s_axi_control_arvalid", 0);
        self.set("s_axi_control_rready", 1);
        let v = loop {
            let o = self.tick();
            if o["s_axi_control_rvalid"] == 1 {
                break o["s_axi_control_rdata"] as u32;
            }
        };
        self.set("s_axi_control_rready", 0);
        v
    }
}

fn run(tb: &mut Tb, n: u32, src: u64, dst: u64, k: u32) {
    tb.write(0x10, n);
    tb.write(0x18, src as u32);
    tb.write(0x1c, (src >> 32) as u32);
    tb.write(0x24, dst as u32);
    tb.write(0x28, (dst >> 32) as u32);
    tb.write(0x30, k);
    assert_eq!(tb.read(0x1c), (src >> 32) as u32);
    assert_eq!(tb.read(0x24), dst as u32);
    let ctrl = tb.read(0x00);
    assert_eq!(ctrl & 0x5, 0x4, "idle, not started: {ctrl:#x}");
    tb.write(0x00, 1);
    let start = tb.cycles;
    loop {
        let c = tb.read(0x00);
        if c & 0x2 != 0 {
            assert_eq!(c & 0x1, 0, "ap_start still up with ap_done");
            break;
        }
        assert!(tb.cycles - start < 100_000, "timeout");
    }
    // ap_done clears on read
    assert_eq!(tb.read(0x00) & 0x2, 0);
    assert_eq!(tb.read(0x00) & 0x4, 0x4);
}

fn main() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../src/top.cael");
    let module = caelum::loader::load_module(path).expect("load");
    caelum::sema::check_module(&module).expect("check");
    let sim = Sim::new(&module, &HashMap::new());
    let mut tb = Tb {
        sim,
        ins: HashMap::new(),
        mem: HashMap::new(),
        rd_pending: None,
        wr_addr: None,
        wr_data: None,
        b_pending: false,
        cycles: 0,
    };
    for p in [
        "s_axi_control_awvalid", "s_axi_control_awaddr", "s_axi_control_wvalid", "s_axi_control_wdata",
        "s_axi_control_wstrb", "s_axi_control_bready", "s_axi_control_arvalid", "s_axi_control_araddr",
        "s_axi_control_rready",
    ] {
        tb.set(p, 0);
    }
    tb.set("ap_rst_n", 0);
    tb.tick();
    tb.tick();
    tb.set("ap_rst_n", 1);

    let src = 0x1_0000_1000u64;
    let dst = 0x2_0000_4000u64;
    for i in 0..64u64 {
        tb.mem.insert(src + 4 * i, (i as u32).wrapping_mul(0x0101_0101) ^ 0xdead_0000);
    }
    run(&mut tb, 64, src, dst, 0xffff_fff0);
    for i in 0..64u64 {
        let want = ((i as u32).wrapping_mul(0x0101_0101) ^ 0xdead_0000).wrapping_add(0xffff_fff0);
        assert_eq!(tb.mem.get(&(dst + 4 * i)), Some(&want), "word {i}");
    }
    assert!(!tb.mem.contains_key(&(dst + 4 * 64)));
    println!("n=64 ok, {} cycles", tb.cycles);

    // n = 0 finishes without touching memory, and a second run works after the first
    let before = tb.mem.len();
    run(&mut tb, 0, src, dst + 0x1000, 1);
    assert_eq!(tb.mem.len(), before);
    println!("n=0 ok");

    // interrupt: GIE + IER done, ISR toggles back on write
    tb.write(0x04, 1);
    tb.write(0x08, 1);
    run(&mut tb, 3, src, dst + 0x2000, 7);
    assert_eq!(tb.read(0x0c), 1);
    assert_eq!(tb.tick()["interrupt"], 1);
    tb.write(0x0c, 1);
    assert_eq!(tb.read(0x0c), 0);
    assert_eq!(tb.tick()["interrupt"], 0);
    assert_eq!(tb.mem[&(dst + 0x2000 + 8)], tb.mem[&(src + 8)] + 7);
    println!("interrupt ok");
}
