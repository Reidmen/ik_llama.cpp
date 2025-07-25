//
// Copyright (C) 2023-2025 The ggml authors
// Copyright (C) 2024-2025 Iwan Kawrakow
// MIT license
// SPDX-License-Identifier: MIT
//

#pragma once

//
// GGML Tensor Library
//
// This documentation is still a work in progress.
// If you wish some specific topics to be covered, feel free to drop a comment:
//
//   https://github.com/ggerganov/whisper.cpp/issues/40
//
// ## Overview
//
// This library implements:
//
//  - a set of tensor operations
//  - automatic differentiation
//  - basic optimization algorithms
//
// The aim of this library is to provide a minimalistic approach for various machine learning tasks. This includes,
// but is not limited to, the following:
//
//  - linear regression
//  - support vector machines
//  - neural networks
//
// The library allows the user to define a certain function using the available tensor operations. This function
// definition is represented internally via a computation graph. Each tensor operation in the function definition
// corresponds to a node in the graph. Having the computation graph defined, the user can choose to compute the
// function's value and/or its gradient with respect to the input variables. Optionally, the function can be optimized
// using one of the available optimization algorithms.
//
// For example, here we define the function: f(x) = a*x^2 + b
//
//   {
//       struct ggml_init_params params = {
//           .mem_size   = 16*1024*1024,
//           .mem_buffer = NULL,
//       };
//
//       // memory allocation happens here
//       struct ggml_context * ctx = ggml_init(params);
//
//       struct ggml_tensor * x = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 1);
//
//       ggml_set_param(ctx, x); // x is an input variable
//
//       struct ggml_tensor * a  = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 1);
//       struct ggml_tensor * b  = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 1);
//       struct ggml_tensor * x2 = ggml_mul(ctx, x, x);
//       struct ggml_tensor * f  = ggml_add(ctx, ggml_mul(ctx, a, x2), b);
//
//       ...
//   }
//
// Notice that the function definition above does not involve any actual computation. The computation is performed only
// when the user explicitly requests it. For example, to compute the function's value at x = 2.0:
//
//   {
//       ...
//
//       struct ggml_cgraph * gf = ggml_new_graph(ctx);
//       ggml_build_forward_expand(gf, f);
//
//       // set the input variable and parameter values
//       ggml_set_f32(x, 2.0f);
//       ggml_set_f32(a, 3.0f);
//       ggml_set_f32(b, 4.0f);
//
//       ggml_graph_compute_with_ctx(ctx, &gf, n_threads);
//
//       printf("f = %f\n", ggml_get_f32_1d(f, 0));
//
//       ...
//   }
//
// The actual computation is performed in the ggml_graph_compute() function.
//
// The ggml_new_tensor_...() functions create new tensors. They are allocated in the memory buffer provided to the
// ggml_init() function. You have to be careful not to exceed the memory buffer size. Therefore, you have to know
// in advance how much memory you need for your computation. Alternatively, you can allocate a large enough memory
// and after defining the computation graph, call the ggml_used_mem() function to find out how much memory was
// actually needed.
//
// The ggml_set_param() function marks a tensor as an input variable. This is used by the automatic
// differentiation and optimization algorithms.
//
// The described approach allows to define the function graph once and then compute its forward or backward graphs
// multiple times. All computations will use the same memory buffer allocated in the ggml_init() function. This way
// the user can avoid the memory allocation overhead at runtime.
//
// The library supports multi-dimensional tensors - up to 4 dimensions. The FP16 and FP32 data types are first class
// citizens, but in theory the library can be extended to support FP8 and integer data types.
//
// Each tensor operation produces a new tensor. Initially the library was envisioned to support only the use of unary
// and binary operations. Most of the available operations fall into one of these two categories. With time, it became
// clear that the library needs to support more complex operations. The way to support these operations is not clear
// yet, but a few examples are demonstrated in the following operations:
//
//   - ggml_permute()
//   - ggml_conv_1d_1s()
//   - ggml_conv_1d_2s()
//
// For each tensor operator, the library implements a forward and backward computation function. The forward function
// computes the output tensor value given the input tensor values. The backward function computes the adjoint of the
// input tensors given the adjoint of the output tensor. For a detailed explanation of what this means, take a
// calculus class, or watch the following video:
//
//   What is Automatic Differentiation?
//   https://www.youtube.com/watch?v=wG_nF1awSSY
//
//
// ## Tensor data (struct ggml_tensor)
//
// The tensors are stored in memory via the ggml_tensor struct. The structure provides information about the size of
// the tensor, the data type, and the memory buffer where the tensor data is stored. Additionally, it contains
// pointers to the "source" tensors - i.e. the tensors that were used to compute the current tensor. For example:
//
//   {
//       struct ggml_tensor * c = ggml_add(ctx, a, b);
//
//       assert(c->src[0] == a);
//       assert(c->src[1] == b);
//   }
//
// The multi-dimensional tensors are stored in row-major order. The ggml_tensor struct contains fields for the
// number of elements in each dimension ("ne") as well as the number of bytes ("nb", a.k.a. stride). This allows
// to store tensors that are not contiguous in memory, which is useful for operations such as transposition and
// permutation. All tensor operations have to take the stride into account and not assume that the tensor is
// contiguous in memory.
//
// The data of the tensor is accessed via the "data" pointer. For example:
//
//   {
//       const int nx = 2;
//       const int ny = 3;
//
//       struct ggml_tensor * a = ggml_new_tensor_2d(ctx, GGML_TYPE_F32, nx, ny);
//
//       for (int y = 0; y < ny; y++) {
//           for (int x = 0; x < nx; x++) {
//               *(float *) ((char *) a->data + y*a->nb[1] + x*a->nb[0]) = x + y;
//           }
//       }
//
//       ...
//   }
//
// Alternatively, there are helper functions, such as ggml_get_f32_1d() and ggml_set_f32_1d() that can be used.
//
// ## The matrix multiplication operator (ggml_mul_mat)
//
// TODO
//
//
// ## Multi-threading
//
// TODO
//
//
// ## Overview of ggml.c
//
// TODO
//
//
// ## SIMD optimizations
//
// TODO
//
//
// ## Debugging ggml
//
// TODO
//
//

#ifdef GGML_SHARED
#    if defined(_WIN32) && !defined(__MINGW32__)
#        ifdef GGML_BUILD
#            define GGML_API __declspec(dllexport)
#        else
#            define GGML_API __declspec(dllimport)
#        endif
#    else
#        define GGML_API __attribute__ ((visibility ("default")))
#    endif
#else
#    define GGML_API
#endif

#ifdef GGML_MULTIPLATFORM
#    if defined(_WIN32)
#        define GGML_CALL
#    else
#        define GGML_CALL __attribute__((__ms_abi__))
#    endif
#else
#    define GGML_CALL
#endif

// TODO: support for clang
#ifdef __GNUC__
#    define GGML_DEPRECATED(func, hint) func __attribute__((deprecated(hint)))
#elif defined(_MSC_VER)
#    define GGML_DEPRECATED(func, hint) __declspec(deprecated(hint)) func
#else
#    define GGML_DEPRECATED(func, hint) func
#endif

#ifndef __GNUC__
#    define GGML_ATTRIBUTE_FORMAT(...)
#elif defined(__MINGW32__)
#    define GGML_ATTRIBUTE_FORMAT(...) __attribute__((format(gnu_printf, __VA_ARGS__)))
#else
#    define GGML_ATTRIBUTE_FORMAT(...) __attribute__((format(printf, __VA_ARGS__)))
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define GGML_FILE_MAGIC   0x67676d6c // "ggml"
#define GGML_FILE_VERSION 1

#define GGML_QNT_VERSION        2    // bump this on quantization format changes
#define GGML_QNT_VERSION_FACTOR 1000 // do not change this

#define GGML_MAX_DIMS           4
#define GGML_MAX_PARAMS         2048
#ifndef GGML_MAX_CONTEXTS
// Maximum number of model contexts (e.g., for model shards). 
// Increase this value using -DGGML_MAX_CONTEXTS=<value> in CMake 
// if you need to load more than 64 model shards.
#define GGML_MAX_CONTEXTS 64
#endif
#define GGML_MAX_SRC            10
#ifndef GGML_MAX_NAME
#define GGML_MAX_NAME           64
#endif
#define GGML_MAX_OP_PARAMS      64
#define GGML_DEFAULT_N_THREADS  4
#define GGML_DEFAULT_GRAPH_SIZE 2048
#if UINTPTR_MAX == 0xFFFFFFFF
    #define GGML_MEM_ALIGN 4
#else
    #define GGML_MEM_ALIGN 16
#endif

#define GGML_EXIT_SUCCESS 0
#define GGML_EXIT_ABORTED 1

#define GGUF_MAGIC "GGUF"

#define GGUF_VERSION 3

#define GGUF_DEFAULT_ALIGNMENT 32

#define GGML_UNUSED(x) (void)(x)

#define GGML_PAD(x, n) (((x) + (n) - 1) & ~((n) - 1))

#ifndef NDEBUG
#define GGML_UNREACHABLE() do { fprintf(stderr, "statement should be unreachable\n"); abort(); } while(0)
#elif defined(__GNUC__)
#define GGML_UNREACHABLE() __builtin_unreachable()
#elif defined(_MSC_VER)
#define GGML_UNREACHABLE() __assume(0)
#else
#define GGML_UNREACHABLE() ((void) 0)
#endif

#ifdef __cplusplus
#define GGML_NORETURN [[noreturn]]
#elif defined(_MSC_VER)
#define GGML_NORETURN __declspec(noreturn)
#else
#define GGML_NORETURN _Noreturn
#endif

#define GGML_ABORT(...) ggml_abort(__FILE__, __LINE__, __VA_ARGS__)
#define GGML_ASSERT(x) if (!(x)) GGML_ABORT("GGML_ASSERT(%s) failed", #x)

// used to copy the number of elements and stride in bytes of tensors into local variables.
// main purpose is to reduce code duplication and improve readability.
//
// example:
//
//    GGML_TENSOR_LOCALS(int64_t, ne1, src1, ne);
//    GGML_TENSOR_LOCALS(size_t,  nb1, src1, nb);
//
#define GGML_TENSOR_LOCALS_1(type, prefix, pointer, array) \
    const type prefix##0 = (pointer)->array[0]; \
    GGML_UNUSED(prefix##0);
#define GGML_TENSOR_LOCALS_2(type, prefix, pointer, array) \
    GGML_TENSOR_LOCALS_1    (type, prefix, pointer, array) \
    const type prefix##1 = (pointer)->array[1]; \
    GGML_UNUSED(prefix##1);
#define GGML_TENSOR_LOCALS_3(type, prefix, pointer, array) \
    GGML_TENSOR_LOCALS_2    (type, prefix, pointer, array) \
    const type prefix##2 = (pointer)->array[2]; \
    GGML_UNUSED(prefix##2);
#define GGML_TENSOR_LOCALS(type, prefix, pointer, array) \
    GGML_TENSOR_LOCALS_3  (type, prefix, pointer, array) \
    const type prefix##3 = (pointer)->array[3]; \
    GGML_UNUSED(prefix##3);

#define GGML_TENSOR_UNARY_OP_LOCALS \
    GGML_TENSOR_LOCALS(int64_t, ne0, src0, ne) \
    GGML_TENSOR_LOCALS(size_t,  nb0, src0, nb) \
    GGML_TENSOR_LOCALS(int64_t, ne,  dst,  ne) \
    GGML_TENSOR_LOCALS(size_t,  nb,  dst,  nb)

#define GGML_TENSOR_BINARY_OP_LOCALS \
    GGML_TENSOR_LOCALS(int64_t, ne0, src0, ne) \
    GGML_TENSOR_LOCALS(size_t,  nb0, src0, nb) \
    GGML_TENSOR_LOCALS(int64_t, ne1, src1, ne) \
    GGML_TENSOR_LOCALS(size_t,  nb1, src1, nb) \
    GGML_TENSOR_LOCALS(int64_t, ne,  dst,  ne) \
    GGML_TENSOR_LOCALS(size_t,  nb,  dst,  nb)

#define GGML_TENSOR_BINARY_OP_LOCALS01 \
    GGML_TENSOR_LOCALS(int64_t, ne0, src0, ne) \
    GGML_TENSOR_LOCALS(size_t,  nb0, src0, nb) \
    GGML_TENSOR_LOCALS(int64_t, ne1, src1, ne) \
    GGML_TENSOR_LOCALS(size_t,  nb1, src1, nb)

#ifdef  __cplusplus
extern "C" {
#endif

    GGML_NORETURN GGML_ATTRIBUTE_FORMAT(3, 4)
    GGML_API void ggml_abort(const char * file, int line, const char * fmt, ...);

    enum ggml_status {
        GGML_STATUS_ALLOC_FAILED = -2,
        GGML_STATUS_FAILED = -1,
        GGML_STATUS_SUCCESS = 0,
        GGML_STATUS_ABORTED = 1,
    };

    // get ggml_status name string
    GGML_API GGML_CALL const char * ggml_status_to_string(enum ggml_status status);

    // ieee 754-2008 half-precision float16
    // todo: make this not an integral type
    typedef uint16_t ggml_fp16_t;
    GGML_API float       ggml_fp16_to_fp32(ggml_fp16_t);
    GGML_API ggml_fp16_t ggml_fp32_to_fp16(float);
    GGML_API void        ggml_fp16_to_fp32_row(const ggml_fp16_t *, float *, int64_t);
    GGML_API void        ggml_fp32_to_fp16_row(const float *, ggml_fp16_t *, int64_t);

    // google brain half-precision bfloat16
    typedef struct { uint16_t bits; } ggml_bf16_t;
    GGML_API ggml_bf16_t ggml_fp32_to_bf16(float);
    GGML_API float       ggml_bf16_to_fp32(ggml_bf16_t);  // consider just doing << 16
    GGML_API void        ggml_bf16_to_fp32_row(const ggml_bf16_t *, float *, int64_t);
    GGML_API void        ggml_fp32_to_bf16_row_ref(const float *, ggml_bf16_t *, int64_t);
    GGML_API void        ggml_fp32_to_bf16_row(const float *, ggml_bf16_t *, int64_t);

    struct ggml_object;
    struct ggml_context;

    // NOTE: always add types at the end of the enum to keep backward compatibility
    enum ggml_type {
        GGML_TYPE_F32     = 0,
        GGML_TYPE_F16     = 1,
        GGML_TYPE_Q4_0    = 2,
        GGML_TYPE_Q4_1    = 3,
        // GGML_TYPE_Q4_2 = 4, support has been removed
        // GGML_TYPE_Q4_3 = 5, support has been removed
        GGML_TYPE_Q5_0    = 6,
        GGML_TYPE_Q5_1    = 7,
        GGML_TYPE_Q8_0    = 8,
        GGML_TYPE_Q8_1    = 9,
        GGML_TYPE_Q2_K    = 10,
        GGML_TYPE_Q3_K    = 11,
        GGML_TYPE_Q4_K    = 12,
        GGML_TYPE_Q5_K    = 13,
        GGML_TYPE_Q6_K    = 14,
        GGML_TYPE_Q8_K    = 15,
        GGML_TYPE_IQ2_XXS = 16,
        GGML_TYPE_IQ2_XS  = 17,
        GGML_TYPE_IQ3_XXS = 18,
        GGML_TYPE_IQ1_S   = 19,
        GGML_TYPE_IQ4_NL  = 20,
        GGML_TYPE_IQ3_S   = 21,
        GGML_TYPE_IQ2_S   = 22,
        GGML_TYPE_IQ4_XS  = 23,
        GGML_TYPE_I8      = 24,
        GGML_TYPE_I16     = 25,
        GGML_TYPE_I32     = 26,
        GGML_TYPE_I64     = 27,
        GGML_TYPE_F64     = 28,
        GGML_TYPE_IQ1_M   = 29,
        GGML_TYPE_BF16    = 30,
        GGML_TYPE_Q4_0_4_4 = 31,
        GGML_TYPE_Q4_0_4_8 = 32,
        GGML_TYPE_Q4_0_8_8 = 33,
        //
        // So we are able to consume MS BitNet I2_S quants
        //
        GGML_TYPE_I2_S    = 36,
        //
        GGML_TYPE_Q8_0_X4 = 97,
        GGML_TYPE_Q8_1_X4 = 98,
        GGML_TYPE_Q8_2_X4 = 99,
        GGML_TYPE_Q6_0    = 133,
        GGML_TYPE_IQ1_BN  = 134,
        GGML_TYPE_IQ2_BN  = 135,
        GGML_TYPE_Q8_K64  = 136,
        GGML_TYPE_IQ2_K   = 137,
        GGML_TYPE_IQ3_K   = 138,
        GGML_TYPE_IQ4_K   = 139,
        GGML_TYPE_IQ5_K   = 140,
        GGML_TYPE_IQ6_K   = 141,
        // depricated: GGML_TYPE_IQ2_TN  = 142,
        // depricated: GGML_TYPE_IQ1_TN  = 143,
        GGML_TYPE_IQ4_KS  = 144,
        GGML_TYPE_IQ2_KS  = 145,
        GGML_TYPE_IQ4_KSS = 146,
        GGML_TYPE_Q8_K16  = 147,
        GGML_TYPE_Q8_K32  = 148,
        GGML_TYPE_Q8_KR8  = 149,
        GGML_TYPE_Q8_K128 = 150,
        GGML_TYPE_Q8_KV   = 151,
        GGML_TYPE_IQ5_KS  = 152,
        GGML_TYPE_IQ2_KT  = 153,
        GGML_TYPE_IQ3_KT  = 154,
        GGML_TYPE_IQ4_KT  = 155,
        GGML_TYPE_IQ3_KS  = 156,
        GGML_TYPE_IQ2_KL  = 157,
        GGML_TYPE_IQ1_KT  = 158,

        GGML_TYPE_Q4_0_R8   = 202,
        GGML_TYPE_Q5_0_R4   = 206,
        GGML_TYPE_Q8_0_R8   = 208,
        GGML_TYPE_Q2_K_R4   = 210,
        GGML_TYPE_Q3_K_R4   = 211,
        GGML_TYPE_Q4_K_R4   = 212,
        GGML_TYPE_Q5_K_R4   = 213,
        GGML_TYPE_Q6_K_R4   = 214,
        GGML_TYPE_IQ2_XXS_R4= 216,
        GGML_TYPE_IQ2_XS_R4 = 217,
        GGML_TYPE_IQ3_XXS_R4= 218,
        GGML_TYPE_IQ1_S_R4  = 219,
        GGML_TYPE_IQ4_NL_R4 = 220,
        GGML_TYPE_IQ3_S_R4  = 221,
        GGML_TYPE_IQ2_S_R4  = 222,
        GGML_TYPE_IQ4_XS_R8 = 223,
        GGML_TYPE_IQ1_M_R4  = 229,
        GGML_TYPE_BF16_R16  = 230,
        GGML_TYPE_Q6_0_R4   = 233,
        GGML_TYPE_IQ2_BN_R4 = 335,
        GGML_TYPE_IQ2_K_R4  = 337,
        GGML_TYPE_IQ3_K_R4  = 338,
        GGML_TYPE_IQ4_K_R4  = 339,
        GGML_TYPE_IQ5_K_R4  = 340,
        GGML_TYPE_IQ4_KS_R4 = 344,
        GGML_TYPE_IQ5_KS_R4 = 352,
        GGML_TYPE_Q8_KV_R8  = 398,
        GGML_TYPE_Q8_K_R8   = 399,
        GGML_TYPE_COUNT,
    };

    // precision
    enum ggml_prec {
        GGML_PREC_DEFAULT,
        GGML_PREC_F32,
    };

    enum ggml_backend_type {
        GGML_BACKEND_TYPE_CPU = 0,
        GGML_BACKEND_TYPE_GPU = 10,
        GGML_BACKEND_TYPE_GPU_SPLIT = 20,
    };

    // model file types
    enum ggml_ftype {
        GGML_FTYPE_UNKNOWN        = -1,
        GGML_FTYPE_ALL_F32        = 0,
        GGML_FTYPE_MOSTLY_F16     = 1,  // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_0    = 2,  // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_1    = 3,  // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_1_SOME_F16 = 4, // tok_embeddings.weight and output.weight are F16
        GGML_FTYPE_MOSTLY_Q8_0    = 7,  // except 1d tensors
        GGML_FTYPE_MOSTLY_Q5_0    = 8,  // except 1d tensors
        GGML_FTYPE_MOSTLY_Q5_1    = 9,  // except 1d tensors
        GGML_FTYPE_MOSTLY_Q2_K    = 10, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q3_K    = 11, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_K    = 12, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q5_K    = 13, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q6_K    = 14, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_XXS = 15, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_XS  = 16, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_XXS = 17, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ1_S   = 18, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_NL  = 19, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_S   = 20, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_S   = 21, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_XS  = 22, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ1_M   = 23, // except 1d tensors
        GGML_FTYPE_MOSTLY_BF16    = 24, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_0_4_4 = 25, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_0_4_8 = 26, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_0_8_8 = 27, // except 1d tensors
        //
        GGML_FTYPE_MOSTLY_Q6_0    = 127, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ1_BN  = 128, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_BN  = 129, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_K   = 130, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_K   = 131, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_K   = 132, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ5_K   = 133, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ6_K   = 134, // except 1d tensors
        // depricated: GGML_FTYPE_MOSTLY_IQ2_TN  = 135, // except 1d tensors
        // depricated: GGML_FTYPE_MOSTLY_IQ1_TN  = 136, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_KS  = 137, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_KS  = 138, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_KSS = 139, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q8_KV   = 140, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ5_KS  = 141, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_KT  = 142, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_KT  = 143, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_KT  = 144, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_KS  = 145, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_KL  = 146, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ1_KT  = 147, // except 1d tensors
                                         //
        GGML_FTYPE_MOSTLY_Q4_0_R8   = 202, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q8_0_R8   = 207, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q5_0_R4   = 208, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q2_K_R4   = 210, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q3_K_R4   = 211, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q4_K_R4   = 212, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q5_K_R4   = 213, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q6_K_R4   = 214, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_XXS_R4= 215, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_XS_R4 = 216, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_XXS_R4= 217, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ1_S_R4  = 218, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_NL_R4 = 219, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_S_R4  = 220, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_S_R4  = 221, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_XS_R8 = 222, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ1_M_R4  = 223, // except 1d tensors
        GGML_FTYPE_MOSTLY_BF16_R16  = 224, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q6_0_R4   = 227, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_BN_R4 = 329, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ2_K_R4  = 330, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ3_K_R4  = 331, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_K_R4  = 332, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ5_K_R4  = 333, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ4_KS_R4 = 337, // except 1d tensors
        GGML_FTYPE_MOSTLY_IQ5_KS_R4 = 341, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q8_KV_R8  = 398, // except 1d tensors
        GGML_FTYPE_MOSTLY_Q8_K_R8   = 399, // except 1d tensors
    };

    // available tensor operations:
    enum ggml_op {
        GGML_OP_NONE = 0,

        GGML_OP_DUP,
        GGML_OP_ADD,
        GGML_OP_ADD1,
        GGML_OP_ACC,
        GGML_OP_SUB,
        GGML_OP_MUL,
        GGML_OP_DIV,
        GGML_OP_SQR,
        GGML_OP_SQRT,
        GGML_OP_LOG,
        GGML_OP_SUM,
        GGML_OP_SUM_ROWS,
        GGML_OP_MEAN,
        GGML_OP_ARGMAX,
        GGML_OP_REPEAT,
        GGML_OP_REPEAT_BACK,
        GGML_OP_CONCAT,
        GGML_OP_SILU_BACK,
        GGML_OP_NORM, // normalize
        GGML_OP_RMS_NORM,
        GGML_OP_RMS_NORM_BACK,
        GGML_OP_GROUP_NORM,
        GGML_OP_FUSED_RMS_NORM,
        GGML_OP_FUSED_MUL_UNARY,
        GGML_OP_MULTI_ADD,

        GGML_OP_MUL_MAT,
        GGML_OP_MUL_MAT_ID,
        GGML_OP_OUT_PROD,
        GGML_OP_MOE_FUSED_UP_GATE,

        GGML_OP_SCALE,
        GGML_OP_SET,
        GGML_OP_CPY,
        GGML_OP_CONT,
        GGML_OP_RESHAPE,
        GGML_OP_VIEW,
        GGML_OP_PERMUTE,
        GGML_OP_TRANSPOSE,
        GGML_OP_GET_ROWS,
        GGML_OP_GET_ROWS_BACK,
        GGML_OP_DIAG,
        GGML_OP_DIAG_MASK_INF,
        GGML_OP_DIAG_MASK_ZERO,
        GGML_OP_SOFT_MAX,
        GGML_OP_SOFT_MAX_BACK,
        GGML_OP_ROPE,
        GGML_OP_ROPE_BACK,
        GGML_OP_CLAMP,
        GGML_OP_CONV_TRANSPOSE_1D,
        GGML_OP_IM2COL,
        GGML_OP_CONV_TRANSPOSE_2D,
        GGML_OP_POOL_1D,
        GGML_OP_POOL_2D,
        GGML_OP_UPSCALE, // nearest interpolate
        GGML_OP_PAD,
        GGML_OP_ARANGE,
        GGML_OP_TIMESTEP_EMBEDDING,
        GGML_OP_ARGSORT,
        GGML_OP_ARGSORT_THRESH,
        GGML_OP_LEAKY_RELU,
        GGML_OP_SOFTCAP,
        GGML_OP_SOFT_CAP_MAX,

        GGML_OP_FLASH_ATTN_EXT,
        GGML_OP_FLASH_ATTN_BACK,
        GGML_OP_SSM_CONV,
        GGML_OP_SSM_SCAN,
        GGML_OP_WIN_PART,
        GGML_OP_WIN_UNPART,
        GGML_OP_GET_REL_POS,
        GGML_OP_ADD_REL_POS,
        GGML_OP_UNARY,

        GGML_OP_MAP_UNARY,
        GGML_OP_MAP_BINARY,

        GGML_OP_MAP_CUSTOM1_F32,
        GGML_OP_MAP_CUSTOM2_F32,
        GGML_OP_MAP_CUSTOM3_F32,

        GGML_OP_MAP_CUSTOM1,
        GGML_OP_MAP_CUSTOM2,
        GGML_OP_MAP_CUSTOM3,

        GGML_OP_CROSS_ENTROPY_LOSS,
        GGML_OP_CROSS_ENTROPY_LOSS_BACK,
        GGML_OP_COUNT,
    };

    enum ggml_unary_op {
        GGML_UNARY_OP_ABS,
        GGML_UNARY_OP_SGN,
        GGML_UNARY_OP_NEG,
        GGML_UNARY_OP_STEP,
        GGML_UNARY_OP_TANH,
        GGML_UNARY_OP_ELU,
        GGML_UNARY_OP_RELU,
        GGML_UNARY_OP_SIGMOID,
        GGML_UNARY_OP_GELU,
        GGML_UNARY_OP_GELU_QUICK,
        GGML_UNARY_OP_SILU,
        GGML_UNARY_OP_HARDSWISH,
        GGML_UNARY_OP_HARDSIGMOID,
        GGML_UNARY_OP_SWIGLU,

        GGML_UNARY_OP_COUNT,
    };

    enum ggml_object_type {
        GGML_OBJECT_TYPE_TENSOR,
        GGML_OBJECT_TYPE_GRAPH,
        GGML_OBJECT_TYPE_WORK_BUFFER
    };

    enum ggml_log_level {
        GGML_LOG_LEVEL_ERROR = 2,
        GGML_LOG_LEVEL_WARN  = 3,
        GGML_LOG_LEVEL_INFO  = 4,
        GGML_LOG_LEVEL_DEBUG = 5
    };

    enum ggml_tensor_flag {
        GGML_TENSOR_FLAG_INPUT  = 1,
        GGML_TENSOR_FLAG_OUTPUT = 2,
        GGML_TENSOR_FLAG_PARAM  = 4,
    };

    // ggml object
    struct ggml_object {
        size_t offs;
        size_t size;

        struct ggml_object * next;

        enum ggml_object_type type;

        char padding[4];
    };

    static const size_t GGML_OBJECT_SIZE = sizeof(struct ggml_object);

    // n-dimensional tensor
    struct ggml_tensor {
        enum ggml_type         type;

        GGML_DEPRECATED(enum ggml_backend_type backend, "use the buffer type to find the storage location of the tensor");

        struct ggml_backend_buffer * buffer;

        int64_t ne[GGML_MAX_DIMS]; // number of elements
        size_t  nb[GGML_MAX_DIMS]; // stride in bytes:
                                   // nb[0] = ggml_type_size(type)
                                   // nb[1] = nb[0]   * (ne[0] / ggml_blck_size(type)) + padding
                                   // nb[i] = nb[i-1] * ne[i-1]

        // compute data
        enum ggml_op op;

        // op params - allocated as int32_t for alignment
        int32_t op_params[GGML_MAX_OP_PARAMS / sizeof(int32_t)];

        int32_t flags;

        struct ggml_tensor * grad;
        struct ggml_tensor * src[GGML_MAX_SRC];

        // source tensor and offset for views
        struct ggml_tensor * view_src;
        size_t               view_offs;

        void * data;

        char name[GGML_MAX_NAME];

        void * extra; // extra things e.g. for ggml-cuda.cu

        // char padding[4];
    };

    static const size_t GGML_TENSOR_SIZE = sizeof(struct ggml_tensor);

    // Abort callback
    // If not NULL, called before ggml computation
    // If it returns true, the computation is aborted
    typedef bool (*ggml_abort_callback)(void * data);

    // the compute plan that needs to be prepared for ggml_graph_compute()
    // since https://github.com/ggerganov/ggml/issues/287
    struct ggml_cplan {
        size_t    work_size; // size of work buffer, calculated by `ggml_graph_plan()`
        uint8_t * work_data; // work buffer, to be allocated by caller before calling to `ggml_graph_compute()`

        int n_threads;

        // abort ggml_graph_compute when true
        ggml_abort_callback abort_callback;
        void *              abort_callback_data;
    };

    enum ggml_cgraph_eval_order {
        GGML_CGRAPH_EVAL_ORDER_LEFT_TO_RIGHT = 0,
        GGML_CGRAPH_EVAL_ORDER_RIGHT_TO_LEFT,
        GGML_CGRAPH_EVAL_ORDER_COUNT
    };

    typedef uint32_t ggml_bitset_t;

    struct ggml_hash_set {
        size_t size;
        ggml_bitset_t * used;
        struct ggml_tensor ** keys;
    };

    // computation graph
    struct ggml_cgraph {
        int size;
        int n_nodes;
        int n_leafs;

        struct ggml_tensor ** nodes;
        struct ggml_tensor ** grads;
        struct ggml_tensor ** leafs;

        struct ggml_hash_set visited_hash_set;

        enum ggml_cgraph_eval_order order;
    };

    // scratch buffer
    struct ggml_scratch {
        size_t offs;
        size_t size;
        void * data;
    };

    struct ggml_init_params {
        // memory pool
        size_t mem_size;   // bytes
        void * mem_buffer; // if NULL, memory will be allocated internally
        bool   no_alloc;   // don't allocate memory for the tensor data
    };

    // numa strategies
    enum ggml_numa_strategy {
        GGML_NUMA_STRATEGY_DISABLED   = 0,
        GGML_NUMA_STRATEGY_DISTRIBUTE = 1,
        GGML_NUMA_STRATEGY_ISOLATE    = 2,
        GGML_NUMA_STRATEGY_NUMACTL    = 3,
        GGML_NUMA_STRATEGY_MIRROR     = 4,
        GGML_NUMA_STRATEGY_COUNT
    };

    //
    // GUID
    //

    // GUID types
    typedef uint8_t ggml_guid[16];
    typedef ggml_guid * ggml_guid_t;

    GGML_API bool ggml_guid_matches(ggml_guid_t guid_a, ggml_guid_t guid_b);

    // misc

    GGML_API void    ggml_time_init(void); // call this once at the beginning of the program
    GGML_API int64_t ggml_time_ms(void);
    GGML_API int64_t ggml_time_us(void);
    GGML_API int64_t ggml_cycles(void);
    GGML_API int64_t ggml_cycles_per_ms(void);

    // accepts a UTF-8 path, even on Windows
    GGML_API FILE *  ggml_fopen(const char * fname, const char * mode);

    GGML_API void    ggml_numa_init(enum ggml_numa_strategy numa); // call once for better performance on NUMA systems
    GGML_API bool    ggml_is_numa(void); // true if init detected that system has >1 NUMA node

    GGML_API void    ggml_print_object (const struct ggml_object * obj);
    GGML_API void    ggml_print_objects(const struct ggml_context * ctx);

    GGML_API GGML_CALL int64_t ggml_nelements   (const struct ggml_tensor * tensor);
    GGML_API GGML_CALL int64_t ggml_nrows       (const struct ggml_tensor * tensor);
    GGML_API GGML_CALL size_t  ggml_nbytes      (const struct ggml_tensor * tensor);
    GGML_API           size_t  ggml_nbytes_pad  (const struct ggml_tensor * tensor); // same as ggml_nbytes() but padded to GGML_MEM_ALIGN

    // TODO: remove the following from the public API to avoid unnecessary assumptions about data layout
    GGML_API GGML_CALL int64_t ggml_blck_size(enum ggml_type type);
    GGML_API GGML_CALL size_t  ggml_type_size(enum ggml_type type);             // size in bytes for all elements in a block
    GGML_API GGML_CALL size_t  ggml_row_size (enum ggml_type type, int64_t ne); // size in bytes for all elements in a row

    GGML_DEPRECATED(
    GGML_API double ggml_type_sizef(enum ggml_type type), // ggml_type_size()/ggml_blck_size() as float
    "use ggml_row_size() instead");

    GGML_API GGML_CALL const char * ggml_type_name(enum ggml_type type);
    GGML_API GGML_CALL const char * ggml_op_name  (enum ggml_op   op);
    GGML_API           const char * ggml_op_symbol(enum ggml_op   op);

    GGML_API GGML_CALL bool ggml_is_noop(const struct ggml_tensor * tensor);

    GGML_API           const char * ggml_unary_op_name(enum ggml_unary_op op);
    GGML_API GGML_CALL const char * ggml_op_desc(const struct ggml_tensor * t); // unary or op name

    GGML_API GGML_CALL size_t  ggml_element_size(const struct ggml_tensor * tensor);

    GGML_API GGML_CALL bool    ggml_is_quantized(enum ggml_type type);

    // TODO: temporary until model loading of ggml examples is refactored
    GGML_API enum ggml_type ggml_ftype_to_ggml_type(enum ggml_ftype ftype);

    GGML_API GGML_CALL bool ggml_is_transposed(const struct ggml_tensor * tensor);
    GGML_API GGML_CALL bool ggml_is_permuted  (const struct ggml_tensor * tensor);
    GGML_API GGML_CALL bool ggml_is_empty     (const struct ggml_tensor * tensor);
    GGML_API           bool ggml_is_scalar    (const struct ggml_tensor * tensor);
    GGML_API           bool ggml_is_vector    (const struct ggml_tensor * tensor);
    GGML_API           bool ggml_is_matrix    (const struct ggml_tensor * tensor);
    GGML_API           bool ggml_is_3d        (const struct ggml_tensor * tensor);
    GGML_API           int  ggml_n_dims       (const struct ggml_tensor * tensor); // returns 1 for scalars

    GGML_API GGML_CALL bool ggml_is_contiguous  (const struct ggml_tensor * tensor);
    GGML_API GGML_CALL bool ggml_is_contiguous_0(const struct ggml_tensor * tensor); // same as ggml_is_contiguous()
    GGML_API GGML_CALL bool ggml_is_contiguous_1(const struct ggml_tensor * tensor); // contiguous for dims >= 1
    GGML_API GGML_CALL bool ggml_is_contiguous_2(const struct ggml_tensor * tensor); // contiguous for dims >= 2

    // returns whether the tensor elements are allocated as one contiguous block of memory (no gaps, but permutation ok)
    GGML_API bool ggml_is_contiguously_allocated(const struct ggml_tensor * tensor);

    // true for tensor that is stored in memory as CxWxHxN and has been permuted to WxHxCxN
    GGML_API bool ggml_is_contiguous_channels(const struct ggml_tensor * tensor);

    // true if the elements in dimension 0 are contiguous, or there is just 1 block of elements
    GGML_API bool ggml_is_contiguous_rows(const struct ggml_tensor * tensor);

    GGML_API bool ggml_are_same_shape (const struct ggml_tensor * t0, const struct ggml_tensor * t1);
    GGML_API bool ggml_are_same_stride(const struct ggml_tensor * t0, const struct ggml_tensor * t1);

    GGML_API bool ggml_can_repeat(const struct ggml_tensor * t0, const struct ggml_tensor * t1);

    // use this to compute the memory overhead of a tensor
    GGML_API size_t ggml_tensor_overhead(void);

    GGML_API bool ggml_validate_row_data(enum ggml_type type, const void * data, size_t nbytes);

    // main

    GGML_API struct ggml_context * ggml_init(struct ggml_init_params params);
    GGML_API void                  ggml_free(struct ggml_context * ctx);

    GGML_API size_t  ggml_used_mem(const struct ggml_context * ctx);

    GGML_API size_t  ggml_set_scratch (struct ggml_context * ctx, struct ggml_scratch scratch);
    GGML_API bool    ggml_get_no_alloc(struct ggml_context * ctx);
    GGML_API void    ggml_set_no_alloc(struct ggml_context * ctx, bool no_alloc);

    GGML_API void *  ggml_get_mem_buffer     (const struct ggml_context * ctx);
    GGML_API size_t  ggml_get_mem_size       (const struct ggml_context * ctx);
    GGML_API size_t  ggml_get_max_tensor_size(const struct ggml_context * ctx);

    GGML_API struct ggml_tensor * ggml_new_tensor(
            struct ggml_context * ctx,
            enum   ggml_type type,
            int    n_dims,
            const int64_t *ne);

    GGML_API struct ggml_tensor * ggml_new_tensor_1d(
            struct ggml_context * ctx,
            enum   ggml_type type,
            int64_t ne0);

    GGML_API struct ggml_tensor * ggml_new_tensor_2d(
            struct ggml_context * ctx,
            enum   ggml_type type,
            int64_t ne0,
            int64_t ne1);

    GGML_API struct ggml_tensor * ggml_new_tensor_3d(
            struct ggml_context * ctx,
            enum   ggml_type type,
            int64_t ne0,
            int64_t ne1,
            int64_t ne2);

    GGML_API struct ggml_tensor * ggml_new_tensor_4d(
            struct ggml_context * ctx,
            enum   ggml_type type,
            int64_t ne0,
            int64_t ne1,
            int64_t ne2,
            int64_t ne3);

    GGML_API struct ggml_tensor * ggml_new_i32(struct ggml_context * ctx, int32_t value);
    GGML_API struct ggml_tensor * ggml_new_f32(struct ggml_context * ctx, float value);

    GGML_API struct ggml_tensor * ggml_dup_tensor (struct ggml_context * ctx, const struct ggml_tensor * src);
    GGML_API struct ggml_tensor * ggml_view_tensor(struct ggml_context * ctx, struct ggml_tensor * src);

    // Context tensor enumeration and lookup
    GGML_API struct ggml_tensor * ggml_get_first_tensor(const struct ggml_context * ctx);
    GGML_API struct ggml_tensor * ggml_get_next_tensor (const struct ggml_context * ctx, struct ggml_tensor * tensor);
    GGML_API struct ggml_tensor * ggml_get_tensor(struct ggml_context * ctx, const char * name);

    GGML_API struct ggml_tensor * ggml_set_zero(struct ggml_tensor * tensor);
    GGML_API struct ggml_tensor * ggml_set_i32 (struct ggml_tensor * tensor, int32_t value);
    GGML_API struct ggml_tensor * ggml_set_f32 (struct ggml_tensor * tensor, float value);

    // Converts a flat index into coordinates
    GGML_API void    ggml_unravel_index(const struct ggml_tensor * tensor, int64_t i, int64_t * i0, int64_t * i1, int64_t * i2, int64_t * i3);

    GGML_API int32_t ggml_get_i32_1d(const struct ggml_tensor * tensor, int i);
    GGML_API void    ggml_set_i32_1d(const struct ggml_tensor * tensor, int i, int32_t value);

    GGML_API int32_t ggml_get_i32_nd(const struct ggml_tensor * tensor, int i0, int i1, int i2, int i3);
    GGML_API void    ggml_set_i32_nd(const struct ggml_tensor * tensor, int i0, int i1, int i2, int i3, int32_t value);

    GGML_API float   ggml_get_f32_1d(const struct ggml_tensor * tensor, int i);
    GGML_API void    ggml_set_f32_1d(const struct ggml_tensor * tensor, int i, float value);

    GGML_API float   ggml_get_f32_nd(const struct ggml_tensor * tensor, int i0, int i1, int i2, int i3);
    GGML_API void    ggml_set_f32_nd(const struct ggml_tensor * tensor, int i0, int i1, int i2, int i3, float value);

    GGML_API void *  ggml_get_data    (const struct ggml_tensor * tensor);
    GGML_API float * ggml_get_data_f32(const struct ggml_tensor * tensor);

    GGML_API GGML_CALL enum ggml_unary_op ggml_get_unary_op(const struct ggml_tensor * tensor);

    GGML_API const char *         ggml_get_name   (const struct ggml_tensor * tensor);
    GGML_API struct ggml_tensor * ggml_set_name   (      struct ggml_tensor * tensor, const char * name);
    GGML_ATTRIBUTE_FORMAT(2, 3)
    GGML_API struct ggml_tensor * ggml_format_name(      struct ggml_tensor * tensor, const char * fmt, ...);

    //
    // operations on tensors with backpropagation
    //

    GGML_API struct ggml_tensor * ggml_dup(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_dup_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_add(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_add_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_add_cast(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            enum   ggml_type      type);

    GGML_API struct ggml_tensor * ggml_add1(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_add1_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_multi_add(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int n_experts);

    // dst = a
    // view(dst, nb1, nb2, nb3, offset) += b
    // return dst
    GGML_API struct ggml_tensor * ggml_acc(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                nb1,
            size_t                nb2,
            size_t                nb3,
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_acc_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                nb1,
            size_t                nb2,
            size_t                nb3,
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_sub(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_sub_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_mul(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_mul_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_fused_mul_unary(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            enum ggml_unary_op    op);

    GGML_API struct ggml_tensor * ggml_fused_mul_unary_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            enum ggml_unary_op    op);

    GGML_API struct ggml_tensor * ggml_div(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_div_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_sqr(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_sqr_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_sqrt(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_sqrt_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_log(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_log_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // return scalar
    GGML_API struct ggml_tensor * ggml_sum(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // sums along rows, with input shape [a,b,c,d] return shape [1,b,c,d]
    GGML_API struct ggml_tensor * ggml_sum_rows(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // mean along rows
    GGML_API struct ggml_tensor * ggml_mean(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // argmax along rows
    GGML_API struct ggml_tensor * ggml_argmax(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);


    // if a is the same shape as b, and a is not parameter, return a
    // otherwise, return a new tensor: repeat(a) to fit in b
    GGML_API struct ggml_tensor * ggml_repeat(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // sums repetitions in a into shape of b
    GGML_API struct ggml_tensor * ggml_repeat_back(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // concat a and b along dim
    // used in stable-diffusion
    GGML_API struct ggml_tensor * ggml_concat(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   dim);

    GGML_API struct ggml_tensor * ggml_abs(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_abs_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_sgn(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_sgn_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_neg(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_neg_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_step(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_step_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_tanh(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_tanh_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_elu(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_elu_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_relu(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_leaky_relu(
            struct ggml_context * ctx,
            struct ggml_tensor  * a, float negative_slope, bool inplace);

    GGML_API struct ggml_tensor * ggml_relu_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_sigmoid(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_sigmoid_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_gelu(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_gelu_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_gelu_quick(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_gelu_quick_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_silu(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_silu_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    GGML_API struct ggml_tensor * ggml_swiglu(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // a - x
    // b - dy
    GGML_API struct ggml_tensor * ggml_silu_back(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // hardswish(x) = x * relu6(x + 3) / 6
    GGML_API struct ggml_tensor * ggml_hardswish(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // hardsigmoid(x) = relu6(x + 3) / 6
    GGML_API struct ggml_tensor * ggml_hardsigmoid(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // normalize along rows
    GGML_API struct ggml_tensor * ggml_norm(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 eps);

    GGML_API struct ggml_tensor * ggml_norm_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 eps);

    GGML_API struct ggml_tensor * ggml_rms_norm(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 eps);

    GGML_API struct ggml_tensor * ggml_rms_norm_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 eps);

    GGML_API struct ggml_tensor * ggml_fused_rms_norm(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            float                 eps);

    GGML_API struct ggml_tensor * ggml_fused_rms_norm_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            float                 eps);

    // group normalize along ne0*ne1*n_groups
    // used in stable-diffusion
    GGML_API struct ggml_tensor * ggml_group_norm(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   n_groups,
            float                 eps);

    GGML_API struct ggml_tensor * ggml_group_norm_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   n_groups,
            float                 eps);

    // a - x
    // b - dy
    GGML_API struct ggml_tensor * ggml_rms_norm_back(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            float                 eps);

    // A: k columns, n rows => [ne03, ne02, n, k]
    // B: k columns, m rows  (i.e. we transpose it internally) => [ne03 * x, ne02 * y, m, k]
    // result is n columns, m rows => [ne03 * x, ne02 * y, m, n]
    GGML_API struct ggml_tensor * ggml_mul_mat(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // change the precision of a matrix multiplication
    // set to GGML_PREC_F32 for higher precision (useful for phi-2)
    GGML_API void ggml_mul_mat_set_prec(
            struct ggml_tensor * a,
            enum ggml_prec       prec);

    // indirect matrix multiplication
    GGML_API struct ggml_tensor * ggml_mul_mat_id(
            struct ggml_context * ctx,
            struct ggml_tensor  * as,
            struct ggml_tensor  * b,
            struct ggml_tensor  * ids);

    // MoE up + gate + unary
    GGML_API struct ggml_tensor * ggml_moe_up_gate(
            struct ggml_context * ctx,
            struct ggml_tensor  * as_up,
            struct ggml_tensor  * as_gate,
            struct ggml_tensor  * b,
            struct ggml_tensor  * ids,
            enum ggml_unary_op    op);

    // A: m columns, n rows,
    // B: p columns, n rows,
    // result is m columns, p rows
    GGML_API struct ggml_tensor * ggml_out_prod(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    //
    // operations on tensors without backpropagation
    //

    GGML_API struct ggml_tensor * ggml_scale(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 s);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_scale_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 s);

    GGML_API struct ggml_tensor * ggml_softcap(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 s_before,
            float                 s_after);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_softcap_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 s_before,
            float                 s_after);

    GGML_API struct ggml_tensor * ggml_softcap_max(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * mask,
            float                 scale,
            float                 max_bias,
            float                 s_before,
            float                 s_after);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_softcap_max_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * mask,
            float                 scale,
            float                 max_bias,
            float                 s_before,
            float                 s_after);

    // b -> view(a,offset,nb1,nb2,3), return modified a
    GGML_API struct ggml_tensor * ggml_set(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                nb1,
            size_t                nb2,
            size_t                nb3,
            size_t                offset);

    // b -> view(a,offset,nb1,nb2,3), return view(a)
    GGML_API struct ggml_tensor * ggml_set_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                nb1,
            size_t                nb2,
            size_t                nb3,
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_set_1d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_set_1d_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                offset);

    // b -> view(a,offset,nb1,nb2,3), return modified a
    GGML_API struct ggml_tensor * ggml_set_2d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                nb1,
            size_t                offset);

    // b -> view(a,offset,nb1,nb2,3), return view(a)
    GGML_API struct ggml_tensor * ggml_set_2d_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            size_t                nb1,
            size_t                offset);

    // a -> b, return view(b)
    GGML_API struct ggml_tensor * ggml_cpy(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_cast(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            enum   ggml_type      type);

    // make contiguous
    GGML_API struct ggml_tensor * ggml_cont(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // make contiguous, with new shape
    GGML_API struct ggml_tensor * ggml_cont_1d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0);

    GGML_API struct ggml_tensor * ggml_cont_2d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1);

    GGML_API struct ggml_tensor * ggml_cont_3d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1,
            int64_t               ne2);

    GGML_API struct ggml_tensor * ggml_cont_4d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1,
            int64_t               ne2,
            int64_t               ne3);

    // return view(a), b specifies the new shape
    // TODO: when we start computing gradient, make a copy instead of view
    GGML_API struct ggml_tensor * ggml_reshape(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // return view(a)
    // TODO: when we start computing gradient, make a copy instead of view
    GGML_API struct ggml_tensor * ggml_reshape_1d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0);

    GGML_API struct ggml_tensor * ggml_reshape_2d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1);

    // return view(a)
    // TODO: when we start computing gradient, make a copy instead of view
    GGML_API struct ggml_tensor * ggml_reshape_3d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1,
            int64_t               ne2);

    GGML_API struct ggml_tensor * ggml_reshape_4d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1,
            int64_t               ne2,
            int64_t               ne3);

    // offset in bytes
    GGML_API struct ggml_tensor * ggml_view_1d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_view_2d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1,
            size_t                nb1, // row stride in bytes
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_view_3d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1,
            int64_t               ne2,
            size_t                nb1, // row   stride in bytes
            size_t                nb2, // slice stride in bytes
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_view_4d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int64_t               ne0,
            int64_t               ne1,
            int64_t               ne2,
            int64_t               ne3,
            size_t                nb1, // row   stride in bytes
            size_t                nb2, // slice stride in bytes
            size_t                nb3,
            size_t                offset);

    GGML_API struct ggml_tensor * ggml_permute(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   axis0,
            int                   axis1,
            int                   axis2,
            int                   axis3);

    // alias for ggml_permute(ctx, a, 1, 0, 2, 3)
    GGML_API struct ggml_tensor * ggml_transpose(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // supports 3D: a->ne[2] == b->ne[1]
    GGML_API struct ggml_tensor * ggml_get_rows(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_get_rows_back(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            struct ggml_tensor  * c);

    GGML_API struct ggml_tensor * ggml_diag(
        struct ggml_context     * ctx,
        struct ggml_tensor      * a);

    // set elements above the diagonal to -INF
    GGML_API struct ggml_tensor * ggml_diag_mask_inf(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   n_past);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_diag_mask_inf_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   n_past);

    // set elements above the diagonal to 0
    GGML_API struct ggml_tensor * ggml_diag_mask_zero(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   n_past);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_diag_mask_zero_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   n_past);

    GGML_API struct ggml_tensor * ggml_soft_max(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_soft_max_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a);

    // fused soft_max(a*scale + mask*(ALiBi slope))
    // mask is optional
    // max_bias = 0.0f for no ALiBi
    GGML_API struct ggml_tensor * ggml_soft_max_ext(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * mask,
            float                 scale,
            float                 max_bias);

    GGML_API struct ggml_tensor * ggml_soft_max_back(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_soft_max_back_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // rotary position embedding
    // if mode & 1 == 1, skip n_past elements (NOT SUPPORTED)
    // if mode & 2 == 1, GPT-NeoX style
    //
    // b is an int32 vector with size a->ne[2], it contains the positions
    GGML_API struct ggml_tensor * ggml_rope(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   n_dims,
            int                   mode);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_rope_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   n_dims,
            int                   mode);

    // custom RoPE
    // c is freq factors (e.g. phi3-128k), (optional)
    GGML_API struct ggml_tensor * ggml_rope_ext(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            struct ggml_tensor  * c,
            int                   n_dims,
            int                   mode,
            int                   n_ctx_orig,
            float                 freq_base,
            float                 freq_scale,
            float                 ext_factor,
            float                 attn_factor,
            float                 beta_fast,
            float                 beta_slow);

    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_rope_ext_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            struct ggml_tensor  * c,
            int                   n_dims,
            int                   mode,
            int                   n_ctx_orig,
            float                 freq_base,
            float                 freq_scale,
            float                 ext_factor,
            float                 attn_factor,
            float                 beta_fast,
            float                 beta_slow);

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_rope_custom(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   n_dims,
            int                   mode,
            int                   n_ctx_orig,
            float                 freq_base,
            float                 freq_scale,
            float                 ext_factor,
            float                 attn_factor,
            float                 beta_fast,
            float                 beta_slow),
        "use ggml_rope_ext instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_rope_custom_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   n_dims,
            int                   mode,
            int                   n_ctx_orig,
            float                 freq_base,
            float                 freq_scale,
            float                 ext_factor,
            float                 attn_factor,
            float                 beta_fast,
            float                 beta_slow),
        "use ggml_rope_ext_inplace instead");

    // compute correction dims for YaRN RoPE scaling
    GGML_CALL void ggml_rope_yarn_corr_dims(
        int n_dims, int n_ctx_orig, float freq_base, float beta_fast, float beta_slow, float dims[2]);

    // rotary position embedding backward, i.e compute dx from dy
    // a - dy
    GGML_API struct ggml_tensor * ggml_rope_back(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            struct ggml_tensor  * c,
            int                   n_dims,
            int                   mode,
            int                   n_ctx_orig,
            float                 freq_base,
            float                 freq_scale,
            float                 ext_factor,
            float                 attn_factor,
            float                 beta_fast,
            float                 beta_slow);

    // clamp
    // in-place, returns view(a)
    GGML_API struct ggml_tensor * ggml_clamp(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            float                 min,
            float                 max);

    GGML_API struct ggml_tensor * ggml_im2col(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                  s0,
            int                  s1,
            int                  p0,
            int                  p1,
            int                  d0,
            int                  d1,
            bool                 is_2D,
            enum ggml_type       dst_type);

    GGML_API struct ggml_tensor * ggml_conv_depthwise_2d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                  s0,
            int                  s1,
            int                  p0,
            int                  p1,
            int                  d0,
            int                  d1);

    GGML_API struct ggml_tensor * ggml_conv_1d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   s0,  // stride
            int                   p0,  // padding
            int                   d0); // dilation

    // conv_1d with padding = half
    // alias for ggml_conv_1d(a, b, s, a->ne[0]/2, d)
    GGML_API struct ggml_tensor* ggml_conv_1d_ph(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   s,
            int                   d);

    GGML_API struct ggml_tensor * ggml_conv_transpose_1d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   s0,
            int                   p0,
            int                   d0);

    GGML_API struct ggml_tensor * ggml_conv_2d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   s0,
            int                   s1,
            int                   p0,
            int                   p1,
            int                   d0,
            int                   d1);


    // kernel size is a->ne[0] x a->ne[1]
    // stride is equal to kernel size
    // padding is zero
    // example:
    // a:     16   16    3  768
    // b:   1024 1024    3    1
    // res:   64   64  768    1
    // used in sam
    GGML_API struct ggml_tensor * ggml_conv_2d_sk_p0(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    // kernel size is a->ne[0] x a->ne[1]
    // stride is 1
    // padding is half
    // example:
    // a:      3    3    256  256
    // b:     64   64    256    1
    // res:   64   64    256    1
    // used in sam
    GGML_API struct ggml_tensor * ggml_conv_2d_s1_ph(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b);

    GGML_API struct ggml_tensor * ggml_conv_transpose_2d_p0(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * b,
            int                   stride);

    enum ggml_op_pool {
        GGML_OP_POOL_MAX,
        GGML_OP_POOL_AVG,
        GGML_OP_POOL_COUNT,
    };

    GGML_API struct ggml_tensor * ggml_pool_1d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            enum ggml_op_pool     op,
            int                   k0, // kernel size
            int                   s0, // stride
            int                   p0); // padding

    // the result will have 2*p0 padding for the first dimension
    // and 2*p1 padding for the second dimension
    GGML_API struct ggml_tensor * ggml_pool_2d(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            enum ggml_op_pool     op,
            int                   k0,
            int                   k1,
            int                   s0,
            int                   s1,
            float                 p0,
            float                 p1);

    // nearest interpolate
    // multiplies ne0 and ne1 by scale factor
    // used in stable-diffusion
    GGML_API struct ggml_tensor * ggml_upscale(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   scale_factor);

    // nearest interpolate
    // nearest interpolate to specified dimensions
    // used in tortoise.cpp
    GGML_API struct ggml_tensor * ggml_upscale_ext(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   ne0,
            int                   ne1,
            int                   ne2,
            int                   ne3);

    // pad each dimension with zeros: [x, ..., x] -> [x, ..., x, 0, ..., 0]
    GGML_API struct ggml_tensor * ggml_pad(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                  p0,
            int                  p1,
            int                  p2,
            int                  p3);

    // Ref: https://github.com/CompVis/stable-diffusion/blob/main/ldm/modules/diffusionmodules/util.py#L151
    // timesteps: [N,]
    // return: [N, dim]
    GGML_API struct ggml_tensor * ggml_timestep_embedding(
            struct ggml_context * ctx,
            struct ggml_tensor  * timesteps,
            int                   dim,
            int                   max_period);

    // sort rows
    enum ggml_sort_order {
        GGML_SORT_ORDER_ASC,
        GGML_SORT_ORDER_DESC,
    };

    GGML_API struct ggml_tensor * ggml_argsort(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            enum ggml_sort_order  order);

    GGML_API struct ggml_tensor * ggml_argsort_thresh(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   min_entries,
            float                 threshold);

    GGML_API struct ggml_tensor * ggml_arange(
            struct ggml_context * ctx,
            float                 start,
            float                 stop,
            float                 step);

    // top k elements per row
    GGML_API struct ggml_tensor * ggml_top_k(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   k);
    GGML_API struct ggml_tensor * ggml_top_k_thresh(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   k,
            int                   min_entries,
            float                 thresh);

#define GGML_KQ_MASK_PAD 64

    // q:    [n_embd, n_batch,     n_head,    1]
    // k:    [n_embd, n_kv,        n_head_kv, 1]
    // v:    [n_embd, n_kv,        n_head_kv, 1] !! not transposed !!
    // mask: [n_kv,   n_batch_pad, 1,         1] !! n_batch_pad = GGML_PAD(n_batch, GGML_KQ_MASK_PAD) !!
    // res:  [n_embd, n_head,      n_batch,   1] !! permuted !!
    GGML_API struct ggml_tensor * ggml_flash_attn_ext(
            struct ggml_context * ctx,
            struct ggml_tensor  * q,
            struct ggml_tensor  * k,
            struct ggml_tensor  * v,
            struct ggml_tensor  * mask,
            float                 scale,
            float                 max_bias,
            float                 softcap);

    GGML_API void ggml_flash_attn_ext_set_prec(
            struct ggml_tensor * a,
            enum ggml_prec       prec);

    // TODO: needs to be adapted to ggml_flash_attn_ext
    GGML_API struct ggml_tensor * ggml_flash_attn_back(
           struct ggml_context * ctx,
           struct ggml_tensor  * q,
           struct ggml_tensor  * k,
           struct ggml_tensor  * v,
           struct ggml_tensor  * d,
           bool                  masked);

    GGML_API struct ggml_tensor * ggml_ssm_conv(
            struct ggml_context * ctx,
            struct ggml_tensor  * s,
            struct ggml_tensor  * x,
            struct ggml_tensor  * c,
            struct ggml_tensor  * sq);

    GGML_API struct ggml_tensor * ggml_ssm_scan(
            struct ggml_context * ctx,
            struct ggml_tensor  * s,
            struct ggml_tensor  * x,
            struct ggml_tensor  * dt,
            struct ggml_tensor  * A,
            struct ggml_tensor  * B,
            struct ggml_tensor  * C,
            struct ggml_tensor  * sq);

    // partition into non-overlapping windows with padding if needed
    // example:
    // a:   768   64   64    1
    // w:    14
    // res: 768   14   14    25
    // used in sam
    GGML_API struct ggml_tensor * ggml_win_part(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   w);

    // reverse of ggml_win_part
    // used in sam
    GGML_API struct ggml_tensor * ggml_win_unpart(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   w0,
            int                   h0,
            int                   w);

    GGML_API struct ggml_tensor * ggml_unary(
            struct ggml_context * ctx,
             struct ggml_tensor * a,
             enum ggml_unary_op op);

    GGML_API struct ggml_tensor * ggml_unary_inplace(
        struct ggml_context * ctx,
        struct ggml_tensor  * a,
        enum ggml_unary_op op);

    // used in sam
    GGML_API struct ggml_tensor * ggml_get_rel_pos(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            int                   qh,
            int                   kh);

    // used in sam
    GGML_API struct ggml_tensor * ggml_add_rel_pos(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * pw,
            struct ggml_tensor  * ph);

    GGML_API struct ggml_tensor * ggml_add_rel_pos_inplace(
            struct ggml_context * ctx,
            struct ggml_tensor  * a,
            struct ggml_tensor  * pw,
            struct ggml_tensor  * ph);

    // custom operators

    typedef void (*ggml_unary_op_f32_t) (const int, float *, const float *);
    typedef void (*ggml_binary_op_f32_t)(const int, float *, const float *, const float *);

    typedef void (*ggml_custom1_op_f32_t)(struct ggml_tensor *, const struct ggml_tensor *);
    typedef void (*ggml_custom2_op_f32_t)(struct ggml_tensor *, const struct ggml_tensor *, const struct ggml_tensor *);
    typedef void (*ggml_custom3_op_f32_t)(struct ggml_tensor *, const struct ggml_tensor *, const struct ggml_tensor *, const struct ggml_tensor *);

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_unary_f32(
            struct ggml_context        * ctx,
            struct ggml_tensor         * a,
                   ggml_unary_op_f32_t   fun),
        "use ggml_map_custom1 instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_unary_inplace_f32(
            struct ggml_context        * ctx,
            struct ggml_tensor         * a,
                   ggml_unary_op_f32_t   fun),
        "use ggml_map_custom1_inplace instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_binary_f32(
            struct ggml_context         * ctx,
            struct ggml_tensor          * a,
            struct ggml_tensor          * b,
                   ggml_binary_op_f32_t   fun),
        "use ggml_map_custom2 instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_binary_inplace_f32(
            struct ggml_context         * ctx,
            struct ggml_tensor          * a,
            struct ggml_tensor          * b,
                   ggml_binary_op_f32_t   fun),
        "use ggml_map_custom2_inplace instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_custom1_f32(
            struct ggml_context          * ctx,
            struct ggml_tensor           * a,
                   ggml_custom1_op_f32_t   fun),
        "use ggml_map_custom1 instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_custom1_inplace_f32(
            struct ggml_context          * ctx,
            struct ggml_tensor           * a,
                   ggml_custom1_op_f32_t   fun),
        "use ggml_map_custom1_inplace instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_custom2_f32(
            struct ggml_context          * ctx,
            struct ggml_tensor           * a,
            struct ggml_tensor           * b,
                   ggml_custom2_op_f32_t   fun),
        "use ggml_map_custom2 instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_custom2_inplace_f32(
            struct ggml_context          * ctx,
            struct ggml_tensor           * a,
            struct ggml_tensor           * b,
                   ggml_custom2_op_f32_t   fun),
        "use ggml_map_custom2_inplace instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_custom3_f32(
            struct ggml_context          * ctx,
            struct ggml_tensor           * a,
            struct ggml_tensor           * b,
            struct ggml_tensor           * c,
                   ggml_custom3_op_f32_t   fun),
        "use ggml_map_custom3 instead");

    GGML_DEPRECATED(GGML_API struct ggml_tensor * ggml_map_custom3_inplace_f32(
            struct ggml_context          * ctx,
            struct ggml_tensor           * a,
            struct ggml_tensor           * b,
            struct ggml_tensor           * c,
                   ggml_custom3_op_f32_t   fun),
        "use ggml_map_custom3_inplace instead");

    // custom operators v2

    typedef void (*ggml_custom1_op_t)(struct ggml_tensor * dst , const struct ggml_tensor * a, int ith, int nth, void * userdata);
    typedef void (*ggml_custom2_op_t)(struct ggml_tensor * dst , const struct ggml_tensor * a, const struct ggml_tensor * b, int ith, int nth, void * userdata);
    typedef void (*ggml_custom3_op_t)(struct ggml_tensor * dst , const struct ggml_tensor * a, const struct ggml_tensor * b, const struct ggml_tensor * c, int ith, int nth, void * userdata);

    #define GGML_N_TASKS_MAX -1

    GGML_API struct ggml_tensor * ggml_map_custom1(
            struct ggml_context   * ctx,
            struct ggml_tensor    * a,
            ggml_custom1_op_t       fun,
            int                     n_tasks,
            void                  * userdata);

    GGML_API struct ggml_tensor * ggml_map_custom1_inplace(
            struct ggml_context   * ctx,
            struct ggml_tensor    * a,
            ggml_custom1_op_t       fun,
            int                     n_tasks,
            void                  * userdata);

    GGML_API struct ggml_tensor * ggml_map_custom2(
            struct ggml_context   * ctx,
            struct ggml_tensor    * a,
            struct ggml_tensor    * b,
            ggml_custom2_op_t       fun,
            int                     n_tasks,
            void                  * userdata);

    GGML_API struct ggml_tensor * ggml_map_custom2_inplace(
            struct ggml_context   * ctx,
            struct ggml_tensor    * a,
            struct ggml_tensor    * b,
            ggml_custom2_op_t       fun,
            int                     n_tasks,
            void                  * userdata);

    GGML_API struct ggml_tensor * ggml_map_custom3(
            struct ggml_context   * ctx,
            struct ggml_tensor    * a,
            struct ggml_tensor    * b,
            struct ggml_tensor    * c,
            ggml_custom3_op_t       fun,
            int                     n_tasks,
            void                  * userdata);

    GGML_API struct ggml_tensor * ggml_map_custom3_inplace(
            struct ggml_context   * ctx,
            struct ggml_tensor    * a,
            struct ggml_tensor    * b,
            struct ggml_tensor    * c,
            ggml_custom3_op_t       fun,
            int                     n_tasks,
            void                  * userdata);

    // loss function

    GGML_API struct ggml_tensor * ggml_cross_entropy_loss(
            struct ggml_context         * ctx,
            struct ggml_tensor          * a,
            struct ggml_tensor          * b);

    GGML_API struct ggml_tensor * ggml_cross_entropy_loss_back(
            struct ggml_context         * ctx,
            struct ggml_tensor          * a,
            struct ggml_tensor          * b,
            struct ggml_tensor          * c);

    //
    // automatic differentiation
    //

    GGML_API void ggml_set_param(
            struct ggml_context * ctx,
            struct ggml_tensor  * tensor);


    GGML_API void ggml_build_forward_expand (struct ggml_cgraph * cgraph, struct ggml_tensor * tensor);
    GGML_API void ggml_build_backward_expand(struct ggml_context * ctx, struct ggml_cgraph * gf, struct ggml_cgraph * gb, bool keep);

    // graph allocation in a context
    GGML_API struct ggml_cgraph * ggml_new_graph         (struct ggml_context * ctx); // size = GGML_DEFAULT_GRAPH_SIZE, grads = false
    GGML_API struct ggml_cgraph * ggml_new_graph_custom  (struct ggml_context * ctx, size_t size, bool grads);
    GGML_API struct ggml_cgraph * ggml_graph_dup         (struct ggml_context * ctx, struct ggml_cgraph * cgraph);
    GGML_API struct ggml_cgraph   ggml_graph_view        (struct ggml_cgraph * cgraph, int i0, int i1);
    GGML_API void                 ggml_graph_cpy         (struct ggml_cgraph * src, struct ggml_cgraph * dst);
    GGML_API void                 ggml_graph_reset       (struct ggml_cgraph * cgraph);  // zero grads
    GGML_API void                 ggml_graph_clear       (struct ggml_cgraph * cgraph);

    GGML_API size_t ggml_graph_overhead(void);
    GGML_API size_t ggml_graph_overhead_custom(size_t size, bool grads);

    // ggml_graph_plan() has to be called before ggml_graph_compute()
    // when plan.work_size > 0, caller must allocate memory for plan.work_data
    GGML_API struct ggml_cplan ggml_graph_plan   (const struct ggml_cgraph * cgraph, int n_threads /*= GGML_DEFAULT_N_THREADS*/);
    GGML_API enum ggml_status  ggml_graph_compute(      struct ggml_cgraph * cgraph, struct ggml_cplan * cplan);
    // same as ggml_graph_compute() but the work data is allocated as a part of the context
    // note: the drawback of this API is that you must have ensured that the context has enough memory for the work data
    GGML_API enum ggml_status  ggml_graph_compute_with_ctx(struct ggml_context * ctx, struct ggml_cgraph * cgraph, int n_threads);

    GGML_API struct ggml_tensor * ggml_graph_get_tensor(struct ggml_cgraph * cgraph, const char * name);

    GGML_API void                 ggml_graph_export(const struct ggml_cgraph * cgraph, const char * fname);
    GGML_API struct ggml_cgraph * ggml_graph_import(const char * fname, struct ggml_context ** ctx_data, struct ggml_context ** ctx_eval);

    // print info and performance information for the graph
    GGML_API void ggml_graph_print(const struct ggml_cgraph * cgraph);

    // dump the graph into a file using the dot format
    GGML_API void ggml_graph_dump_dot(const struct ggml_cgraph * gb, const struct ggml_cgraph * gf, const char * filename);

    // build gradient checkpointing backward graph gb for gf using provided checkpoints
    // gb_tmp will contain original backward graph with rewritten backward process nodes,
    // but without the second forward pass nodes.
    GGML_API void ggml_build_backward_gradient_checkpointing(
            struct ggml_context   * ctx,
            struct ggml_cgraph    * gf,
            struct ggml_cgraph    * gb,
            struct ggml_cgraph    * gb_tmp,
            struct ggml_tensor  * * checkpoints,
            int                     n_checkpoints);
    //
    // optimization
    //

    // optimization methods
    enum ggml_opt_type {
        GGML_OPT_TYPE_ADAM,
        GGML_OPT_TYPE_LBFGS,
    };

    // linesearch methods
    enum ggml_linesearch {
        GGML_LINESEARCH_DEFAULT = 1,

        GGML_LINESEARCH_BACKTRACKING_ARMIJO       = 0,
        GGML_LINESEARCH_BACKTRACKING_WOLFE        = 1,
        GGML_LINESEARCH_BACKTRACKING_STRONG_WOLFE = 2,
    };

    // optimization return values
    enum ggml_opt_result {
        GGML_OPT_RESULT_OK = 0,
        GGML_OPT_RESULT_DID_NOT_CONVERGE,
        GGML_OPT_RESULT_NO_CONTEXT,
        GGML_OPT_RESULT_INVALID_WOLFE,
        GGML_OPT_RESULT_FAIL,
        GGML_OPT_RESULT_CANCEL,

        GGML_LINESEARCH_FAIL = -128,
        GGML_LINESEARCH_MINIMUM_STEP,
        GGML_LINESEARCH_MAXIMUM_STEP,
        GGML_LINESEARCH_MAXIMUM_ITERATIONS,
        GGML_LINESEARCH_INVALID_PARAMETERS,
    };

    typedef void (*ggml_opt_callback)(void * data, int accum_step, float * sched, bool * cancel);
    typedef void (*ggml_log_callback)(enum ggml_log_level level, const char * text, void * user_data);

    // optimization parameters
    //
    //   see ggml.c (ggml_opt_default_params) for default values
    //
    struct ggml_opt_params {
        enum ggml_opt_type type;

        size_t graph_size;

        int n_threads;

        // delta-based convergence test
        //
        //   if past == 0 - disabled
        //   if past > 0:
        //     stop if |f(x) - f(x_past)| < delta * max(1, |f(x)|)
        //
        int past;
        float delta;

        // maximum number of iterations without improvement
        //
        //   if 0 - disabled
        //   if > 0:
        //     assume convergence if no cost improvement in this number of iterations
        //
        int max_no_improvement;

        bool print_forward_graph;
        bool print_backward_graph;

        int n_gradient_accumulation;

        // ADAM parameters
        struct {
            int n_iter;

            float sched; // schedule multiplier (fixed, decay or warmup)
            float decay; // weight decay for AdamW, use 0.0f to disable
            int   decay_min_ndim; // minimum number of tensor dimension to apply weight decay
            float alpha; // learning rate
            float beta1;
            float beta2;
            float eps;   // epsilon for numerical stability
            float eps_f; // epsilon for convergence test
            float eps_g; // epsilon for convergence test
            float gclip; // gradient clipping
        } adam;

        // LBFGS parameters
        struct {
            int m; // number of corrections to approximate the inv. Hessian
            int n_iter;
            int max_linesearch;

            float eps;      // convergence tolerance
            float ftol;     // line search tolerance
            float wolfe;
            float min_step;
            float max_step;

            enum ggml_linesearch linesearch;
        } lbfgs;
    };

    struct ggml_opt_context {
        struct ggml_context * ctx;
        struct ggml_opt_params params;

        int iter;
        int64_t nx; // number of parameter elements

        bool just_initialized;

        float loss_before;
        float loss_after;

        struct {
            struct ggml_tensor * g;  // current gradient
            struct ggml_tensor * m;  // first moment
            struct ggml_tensor * v;  // second moment
            struct ggml_tensor * pf; // past function values
            float fx_best;
            float fx_prev;
            int n_no_improvement;
        } adam;

        struct {
            struct ggml_tensor * x;    // current parameters
            struct ggml_tensor * xp;   // previous parameters
            struct ggml_tensor * g;    // current gradient
            struct ggml_tensor * gp;   // previous gradient
            struct ggml_tensor * d;    // search direction
            struct ggml_tensor * pf;   // past function values
            struct ggml_tensor * lmal; // the L-BFGS memory alpha
            struct ggml_tensor * lmys; // the L-BFGS memory ys
            struct ggml_tensor * lms;  // the L-BFGS memory s
            struct ggml_tensor * lmy;  // the L-BFGS memory y
            float fx_best;
            float step;
            int j;
            int k;
            int end;
            int n_no_improvement;
        } lbfgs;
    };

    GGML_API struct ggml_opt_params ggml_opt_default_params(enum ggml_opt_type type);

    // optimize the function defined by the tensor f
    GGML_API enum ggml_opt_result ggml_opt(
            struct ggml_context * ctx,
            struct ggml_opt_params params,
            struct ggml_tensor * f);

    // initialize optimizer context
    GGML_API void ggml_opt_init(
            struct ggml_context     * ctx,
            struct ggml_opt_context * opt,
            struct ggml_opt_params    params,
            int64_t                   nx);

    // continue optimizing the function defined by the tensor f
    GGML_API enum ggml_opt_result ggml_opt_resume(
            struct ggml_context * ctx,
            struct ggml_opt_context * opt,
            struct ggml_tensor * f);

    // continue optimizing the function defined by the tensor f
    GGML_API enum ggml_opt_result ggml_opt_resume_g(
            struct ggml_context * ctx,
            struct ggml_opt_context * opt,
            struct ggml_tensor * f,
            struct ggml_cgraph * gf,
            struct ggml_cgraph * gb,
            ggml_opt_callback callback,
            void * callback_data);

    //
    // tensor flags
    //
    GGML_API void ggml_set_input(struct ggml_tensor * tensor);
    GGML_API void ggml_set_output(struct ggml_tensor * tensor);

    //
    // quantization
    //

    // - ggml_quantize_init can be called multiple times with the same type
    //   it will only initialize the quantization tables for the first call or after ggml_quantize_free
    //   automatically called by ggml_quantize_chunk for convenience
    //
    // - ggml_quantize_free will free any memory allocated by ggml_quantize_init
    //   call this at the end of the program to avoid memory leaks
    //
    // note: these are thread-safe
    //
    GGML_API void ggml_quantize_init(enum ggml_type type);
    GGML_API void ggml_quantize_free(void);

    // some quantization type cannot be used without an importance matrix
    GGML_API bool ggml_quantize_requires_imatrix(enum ggml_type type);

    // calls ggml_quantize_init internally (i.e. can allocate memory)
    GGML_API size_t ggml_quantize_chunk(
            enum ggml_type   type,
               const float * src,
                      void * dst,
                   int64_t   start,
                   int64_t   nrows,
                   int64_t   n_per_row,
               const float * imatrix);

    //
    // gguf
    //

    enum gguf_type {
        GGUF_TYPE_UINT8   = 0,
        GGUF_TYPE_INT8    = 1,
        GGUF_TYPE_UINT16  = 2,
        GGUF_TYPE_INT16   = 3,
        GGUF_TYPE_UINT32  = 4,
        GGUF_TYPE_INT32   = 5,
        GGUF_TYPE_FLOAT32 = 6,
        GGUF_TYPE_BOOL    = 7,
        GGUF_TYPE_STRING  = 8,
        GGUF_TYPE_ARRAY   = 9,
        GGUF_TYPE_UINT64  = 10,
        GGUF_TYPE_INT64   = 11,
        GGUF_TYPE_FLOAT64 = 12,
        GGUF_TYPE_COUNT,       // marks the end of the enum
    };

    struct gguf_context;

    struct gguf_init_params {
        bool no_alloc;

        // if not NULL, create a ggml_context and allocate the tensor data in it
        struct ggml_context ** ctx;
    };

    GGML_API struct gguf_context * gguf_init_empty(void);
    GGML_API struct gguf_context * gguf_init_from_file(const char * fname, struct gguf_init_params params);
    //GGML_API struct gguf_context * gguf_init_from_buffer(..);

    GGML_API void gguf_free(struct gguf_context * ctx);

    GGML_API const char * gguf_type_name(enum gguf_type type);

    GGML_API int    gguf_get_version    (const struct gguf_context * ctx);
    GGML_API size_t gguf_get_alignment  (const struct gguf_context * ctx);
    GGML_API size_t gguf_get_data_offset(const struct gguf_context * ctx);
    GGML_API void * gguf_get_data       (const struct gguf_context * ctx);

    GGML_API int          gguf_get_n_kv(const struct gguf_context * ctx);
    GGML_API int          gguf_find_key(const struct gguf_context * ctx, const char * key);
    GGML_API const char * gguf_get_key (const struct gguf_context * ctx, int key_id);

    GGML_API enum gguf_type gguf_get_kv_type (const struct gguf_context * ctx, int key_id);
    GGML_API enum gguf_type gguf_get_arr_type(const struct gguf_context * ctx, int key_id);

    // will abort if the wrong type is used for the key
    GGML_API uint8_t      gguf_get_val_u8  (const struct gguf_context * ctx, int key_id);
    GGML_API int8_t       gguf_get_val_i8  (const struct gguf_context * ctx, int key_id);
    GGML_API uint16_t     gguf_get_val_u16 (const struct gguf_context * ctx, int key_id);
    GGML_API int16_t      gguf_get_val_i16 (const struct gguf_context * ctx, int key_id);
    GGML_API uint32_t     gguf_get_val_u32 (const struct gguf_context * ctx, int key_id);
    GGML_API int32_t      gguf_get_val_i32 (const struct gguf_context * ctx, int key_id);
    GGML_API float        gguf_get_val_f32 (const struct gguf_context * ctx, int key_id);
    GGML_API uint64_t     gguf_get_val_u64 (const struct gguf_context * ctx, int key_id);
    GGML_API int64_t      gguf_get_val_i64 (const struct gguf_context * ctx, int key_id);
    GGML_API double       gguf_get_val_f64 (const struct gguf_context * ctx, int key_id);
    GGML_API bool         gguf_get_val_bool(const struct gguf_context * ctx, int key_id);
    GGML_API const char * gguf_get_val_str (const struct gguf_context * ctx, int key_id);
    GGML_API const void * gguf_get_val_data(const struct gguf_context * ctx, int key_id);
    GGML_API int          gguf_get_arr_n   (const struct gguf_context * ctx, int key_id);
    GGML_API const void * gguf_get_arr_data(const struct gguf_context * ctx, int key_id);
    GGML_API const char * gguf_get_arr_str (const struct gguf_context * ctx, int key_id, int i);

    GGML_API int            gguf_get_n_tensors    (const struct gguf_context * ctx);
    GGML_API int            gguf_find_tensor      (const struct gguf_context * ctx, const char * name);
    GGML_API size_t         gguf_get_tensor_offset(const struct gguf_context * ctx, int i);
    GGML_API char *         gguf_get_tensor_name  (const struct gguf_context * ctx, int i);
    GGML_API enum ggml_type gguf_get_tensor_type  (const struct gguf_context * ctx, int i);

    // removes key if it exists
    GGML_API void gguf_remove_key(struct gguf_context * ctx, const char * key);

    // overrides existing values or adds a new one
    GGML_API void gguf_set_val_u8  (struct gguf_context * ctx, const char * key, uint8_t  val);
    GGML_API void gguf_set_val_i8  (struct gguf_context * ctx, const char * key, int8_t   val);
    GGML_API void gguf_set_val_u16 (struct gguf_context * ctx, const char * key, uint16_t val);
    GGML_API void gguf_set_val_i16 (struct gguf_context * ctx, const char * key, int16_t  val);
    GGML_API void gguf_set_val_u32 (struct gguf_context * ctx, const char * key, uint32_t val);
    GGML_API void gguf_set_val_i32 (struct gguf_context * ctx, const char * key, int32_t  val);
    GGML_API void gguf_set_val_f32 (struct gguf_context * ctx, const char * key, float    val);
    GGML_API void gguf_set_val_u64 (struct gguf_context * ctx, const char * key, uint64_t val);
    GGML_API void gguf_set_val_i64 (struct gguf_context * ctx, const char * key, int64_t  val);
    GGML_API void gguf_set_val_f64 (struct gguf_context * ctx, const char * key, double   val);
    GGML_API void gguf_set_val_bool(struct gguf_context * ctx, const char * key, bool     val);
    GGML_API void gguf_set_val_str (struct gguf_context * ctx, const char * key, const char * val);
    GGML_API void gguf_set_arr_data(struct gguf_context * ctx, const char * key, enum gguf_type type, const void * data, int n);
    GGML_API void gguf_set_arr_str (struct gguf_context * ctx, const char * key, const char ** data, int n);

    // set or add KV pairs from another context
    GGML_API void gguf_set_kv(struct gguf_context * ctx, struct gguf_context * src);

    // manage tensor info
    GGML_API void gguf_add_tensor(struct gguf_context * ctx, const struct ggml_tensor * tensor);
    GGML_API void gguf_set_tensor_type(struct gguf_context * ctx, const char * name, enum ggml_type type);
    GGML_API void gguf_set_tensor_data(struct gguf_context * ctx, const char * name, const void * data, size_t size);

    // writing gguf files can be done in 2 ways:
    //
    // - write the entire gguf_context to a binary file in a single pass:
    //
    //   gguf_write_to_file(ctx, fname);
    //
    // - first prepare a file with a placeholder for the meta data, write the tensor data, then write the meta data:
    //
    //   FILE * f = fopen(fname, "wb");
    //   fseek(f, gguf_get_meta_size(ctx), SEEK_SET);
    //   fwrite(f, ...);
    //   void * data = gguf_meta_get_meta_data(ctx);
    //   fseek(f, 0, SEEK_SET);
    //   fwrite(f, data, gguf_get_meta_size(ctx));
    //   free(data);
    //   fclose(f);
    //

    // write the entire context to a binary file
    GGML_API void gguf_write_to_file(const struct gguf_context * ctx, const char * fname, bool only_meta);

    // get the size in bytes of the meta data (header, kv pairs, tensor info) including padding
    GGML_API size_t gguf_get_meta_size(const struct gguf_context * ctx);
    GGML_API void   gguf_get_meta_data(const struct gguf_context * ctx, void * data);

    //
    // system info
    //

    GGML_API int ggml_cpu_has_avx        (void);
    GGML_API int ggml_cpu_has_avx_vnni   (void);
    GGML_API int ggml_cpu_has_avx2       (void);
    GGML_API int ggml_cpu_has_avx512     (void);
    GGML_API int ggml_cpu_has_avx512_vbmi(void);
    GGML_API int ggml_cpu_has_avx512_vnni(void);
    GGML_API int ggml_cpu_has_avx512_bf16(void);
    GGML_API int ggml_cpu_has_fma        (void);
    GGML_API int ggml_cpu_has_neon       (void);
    GGML_API int ggml_cpu_has_sve        (void);
    GGML_API int ggml_cpu_has_arm_fma    (void);
    GGML_API int ggml_cpu_has_metal      (void);
    GGML_API int ggml_cpu_has_f16c       (void);
    GGML_API int ggml_cpu_has_fp16_va    (void);
    GGML_API int ggml_cpu_has_wasm_simd  (void);
    GGML_API int ggml_cpu_has_blas       (void);
    GGML_API int ggml_cpu_has_cuda       (void);
    GGML_API int ggml_cpu_has_vulkan     (void);
    GGML_API int ggml_cpu_has_kompute    (void);
    GGML_API int ggml_cpu_has_gpublas    (void);
    GGML_API int ggml_cpu_has_sse3       (void);
    GGML_API int ggml_cpu_has_ssse3      (void);
    GGML_API int ggml_cpu_has_sycl       (void);
    GGML_API int ggml_cpu_has_rpc        (void);
    GGML_API int ggml_cpu_has_vsx        (void);
    GGML_API int ggml_cpu_has_matmul_int8(void);
    GGML_API int ggml_cpu_has_cann       (void);
    GGML_API int ggml_cpu_has_llamafile  (void);

    //
    // Internal types and functions exposed for tests and benchmarks
    //

#ifdef  __cplusplus
// restrict not standard in C++
#define GGML_RESTRICT
#else
#define GGML_RESTRICT restrict
#endif
    typedef void (*ggml_to_float_t)  (const void  * GGML_RESTRICT x, float * GGML_RESTRICT y, int64_t k);
    typedef void (*ggml_from_float_t)(const float * GGML_RESTRICT x, void  * GGML_RESTRICT y, int64_t k);
    typedef void (*ggml_from_float_to_mat_t)
                                     (const float * GGML_RESTRICT x, void * GGML_RESTRICT y, int64_t nr, int64_t k, int64_t bs);
    typedef void (*ggml_vec_dot_t)  (int n, float * GGML_RESTRICT s, size_t bs, const void * GGML_RESTRICT x, size_t bx,
                                       const void * GGML_RESTRICT y, size_t by, int nrc);
    typedef void (*ggml_gemv_t)     (int n, float * GGML_RESTRICT s, size_t bs, const void * GGML_RESTRICT x,
                                       const void * GGML_RESTRICT y, int nr, int nc);
    typedef void (*ggml_gemm_t)     (int n, float * GGML_RESTRICT s, size_t bs, const void * GGML_RESTRICT x,
                                       const void * GGML_RESTRICT y, int nr, int nc);

    typedef struct {
        const char             * type_name;
        int64_t                  blck_size;
        int64_t                  blck_size_interleave; // interleave elements in blocks
        size_t                   type_size;
        bool                     is_quantized;
        ggml_to_float_t          to_float;
        ggml_from_float_t        from_float;
        ggml_from_float_t        from_float_ref;
        ggml_from_float_to_mat_t from_float_to_mat;
        ggml_vec_dot_t           vec_dot;
        enum ggml_type           vec_dot_type;
        int64_t                  nrows; // number of rows to process simultaneously
        int64_t                  ncols; // number of columns to process simultaneously
        ggml_gemv_t              gemv;
        ggml_gemm_t              gemm;
        int64_t                  row_meta_size;
    } ggml_type_traits_t;

    GGML_API ggml_type_traits_t ggml_internal_get_type_traits(enum ggml_type type);

#ifdef  __cplusplus
}
#endif
