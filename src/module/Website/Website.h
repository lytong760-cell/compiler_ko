#ifndef KO_WEBSITE_H
#define KO_WEBSITE_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    const char *url;
    const char *method;
    const char *body;
    int timeout_ms;
} KoHttpRequest;

typedef struct {
    int status_code;
    const char *body;
    size_t body_len;
    char error[256];
} KoHttpResponse;

KoHttpResponse* ko_http_get(const char *url, int timeout_ms);
KoHttpResponse* ko_http_post(const char *url, const char *body, int timeout_ms);
KoHttpResponse* ko_http_request(const KoHttpRequest *req);
void ko_http_response_free(KoHttpResponse *res);
const char* ko_url_encode(const char *str);
char* ko_url_decode(const char *str);