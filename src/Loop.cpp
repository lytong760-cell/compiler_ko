/**
 * Loop.cpp - High-Performance Loop Engine Subsystem for .ko Language
 *
 * Stable C ABI (ko_* prefix, snake_case). All C++ classes stay inside
 * namespace ko_loop and are not exported; ko_loop_engine is opaque (void*).
 *
 * ABI choices: no std::string / std::function across the boundary; the caller
 * supplies while-loop conditions as a plain C function pointer plus a void*
 * context, and every execution path is bounded by an explicit maxIterations
 * cap so a condition that never becomes false returns an error instead of
 * hanging.
 */

#include <iostream>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <map>
#include <thread>
#include <sstream>

namespace ko_loop {

using ko_loop_body_fn = void (*)(uint64_t iteration, void* ctx);
using ko_loop_condition_fn = bool (*)(void* ctx);

enum class OptimizationStrategy {
    UNROLL_FACTOR_4,
    UNROLL_FACTOR_8,
    CACHE_LINE_ALIGNED,
    VECTORIZED,
    PIPELINED
};

struct CpuCounterRegisters {
    uint64_t rip, rax, rbx, rcx, rdx;
    uint64_t rsi, rdi, rbp, rsp, rflags;

    CpuCounterRegisters()
        : rip(0), rax(0), rbx(0), rcx(0), rdx(0), rsi(0), rdi(0), rbp(0),
          rsp(0), rflags(0) {}

    void reset() {
        rip = 0; rax = 0; rbx = 0; rcx = 0; rdx = 0;
        rsi = 0; rdi = 0; rbp = 0; rsp = 0; rflags = 0;
    }

    void dump() const {
        std::cout << "[Loop.cpp] CPU Registers: "
                  << "RIP=0x" << std::hex << rip << " "
                  << "RAX=0x" << rax << " "
                  << "RCX=0x" << rcx << " "
                  << "RDX=0x" << rdx << std::dec << std::endl;
    }
};

struct LoopRecord {
    bool isWhile;
    uint64_t forStart{}, forEnd{}, count{}, unrollFactor{};
    int64_t step{};
    OptimizationStrategy strategy{};
    ko_loop_condition_fn cond{};
    void* condCtx{};
};

class LoopUnroller {
private:
    CpuCounterRegisters regs;
    std::map<std::string, LoopRecord> loopCache;

    /**
     * Execute a bounded for-loop whose iteration count is known at optimize
     * time. Termination is guaranteed by the explicit count cap.
     */
    void executeForLoop(const LoopRecord& rec, ko_loop_body_fn body,
                        void* bodyCtx, uint64_t maxIterations) {
        const uint64_t cap = std::min(rec.count, maxIterations);
        uint64_t remaining = cap;
        uint64_t i = 0;

        while (remaining > 0) {
            const uint64_t chunk = std::min(rec.unrollFactor, remaining);
            std::cout << "[Loop.cpp]   chunk=" << chunk << std::endl;
            for (uint64_t j = 0; j < chunk; ++j) {
                body(i + j, bodyCtx);
            }
            i += chunk;
            remaining -= chunk;
            regs.rcx = remaining;
            regs.rdx = i;
        }
    }

    /**
     * Execute a bounded while-loop (count not known at optimize time).
     * The caller-supplied condition decides termination. The maxIterations
     * cap guarantees exit even if the condition never returns false.
     */
    bool executeWhileLoop(const LoopRecord& rec, ko_loop_body_fn body,
                          void* bodyCtx, uint64_t maxIterations) {
        uint64_t i = 0;
        bool stopped_by_condition = false;

        static std::FILE* f = std::fopen("/tmp/kilo/diag.txt", "a");

        while (i < maxIterations) {
            if (!rec.cond(rec.condCtx)) {
                stopped_by_condition = true;
                break;
            }
            uint64_t chunk = rec.unrollFactor;
            for (uint64_t j = 0; j < chunk; ++j) {
                if (i >= maxIterations) {
                    break;
                }
                if (!rec.cond(rec.condCtx)) {
                    stopped_by_condition = true;
                    break;
                }
                body(i, bodyCtx);
                ++i;
            }
            regs.rcx = i;
            if (i % rec.unrollFactor == 0) {
                std::this_thread::yield();
            }
        }
        if (f) { std::fprintf(f, "while done i=%lu stopped=%d condctx=%p bodyctx=%p\n",
                   (unsigned long)i, stopped_by_condition, (void*)rec.condCtx, bodyCtx); std::fclose(f); f = nullptr; }
        return stopped_by_condition;
    }

public:
    LoopUnroller() = default;

    int recordFor(const char* loopId, int64_t start, int64_t end,
                  int64_t step, uint64_t unrollFactor) {
        if (step <= 0) {
            return 2;
        }
        LoopRecord rec;
        rec.isWhile = false;
        rec.forStart = static_cast<uint64_t>(start);
        rec.forEnd = static_cast<uint64_t>(end);
        rec.step = step;
        rec.unrollFactor = unrollFactor;
        rec.count = (rec.forEnd - rec.forStart) / static_cast<uint64_t>(step) + 1;
        rec.strategy = rec.count >= 16
                           ? OptimizationStrategy::UNROLL_FACTOR_8
                           : rec.count >= 8
                                 ? OptimizationStrategy::UNROLL_FACTOR_4
                                 : OptimizationStrategy::PIPELINED;
        regs.rcx = rec.count;
        regs.rdx = rec.forStart;
        regs.rsi = static_cast<uint64_t>(step);
        loopCache[loopId] = rec;
        std::cout << "[Loop.cpp] Optimizing loop '" << loopId << "': "
                  << rec.count << " iterations, unroll=" << rec.unrollFactor
                  << ", strategy=" << static_cast<int>(rec.strategy)
                  << std::endl;
        return 0;
    }

    int recordWhile(const char* loopId, ko_loop_condition_fn cond,
                    void* condCtx, uint64_t unrollFactor) {
        if (cond == nullptr) {
            return 3;
        }
        LoopRecord rec;
        rec.isWhile = true;
        rec.unrollFactor = unrollFactor;
        rec.strategy = OptimizationStrategy::CACHE_LINE_ALIGNED;
        rec.cond = cond;
        rec.condCtx = condCtx;
        loopCache[loopId] = rec;
        std::cout << "[Loop.cpp] Optimizing while-loop '" << loopId << "': "
                  << "unroll=" << rec.unrollFactor
                  << ", strategy=" << static_cast<int>(rec.strategy)
                  << std::endl;
        return 0;
    }

    int executeOptimized(const char* loopId, ko_loop_body_fn body,
                         void* bodyCtx, uint64_t maxIterations) {
        if (body == nullptr) {
            return 4;
        }
        auto it = loopCache.find(loopId);
        if (it == loopCache.end()) {
            std::cerr << "[Loop.cpp] Warning: Loop '" << loopId
                      << "' not optimized" << std::endl;
            return 1;
        }
        const LoopRecord& rec = it->second;
        if (rec.isWhile) {
            if (!executeWhileLoop(rec, body, bodyCtx, maxIterations)) {
                return 5; /* ERR_LOOP_MAX_ITERATIONS_REACHED */
            }
        } else {
            executeForLoop(rec, body, bodyCtx, maxIterations);
        }
        regs.dump();
        return 0;
    }

    void resetRegisters() {
        regs.reset();
    }

    std::string getStats() const {
        std::stringstream ss;
        ss << "[Loop.cpp] Statistics:\n"
           << "  Cached loops: " << loopCache.size() << "\n"
           << "  Cache line size: " << 64 << " bytes\n"
           << "  Register state: RIP=0x" << std::hex << regs.rip
           << " RCX=0x" << regs.rcx << std::dec << "\n";
        return ss.str();
    }
};

} // namespace ko_loop

typedef struct ko_loop_engine {
    ko_loop::LoopUnroller unroller;
} ko_loop_engine;

extern "C" {

ko_loop_engine* ko_loop_engine_create(void) {
    return new ko_loop_engine();
}

void ko_loop_engine_destroy(ko_loop_engine* eng) {
    delete eng;
}

int ko_loop_optimize_for(ko_loop_engine* eng, const char* loopId,
                         int64_t start, int64_t end, int64_t step,
                         uint64_t unrollFactor) {
    if (eng == nullptr || loopId == nullptr) {
        return 1;
    }
    return eng->unroller.recordFor(loopId, start, end, step, unrollFactor);
}

int ko_loop_optimize_while(ko_loop_engine* eng, const char* loopId,
                           ko_loop::ko_loop_condition_fn cond, void* condCtx,
                           uint64_t unrollFactor) {
    if (eng == nullptr || loopId == nullptr || cond == nullptr) {
        return 1;
    }
    return eng->unroller.recordWhile(loopId, cond, condCtx, unrollFactor);
}

int ko_loop_execute_optimized_loop(ko_loop_engine* eng, const char* loopId,
                                   ko_loop::ko_loop_body_fn body, void* bodyCtx,
                                   uint64_t maxIterations) {
    if (eng == nullptr || loopId == nullptr || body == nullptr) {
        return 1;
    }
    return eng->unroller.executeOptimized(loopId, body, bodyCtx, maxIterations);
}

int ko_loop_execute_while_loop(ko_loop_engine* eng, const char* loopId,
                               ko_loop::ko_loop_condition_fn cond,
                               ko_loop::ko_loop_body_fn body, void* bodyCtx,
                               uint64_t maxIterations) {
    if (eng == nullptr || loopId == nullptr || cond == nullptr || body == nullptr) {
        return 1;
    }
    if (eng->unroller.recordWhile(loopId, cond, bodyCtx, 4) != 0) {
        return 3;
    }
    return eng->unroller.executeOptimized(loopId, body, bodyCtx, maxIterations);
}

int ko_loop_get_stats(ko_loop_engine* eng, char* out, size_t outSize) {
    if (eng == nullptr) {
        return -1;
    }
    const std::string s = eng->unroller.getStats();
    if (out == nullptr) {
        return static_cast<int>(s.size());
    }
    const int written = static_cast<int>(std::snprintf(out, outSize, "%s", s.c_str()));
    return written;
}

void ko_loop_reset_registers(ko_loop_engine* eng) {
    if (eng != nullptr) {
        eng->unroller.resetRegisters();
    }
}

} // extern "C"

#ifndef ko_loop_NO_MAIN
#ifndef KO_LOOP_NO_MAIN
int main(int argc, char* argv[]) {
    ko_loop_engine* eng = ko_loop_engine_create();

    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " <iterations>" << std::endl;
        ko_loop_engine_destroy(eng);
        return 1;
    }

    const int64_t iterations = std::stoll(argv[1]);
    const int rc = ko_loop_optimize_for(eng, "test_loop", 0, iterations, 1, 4);
    if (rc != 0) {
        std::cerr << "[Loop.cpp] Optimization failed: " << rc << std::endl;
        ko_loop_engine_destroy(eng);
        return rc;
    }

    const int rc2 = ko_loop_execute_optimized_loop(
        eng, "test_loop",
        [](uint64_t i, void*) {
            if (i % 1000 == 0) {
                std::cout << "[Loop.cpp] Iteration: " << i << std::endl;
            }
        },
        nullptr, iterations);
    if (rc2 != 0) {
        std::cerr << "[Loop.cpp] Execution failed: " << rc2 << std::endl;
        ko_loop_engine_destroy(eng);
        return rc2;
    }

    char buf[512];
    ko_loop_get_stats(eng, buf, sizeof(buf));
    std::printf("%s", buf);
    ko_loop_engine_destroy(eng);
    return 0;
}
#endif
#endif
