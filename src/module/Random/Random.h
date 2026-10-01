#ifndef KO_RANDOM_H
#define KO_RANDOM_H

#include <stdint.h>
#include <stddef.h>

int64_t ko_random_int(void);
double ko_random_float(void);
void ko_random_seed(int64_t seed);
void ko_random_bytes(uint8_t *buf, size_t len);

#endif