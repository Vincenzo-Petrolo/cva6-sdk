// matmul.c
// Build-time size: define N via -D, e.g. -DN=128
// Example run: ./matmul128

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#ifndef N
#error "Please compile with -DN=<size>, e.g., -DN=128"
#endif

// Use double for decent precision/perf balance.
typedef double scalar_t;

// Simple, portable aligned alloc (falls back to malloc if posix_memalign unavailable)
static void* xaligned_alloc(size_t alignment, size_t bytes) {
#if defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE >= 200112L
    void* p = NULL;
    if (posix_memalign(&p, alignment, bytes) != 0) return NULL;
    return p;
#elif defined(_MSC_VER)
    return _aligned_malloc(bytes, alignment);
#else
    (void)alignment;
    return malloc(bytes);
#endif
}

static void xfree(void* p) {
#if defined(_MSC_VER)
    _aligned_free(p);
#else
    free(p);
#endif
}

// Initialize A and B with deterministic values so checksums are reproducible.
static void init_matrices(scalar_t* A, scalar_t* B) {
    for (int i = 0; i < N; ++i) {
        for (int j = 0; j < N; ++j) {
            A[i * N + j] = (scalar_t)((i + j) % 13) * 0.5;
            B[i * N + j] = (scalar_t)((i == j) ? 2.0 : ((i + 2*j) % 7) * 0.25);
        }
    }
}

// Compute C = A * B (row-major). Loop order i-k-j to improve cache locality.
static void matmul(const scalar_t* A, const scalar_t* B, scalar_t* C) {
    // Zero C
    for (int i = 0; i < N * N; ++i) C[i] = 0.0;

    for (int i = 0; i < N; ++i) {
        const int iN = i * N;
        for (int k = 0; k < N; ++k) {
            const scalar_t aik = A[iN + k];
            const int kN = k * N;
            // Unrolling by 4 is a light perf win; safe for any N.
            int j = 0;
            for (; j + 3 < N; j += 4) {
                C[iN + j + 0] += aik * B[kN + j + 0];
                C[iN + j + 1] += aik * B[kN + j + 1];
                C[iN + j + 2] += aik * B[kN + j + 2];
                C[iN + j + 3] += aik * B[kN + j + 3];
            }
            for (; j < N; ++j) {
                C[iN + j] += aik * B[kN + j];
            }
        }
    }
}

static double wall_seconds(void) {
#if defined(_POSIX_C_SOURCE) && _POSIX_C_SOURCE >= 199309L
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
#else
    return (double)clock() / (double)CLOCKS_PER_SEC;
#endif
}

int main(void) {
    size_t bytes = (size_t)N * (size_t)N * sizeof(scalar_t);

    scalar_t* A = (scalar_t*)xaligned_alloc(64, bytes);
    scalar_t* B = (scalar_t*)xaligned_alloc(64, bytes);
    scalar_t* C = (scalar_t*)xaligned_alloc(64, bytes);

    if (!A || !B || !C) {
        fprintf(stderr, "Allocation failed for N=%d (bytes per matrix=%zu)\n", N, bytes);
        xfree(A); xfree(B); xfree(C);
        return 1;
    }

    init_matrices(A, B);

    double t0 = wall_seconds();
    matmul(A, B, C);
    double t1 = wall_seconds();

    // Compute a checksum to validate results without printing the whole matrix
    long double checksum = 0.0;
    for (int i = 0; i < N * N; ++i) checksum += C[i];

    printf("N=%d  time=%.6f s  checksum=%.10Lf\n", N, t1 - t0, checksum);

    xfree(A);
    xfree(B);
    xfree(C);
    return 0;
}
