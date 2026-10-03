#include "Random.h"
#include <stdlib.h>
#include <time.h>
#include <stdint.h>

static uint64_t current_seed = 0;

int64_t ko_random_int(void) {
    if (current_seed == 0) {
        current_seed = (uint64_t)time(NULL);
    }
    current_seed = current_seed * 6364136223846793005ULL + 1;
    return (int64_t)(current_seed >> 32);
}

double ko_random_float(void) {
    return (double)ko_random_int() / ((double)((1ULL << 32) - 1));
}

void ko_random_seed(int64_t seed) {
    current_seed = (uint64_t)seed;
}

void ko_random_bytes(uint8_t *buf, size_t len) {
    for (size_t i = 0; i < len; i++) {
        buf[i] = (uint8_t)(ko_random_int() & 0xFF);
    }
}