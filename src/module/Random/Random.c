#include "Random.h"
#include <stdlib.h>
#include <time.h>
#include <stdint.h>
#include <stdatomic.h>

static _Atomic uint64_t current_seed = 0;

int64_t ko_random_int(void) {
    uint64_t expected = atomic_load(&current_seed);

    // Phase 1: Ensure seed is initialized once (thread-safe)
    if (expected == 0) {
        if (atomic_compare_exchange_strong(&current_seed, &expected, (uint64_t)time(NULL))) {
            // This thread seeded it; expected is unchanged (still 0 by C11 spec),
            // so read the actual seeded value:
            expected = (uint64_t)time(NULL);
        } else {
            // Another thread seeded it first; expected now holds current value
            expected = atomic_load(&current_seed);
        }
    }

    // Phase 2: Compute next state and atomically update current_seed
    uint64_t next = expected * 6364136223846793005ULL + 1;
    uint64_t comp = expected;

    while (!atomic_compare_exchange_weak(&current_seed, &comp, next)) {
        // CAS failed: comp now holds current seed value
        next = comp * 6364136223846793005ULL + 1;
    }

    return (int64_t)(next >> 32);
}

double ko_random_float(void) {
    return (double)ko_random_int() / (double)(1ULL << 32);
}

void ko_random_seed(int64_t seed) {
    atomic_store(&current_seed, (uint64_t)seed);
}

void ko_random_bytes(int64_t length, uint8_t *buf) {
    if (length <= 0 || buf == NULL) {
        return;
    }
    for (int64_t i = 0; i < length; i++) {
        buf[i] = (uint8_t)(ko_random_int() & 0xFF);
    }
}