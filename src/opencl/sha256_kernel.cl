/*
 * Developed by Claudio André <claudio.andre at correios.net.br> in 2012
 *
 * More information at http://openwall.info/wiki/john/OpenCL-RAWSHA-256
 *
 * Copyright (c) 2012 Claudio André <claudio.andre at correios.net.br>
 * This program comes with ABSOLUTELY NO WARRANTY; express or implied.
 *
 * This is free software, and you are welcome to redistribute it
 * under certain conditions; as expressed here
 * http://www.gnu.org/licenses/gpl-2.0.html
 */

#define _OPENCL_COMPILER
#include "opencl_rawsha256.h"

inline void init_ctx(sha256_ctx * ctx) {

    ctx->H[0] = H0;
    ctx->H[1] = H1;
    ctx->H[2] = H2;
    ctx->H[3] = H3;
    ctx->H[4] = H4;
    ctx->H[5] = H5;
    ctx->H[6] = H6;
    ctx->H[7] = H7;
}

inline void _memcpy(               uint8_t * dest,
                    __global const uint8_t * src) {

    uint32_t * l = (uint32_t *) dest;
    __global uint32_t * s = (__global uint32_t *) src;

    #pragma unroll
    for (int i = 0; i < PLAINTEXT_LENGTH; i += 4)
        *l++ = *s++;
}

inline void sha256_block(sha256_ctx * ctx) {
#define  a   ctx->H[0]
#define  b   ctx->H[1]
#define  c   ctx->H[2]
#define  d   ctx->H[3]
#define  e   ctx->H[4]
#define  f   ctx->H[5]
#define  g   ctx->H[6]
#define  h   ctx->H[7]
#define  w   ctx->buffer->mem_32

    uint32_t t1, t2;

    #pragma unroll
    for (int i = 0; i < 15; i++)
        w[i] = SWAP32(ctx->buffer->mem_32[i]);

    #pragma unroll
    for (int i = 0; i < 16; i++) {
        t1 = k[i] + w[i] + h + Sigma1(e) + Ch(e, f, g);
        t2 = Maj(a, b, c) + Sigma0(a);

        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    #pragma unroll
    for (int i = 16; i < 61; i++) {
        w[i & 15] = sigma1(w[(i - 2) & 15]) + sigma0(w[(i - 15) & 15]) + w[(i - 16) & 15] + w[(i - 7) & 15];
        t1 = k[i] + w[i & 15] + h + Sigma1(e) + Ch(e, f, g);
        t2 = Maj(a, b, c) + Sigma0(a);

        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }
}

inline void insert_to_buffer(         sha256_ctx    * ctx,
                             __global const uint8_t * string,
                                      const uint32_t  len) {

    _memcpy(ctx->buffer->mem_08, string);
    ctx->buflen = len;
}

inline void ctx_update(         sha256_ctx * ctx,
                       __global uint8_t    * string,
                                uint32_t     len) {

    insert_to_buffer(ctx, string, len);
}

inline void ctx_append_1(sha256_ctx * ctx) {

    uint32_t * l = ctx->buffer->mem_32 + PLAINTEXT_ARRAY;

    #pragma unroll
    for (int i = PLAINTEXT_LENGTH; i < 60; i += 4)
        *l++ = 0;
}

inline void ctx_add_length(sha256_ctx * ctx) {

    ctx->buffer[15].mem_32[0] = ctx->buflen * 8;
}

inline void finish_ctx(sha256_ctx * ctx) {

    ctx_append_1(ctx);
    ctx_add_length(ctx);
}

inline void sha256_crypt(__global sha256_password * keys_data,
                                  sha256_ctx      * ctx) {
#define pass        keys_data->pass->mem_08
#define passlen     keys_data->length

    init_ctx(ctx);

    ctx_update(ctx, pass, passlen);
    finish_ctx(ctx);

    /* Run the collected hash value through sha256. */
    sha256_block(ctx);
}

__kernel
void kernel_crypt(__global   sha256_password * keys_buffer,
                  __global   uint32_t        * out_buffer) {

    //Compute buffers (on CPU and NVIDIA, better private)
    sha256_ctx     ctx;

    //Get the task to be done
    size_t gid = get_global_id(0);

    //Do the job
    sha256_crypt(&keys_buffer[gid], &ctx);

    //Save parcial results.
    out_buffer[gid] = ctx.H[0];
}

__kernel
void kernel_cmp(__global   uint32_t        * partial_hash,
                __constant uint32_t        * partial_binary,
                __global   int             * result) {

    //Get the task to be done
    size_t gid = get_global_id(0);

    //Compare with partial computed hash.
    if (*partial_binary == partial_hash[gid]) {
        //Barrier point. FIX IT
        *result = 1;
    }
}