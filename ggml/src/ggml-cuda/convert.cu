//
// Copyright (C) 2023-2024 The ggml authors
// Copyright (C) 2024 Iwan Kawrakow
// MIT license
// SPDX-License-Identifier: MIT
//

#include "convert.cuh"
#include "dequantize.cuh"

#define CUDA_Q8_0_NE_ALIGN 2048

template <int qk, int qr, dequantize_kernel_t dequantize_kernel, typename dst_t>
static __global__ void dequantize_block(const void * __restrict__ vx, dst_t * __restrict__ y, const int64_t k) {
    const int64_t i = (int64_t)2*(blockDim.x*blockIdx.x + threadIdx.x);

    if (i >= k) {
        return;
    }

    const int64_t ib = i/qk; // block index
    const int64_t iqs = (i%qk)/qr; // quant index
    const int64_t iybs = i - i%qk; // y block start index
    const int64_t y_offset = qr == 1 ? 1 : qk/2;

    // dequantize
    dfloat2 v;
    dequantize_kernel(vx, ib, iqs, v);

    y[iybs + iqs + 0]        = v.x;
    y[iybs + iqs + y_offset] = v.y;
}

template <bool need_check>
static __global__ void dequantize_block_q8_0_f16(const void * __restrict__ vx, half * __restrict__ y, const int64_t k) {
#if __CUDA_ARCH__ >= CC_PASCAL
    constexpr int nint = CUDA_Q8_0_NE_ALIGN/sizeof(int) + WARP_SIZE;

    const int64_t   i0 = CUDA_Q8_0_NE_ALIGN*blockIdx.x;
    const int * x0 = ((int *) vx) + blockIdx.x * nint;
    half2 * y2 = (half2 *) (y + i0);

    __shared__ int vals[nint];

#pragma unroll
    for (int ix0 = 0; ix0 < nint; ix0 += WARP_SIZE) {
        if (need_check && i0*sizeof(block_q8_0)/QK8_0 + sizeof(int)*(ix0 + threadIdx.x) >= k*sizeof(block_q8_0)/QK8_0) {
            break;
        }

        const int ix = ix0 + threadIdx.x;
        vals[ix] = x0[ix];
    }

    __syncthreads();

#pragma unroll
    for (int iy = 0; iy < CUDA_Q8_0_NE_ALIGN; iy += 2*WARP_SIZE) {
        if (need_check && i0 + iy + 2*threadIdx.x >= k) {
            return;
        }

        const half * b0 = ((const half  *) vals) + (sizeof(block_q8_0)/sizeof(half)) * ((iy + 2*threadIdx.x)/QK8_0);
        const half    d = *b0;
        const char2  qs = ((const char2 *) (b0 + 1))[threadIdx.x % (QK8_0/2)];

        y2[iy/2 + threadIdx.x] = __hmul2(make_half2(qs.x, qs.y), __half2half2(d));
    }
#else
    GGML_UNUSED(vx);
    GGML_UNUSED(y);
    GGML_UNUSED(k);
    NO_DEVICE_CODE;
#endif // __CUDA_ARCH__ >= CC_PASCAL
}

template<typename dst_t>
static __global__ void dequantize_block_q4_0(const void * __restrict__ vx, dst_t * __restrict__ yy, int nb32) {

    const int64_t i = blockIdx.x;

    // assume 32 threads
    const int64_t tid = threadIdx.x;
    const int64_t il  = tid/8;
    const int64_t ir  = tid%8;
    const int64_t ib = 8*i + ir;
    if (ib >= nb32) {
        return;
    }

    dst_t * y = yy + 256*i + 32*ir + 4*il;

    const block_q4_0 * x = (const block_q4_0 *)vx + ib;
    const float d = __half2float(x->d);
    const float dm = -8*d;

    const uint8_t * q = x->qs + 4*il;

    for (int l = 0; l < 4; ++l) {
        y[l+ 0] = d * (q[l] & 0xF) + dm;
        y[l+16] = d * (q[l] >>  4) + dm;
    }
}

template<typename dst_t>
static __global__ void dequantize_block_q4_1(const void * __restrict__ vx, dst_t * __restrict__ yy, int nb32) {

    const int64_t i = blockIdx.x;

    // assume 32 threads
    const int64_t tid = threadIdx.x;
    const int64_t il  = tid/8;
    const int64_t ir  = tid%8;
    const int64_t ib = 8*i + ir;
    if (ib >= nb32) {
        return;
    }

    dst_t * y = yy + 256*i + 32*ir + 4*il;

    const block_q4_1 * x = (const block_q4_1 *)vx + ib;
    const float2 d = __half22float2(x->dm);

    const uint8_t * q = x->qs + 4*il;

    for (int l = 0; l < 4; ++l) {
        y[l+ 0] = d.x * (q[l] & 0xF) + d.y;
        y[l+16] = d.x * (q[l] >>  4) + d.y;
    }
}

template<typename dst_t>
static __global__ void dequantize_block_q6_0(const void * __restrict__ vx, dst_t * __restrict__ yy, int nb32) {

    const int64_t i = blockIdx.x;

    // assume 32 threads
    const int64_t tid = threadIdx.x;
    const int64_t il  = tid/8;
    const int64_t ir  = tid%8;
    const int64_t ib = 8*i + ir;
    if (ib >= nb32) {
        return;
    }

    dst_t * y = yy + 256*i + 32*ir + 4*il;

    const block_q6_0 * x = (const block_q6_0 *)vx + ib;
    const float d = __half2float(x->d);
    const float dm = -32*d;

    const uint8_t * qs = x->qs + 4*il;
    const uint8_t * qh = x->qh + 4*(il%2);

    for (int l = 0; l < 4; ++l) {
        const uint8_t h = qh[l] >> 4*(il/2);
        y[l+ 0] = d * ((qs[l] & 0xF) | ((h << 4) & 0x30)) + dm;
        y[l+16] = d * ((qs[l] >>  4) | ((h << 2) & 0x30)) + dm;
    }
}

//================================== k-quants

template<typename dst_t>
static __global__ void dequantize_block_q2_K(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_q2_K * x = (const block_q2_K *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t n   = tid/32;
    const int64_t l   = tid - 32*n;
    const int64_t is  = 8*n + l/16;

    const uint8_t q = x[i].qs[32*n + l];
    dst_t * y = yy + i*QK_K + 128*n;

    float dall = __low2half(x[i].dm);
    float dmin = __high2half(x[i].dm);
    y[l+ 0] = dall * (x[i].scales[is+0] & 0xF) * ((q >> 0) & 3) - dmin * (x[i].scales[is+0] >> 4);
    y[l+32] = dall * (x[i].scales[is+2] & 0xF) * ((q >> 2) & 3) - dmin * (x[i].scales[is+2] >> 4);
    y[l+64] = dall * (x[i].scales[is+4] & 0xF) * ((q >> 4) & 3) - dmin * (x[i].scales[is+4] >> 4);
    y[l+96] = dall * (x[i].scales[is+6] & 0xF) * ((q >> 6) & 3) - dmin * (x[i].scales[is+6] >> 4);
}

template<typename dst_t>
static __global__ void dequantize_block_q3_K(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i = blockIdx.x;
    const block_q3_K * x = (const block_q3_K *) vx;

    const int64_t r = threadIdx.x/4;
    const int64_t tid = r/2;
    const int64_t is0 = r%2;
    const int64_t l0 = 16*is0 + 4*(threadIdx.x%4);
    const int64_t n = tid / 4;
    const int64_t j = tid - 4*n;

    uint8_t m = 1 << (4*n + j);
    int64_t is = 8*n + 2*j + is0;
    int shift = 2*j;

    int8_t us = is <  4 ? (x[i].scales[is-0] & 0xF) | (((x[i].scales[is+8] >> 0) & 3) << 4) :
                is <  8 ? (x[i].scales[is-0] & 0xF) | (((x[i].scales[is+4] >> 2) & 3) << 4) :
                is < 12 ? (x[i].scales[is-8] >>  4) | (((x[i].scales[is+0] >> 4) & 3) << 4) :
                          (x[i].scales[is-8] >>  4) | (((x[i].scales[is-4] >> 6) & 3) << 4);
    float d_all = x[i].d;
    float dl = d_all * (us - 32);

    dst_t * y = yy + i*QK_K + 128*n + 32*j;
    const uint8_t * q = x[i].qs + 32*n;
    const uint8_t * hm = x[i].hmask;

    for (int l = l0; l < l0+4; ++l) y[l] = dl * ((int8_t)((q[l] >> shift) & 3) - ((hm[l] & m) ? 0 : 4));
}

static inline __device__ void get_scale_min_k4(int j, const uint8_t * q, uint8_t & d, uint8_t & m) {
    if (j < 4) {
        d = q[j] & 63; m = q[j + 4] & 63;
    } else {
        d = (q[j+4] & 0xF) | ((q[j-4] >> 6) << 4);
        m = (q[j+4] >>  4) | ((q[j-0] >> 6) << 4);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_q4_K(const void * __restrict__ vx, dst_t * __restrict__ yy) {
    const block_q4_K * x = (const block_q4_K *) vx;

    const int64_t i = blockIdx.x;

    // assume 32 threads
    const int64_t tid = threadIdx.x;
    const int64_t il  = tid/8;
    const int64_t ir  = tid%8;
    const int64_t is  = 2*il;
    const int64_t n   = 4;

    dst_t * y = yy + i*QK_K + 64*il + n*ir;

    const float dall = __low2half(x[i].dm);
    const float dmin = __high2half(x[i].dm);

    const uint8_t * q = x[i].qs + 32*il + n*ir;

    uint8_t sc, m;
    get_scale_min_k4(is + 0, x[i].scales, sc, m);
    const float d1 = dall * sc; const float m1 = dmin * m;
    get_scale_min_k4(is + 1, x[i].scales, sc, m);
    const float d2 = dall * sc; const float m2 = dmin * m;
    for (int l = 0; l < n; ++l) {
        y[l + 0] = d1 * (q[l] & 0xF) - m1;
        y[l +32] = d2 * (q[l] >>  4) - m2;
    }
}

template<typename dst_t>
static __global__ void dequantize_block_q5_K(const void * __restrict__ vx, dst_t * __restrict__ yy) {
    const block_q5_K * x = (const block_q5_K *) vx;

    const int64_t i = blockIdx.x;

    // assume 64 threads - this is very slightly better than the one below
    const int64_t tid = threadIdx.x;
    const int64_t il  = tid/16;   // il is in 0...3
    const int64_t ir  = tid%16;   // ir is in 0...15
    const int64_t is  = 2*il;     // is is in 0...6

    dst_t * y = yy + i*QK_K + 64*il + 2*ir;

    const float dall = __low2half(x[i].dm);
    const float dmin = __high2half(x[i].dm);

    const uint8_t * ql = x[i].qs + 32*il + 2*ir;
    const uint8_t * qh = x[i].qh + 2*ir;

    uint8_t sc, m;
    get_scale_min_k4(is + 0, x[i].scales, sc, m);
    const float d1 = dall * sc; const float m1 = dmin * m;
    get_scale_min_k4(is + 1, x[i].scales, sc, m);
    const float d2 = dall * sc; const float m2 = dmin * m;

    uint8_t   hm  = 1 << (2*il);
    y[ 0] = d1 * ((ql[ 0] & 0xF) + (qh[ 0] & hm ? 16 : 0)) - m1;
    y[ 1] = d1 * ((ql[ 1] & 0xF) + (qh[ 1] & hm ? 16 : 0)) - m1;
    hm <<= 1;
    y[32] = d2 * ((ql[ 0] >>  4) + (qh[ 0] & hm ? 16 : 0)) - m2;
    y[33] = d2 * ((ql[ 1] >>  4) + (qh[ 1] & hm ? 16 : 0)) - m2;
}

template<typename dst_t>
static __global__ void dequantize_block_q6_K(const void * __restrict__ vx, dst_t * __restrict__ yy) {
    const block_q6_K * x = (const block_q6_K *) vx;

    const int64_t i = blockIdx.x;

    // assume 64 threads - this is very slightly better than the one below
    const int64_t tid = threadIdx.x;
    const int64_t ip  = tid/32;   // ip is 0 or 1
    const int64_t il  = tid - 32*ip; // 0...32
    const int64_t is  = 8*ip + il/16;

    dst_t * y = yy + i*QK_K + 128*ip + il;

    const float d = x[i].d;

    const uint8_t * ql = x[i].ql + 64*ip + il;
    const uint8_t   qh = x[i].qh[32*ip + il];
    const int8_t  * sc = x[i].scales + is;

    y[ 0] = d * sc[0] * ((int8_t)((ql[ 0] & 0xF) | (((qh >> 0) & 3) << 4)) - 32);
    y[32] = d * sc[2] * ((int8_t)((ql[32] & 0xF) | (((qh >> 2) & 3) << 4)) - 32);
    y[64] = d * sc[4] * ((int8_t)((ql[ 0]  >> 4) | (((qh >> 4) & 3) << 4)) - 32);
    y[96] = d * sc[6] * ((int8_t)((ql[32]  >> 4) | (((qh >> 6) & 3) << 4)) - 32);
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_xxs(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq2_xxs * x = (const block_iq2_xxs  *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 8*il;
    const uint16_t * q2 = x[i].qs + 4*ib;
    const uint8_t  * aux8 = (const uint8_t *)q2;
    const uint8_t  * grid = (const uint8_t *)(iq2xxs_grid + aux8[il]);
    const uint32_t aux32 = q2[2] | (q2[3] << 16);
    const float d = (float)x[i].d * (0.5f + (aux32 >> 28)) * 0.25f;
    const uint8_t signs = ksigns_iq2xs[(aux32 >> 7*il) & 127];
    for (int j = 0; j < 8; ++j) y[j] = d * grid[j] * (signs & kmask_iq2xs[j] ? -1.f : 1.f);
}

inline __device__ int nearest_int(float fval) {
    assert(fval <= 4194303.f);
    float val = fval + 12582912.f;
    int i; memcpy(&i, &val, sizeof(int));
    return (i & 0x007fffff) - 0x00400000;
}

int __device__ __forceinline__ trellis_next_int(uint32_t& val) {
    constexpr uint32_t ka = 0xCBAC1FED;
    val = ka*val;
    return ggml_cuda_dp4a(val & 0x3f3f3f3f, 0x01010101, -126);
}

float __device__ __forceinline__ trellis_next(uint32_t& val) {
    constexpr uint32_t ka = 89226354;
    constexpr uint32_t kb = 64248484;
    constexpr uint32_t kmask = 0x8fff8fff;
    constexpr uint32_t km32 = 0x3b603b60;
    uint32_t s;
    const half * h = (const half *)&s;
    val = ka*val + kb;
    s = (val & kmask) ^ km32;
    return (float)(h[0]+h[1]);
}

template<typename dst_t>
static __global__ void dequantize_block_iq1_kt(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float scale = *(const float *)cx;
    const block_iq1_kt * x = (const block_iq1_kt *)(cx + sizeof(float));
    const int64_t i = ii - (row*n_per_row)/QK_K;

    const int64_t tid = threadIdx.x;
    const int64_t ib = tid; // 0...31
    dst_t * y = yy + ii*QK_K + 8*ib;
    uint32_t idx = (x[i].ql[ib] | ((x[i].qh[ib%16] << (8 - 4*(ib/16))) & 0xf00) | ((x[i].sh[ib/4] << (8 - (ib%4))) & 0x1000)) + 4096;
    const float dl = scale * iq4k_values[x[i].sh[ib/4] & 0xf];
    for (int j = 0; j < 8; ++j) {
        y[j] = dl * trellis_next_int(idx);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_kt(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float scale = *(const float *)cx;
    const block_iq2_kt * x = (const block_iq2_kt *)(cx + sizeof(float));
    const int64_t i = ii - (row*n_per_row)/QK_K;

    const int64_t tid = threadIdx.x;
    const int64_t ib = tid; // 0...31
    dst_t * y = yy + ii*QK_K + 8*ib;
    const uint16_t * ql = (const uint16_t *)x[i].ql;
    uint32_t idx = ql[ib] + 4096;
    const float dl = scale * iq4k_values[((x[i].scales[(ib/4)%4] >> 4*(ib/16)) & 0xf)] * 1.05f;
    for (int j = 0; j < 8; ++j) {
        y[j] = dl * trellis_next_int(idx);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq3_kt(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float scale = *(const float *)cx;
    const block_iq3_kt * x = (const block_iq3_kt *)(cx + sizeof(float));
    const int64_t i = ii - (row*n_per_row)/QK_K;

    const int64_t tid = threadIdx.x;
    const int64_t ib = tid; // 0...31
    dst_t * y = yy + ii*QK_K + 8*ib;
    const uint16_t * ql = (const uint16_t *)x[i].ql;
    uint32_t idx = ql[ib] + 4096;
    const float dl = scale * ((x[i].scales[(ib/4)%4] >> 4*(ib/16)) & 0xf) * 1.01f; //1.015f;
    uint8_t mask = 1 << (ib/4);
    for (int j = 0; j < 8; ++j) {
        y[j] = dl * std::abs(trellis_next_int(idx)) * (x[i].qh[(8*ib+j)%32] & mask ? -1.f : 1.f);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq4_kt(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const float * dptr = (const float *)((const char *)vx + row * row_size);
    float scale = dptr[0] * 1.00f;
    const block_iq4_kt * x = (const block_iq4_kt *)(dptr + 1);
    const int64_t i = ii - (row*n_per_row)/QK_K;

    constexpr int kNumGroups = 64;

    const int64_t tid = threadIdx.x;
    const int64_t ib = tid; // 0...31
    dst_t * y = yy + ii*QK_K + 8*ib;
    const uint32_t * shb = x[i].qs;
    const uint8_t * ql = (const uint8_t *)(shb + 8); //Q::kNblock;
    const uint8_t * qh = ql + kNumGroups;
    const int ib32 = ib/4;
    const int ig = ib%4;
    const int jj = ib32*8 + 2*ig;
    uint32_t offset = shb[ib32] & 1 ? 4096 + 32768 : 4096;
    uint32_t idx1 = ql[jj+0] + ((qh[(jj+0)%(kNumGroups/2)] << (8 - 4*((jj+0)/(kNumGroups/2)))) & 0xf00) + (((shb[ib32] >> (8 + 6*ig+0)) & 7) << 12) + offset;
    uint32_t idx2 = ql[jj+1] + ((qh[(jj+1)%(kNumGroups/2)] << (8 - 4*((jj+1)/(kNumGroups/2)))) & 0xf00) + (((shb[ib32] >> (8 + 6*ig+3)) & 7) << 12) + offset;
    int ls = ((shb[ib32] & 0xff) >> 1) - 64;
    const float dl = scale * ls;
    for (int j = 0; j < 4; ++j) {
        y[j+0] = dl * trellis_next_int(idx1);
        y[j+4] = dl * trellis_next_int(idx2);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_xs(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq2_xs * x = (const block_iq2_xs *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 8*il;
    const uint16_t * q2 = x[i].qs + 4*ib;
    const uint8_t  * grid = (const uint8_t *)(iq2xs_grid + (q2[il] & 511));
    const float d = (float)x[i].d * (0.5f + ((x[i].scales[ib] >> 4*(il/2)) & 0xf)) * 0.25f;
    const uint8_t signs = ksigns_iq2xs[q2[il] >> 9];
    for (int j = 0; j < 8; ++j) y[j] = d * grid[j] * (signs & kmask_iq2xs[j] ? -1.f : 1.f);
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_s(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq2_s * x = (const block_iq2_s *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 8*il;
    const uint8_t * grid = (const uint8_t *)(iq2s_grid + (x[i].qs[4*ib+il] | ((x[i].qh[ib] << (8-2*il)) & 0x300)));
    const float d = (float)x[i].d * (0.5f + ((x[i].scales[ib] >> 4*(il/2)) & 0xf)) * 0.25f;
    const uint8_t signs = x[i].qs[QK_K/8+4*ib+il];
    for (int j = 0; j < 8; ++j) y[j] = d * grid[j] * (signs & kmask_iq2xs[j] ? -1.f : 1.f);
}

template<typename dst_t>
static __global__ void dequantize_block_iq3_xxs(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq3_xxs * x = (const block_iq3_xxs  *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 8*il;
    const uint8_t  * q3 = x[i].qs + 8*ib;
    const uint16_t * gas = (const uint16_t *)(x[i].qs + QK_K/4) + 2*ib;
    const uint8_t  * grid1 = (const uint8_t *)(iq3xxs_grid + q3[2*il+0]);
    const uint8_t  * grid2 = (const uint8_t *)(iq3xxs_grid + q3[2*il+1]);
    const uint32_t aux32 = gas[0] | (gas[1] << 16);
    const float d = (float)x[i].d * (0.5f + (aux32 >> 28)) * 0.5f;
    const uint8_t signs = ksigns_iq2xs[(aux32 >> 7*il) & 127];
    for (int j = 0; j < 4; ++j) {
        y[j+0] = d * grid1[j] * (signs & kmask_iq2xs[j+0] ? -1.f : 1.f);
        y[j+4] = d * grid2[j] * (signs & kmask_iq2xs[j+4] ? -1.f : 1.f);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq3_s(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq3_s * x = (const block_iq3_s *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 8*il;
    const uint8_t * qs = x[i].qs + 8*ib;
    const uint8_t * grid1 = (const uint8_t *)(iq3s_grid + (qs[2*il+0] | ((x[i].qh[ib] << (8-2*il)) & 256)));
    const uint8_t * grid2 = (const uint8_t *)(iq3s_grid + (qs[2*il+1] | ((x[i].qh[ib] << (7-2*il)) & 256)));
    const float d = (float)x[i].d * (1 + 2*((x[i].scales[ib/2] >> 4*(ib%2)) & 0xf));
    const uint8_t signs = x[i].signs[4*ib + il];
    for (int j = 0; j < 4; ++j) {
        y[j+0] = d * grid1[j] * (signs & kmask_iq2xs[j+0] ? -1.f : 1.f);
        y[j+4] = d * grid2[j] * (signs & kmask_iq2xs[j+4] ? -1.f : 1.f);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq1_s(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq1_s * x = (const block_iq1_s  *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 8*il;
    const float delta = x[i].qh[ib] & 0x8000 ? -1 - IQ1S_DELTA : -1 + IQ1S_DELTA;
    const float d = (float)x[i].d * (2*((x[i].qh[ib] >> 12) & 7) + 1);
    uint32_t grid32[2]; const int8_t * q = (const int8_t *)grid32;
    grid32[0] = iq1s_grid_gpu[x[i].qs[4*ib+il] | (((x[i].qh[ib] >> 3*il) & 7) << 8)];
    grid32[1] = (grid32[0] >> 4) & 0x0f0f0f0f;
    grid32[0] &= 0x0f0f0f0f;
    for (int j = 0; j < 8; ++j) {
        y[j] = d * (q[j] + delta);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq1_s_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/32;
    int64_t row  = (8*ii)/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = (8*ii)%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const half * dptr = (const half *)((const char *)vx + 4*row4*row_size);
    const float d = __half2float(dptr[ir]);
    const block_iq1_s_r4 * x = (const block_iq1_s_r4 *)(dptr + 4) + ibl;
    dst_t * y = yy + 256*ii + 32*ib + 8*il;

    float dl = d*(2*((x[ib].qh[ir] >> 12) & 7) + 1);
    float delta = dl * (x[ib].qh[ir] & 0x8000 ? -1-IQ1S_DELTA : -1+IQ1S_DELTA);

    uint32_t grid32[2]; const int8_t * q = (const int8_t *)grid32;
    grid32[0] = iq1s_grid_gpu[x[ib].qs[4*il+ir] | (((x[ib].qh[ir] >> 3*il) & 7) << 8)];
    grid32[1] = (grid32[0] >> 4) & 0x0f0f0f0f;
    grid32[0] &= 0x0f0f0f0f;

    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 8; ++j) y[j] = __float2bfloat16(dl*q[j] + delta);
    } else {
        for (int j = 0; j < 8; ++j) y[j] = dl*q[j] + delta;
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq1_m_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/32;
    int64_t row  = (8*ii)/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = (8*ii)%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const half * dptr = (const half *)((const char *)vx + 4*row4*row_size);
    const float d = __half2float(dptr[ir]);
    const block_iq1_m_r4 * x = (const block_iq1_m_r4 *)(dptr + 4) + ibl;
    dst_t * y = yy + 256*ii + 32*ib + 8*il;

    uint8_t qh = x[ib].qh[4*(il/2)+ir] >> 4*(il%2);
    float dl = d*((x[ib].scales[ir] >> 4*(il/2)) & 0xf);
    float delta = dl * (qh & 0x8 ? -1-IQ1M_DELTA : -1+IQ1M_DELTA);

    uint32_t grid32[2]; const int8_t * q = (const int8_t *)grid32;
    grid32[0] = iq1s_grid_gpu[x[ib].qs[4*il+ir] | ((qh & 7) << 8)];
    grid32[1] = (grid32[0] >> 4) & 0x0f0f0f0f;
    grid32[0] &= 0x0f0f0f0f;

    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 8; ++j) y[j] = __float2bfloat16(dl*q[j] + delta);
    } else {
        for (int j = 0; j < 8; ++j) y[j] = dl*q[j] + delta;
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq1_m(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq1_m * x = (const block_iq1_m  *) vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 8*il;
    const uint16_t * sc = (const uint16_t *)x[i].scales;
    iq1m_scale_t scale;
    scale.u16 = (sc[0] >> 12) | ((sc[1] >> 8) & 0x00f0) | ((sc[2] >> 4) & 0x0f00) | (sc[3] & 0xf000);
    const int64_t ib16 = 2*ib + il/2; // sc[ib16/4] >> 3*(ib16%4) -> sc[ib/2] >> 3*((2*ib+il/2)%4);
    const float d = (float)scale.f16 * (2*((sc[ib16/4] >> 3*(ib16%4)) & 0x7) + 1);
    const float delta = x[i].qh[2*ib+il/2] & (0x08 << 4*(il%2)) ? -1 - IQ1M_DELTA : -1 + IQ1M_DELTA;
    uint32_t grid32[2]; const int8_t * q = (const int8_t *)grid32;
    grid32[0] = iq1s_grid_gpu[x[i].qs[4*ib+il] | (((x[i].qh[2*ib+il/2] >> 4*(il%2)) & 7) << 8)];
    grid32[1] = (grid32[0] >> 4) & 0x0f0f0f0f;
    grid32[0] &= 0x0f0f0f0f;
    for (int j = 0; j < 8; ++j) {
        y[j] = d * (q[j] + delta);
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq1_bn(const void * __restrict__ vx, dst_t * __restrict__ yy,
        int64_t n_per_row, int64_t row_size, int64_t nrows) {

    int64_t ii  = 256*blockIdx.x;
    const int tid = threadIdx.x;
    const int il = tid/4; // 0...7
    const int ib = tid%4; // 0...3
    dst_t * y = yy + ii + 64*ib + 8*il;

    int64_t row = ii / n_per_row;
    if (row >= nrows) return;
    const char * cx = (const char *)vx + row * row_size;
    half d16; memcpy(&d16, cx, sizeof(d16)); // in case not 2-byte aligned
    float d = d16;
    const block_iq1_bn * x = (const block_iq1_bn *)(cx + sizeof(d16));
    ii -= row*n_per_row;
    int64_t i = ii/QK_IQ1BN + ib;

    static const uint8_t k_mult[5] = {81, 27, 9, 3, 1};

//#define COMPUTE_VS(v) 3*v >> 8
#define COMPUTE_VS(v) (v + (v >> 1)) >> 7

    const int i16 = il/2;
    uint8_t q = x[i].ql[3*i16+2*(il%2)];
    for (int j = 0; j < 5; ++j) {
        uint8_t v = k_mult[j]*q;
        int8_t vs = COMPUTE_VS(v);
        y[2*(il%2)+j] = d*(vs - 1);
    }
    q = x[i].ql[3*i16+1];
    for (int j = 0; j < 2; ++j) {
        uint8_t v = k_mult[3*(il%2)+j]*q;
        int8_t vs = COMPUTE_VS(v);
        y[5*(1-(il%2))+j] = d*(vs-1);
    }
    uint8_t v = (il%2) ? k_mult[i16]*x[i].extra : k_mult[2]*q;
    int8_t vs = COMPUTE_VS(v);
    y[7] = d*(vs - 1);

#undef COMPUTE_VS
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_bn(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size, int64_t nrows) {

    int64_t ii  = 256*blockIdx.x;
    const int64_t tid = threadIdx.x;
    int64_t ib64 = tid%4; // 0...3
    int64_t il   = tid/4; // 0...7
    dst_t * y = yy + ii + 64*ib64 + 2*il;

    int64_t row = ii / n_per_row;
    if (row >= nrows) return;
    const char * cx = (const char *)vx + row * row_size;
    float d = *(const float *)cx;
    const block_iq2_bn * x = (const block_iq2_bn *)(cx + sizeof(float));
    ii -= row*n_per_row;
    int64_t i = ii/QK_IQ1BN + ib64;
    const float m = -d;
    auto qs = x[i].qs + 2*il;
    for (int j = 0; j < 2; ++j) {
        y[j+ 0] = d * ((qs[j] >> 0) & 3) + m;
        y[j+16] = d * ((qs[j] >> 2) & 3) + m;
        y[j+32] = d * ((qs[j] >> 4) & 3) + m;
        y[j+48] = d * ((qs[j] >> 6) & 3) + m;
    }
}


template<typename dst_t>
static __global__ void dequantize_block_iq4_nl(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int64_t i   = blockIdx.x;
    const block_iq4_nl * x = (const block_iq4_nl *) vx + i*(QK_K/QK4_NL);

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 4*il;
    const uint8_t  * q4 = x[ib].qs + 4*il;
    const float d = (float)x[ib].d;
    for (int j = 0; j < 4; ++j) {
        y[j+ 0] = d * kvalues_iq4nl[q4[j] & 0xf];
        y[j+16] = d * kvalues_iq4nl[q4[j] >>  4];
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq4_xs(const void * __restrict__ vx, dst_t * __restrict__ yy) {
    const int64_t i   = blockIdx.x;
    const block_iq4_xs * x = (const block_iq4_xs *)vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 4*il;
    const uint8_t  * q4 = x[i].qs + 16*ib + 4*il;
    const float d = (float)x[i].d * ((((x[i].scales_l[ib/2] >> 4*(ib%2)) & 0xf) | (((x[i].scales_h >> 2*ib) & 3) << 4)) - 32);
    for (int j = 0; j < 4; ++j) {
        y[j+ 0] = d * kvalues_iq4nl[q4[j] & 0xf];
        y[j+16] = d * kvalues_iq4nl[q4[j] >>  4];
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq4_ks(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float scale = *(const float *)cx;
    const block_iq4_ks * x = (const block_iq4_ks *)(cx + sizeof(float));
    const int64_t i   = ii - (row*n_per_row)/QK_K;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + ii*QK_K + 32*ib + 4*il;
    const uint8_t  * q4 = x[i].qs + 16*ib + 4*il;
    const float d = scale * ((x[i].scales[ib] & 254) - 127);
    const int8_t * values = iq4k_values + ((x[i].scales[ib] & 1) << 4);
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 4; ++j) {
            y[j+ 0] = __float2bfloat16(d * values[q4[j] & 0xf]);
            y[j+16] = __float2bfloat16(d * values[q4[j] >>  4]);
        }
    } else {
        for (int j = 0; j < 4; ++j) {
            y[j+ 0] = d * values[q4[j] & 0xf];
            y[j+16] = d * values[q4[j] >>  4];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq4_kss(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float scale = *(const float *)cx;
    const block_iq4_kss * x = (const block_iq4_kss *)(cx + sizeof(float));
    const int64_t i   = ii - (row*n_per_row)/QK_K;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + ii*QK_K + 32*ib + 4*il;
    const uint32_t * q4 = x[i].qs + 4*ib;
    uint32_t s32 = (q4[0] & 0x00010001) | ((q4[1] & 0x00010001) << 2) | ((q4[2] & 0x00010001) << 4) | ((q4[3] & 0x00010001) << 6);
    uint8_t ls = (s32 | (s32 >> 15)) & 0xff;
    const float d = scale * ((ls & 254) - 127);
    const int8_t * values = iq4k_values + ((ls & 1) << 4);
    uint32_t aux32[2];
    aux32[0] = q4[il] & 0xfffefffe;
    aux32[0] ^= (aux32[0] >> 1);
    aux32[1] = ((aux32[0] >> 4) & 0x0f0f0f0f);
    aux32[0] &= 0x0f0f0f0f;
    const uint8_t * aux8 = (const uint8_t *)aux32;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 4; ++j) {
            y[j+ 0] = __float2bfloat16(d * values[aux8[j+0]]);
            y[j+16] = __float2bfloat16(d * values[aux8[j+4]]);
        }
    } else {
        for (int j = 0; j < 4; ++j) {
            y[j+ 0] = d * values[aux8[j+0]];
            y[j+16] = d * values[aux8[j+4]];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq4_k(const void * __restrict__ vx, dst_t * __restrict__ yy) {
    const int64_t i   = blockIdx.x;
    const block_iq4_k * x = (const block_iq4_k *)vx;

    const int64_t tid = threadIdx.x;
    const int64_t il = tid/8; // 0...3
    const int64_t ib = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 32*ib + 4*il;
    const uint8_t  * q4 = x[i].qs + 16*ib + 4*il;
    const float d = (float)x[i].d;
    const uint8_t sh = x[i].scales_h[ib/2] >> 4*(ib%2);
    const float d1 = d * (((x[i].scales_l[ib] & 0xf) | ((sh << 4) & 0x30)) - 32);
    const float d2 = d * (((x[i].scales_l[ib] >>  4) | ((sh << 2) & 0x30)) - 32);
    const int8_t * values1 = iq4k_values + 16*((x[i].extra >> (2*ib+0)) & 1);
    const int8_t * values2 = iq4k_values + 16*((x[i].extra >> (2*ib+1)) & 1);
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 4; ++j) {
            y[j+ 0] = __float2bfloat16(d1 * values1[q4[j] & 0xf]);
            y[j+16] = __float2bfloat16(d2 * values2[q4[j] >>  4]);
        }
    } else {
        for (int j = 0; j < 4; ++j) {
            y[j+ 0] = d1 * values1[q4[j] & 0xf];
            y[j+16] = d2 * values2[q4[j] >>  4];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq4_k_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/256;
    int64_t row  = ii/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = row4*nblock + ii%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const block_iq4_k_r4 * x = (const block_iq4_k_r4 *)vx;
    dst_t * y = yy + 256*ii + 32*ib;

    const float d = __half2float(x[ibl].d[ir]);
    int is = 8*ib + ir;
    float dl1 = d * ((((x[ibl].scales_l[is%32] >> 4*(is/32)) & 0xf) | (((x[ibl].scales_h[is%16] >> 2*(is/16)) & 3) << 4)) - 32);
    is += 4;
    float dl2 = d * ((((x[ibl].scales_l[is%32] >> 4*(is/32)) & 0xf) | (((x[ibl].scales_h[is%16] >> 2*(is/16)) & 3) << 4)) - 32);
    auto values1 = iq4k_values + (((x[ibl].extra[ir+0] >> ib) & 1) << 4);
    auto values2 = iq4k_values + (((x[ibl].extra[ir+4] >> ib) & 1) << 4);
    auto qs = x[ibl].qs + 64*ib + 4*ir;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        y[il+ 0] = __float2bfloat16(dl1 * values1[qs[il+ 0] & 0xf]);
        y[il+ 8] = __float2bfloat16(dl1 * values1[qs[il+ 0] >>  4]);
        y[il+16] = __float2bfloat16(dl2 * values2[qs[il+16] & 0xf]);
        y[il+24] = __float2bfloat16(dl2 * values2[qs[il+16] >>  4]);
        y[il+ 4] = __float2bfloat16(dl1 * values1[qs[il+32] & 0xf]);
        y[il+12] = __float2bfloat16(dl1 * values1[qs[il+32] >>  4]);
        y[il+20] = __float2bfloat16(dl2 * values2[qs[il+48] & 0xf]);
        y[il+28] = __float2bfloat16(dl2 * values2[qs[il+48] >>  4]);
    } else {
        y[il+ 0] = dl1 * values1[qs[il+ 0] & 0xf];
        y[il+ 4] = dl1 * values1[qs[il+32] & 0xf];
        y[il+ 8] = dl1 * values1[qs[il+ 0] >>  4];
        y[il+12] = dl1 * values1[qs[il+32] >>  4];
        y[il+16] = dl2 * values2[qs[il+16] & 0xf];
        y[il+20] = dl2 * values2[qs[il+48] & 0xf];
        y[il+24] = dl2 * values2[qs[il+16] >>  4];
        y[il+28] = dl2 * values2[qs[il+48] >>  4];
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq4_ks_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/256;
    int64_t row  = ii/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = ii%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const float * dptr = (const float *)((const char *)vx + 4*row4*row_size);
    const float d = dptr[ir];
    const block_iq4_ks_r4 * x = (const block_iq4_ks_r4 *)(dptr + 4);
    dst_t * y = yy + 256*ii + 32*ib;

    float dl = d * ((x[ibl].scales[4*ib + ir] & 254) - 127);
    auto values = iq4k_values + ((x[ibl].scales[4*ib + ir] & 1) << 4);
    auto qs = x[ibl].qs + 64*ib + 4*ir;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        y[il+ 0] = __float2bfloat16(dl * values[qs[il+ 0] & 0xf]);
        y[il+ 8] = __float2bfloat16(dl * values[qs[il+ 0] >>  4]);
        y[il+16] = __float2bfloat16(dl * values[qs[il+16] & 0xf]);
        y[il+24] = __float2bfloat16(dl * values[qs[il+16] >>  4]);
        y[il+ 4] = __float2bfloat16(dl * values[qs[il+32] & 0xf]);
        y[il+12] = __float2bfloat16(dl * values[qs[il+32] >>  4]);
        y[il+20] = __float2bfloat16(dl * values[qs[il+48] & 0xf]);
        y[il+28] = __float2bfloat16(dl * values[qs[il+48] >>  4]);
    } else {
        y[il+ 0] = dl * values[qs[il+ 0] & 0xf];
        y[il+ 4] = dl * values[qs[il+32] & 0xf];
        y[il+ 8] = dl * values[qs[il+ 0] >>  4];
        y[il+12] = dl * values[qs[il+32] >>  4];
        y[il+16] = dl * values[qs[il+16] & 0xf];
        y[il+20] = dl * values[qs[il+48] & 0xf];
        y[il+24] = dl * values[qs[il+16] >>  4];
        y[il+28] = dl * values[qs[il+48] >>  4];
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq5_k(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int i   = blockIdx.x;
    const block_iq5_k * x = (const block_iq5_k *) vx;

    const int tid = threadIdx.x;
    int ib64 = tid/8; // 0...3
    int il   = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 64*ib64 + 2*il;
    const float d = (float)x[i].d;
    const float dl1 = d * (((x[i].scales_l[2*ib64+0] & 0xf) | ((x[i].scales_h[ib64] << 4) & 0x30)) - 32);
    const float dl2 = d * (((x[i].scales_l[2*ib64+0] >>  4) | ((x[i].scales_h[ib64] << 2) & 0x30)) - 32);
    const float dl3 = d * (((x[i].scales_l[2*ib64+1] & 0xf) | ((x[i].scales_h[ib64] >> 0) & 0x30)) - 32);
    const float dl4 = d * (((x[i].scales_l[2*ib64+1] >>  4) | ((x[i].scales_h[ib64] >> 2) & 0x30)) - 32);
    const uint8_t * qs = x[i].qs + 32*ib64 + 2*il;
    const uint8_t * qh = x[i].qh + 2*il;
    const uint8_t extra = x[i].extra >> 4*(ib64%4);
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 2; ++j) {
            const uint8_t h1 = qh[j] >> 2*(ib64%4), h2 = qh[j+16] >> 2*(ib64%4);
            y[j+ 0] = __float2bfloat16(dl1 * iq5nl_values[(qs[j+ 0] & 0xf) | ((h1 & 1) << 4) | ((extra << 5) & 0x20)]);
            y[j+16] = __float2bfloat16(dl2 * iq5nl_values[(qs[j+16] & 0xf) | ((h2 & 1) << 4) | ((extra << 4) & 0x20)]);
            y[j+32] = __float2bfloat16(dl3 * iq5nl_values[(qs[j+ 0] >>  4) | ((h1 & 2) << 3) | ((extra << 3) & 0x20)]);
            y[j+48] = __float2bfloat16(dl4 * iq5nl_values[(qs[j+16] >>  4) | ((h2 & 2) << 3) | ((extra << 2) & 0x20)]);
        }
    } else {
        for (int j = 0; j < 2; ++j) {
            const uint8_t h1 = qh[j] >> 2*(ib64%4), h2 = qh[j+16] >> 2*(ib64%4);
            y[j+ 0] = dl1 * iq5nl_values[(qs[j+ 0] & 0xf) | ((h1 & 1) << 4) | ((extra << 5) & 0x20)];
            y[j+16] = dl2 * iq5nl_values[(qs[j+16] & 0xf) | ((h2 & 1) << 4) | ((extra << 4) & 0x20)];
            y[j+32] = dl3 * iq5nl_values[(qs[j+ 0] >>  4) | ((h1 & 2) << 3) | ((extra << 3) & 0x20)];
            y[j+48] = dl4 * iq5nl_values[(qs[j+16] >>  4) | ((h2 & 2) << 3) | ((extra << 2) & 0x20)];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq5_k_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/256;
    int64_t row  = ii/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = row4*nblock + ii%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const block_iq5_k_r4 * x = (const block_iq5_k_r4 *)vx;
    dst_t * y = yy + 256*ii + 32*ib;

    const float d = __half2float(x[ibl].d[ir]);
    int is = 8*ib + ir;
    float dl1 = d * ((((x[ibl].scales_l[is%32] >> 4*(is/32)) & 0xf) | (((x[ibl].scales_h[is%16] >> 2*(is/16)) & 3) << 4)) - 32);
    is += 4;
    float dl2 = d * ((((x[ibl].scales_l[is%32] >> 4*(is/32)) & 0xf) | (((x[ibl].scales_h[is%16] >> 2*(is/16)) & 3) << 4)) - 32);
    auto values1 = iq5nl_values + (((x[ibl].extra[ir+0] >> ib) & 1) << 5);
    auto values2 = iq5nl_values + (((x[ibl].extra[ir+4] >> ib) & 1) << 5);
    auto qs = x[ibl].qs + 64*ib + 4*ir;
    auto qh = x[ibl].qh + 16*ib + 4*ir;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        y[il+ 0] = __float2bfloat16(dl1 * values1[(qs[il+ 0] & 0xf) | (((qh[il] >> 0) & 1) << 4)]);
        y[il+ 4] = __float2bfloat16(dl1 * values1[(qs[il+32] & 0xf) | (((qh[il] >> 4) & 1) << 4)]);
        y[il+ 8] = __float2bfloat16(dl1 * values1[(qs[il+ 0] >>  4) | (((qh[il] >> 1) & 1) << 4)]);
        y[il+12] = __float2bfloat16(dl1 * values1[(qs[il+32] >>  4) | (((qh[il] >> 5) & 1) << 4)]);
        y[il+16] = __float2bfloat16(dl2 * values2[(qs[il+16] & 0xf) | (((qh[il] >> 2) & 1) << 4)]);
        y[il+20] = __float2bfloat16(dl2 * values2[(qs[il+48] & 0xf) | (((qh[il] >> 6) & 1) << 4)]);
        y[il+24] = __float2bfloat16(dl2 * values2[(qs[il+16] >>  4) | (((qh[il] >> 3) & 1) << 4)]);
        y[il+28] = __float2bfloat16(dl2 * values2[(qs[il+48] >>  4) | (((qh[il] >> 7) & 1) << 4)]);
    } else {
        y[il+ 0] = dl1 * values1[(qs[il+ 0] & 0xf) | (((qh[il] >> 0) & 1) << 4)];
        y[il+ 4] = dl1 * values1[(qs[il+32] & 0xf) | (((qh[il] >> 4) & 1) << 4)];
        y[il+ 8] = dl1 * values1[(qs[il+ 0] >>  4) | (((qh[il] >> 1) & 1) << 4)];
        y[il+12] = dl1 * values1[(qs[il+32] >>  4) | (((qh[il] >> 5) & 1) << 4)];
        y[il+16] = dl2 * values2[(qs[il+16] & 0xf) | (((qh[il] >> 2) & 1) << 4)];
        y[il+20] = dl2 * values2[(qs[il+48] & 0xf) | (((qh[il] >> 6) & 1) << 4)];
        y[il+24] = dl2 * values2[(qs[il+16] >>  4) | (((qh[il] >> 3) & 1) << 4)];
        y[il+28] = dl2 * values2[(qs[il+48] >>  4) | (((qh[il] >> 7) & 1) << 4)];
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq5_ks_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/256;
    int64_t row  = ii/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = ii%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const float * dptr = (const float *)((const char *)vx + 4*row4*row_size);
    const block_iq5_ks_r4 * x = (const block_iq5_ks_r4 *)(dptr + 4);
    dst_t * y = yy + 256*ii + 32*ib;

    const float d = dptr[ir];
    float dl = d * ((x[ibl].scales[4*ib + ir] & 254) - 127);
    auto values = iq5nl_values + ((x[ibl].scales[4*ib + ir] & 1) << 5);
    auto qs = x[ibl].qs + 64*ib + 4*ir;
    auto qh = x[ibl].qh + 16*ib + 4*ir;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        y[il+ 0] = __float2bfloat16(dl * values[(qs[il+ 0] & 0xf) | (((qh[il] >> 0) & 1) << 4)]);
        y[il+ 4] = __float2bfloat16(dl * values[(qs[il+32] & 0xf) | (((qh[il] >> 4) & 1) << 4)]);
        y[il+ 8] = __float2bfloat16(dl * values[(qs[il+ 0] >>  4) | (((qh[il] >> 1) & 1) << 4)]);
        y[il+12] = __float2bfloat16(dl * values[(qs[il+32] >>  4) | (((qh[il] >> 5) & 1) << 4)]);
        y[il+16] = __float2bfloat16(dl * values[(qs[il+16] & 0xf) | (((qh[il] >> 2) & 1) << 4)]);
        y[il+20] = __float2bfloat16(dl * values[(qs[il+48] & 0xf) | (((qh[il] >> 6) & 1) << 4)]);
        y[il+24] = __float2bfloat16(dl * values[(qs[il+16] >>  4) | (((qh[il] >> 3) & 1) << 4)]);
        y[il+28] = __float2bfloat16(dl * values[(qs[il+48] >>  4) | (((qh[il] >> 7) & 1) << 4)]);
    } else {
        y[il+ 0] = dl * values[(qs[il+ 0] & 0xf) | (((qh[il] >> 0) & 1) << 4)];
        y[il+ 4] = dl * values[(qs[il+32] & 0xf) | (((qh[il] >> 4) & 1) << 4)];
        y[il+ 8] = dl * values[(qs[il+ 0] >>  4) | (((qh[il] >> 1) & 1) << 4)];
        y[il+12] = dl * values[(qs[il+32] >>  4) | (((qh[il] >> 5) & 1) << 4)];
        y[il+16] = dl * values[(qs[il+16] & 0xf) | (((qh[il] >> 2) & 1) << 4)];
        y[il+20] = dl * values[(qs[il+48] & 0xf) | (((qh[il] >> 6) & 1) << 4)];
        y[il+24] = dl * values[(qs[il+16] >>  4) | (((qh[il] >> 3) & 1) << 4)];
        y[il+28] = dl * values[(qs[il+48] >>  4) | (((qh[il] >> 7) & 1) << 4)];
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_k_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/256;
    int64_t row  = ii/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = row4*nblock + ii%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const block_iq2_k_r4 * x = (const block_iq2_k_r4 *)vx;
    dst_t * y = yy + 256*ii + 32*ib;

    const float d = __half2float(x[ibl].d[ir]);
    int is = 8*ib + ir;
    float dl1 = d * (((x[ibl].scales[is%32] >> 4*(is/32)) & 0xf) - 8);
    is += 4;
    float dl2 = d * (((x[ibl].scales[is%32] >> 4*(is/32)) & 0xf) - 8);
    auto values1 = iq2nl_values + (((x[ibl].extra[ir+0] >> ib) & 1) << 2);
    auto values2 = iq2nl_values + (((x[ibl].extra[ir+4] >> ib) & 1) << 2);
    auto ql = x[ibl].qs + 32*ib + 4*ir;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        y[il+ 0] = __float2bfloat16(dl1 * values1[(ql[il+ 0] >> 0) & 3]);
        y[il+ 4] = __float2bfloat16(dl1 * values1[(ql[il+ 0] >> 2) & 3]);
        y[il+ 8] = __float2bfloat16(dl1 * values1[(ql[il+ 0] >> 4) & 3]);
        y[il+12] = __float2bfloat16(dl1 * values1[(ql[il+ 0] >> 6) & 3]);
        y[il+16] = __float2bfloat16(dl2 * values2[(ql[il+16] >> 0) & 3]);
        y[il+20] = __float2bfloat16(dl2 * values2[(ql[il+16] >> 2) & 3]);
        y[il+24] = __float2bfloat16(dl2 * values2[(ql[il+16] >> 4) & 3]);
        y[il+28] = __float2bfloat16(dl2 * values2[(ql[il+16] >> 6) & 3]);
    } else {
        y[il+ 0] = dl1 * values1[(ql[il+ 0] >> 0) & 3];
        y[il+ 4] = dl1 * values1[(ql[il+ 0] >> 2) & 3];
        y[il+ 8] = dl1 * values1[(ql[il+ 0] >> 4) & 3];
        y[il+12] = dl1 * values1[(ql[il+ 0] >> 6) & 3];
        y[il+16] = dl2 * values2[(ql[il+16] >> 0) & 3];
        y[il+20] = dl2 * values2[(ql[il+16] >> 2) & 3];
        y[il+24] = dl2 * values2[(ql[il+16] >> 4) & 3];
        y[il+28] = dl2 * values2[(ql[il+16] >> 6) & 3];
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq3_k_r4(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii = blockIdx.x;

    int64_t nblock = n_per_row/256;
    int64_t row  = ii/nblock;
    int64_t row4 = row/4;
    int64_t ir   = row%4;
    int64_t ibl  = row4*nblock + ii%nblock;

    const int tid = threadIdx.x;
    const int  il = tid/8; // 0...3
    const int  ib = tid%8; // 0...7

    const block_iq3_k_r4 * x = (const block_iq3_k_r4 *)vx;
    dst_t * y = yy + 256*ii + 32*ib;

    const float d = __half2float(x[ibl].d[ir]);
    int is = 8*ib + ir;
    float dl1 = d * (2*((x[ibl].scales_l[is%32] >> 4*(is/32)) & 0xf) + 1) * ((x[ibl].scales_h[is%8] >> (is/8)) & 1 ? -1 : 1);
    is += 4;
    float dl2 = d * (2*((x[ibl].scales_l[is%32] >> 4*(is/32)) & 0xf) + 1) * ((x[ibl].scales_h[is%8] >> (is/8)) & 1 ? -1 : 1);
    auto values1 = iq3nl_values + (((x[ibl].extra[ir+0] >> ib) & 1) << 3);
    auto values2 = iq3nl_values + (((x[ibl].extra[ir+4] >> ib) & 1) << 3);
    auto ql = x[ibl].qs + 32*ib + 4*ir;
    auto qh = x[ibl].qh + 16*ib + 4*ir;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        y[il+ 0] = __float2bfloat16(dl1 * values1[((ql[il+ 0] >> 0) & 3) | ((qh[il] << 2) & 4)]);
        y[il+ 4] = __float2bfloat16(dl1 * values1[((ql[il+ 0] >> 2) & 3) | ((qh[il] << 1) & 4)]);
        y[il+ 8] = __float2bfloat16(dl1 * values1[((ql[il+ 0] >> 4) & 3) | ((qh[il] << 0) & 4)]);
        y[il+12] = __float2bfloat16(dl1 * values1[((ql[il+ 0] >> 6) & 3) | ((qh[il] >> 1) & 4)]);
        y[il+16] = __float2bfloat16(dl2 * values2[((ql[il+16] >> 0) & 3) | ((qh[il] >> 2) & 4)]);
        y[il+20] = __float2bfloat16(dl2 * values2[((ql[il+16] >> 2) & 3) | ((qh[il] >> 3) & 4)]);
        y[il+24] = __float2bfloat16(dl2 * values2[((ql[il+16] >> 4) & 3) | ((qh[il] >> 4) & 4)]);
        y[il+28] = __float2bfloat16(dl2 * values2[((ql[il+16] >> 6) & 3) | ((qh[il] >> 5) & 4)]);
    } else {
        y[il+ 0] = dl1 * values1[((ql[il+ 0] >> 0) & 3) | ((qh[il] << 2) & 4)];
        y[il+ 4] = dl1 * values1[((ql[il+ 0] >> 2) & 3) | ((qh[il] << 1) & 4)];
        y[il+ 8] = dl1 * values1[((ql[il+ 0] >> 4) & 3) | ((qh[il] << 0) & 4)];
        y[il+12] = dl1 * values1[((ql[il+ 0] >> 6) & 3) | ((qh[il] >> 1) & 4)];
        y[il+16] = dl2 * values2[((ql[il+16] >> 0) & 3) | ((qh[il] >> 2) & 4)];
        y[il+20] = dl2 * values2[((ql[il+16] >> 2) & 3) | ((qh[il] >> 3) & 4)];
        y[il+24] = dl2 * values2[((ql[il+16] >> 4) & 3) | ((qh[il] >> 4) & 4)];
        y[il+28] = dl2 * values2[((ql[il+16] >> 6) & 3) | ((qh[il] >> 5) & 4)];
    }
}


template<typename dst_t>
static __global__ void dequantize_block_iq5_ks(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float d = *(const float *)cx;
    const block_iq5_ks * x = (const block_iq5_ks *)(cx + sizeof(float));
    const int64_t i   = ii - (row*n_per_row)/QK_K;

    const int tid = threadIdx.x;
    int ib64 = tid/8; // 0...3
    int il   = tid%8; // 0...7
    dst_t * y = yy + ii*QK_K + 64*ib64 + 2*il;
    const float dl1 = d * ((int)(x[i].scales[2*ib64+0] & 254) - 127);
    const float dl2 = d * ((int)(x[i].scales[2*ib64+1] & 254) - 127);
    const uint8_t * qs = x[i].qs + 32*ib64 + 2*il;
    const uint8_t * qh = x[i].qh + 2*il;
    auto values1 = iq5nl_values + ((x[i].scales[2*ib64+0] & 1) << 5);
    auto values2 = iq5nl_values + ((x[i].scales[2*ib64+1] & 1) << 5);
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 2; ++j) {
            const uint8_t h1 = qh[j] >> 2*(ib64%4), h2 = qh[j+16] >> 2*(ib64%4);
            y[j+ 0] = __float2bfloat16(dl1 * values1[(qs[j+ 0] & 0xf) | ((h1 & 1) << 4)]);
            y[j+16] = __float2bfloat16(dl1 * values1[(qs[j+16] & 0xf) | ((h2 & 1) << 4)]);
            y[j+32] = __float2bfloat16(dl2 * values2[(qs[j+ 0] >>  4) | ((h1 & 2) << 3)]);
            y[j+48] = __float2bfloat16(dl2 * values2[(qs[j+16] >>  4) | ((h2 & 2) << 3)]);
        }
    } else {
        for (int j = 0; j < 2; ++j) {
            const uint8_t h1 = qh[j] >> 2*(ib64%4), h2 = qh[j+16] >> 2*(ib64%4);
            y[j+ 0] = dl1 * values1[(qs[j+ 0] & 0xf) | ((h1 & 1) << 4)];
            y[j+16] = dl1 * values1[(qs[j+16] & 0xf) | ((h2 & 1) << 4)];
            y[j+32] = dl2 * values2[(qs[j+ 0] >>  4) | ((h1 & 2) << 3)];
            y[j+48] = dl2 * values2[(qs[j+16] >>  4) | ((h2 & 2) << 3)];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq6_k(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int i   = blockIdx.x;
    const block_iq6_k * x = (const block_iq6_k *) vx;

    const int tid = threadIdx.x;
    int ib64 = tid/8; // 0...3
    int il   = tid%8; // 0...7
    dst_t * y = yy + i*QK_K + 64*ib64 + 2*il;
    const float d = (float)x[i].d;
    const float dl1 = d * x[i].scales[4*ib64+0];
    const float dl2 = d * x[i].scales[4*ib64+1];
    const float dl3 = d * x[i].scales[4*ib64+2];
    const float dl4 = d * x[i].scales[4*ib64+3];
    const uint8_t * qs = x[i].qs + 32*ib64 + 2*il;
    const uint8_t * qh = x[i].qh + 32*(ib64/2) + 2*il;
    const uint8_t extra = x[i].extra >> 4*(ib64%4);
    for (int j = 0; j < 2; ++j) {
        const uint8_t h1 = qh[j] >> 4*(ib64%2), h2 = qh[j+16] >> 4*(ib64%2);
        uint8_t q1 = (qs[j+ 0] & 0xf) | ((h1 & 0x03) << 4);
        uint8_t q2 = (qs[j+16] & 0xf) | ((h2 & 0x03) << 4);
        uint8_t q3 = (qs[j+ 0] >>  4) | ((h1 & 0x0c) << 2);
        uint8_t q4 = (qs[j+16] >>  4) | ((h2 & 0x0c) << 2);
        if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
            y[j+ 0] = __float2bfloat16(dl1 * (iq6nl_values[q1] + (extra & 1 ? 1 : 0)));
            y[j+16] = __float2bfloat16(dl2 * (iq6nl_values[q2] + (extra & 2 ? 1 : 0)));
            y[j+32] = __float2bfloat16(dl3 * (iq6nl_values[q3] + (extra & 4 ? 1 : 0)));
            y[j+48] = __float2bfloat16(dl4 * (iq6nl_values[q4] + (extra & 8 ? 1 : 0)));
        } else {
            y[j+ 0] = dl1 * (iq6nl_values[q1] + (extra & 1 ? 1 : 0));
            y[j+16] = dl2 * (iq6nl_values[q2] + (extra & 2 ? 1 : 0));
            y[j+32] = dl3 * (iq6nl_values[q3] + (extra & 4 ? 1 : 0));
            y[j+48] = dl4 * (iq6nl_values[q4] + (extra & 8 ? 1 : 0));
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_k(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int i   = blockIdx.x;
    const block_iq2_k * x = (const block_iq2_k *) vx;

    const int tid = threadIdx.x;
    int ib128 = tid/16; // 0 or 1
    int il    = tid%16; // 0...15
    dst_t * y = yy + i*QK_K + 128*ib128 + 2*il;
    const float d = (float)x[i].d;
    const float dl1 = d * (((x[i].scales[4*ib128+0] >> 4*(il/8)) & 0xf) - 8);
    const float dl2 = d * (((x[i].scales[4*ib128+1] >> 4*(il/8)) & 0xf) - 8);
    const float dl3 = d * (((x[i].scales[4*ib128+2] >> 4*(il/8)) & 0xf) - 8);
    const float dl4 = d * (((x[i].scales[4*ib128+3] >> 4*(il/8)) & 0xf) - 8);
    const uint8_t * qs = x[i].qs + 32*ib128 + 2*il;
    const int16_t extra = x[i].extra >> (8*ib128 + (il/8));
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 2; ++j) {
            y[j+ 0] = __float2bfloat16(dl1 * iq2nl_values[((qs[j] >> 0) & 0x03) + ((extra << 2) & 4)]);
            y[j+32] = __float2bfloat16(dl2 * iq2nl_values[((qs[j] >> 2) & 0x03) + ((extra << 0) & 4)]);
            y[j+64] = __float2bfloat16(dl3 * iq2nl_values[((qs[j] >> 4) & 0x03) + ((extra >> 2) & 4)]);
            y[j+96] = __float2bfloat16(dl4 * iq2nl_values[((qs[j] >> 6) & 0x03) + ((extra >> 4) & 4)]);
        }
    } else {
        for (int j = 0; j < 2; ++j) {
            y[j+ 0] = dl1 * iq2nl_values[((qs[j] >> 0) & 0x03) + ((extra << 2) & 4)];
            y[j+32] = dl2 * iq2nl_values[((qs[j] >> 2) & 0x03) + ((extra << 0) & 4)];
            y[j+64] = dl3 * iq2nl_values[((qs[j] >> 4) & 0x03) + ((extra >> 2) & 4)];
            y[j+96] = dl4 * iq2nl_values[((qs[j] >> 6) & 0x03) + ((extra >> 4) & 4)];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_ks(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    const float d = (float)*(const half *)cx;
    const block_iq2_ks * x = (const block_iq2_ks *)(cx + sizeof(half));
    const int64_t i   = ii - (row*n_per_row)/QK_K;

    const int tid = threadIdx.x;
    int ib128 = tid/16; // 0 or 1
    int il    = tid%16; // 0...15
    dst_t * y = yy + ii*QK_K + 128*ib128 + 2*il;
    const int16_t extra = x[i].extra >> 4*ib128;
    const float dl1 = d * (((x[i].scales[2*ib128+0] & 0xf) | ((extra >> 4) & 0x10)) - 16);
    const float dl2 = d * (((x[i].scales[2*ib128+0] >>  4) | ((extra >> 5) & 0x10)) - 16);
    const float dl3 = d * (((x[i].scales[2*ib128+1] & 0xf) | ((extra >> 6) & 0x10)) - 16);
    const float dl4 = d * (((x[i].scales[2*ib128+1] >>  4) | ((extra >> 7) & 0x10)) - 16);
    const uint8_t * qs = x[i].qs + 32*ib128 + 2*il;
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 2; ++j) {
            y[j+ 0] = __float2bfloat16(dl1 * iq2nl_values[((qs[j] >> 0) & 0x03) + ((extra << 2) & 4)]);
            y[j+32] = __float2bfloat16(dl2 * iq2nl_values[((qs[j] >> 2) & 0x03) + ((extra << 1) & 4)]);
            y[j+64] = __float2bfloat16(dl3 * iq2nl_values[((qs[j] >> 4) & 0x03) + ((extra >> 0) & 4)]);
            y[j+96] = __float2bfloat16(dl4 * iq2nl_values[((qs[j] >> 6) & 0x03) + ((extra >> 1) & 4)]);
        }
    } else {
        for (int j = 0; j < 2; ++j) {
            y[j+ 0] = dl1 * iq2nl_values[((qs[j] >> 0) & 0x03) + ((extra << 2) & 4)];
            y[j+32] = dl2 * iq2nl_values[((qs[j] >> 2) & 0x03) + ((extra << 1) & 4)];
            y[j+64] = dl3 * iq2nl_values[((qs[j] >> 4) & 0x03) + ((extra >> 0) & 4)];
            y[j+96] = dl4 * iq2nl_values[((qs[j] >> 6) & 0x03) + ((extra >> 1) & 4)];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq3_k(const void * __restrict__ vx, dst_t * __restrict__ yy) {

    const int i   = blockIdx.x;
    const block_iq3_k * x = (const block_iq3_k *) vx;

    const int tid = threadIdx.x;
    int ib128 = tid/16; // 0 or 1
    int il    = tid%16; // 0...15
    dst_t * y = yy + i*QK_K + 128*ib128 + 2*il;
    const float d = (float)x[i].d;
    const uint16_t sh = x[i].scales_h >> (8*ib128 + (il/8));
    const float dl1 = d * ((2*((x[i].scales_l[4*ib128+0] >> 4*(il/8)) & 0xf) + 1) * ((sh & 0x01) ? -1 : 1));
    const float dl2 = d * ((2*((x[i].scales_l[4*ib128+1] >> 4*(il/8)) & 0xf) + 1) * ((sh & 0x04) ? -1 : 1));
    const float dl3 = d * ((2*((x[i].scales_l[4*ib128+2] >> 4*(il/8)) & 0xf) + 1) * ((sh & 0x10) ? -1 : 1));
    const float dl4 = d * ((2*((x[i].scales_l[4*ib128+3] >> 4*(il/8)) & 0xf) + 1) * ((sh & 0x40) ? -1 : 1));
    const uint8_t * qs = x[i].qs + 32*ib128 + 2*il;
    const uint8_t * qh = x[i].qh + 2*il;
    const int16_t extra = x[i].extra >> (8*ib128 + (il/8));
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 2; ++j) {
            const uint8_t h = qh[j] >> (4*(ib128%2));
            y[j+ 0] = __float2bfloat16(dl1 * iq3nl_values[(((qs[j] >> 0) & 0x03) | ((h & 0x01) << 2)) + ((extra << 3) & 8)]);
            y[j+32] = __float2bfloat16(dl2 * iq3nl_values[(((qs[j] >> 2) & 0x03) | ((h & 0x02) << 1)) + ((extra << 1) & 8)]);
            y[j+64] = __float2bfloat16(dl3 * iq3nl_values[(((qs[j] >> 4) & 0x03) | ((h & 0x04) >> 0)) + ((extra >> 1) & 8)]);
            y[j+96] = __float2bfloat16(dl4 * iq3nl_values[(((qs[j] >> 6) & 0x03) | ((h & 0x08) >> 1)) + ((extra >> 3) & 8)]);
        }
    } else {
        for (int j = 0; j < 2; ++j) {
            const uint8_t h = qh[j] >> (4*(ib128%2));
            y[j+ 0] = dl1 * iq3nl_values[(((qs[j] >> 0) & 0x03) | ((h & 0x01) << 2)) + ((extra << 3) & 8)];
            y[j+32] = dl2 * iq3nl_values[(((qs[j] >> 2) & 0x03) | ((h & 0x02) << 1)) + ((extra << 1) & 8)];
            y[j+64] = dl3 * iq3nl_values[(((qs[j] >> 4) & 0x03) | ((h & 0x04) >> 0)) + ((extra >> 1) & 8)];
            y[j+96] = dl4 * iq3nl_values[(((qs[j] >> 6) & 0x03) | ((h & 0x08) >> 1)) + ((extra >> 3) & 8)];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq2_kl(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float scale = (float)*(const ggml_half *)cx;
    const block_iq2_kl * x = (const block_iq2_kl *)(cx + sizeof(ggml_half));
    const int64_t i   = ii - (row*n_per_row)/QK_K;

    const int64_t tid = threadIdx.x;
    const int64_t ib64 = tid/8;
    const int64_t il   = tid%8;
    dst_t * y = yy + ii*QK_K + 64*ib64 + 4*il;
    const uint8_t  * qs = x[i].qs + 16*ib64 + 2*il;
    const uint8_t  * qh = x[i].qh + 2*il;
    auto sh = x[i].scales_h >> 4*ib64;
    const float d1 = scale * (int(((x[i].scales_l[(2*ib64+0)%4] >> 4*(ib64/2)) & 0xf) | ((sh << 4) & 0x30)) - 32);
    const float d2 = scale * (int(((x[i].scales_l[(2*ib64+1)%4] >> 4*(ib64/2)) & 0xf) | ((sh << 2) & 0x30)) - 32);
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 2; ++j) {
            uint8_t h = qh[j] >> 2*ib64;
            auto val1 = (const int8_t *)(iq2kl_values + ((qs[j] & 0xf) | ((h & 1) << 4)));
            auto val2 = (const int8_t *)(iq2kl_values + ((qs[j] >>  4) | ((h & 2) << 3)));
            y[2*j+ 0] = __float2bfloat16(d1 * val1[0]);
            y[2*j+ 1] = __float2bfloat16(d1 * val1[1]);
            y[2*j+32] = __float2bfloat16(d2 * val2[0]);
            y[2*j+33] = __float2bfloat16(d2 * val2[1]);
        }
    } else {
        for (int j = 0; j < 2; ++j) {
            uint8_t h = qh[j] >> 2*ib64;
            auto val1 = (const int8_t *)(iq2kl_values + ((qs[j] & 0xf) | ((h & 1) << 4)));
            auto val2 = (const int8_t *)(iq2kl_values + ((qs[j] >>  4) | ((h & 2) << 3)));
            y[2*j+ 0] = d1 * val1[0];
            y[2*j+ 1] = d1 * val1[1];
            y[2*j+32] = d2 * val2[0];
            y[2*j+33] = d2 * val2[1];
        }
    }
}

template<typename dst_t>
static __global__ void dequantize_block_iq3_ks(const void * __restrict__ vx, dst_t * __restrict__ yy, int64_t n_per_row, int64_t row_size) {

    int64_t ii  = blockIdx.x;
    int64_t row = (QK_K * ii) / n_per_row;
    const char * cx = (const char *)vx + row * row_size;
    float scale = *(const ggml_half *)cx;
    const block_iq3_ks * x = (const block_iq3_ks *)(cx + sizeof(ggml_half));
    const int64_t i   = ii - (row*n_per_row)/QK_K;

    const int64_t tid = threadIdx.x;
    const int64_t is = tid/16;
    const int64_t il = tid%16;
    dst_t * y = yy + ii*QK_K + 128*is + 2*il;
    const uint8_t  * qs = x[i].qs + 32*is + 2*il;
    const uint8_t  * qh = x[i].qh + 2*il;
    uint16_t extra = x[i].extra >> 4*is;
    const float d0 = scale * (int(((x[i].scales[0] >> 4*is) & 0xf) | ((extra << 4) & 0x10)) - 16);
    const float d1 = scale * (int(((x[i].scales[1] >> 4*is) & 0xf) | ((extra << 3) & 0x10)) - 16);
    const float d2 = scale * (int(((x[i].scales[2] >> 4*is) & 0xf) | ((extra << 2) & 0x10)) - 16);
    const float d3 = scale * (int(((x[i].scales[3] >> 4*is) & 0xf) | ((extra << 1) & 0x10)) - 16);
    extra >>= 8;
    const int8_t * values0 = iq3nl_values + ((extra & 1) << 3);
    const int8_t * values1 = iq3nl_values + ((extra & 2) << 2);
    const int8_t * values2 = iq3nl_values + ((extra & 4) << 1);
    const int8_t * values3 = iq3nl_values + ((extra & 8) << 0);
    if constexpr (std::is_same_v<dst_t, nv_bfloat16>) {
        for (int j = 0; j < 2; ++j) {
            uint8_t h = qh[j] >> 4*is;
            y[j+ 0] = __float2bfloat16(d0 * values0[((qs[j] >> 0) & 3) | ((h << 2) & 4)]);
            y[j+32] = __float2bfloat16(d1 * values1[((qs[j] >> 2) & 3) | ((h << 1) & 4)]);
            y[j+64] = __float2bfloat16(d2 * values2[((qs[j] >> 4) & 3) | ((h >> 0) & 4)]);
            y[j+96] = __float2bfloat16(d3 * values3[((qs[j] >> 6) & 3) | ((h >> 1) & 4)]);
        }
    } else {
        for (int j = 0; j < 2; ++j) {
            uint8_t h = qh[j] >> 4*is;
            y[j+ 0] = d0 * values0[((qs[j] >> 0) & 3) | ((h << 2) & 4)];
            y[j+32] = d1 * values1[((qs[j] >> 2) & 3) | ((h << 1) & 4)];
            y[j+64] = d2 * values2[((qs[j] >> 4) & 3) | ((h >> 0) & 4)];
            y[j+96] = d3 * values3[((qs[j] >> 6) & 3) | ((h >> 1) & 4)];
        }
    }
}

template <int qk, int qr, dequantize_kernel_t dequantize_kernel, typename dst_t>
static void dequantize_block_cuda(const void * __restrict__ vx, dst_t * __restrict__ y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int num_blocks = (k + 2*CUDA_DEQUANTIZE_BLOCK_SIZE - 1) / (2*CUDA_DEQUANTIZE_BLOCK_SIZE);
    dequantize_block<qk, qr, dequantize_kernel><<<num_blocks, CUDA_DEQUANTIZE_BLOCK_SIZE, 0, stream>>>(vx, y, k);
}

static void dequantize_block_q8_0_f16_cuda(const void * __restrict__ vx, half * __restrict__ y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int num_blocks = (k + CUDA_Q8_0_NE_ALIGN - 1) / CUDA_Q8_0_NE_ALIGN;
    if (k % CUDA_Q8_0_NE_ALIGN == 0) {
        const bool need_check = false;
        dequantize_block_q8_0_f16<need_check><<<num_blocks, WARP_SIZE, 0, stream>>>(vx, y, k);
    } else {
        const bool need_check = true;
        dequantize_block_q8_0_f16<need_check><<<num_blocks, WARP_SIZE, 0, stream>>>(vx, y, k);
    }
}

template<typename dst_t>
static void dequantize_row_q2_K_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_q2_K<<<nb, 64, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_q3_K_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_q3_K<<<nb, 64, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_q4_0_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb32 = k / 32;
    const int nb = (k + 255) / 256;
    dequantize_block_q4_0<<<nb, 32, 0, stream>>>(vx, y, nb32);
}

template<typename dst_t>
static void dequantize_row_q6_0_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb32 = k / 32;
    const int nb = (k + 255) / 256;
    dequantize_block_q6_0<<<nb, 32, 0, stream>>>(vx, y, nb32);
}

template<typename dst_t>
static void dequantize_row_q4_1_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb32 = k / 32;
    const int nb = (k + 255) / 256;
    dequantize_block_q4_1<<<nb, 32, 0, stream>>>(vx, y, nb32);
}

template<typename dst_t>
static void dequantize_row_q4_K_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_q4_K<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_q5_K_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_q5_K<<<nb, 64, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_q6_K_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_q6_K<<<nb, 64, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq2_xxs_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq2_xxs<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq1_kt_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq1_kt<<<nb, 32, 0, stream>>>(vx, y, n_per_row, ggml_row_size(GGML_TYPE_IQ1_KT, n_per_row));
}

template<typename dst_t>
static void dequantize_row_iq2_kt_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq2_kt<<<nb, 32, 0, stream>>>(vx, y, n_per_row, ggml_row_size(GGML_TYPE_IQ2_KT, n_per_row));
}

template<typename dst_t>
static void dequantize_row_iq3_kt_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq3_kt<<<nb, 32, 0, stream>>>(vx, y, n_per_row, ggml_row_size(GGML_TYPE_IQ3_KT, n_per_row));
}

template<typename dst_t>
static void dequantize_row_iq4_kt_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq4_kt<<<nb, 32, 0, stream>>>(vx, y, n_per_row, ggml_row_size(GGML_TYPE_IQ4_KT, n_per_row));
}

template<typename dst_t>
static void dequantize_row_iq2_xs_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq2_xs<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq2_s_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq2_s<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq3_xxs_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq3_xxs<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq3_s_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq3_s<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq1_s_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq1_s<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq1_s_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ1_S_R4, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq1_s_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq1_m_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ1_M_R4, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq1_m_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq4_nl_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq4_nl<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq1_m_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = k / QK_K;
    dequantize_block_iq1_m<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq1_bn_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ1_BN, n_per_row);
    const int nb = (k + 255) / 256;
    dequantize_block_iq1_bn<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size, nrows);
}

template<typename dst_t>
static void dequantize_row_iq2_bn_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ2_BN, n_per_row);
    const int nb = (k + 255) / 256;
    dequantize_block_iq2_bn<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size, nrows);
}

template<typename dst_t>
static void dequantize_row_iq4_xs_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq4_xs<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq4_ks_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ4_KS, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq4_ks<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq5_ks_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ5_KS, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq5_ks<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq4_kss_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ4_KSS, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq4_kss<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq2_ks_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ2_KS, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq2_ks<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq2_k_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq2_k<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq3_k_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq3_k<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq2_kl_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ2_KL, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq2_kl<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq3_ks_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ3_KS, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq3_ks<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq3_k_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ3_K, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq3_k_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq2_k_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ2_K, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq2_k_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq4_k_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq4_k<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq4_k_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ4_K, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq4_k_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq4_ks_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ4_KS, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq4_ks_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq5_k_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq5_k<<<nb, 32, 0, stream>>>(vx, y);
}

template<typename dst_t>
static void dequantize_row_iq5_k_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ5_K, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq5_k_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq5_ks_r4_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int64_t row_size = ggml_row_size(GGML_TYPE_IQ5_KS, n_per_row);
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq5_ks_r4<<<nb, 32, 0, stream>>>(vx, y, n_per_row, row_size);
}

template<typename dst_t>
static void dequantize_row_iq6_k_cuda(const void * vx, dst_t * y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int nb = (k + QK_K - 1) / QK_K;
    dequantize_block_iq6_k<<<nb, 32, 0, stream>>>(vx, y);
}

template <typename src_t, typename dst_t>
static __global__ void convert_unary(const void * __restrict__ vx, dst_t * __restrict__ y, const int64_t k) {
    const int64_t i = (int64_t)blockDim.x*blockIdx.x + threadIdx.x;

    if (i >= k) {
        return;
    }

    const src_t * x = (src_t *) vx;

    y[i] = x[i];
}

template <typename dst_t>
static __global__ void convert_from_bf16(const nv_bfloat16 * __restrict__ x, dst_t * __restrict__ y, const int64_t k) {
    const int64_t i = (int64_t)blockDim.x*blockIdx.x + threadIdx.x;

    if (i >= k) {
        return;
    }

    y[i] = __bfloat162float(x[i]);
}

static __global__ void convert_to_bf16(const float * __restrict__ x, nv_bfloat16 * __restrict__ y, const int64_t k) {
    const int64_t i = (int64_t)blockDim.x*blockIdx.x + threadIdx.x;

    if (i >= k) {
        return;
    }

    y[i] = __float2bfloat16(x[i]);
}

static __global__ void convert_to_bf16(const half * __restrict__ x, nv_bfloat16 * __restrict__ y, const int64_t k) {
    const int64_t i = (int64_t)blockDim.x*blockIdx.x + threadIdx.x;

    if (i >= k) {
        return;
    }

    y[i] = __float2bfloat16((float)x[i]);
}

template <typename src_t, typename dst_t>
static void convert_unary_cuda(const void * __restrict__ vx, dst_t * __restrict__ y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows * n_per_row;
    const int num_blocks = (k + CUDA_DEQUANTIZE_BLOCK_SIZE - 1) / CUDA_DEQUANTIZE_BLOCK_SIZE;
    convert_unary<src_t><<<num_blocks, CUDA_DEQUANTIZE_BLOCK_SIZE, 0, stream>>>(vx, y, k);
}

template <typename dst_t>
static void convert_from_bf16_cuda(const void * __restrict__ vx, dst_t * __restrict__ y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows*n_per_row;
    const int num_blocks = (k + CUDA_DEQUANTIZE_BLOCK_SIZE - 1) / CUDA_DEQUANTIZE_BLOCK_SIZE;
    convert_from_bf16<<<num_blocks, CUDA_DEQUANTIZE_BLOCK_SIZE, 0, stream>>>((const nv_bfloat16 *)vx, y, k);
}

template <typename src_t>
static void convert_to_bf16_cuda(const void * __restrict__ vx, nv_bfloat16 * __restrict__ y, const int64_t nrows, const int64_t n_per_row, cudaStream_t stream) {
    const int64_t k = nrows*n_per_row;
    const int num_blocks = (k + CUDA_DEQUANTIZE_BLOCK_SIZE - 1) / CUDA_DEQUANTIZE_BLOCK_SIZE;
    convert_to_bf16<<<num_blocks, CUDA_DEQUANTIZE_BLOCK_SIZE, 0, stream>>>((const src_t *)vx, y, k);
}

to_bf16_cuda_t ggml_get_to_bf16_cuda(ggml_type type) {
    switch (type) {
        case GGML_TYPE_F32:
            return convert_to_bf16_cuda<float>;
        case GGML_TYPE_F16:
            return convert_to_bf16_cuda<half>;
        case GGML_TYPE_IQ2_KS:
            return dequantize_row_iq2_ks_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ2_K:
            return dequantize_row_iq2_k_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ3_K:
            return dequantize_row_iq3_k_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ2_KL:
            return dequantize_row_iq2_kl_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ3_KS:
            return dequantize_row_iq3_ks_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ4_KSS:
            return dequantize_row_iq4_kss_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ4_KS:
            return dequantize_row_iq4_ks_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ5_KS:
            return dequantize_row_iq5_ks_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ4_K:
            return dequantize_row_iq4_k_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ5_K:
            return dequantize_row_iq5_k_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ6_K:
            return dequantize_row_iq6_k_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ2_K_R4:
            return dequantize_row_iq2_k_r4_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ3_K_R4:
            return dequantize_row_iq3_k_r4_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ4_K_R4:
            return dequantize_row_iq4_k_r4_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ4_KS_R4:
            return dequantize_row_iq4_ks_r4_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ5_K_R4:
            return dequantize_row_iq5_k_r4_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ5_KS_R4:
            return dequantize_row_iq5_ks_r4_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ1_S_R4:
            return dequantize_row_iq1_s_r4_cuda<nv_bfloat16>;
        case GGML_TYPE_IQ1_M_R4:
            return dequantize_row_iq1_m_r4_cuda<nv_bfloat16>;
        default:
            return nullptr;
    }
}

to_fp16_cuda_t ggml_get_to_fp16_cuda(ggml_type type) {
    switch (type) {
        case GGML_TYPE_Q4_0:
            return dequantize_row_q4_0_cuda;
        case GGML_TYPE_Q4_1:
            return dequantize_row_q4_1_cuda;
        case GGML_TYPE_Q5_0:
            return dequantize_block_cuda<QK5_0, QR5_0, dequantize_q5_0>;
        case GGML_TYPE_Q5_1:
            return dequantize_block_cuda<QK5_1, QR5_1, dequantize_q5_1>;
        case GGML_TYPE_Q6_0:
            return dequantize_row_q6_0_cuda;
        case GGML_TYPE_Q8_0:
            if (ggml_cuda_info().devices[ggml_cuda_get_device()].cc >= CC_PASCAL) {
                return dequantize_block_q8_0_f16_cuda;
            }
            return dequantize_block_cuda<QK8_0, QR8_0, dequantize_q8_0>;
        case GGML_TYPE_Q2_K:
            return dequantize_row_q2_K_cuda;
        case GGML_TYPE_Q3_K:
            return dequantize_row_q3_K_cuda;
        case GGML_TYPE_Q4_K:
            return dequantize_row_q4_K_cuda;
        case GGML_TYPE_Q5_K:
            return dequantize_row_q5_K_cuda;
        case GGML_TYPE_Q6_K:
            return dequantize_row_q6_K_cuda;
        case GGML_TYPE_IQ2_XXS:
            return dequantize_row_iq2_xxs_cuda;
        case GGML_TYPE_IQ1_KT:
            return dequantize_row_iq1_kt_cuda;
        case GGML_TYPE_IQ2_KT:
            return dequantize_row_iq2_kt_cuda;
        case GGML_TYPE_IQ3_KT:
            return dequantize_row_iq3_kt_cuda;
        case GGML_TYPE_IQ4_KT:
            return dequantize_row_iq4_kt_cuda;
        case GGML_TYPE_IQ2_XS:
            return dequantize_row_iq2_xs_cuda;
        case GGML_TYPE_IQ2_S:
            return dequantize_row_iq2_s_cuda;
        case GGML_TYPE_IQ3_XXS:
            return dequantize_row_iq3_xxs_cuda;
        case GGML_TYPE_IQ1_S:
            return dequantize_row_iq1_s_cuda;
        case GGML_TYPE_IQ1_S_R4:
            return dequantize_row_iq1_s_r4_cuda;
        case GGML_TYPE_IQ1_M_R4:
            return dequantize_row_iq1_m_r4_cuda;
        case GGML_TYPE_IQ1_M:
            return dequantize_row_iq1_m_cuda;
        case GGML_TYPE_IQ1_BN:
            return dequantize_row_iq1_bn_cuda;
        case GGML_TYPE_IQ2_BN:
            return dequantize_row_iq2_bn_cuda;
        case GGML_TYPE_IQ4_NL:
            return dequantize_row_iq4_nl_cuda;
        case GGML_TYPE_IQ4_XS:
            return dequantize_row_iq4_xs_cuda;
        case GGML_TYPE_IQ4_KS:
            return dequantize_row_iq4_ks_cuda;
        case GGML_TYPE_IQ4_KSS:
            return dequantize_row_iq4_kss_cuda;
        case GGML_TYPE_IQ5_KS:
            return dequantize_row_iq5_ks_cuda;
        case GGML_TYPE_IQ2_KS:
            return dequantize_row_iq2_ks_cuda;
        case GGML_TYPE_IQ2_K:
            return dequantize_row_iq2_k_cuda;
        case GGML_TYPE_IQ3_K:
            return dequantize_row_iq3_k_cuda;
        case GGML_TYPE_IQ2_KL:
            return dequantize_row_iq2_kl_cuda;
        case GGML_TYPE_IQ3_KS:
            return dequantize_row_iq3_ks_cuda;
        case GGML_TYPE_IQ4_K:
            return dequantize_row_iq4_k_cuda;
        case GGML_TYPE_IQ5_K:
            return dequantize_row_iq5_k_cuda;
        case GGML_TYPE_IQ6_K:
            return dequantize_row_iq6_k_cuda;
        case GGML_TYPE_IQ3_S:
            return dequantize_row_iq3_s_cuda;
        case GGML_TYPE_F32:
            return convert_unary_cuda<float>;
        case GGML_TYPE_BF16:
            return convert_from_bf16_cuda;
        case GGML_TYPE_IQ2_K_R4:
            return dequantize_row_iq2_k_r4_cuda;
        case GGML_TYPE_IQ3_K_R4:
            return dequantize_row_iq3_k_r4_cuda;
        case GGML_TYPE_IQ4_K_R4:
            return dequantize_row_iq4_k_r4_cuda;
        case GGML_TYPE_IQ4_KS_R4:
            return dequantize_row_iq4_ks_r4_cuda;
        case GGML_TYPE_IQ5_K_R4:
            return dequantize_row_iq5_k_r4_cuda;
        case GGML_TYPE_IQ5_KS_R4:
            return dequantize_row_iq5_ks_r4_cuda;
        default:
            return nullptr;
    }
}

to_fp32_cuda_t ggml_get_to_fp32_cuda(ggml_type type) {
    switch (type) {
        case GGML_TYPE_Q4_0:
            return dequantize_row_q4_0_cuda;
        case GGML_TYPE_Q4_1:
            return dequantize_row_q4_1_cuda;
        case GGML_TYPE_Q5_0:
            return dequantize_block_cuda<QK5_0, QR5_0, dequantize_q5_0>;
        case GGML_TYPE_Q5_1:
            return dequantize_block_cuda<QK5_1, QR5_1, dequantize_q5_1>;
        case GGML_TYPE_Q6_0:
            return dequantize_row_q6_0_cuda;
        case GGML_TYPE_Q8_0:
            return dequantize_block_cuda<QK8_0, QR8_0, dequantize_q8_0>;
        case GGML_TYPE_Q2_K:
            return dequantize_row_q2_K_cuda;
        case GGML_TYPE_Q3_K:
            return dequantize_row_q3_K_cuda;
        case GGML_TYPE_Q4_K:
            return dequantize_row_q4_K_cuda;
        case GGML_TYPE_Q5_K:
            return dequantize_row_q5_K_cuda;
        case GGML_TYPE_Q6_K:
            return dequantize_row_q6_K_cuda;
        case GGML_TYPE_IQ2_XXS:
            return dequantize_row_iq2_xxs_cuda;
        case GGML_TYPE_IQ1_KT:
            return dequantize_row_iq1_kt_cuda;
        case GGML_TYPE_IQ2_KT:
            return dequantize_row_iq2_kt_cuda;
        case GGML_TYPE_IQ3_KT:
            return dequantize_row_iq3_kt_cuda;
        case GGML_TYPE_IQ4_KT:
            return dequantize_row_iq4_kt_cuda;
        case GGML_TYPE_IQ2_XS:
            return dequantize_row_iq2_xs_cuda;
        case GGML_TYPE_IQ2_S:
            return dequantize_row_iq2_s_cuda;
        case GGML_TYPE_IQ3_XXS:
            return dequantize_row_iq3_xxs_cuda;
        case GGML_TYPE_IQ1_S:
            return dequantize_row_iq1_s_cuda;
        case GGML_TYPE_IQ1_S_R4:
            return dequantize_row_iq1_s_r4_cuda;
        case GGML_TYPE_IQ1_M_R4:
            return dequantize_row_iq1_m_r4_cuda;
        case GGML_TYPE_IQ1_M:
            return dequantize_row_iq1_m_cuda;
        case GGML_TYPE_IQ1_BN:
            return dequantize_row_iq1_bn_cuda;
        case GGML_TYPE_IQ2_BN:
            return dequantize_row_iq2_bn_cuda;
        case GGML_TYPE_IQ4_NL:
            return dequantize_row_iq4_nl_cuda;
        case GGML_TYPE_IQ4_XS:
            return dequantize_row_iq4_xs_cuda;
        case GGML_TYPE_IQ4_KS:
            return dequantize_row_iq4_ks_cuda;
        case GGML_TYPE_IQ4_KSS:
            return dequantize_row_iq4_kss_cuda;
        case GGML_TYPE_IQ5_KS:
            return dequantize_row_iq5_ks_cuda;
        case GGML_TYPE_IQ2_KS:
            return dequantize_row_iq2_ks_cuda;
        case GGML_TYPE_IQ2_K:
            return dequantize_row_iq2_k_cuda;
        case GGML_TYPE_IQ3_K:
            return dequantize_row_iq3_k_cuda;
        case GGML_TYPE_IQ2_KL:
            return dequantize_row_iq2_kl_cuda;
        case GGML_TYPE_IQ3_KS:
            return dequantize_row_iq3_ks_cuda;
        case GGML_TYPE_IQ4_K:
            return dequantize_row_iq4_k_cuda;
        case GGML_TYPE_IQ5_K:
            return dequantize_row_iq5_k_cuda;
        case GGML_TYPE_IQ6_K:
            return dequantize_row_iq6_k_cuda;
        case GGML_TYPE_IQ3_S:
            return dequantize_row_iq3_s_cuda;
        case GGML_TYPE_F16:
            return convert_unary_cuda<half>;
        case GGML_TYPE_BF16:
            return convert_from_bf16_cuda;
        case GGML_TYPE_IQ2_K_R4:
            return dequantize_row_iq2_k_r4_cuda;
        case GGML_TYPE_IQ3_K_R4:
            return dequantize_row_iq3_k_r4_cuda;
        case GGML_TYPE_IQ4_K_R4:
            return dequantize_row_iq4_k_r4_cuda;
        case GGML_TYPE_IQ4_KS_R4:
            return dequantize_row_iq4_ks_r4_cuda;
        case GGML_TYPE_IQ5_K_R4:
            return dequantize_row_iq5_k_r4_cuda;
        case GGML_TYPE_IQ5_KS_R4:
            return dequantize_row_iq5_ks_r4_cuda;
        default:
            return nullptr;
    }
}
