// host for AddScalar: dst[i] = src[i] + k
// ./host <kernel.xclbin> [n]
// hw_emu: XCL_EMULATION_MODE=hw_emu, emconfig.json next to the binary (caelum run does both)
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include <xrt/xrt_bo.h>
#include <xrt/xrt_device.h>
#include <xrt/xrt_kernel.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <kernel.xclbin> [n]\n", argv[0]);
        return 2;
    }
    const uint32_t n = argc > 2 ? std::strtoul(argv[2], nullptr, 0) : 1024;
    const uint32_t k = 0x1234;

    xrt::device device(0);
    auto uuid = device.load_xclbin(argv[1]);
    xrt::kernel kernel(device, uuid, "AddScalar");

    const size_t bytes = n * sizeof(uint32_t);
    xrt::bo src(device, bytes, kernel.group_id(1));
    xrt::bo dst(device, bytes, kernel.group_id(2));
    auto *in = src.map<uint32_t *>();
    auto *out = dst.map<uint32_t *>();
    for (uint32_t i = 0; i < n; i++) {
        in[i] = i * 0x01010101u;
        out[i] = 0;
    }
    src.sync(XCL_BO_SYNC_BO_TO_DEVICE);
    dst.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    auto run = kernel(n, src, dst, k);
    run.wait();

    dst.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    uint32_t bad = 0;
    for (uint32_t i = 0; i < n; i++) {
        if (out[i] != in[i] + k) {
            if (bad < 8)
                std::printf("dst[%u] = %#x, want %#x\n", i, out[i], in[i] + k);
            bad++;
        }
    }
    std::printf("%s: %u words, %u wrong\n", bad ? "FAIL" : "PASS", n, bad);
    return bad ? 1 : 0;
}
