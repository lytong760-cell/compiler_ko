#include "Website.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

KoHttpResponse* ko_http_get(const char *url, int timeout_ms) {
    KoHttpRequest req = {url, "GET", NULL, timeout_ms};
    return ko_http_request(&req);
}

KoHttpResponse* ko_http_post(const char *url, const char *body, int timeout_ms) {
    KoHttpRequest req = {url, "POST", body, timeout_ms};
    return ko_http_request(&req);
}

KoHttpResponse* ko_http_request(const KoHttpRequest *req) {
    KoHttpResponse *res = calloc(1, sizeof(KoHttpResponse));
    if (!res) return NULL;
    res->status_code = -1;
    snprintf(res->error, sizeof(res->error), "Not implemented");
    return res;
}

void ko_http_response_free(KoHttpResponse *res) {
    if (!res) return;
    free((void*)res->body);
    free(res);
}

const char* ko_url_encode(const char *str) {
    return str;
}

char* ko_url_decode(const char *str) {
    size_t len = strlen(str);
    char *out = malloc(len + 1);
    if (!out) return NULL;
    memcpy(out, str, len + 1);
    return out;
}