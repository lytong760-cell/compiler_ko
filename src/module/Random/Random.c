#include "Random.h"
#include <stdlib.h>
#include <time.h>

static int64_t current_seed = 0;

int64_t ko_random_int(void) {
    if (current_seed == 0) {
        current_seed = (int64_t)time(NULL);
    }
    current_seed = current_seed * 6364136223846793005ULL + 1;
    return (int64_t)(current_seed >> 32);
}

double ko_random_float(void) {
    return (double)ko_random_int() / (double)INT64_MAX;
}

void ko_random_seed(int64_t seed) {
    current_seed = seed;
}

void ko_random_bytes(uint8_t *buf, size_t len) {
    for (size_t i = 0; i < len; i++) {
        buf[i] = (uint8_t)(ko_random_int() & 0xFF);
    }
}