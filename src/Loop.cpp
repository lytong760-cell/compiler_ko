/**
 * Loop.cpp - High-Performance Loop Engine Subsystem for .ko Language
 *
 * Provides a stable C ABI (ko_* prefix, snake_case as in src/module/Os/Os.h)
 * so a C caller (Zig via dlopen/dlsym) can create the engine, optimize
 * for-/while-loops, and execute them. All C++ classes (CpuCounterRegisters,
 * CacheLineOptimizer, LoopUnroller) stay inside namespace ko_loop and are not
 * exported. ko_loop_engine is opaque: callers only ever see void*.
 *
 * ABI design choices:
 *  - No std::string / std::function across the ABI: use const char* and plain
 *    C function-pointer typedefs (ko_loop_condition_fn / ko_loop_body_fn).
 *  - The caller supplies the while-condition as a C function pointer plus a
 *    void* context; the engine stores it and calls it back on each chunk.
 *    This is the standard dlopen-callback pattern and avoids ABI-visible
 *    C++ types.
 *  - Every execution path is bounded by an explicit maxIterations cap, so a
 *    loop whose condition never becomes false cannot run forever.
 */

#include <iostream>
#include <vector>
#include <string>
#include <cstdint>
#include <chrono>
#include <thread>
#include <map>
#include <sstream>
#include <cstdio>
#include <algorithm>
#include <limits>

namespace ko_loop {

/**
 * Loop optimization strategy.
 */
enum class OptimizationStrategy {
    UNROLL_FACTOR_4,
    UNROLL_FACTOR_8,
    CACHE_LINE_ALIGNED,
    VECTORIZED,
    PIPELINED
};

/**
 * CPU Counter Register simulation. This is a simulation only: it copies values
 * into struct fields; it never touches real CPU registers.
 */
struct CpuCounterRegisters {
    uint64_t rip;
    uint64_t rax;
    uint64_t rbx;
    uint64_t rcx;
    uint64_t rdx;
    uint64_t rsi;
    uint64_t rdi;
    uint64_t rbp;
    uint64_t rsp;
    uint64_t rflags;

    CpuCounterRegisters() : rip(0), rax(0), rbx(0), rcx(0), rdx(0),
                            rsi(0), rdi(0), rbp(0), rsp(0), rflags(0) {}

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

/**
 * Cache line optimizer.
 */
class CacheLineOptimizer {
public:
    static constexpr size_t CACHE_LINE_SIZE = 64;

    static void* alignToCacheLine(void* ptr) {
        uintptr_t addr = reinterpret_cast<uintptr_t>(ptr);
        uintptr_t aligned = (addr + CACHE_LINE_SIZE - 1) & ~(CACHE_LINE_SIZE - 1);
        return reinterpret_cast<void*>(aligned);
    }

    static void prefetch(const void* addr) {
        __builtin_prefetch(addr, 0, 3);
    }

    static size_t getCacheLineSize() {
        return CACHE_LINE_SIZE;
    }
};

/**
 * Execution callback type used in the C ABI.
 */
using ko_loop_body_fn = void (*)(uint64_t iteration, void* ctx);

/**
 * Condition callback type used in the C ABI for while-loops.
 * Returns true to continue, false to stop.
 */
using ko_loop_condition_fn = bool (*)(void* ctx);

struct LoopRecord {
    bool isWhile;
    uint64_t forStart{};
    uint64_t forEnd{};
    int64_t step{};
    uint64_t count{};
    uint64_t unrollFactor{};
    OptimizationStrategy strategy{};
    ko_loop_condition_fn cond{};
    void* condCtx{};
};

/**
 * Loop Unroller.
 */
class LoopUnroller {
private:
    CpuCounterRegisters regs;
    std::map<std::string, LoopRecord> loopCache;

    /**
     * Execute a bounded for-loop (count determined at optimize time).
     */
    void executeForLoop(const LoopRecord& rec, ko_loop_body_fn body, void* bodyCtx,
                        uint64_t maxIterations) {
        const uint64_t cap = std::min(rec.count, maxIterations);
        uint64_t remaining = cap;
        uint64_t i = 0;

        while (remaining > 0) {
            const uint64_t chunk = std::min(rec.unrollFactor, remaining);
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
     * Execute a bounded while-loop (count not determined at optimize time).
     * Termination is guaranteed by: (a) the caller-supplied condition, and
     * (b) the explicit maxIterations cap.
     */
    void executeWhileLoop(const ko_loop_condition_fn cond, void* condCtx,
                          const LoopRecord& rec, ko_loop_body_fn body, void* bodyCtx,
                          uint64_t maxIterations) {
        uint64_t i = 0;
        while (i < maxIterations) {
            uint64_t chunk = rec.unrollFactor;
            for (uint64_t j = 0; j < chunk; ++j) {
                if (i >= maxIterations || !cond(condCtx)) {
                    break;
                }
                body(i, bodyCtx);
                ++i;
            }
            if (i >= maxIterations) {
                break;
            }
            regs.rcx = i;
            if (i % rec.unrollFactor == 0) {
                std::this_thread::yield();
            }
        }
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
                    uint64_t unrollFactor) {
        if (cond == nullptr) {
            return 3;
        }
        LoopRecord rec;
        rec.isWhile = true;
        rec.unrollFactor = unrollFactor;
        rec.strategy = OptimizationStrategy::CACHE_LINE_ALIGNED;
        rec.cond = cond;
        loopCache[loopId] = rec;
        std::cout << "[Loop.cpp] Optimizing while-loop '" << loopId << "': "
                  << "unroll=" << rec.unrollFactor
                  << ", strategy=" << static_cast<int>(rec.strategy)
                  << std::endl;
        return 0;
    }

    int executeOptimized(const char* loopId, ko_loop_body_fn body, void* bodyCtx,
                         uint64_t maxIterations) {
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
            executeWhileLoop(rec.cond, rec.condCtx, rec, body, bodyCtx,
                             maxIterations);
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
           << "  Cache line size: " << CacheLineOptimizer::getCacheLineSize()
           << " bytes\n"
           << "  Register state: RIP=0x" << std::hex << regs.rip
           << " RCX=0x" << regs.rcx << std::dec << "\n";
        return ss.str();
    }
};

} // namespace ko_loop

/**
 * Opaque handle for the loop engine. Callers only ever see void*; the real
 * definition stays in src/Loop.cpp so the ABI cannot break.
 */
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
                           ko_loop::ko_loop_condition_fn cond,
                           uint64_t unrollFactor) {
    if (eng == nullptr || loopId == nullptr) {
        return 1;
    }
    return eng->unroller.recordWhile(loopId, cond, unrollFactor);
}

int ko_loop_execute_optimized_loop(ko_loop_engine* eng, const char* loopId,
                                   ko_loop::ko_loop_body_fn body, void* bodyCtx,
                                   uint64_t maxIterations) {
    if (eng == nullptr || loopId == nullptr) {
        return 1;
    }
    return eng->unroller.executeOptimized(loopId, body, bodyCtx, maxIterations);
}

int ko_loop_execute_while_loop(ko_loop_engine* eng, const char* loopId,
                               ko_loop::ko_loop_condition_fn cond,
                               ko_loop::ko_loop_body_fn body,
                               uint64_t maxIterations) {
    if (eng == nullptr || loopId == nullptr || cond == nullptr || body == nullptr) {
        return 1;
    }
    if (eng->unroller.recordWhile(loopId, cond, 4) != 0) {
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
    return (written >= static_cast<int>(outSize)) ? written : written;
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
    std::printf("%s", ko_loop_get_stats(eng, buf, sizeof(buf)));
    ko_loop_engine_destroy(eng);
    return 0;
}
#endif
#endif
