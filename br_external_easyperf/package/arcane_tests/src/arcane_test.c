#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <math.h>
#include <inttypes.h>
#include "arcane_user.h"

// ----------------------------------------------------------------------------
// Configuration
// ----------------------------------------------------------------------------
#ifndef BATCH
#define BATCH 2
#endif
#ifndef HEAD
#define HEAD 2
#endif
#define M 300
#define K 300
#define N 300
#define MAXINT 10

// Quantization Constants
#define A_ZP 0
#define B_ZP 0
#define C_ZP 0
#define A_SCALE 0.0788717195391655
#define C_SCALE 0.11640336364507675

// Fixed-point params
#define FIXED_POINT_FRACTIONAL_BITS 31

// ----------------------------------------------------------------------------
// Data Type Configuration (Matches arcane_qmatmul_test_s8.ps_dram.c)
// ----------------------------------------------------------------------------
#ifndef L1_DT_WIDTH
#define L1_DT_WIDTH 32
#endif

#ifndef IS_SIGNED
#define IS_SIGNED 0
#endif

enum {m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15, mNONE=255};

typedef enum {
    u8   = 0b000,
    u16  = 0b001,
    u32  = 0b010,
    s8   = 0b100,
    s16  = 0b101,
    s32  = 0b110
} tensor_type_t;

// Define Type, Limits, and XMR Macro based on Width AND Sign
#if (L1_DT_WIDTH == 8)
    #if IS_SIGNED
        typedef int8_t  elem_t;
        #define MIN_VAL -128
        #define MAX_VAL 127
        #define XMR_SETUP xmr_s8 
    #else
        typedef uint8_t elem_t;
        #define MIN_VAL 0
        #define MAX_VAL 255
        #define XMR_SETUP xmr_u8 
    #endif
#elif (L1_DT_WIDTH == 16)
    #if IS_SIGNED
        typedef int16_t elem_t;
        #define MIN_VAL -128 
        #define MAX_VAL 127
        #define XMR_SETUP xmr_s16
    #else
        typedef uint16_t elem_t;
        #define MIN_VAL 0
        #define MAX_VAL 255 
        #define XMR_SETUP xmr_u16
    #endif
#elif (L1_DT_WIDTH == 32)
    #if IS_SIGNED
        typedef int32_t elem_t;
        #define MIN_VAL -127 
        #define MAX_VAL 128 
        #define XMR_SETUP xmr_s32
    #else
        typedef uint32_t elem_t;
        #define MIN_VAL 0
        #define MAX_VAL 255 
        #define XMR_SETUP xmr_u32
    #endif
#else
  #error "Unsupported L1_DT_WIDTH (use 8, 16, or 32)"
#endif

// Helper Macros for XMR
#define xmr_s32(md, mat, head, batch) \
  asm volatile("xmr.w %0, %1, %2" : : "r"(mat->phys_addr), "r"((s32 << 29) | (batch << 16) | (head)), "r"((md << 28) | (mat->cols << 14) | mat->rows) : "memory")

#define xmr_s16(md, mat, head, batch) \
  asm volatile("xmr.w %0, %1, %2" : : "r"(mat->phys_addr), "r"((s16 << 29) | (batch << 16) | (head)), "r"((md << 28) | (mat->cols << 14) | mat->rows) : "memory")

#define xmr_s8(md, mat, head, batch) \
  asm volatile("xmr.w %0, %1, %2" : : "r"(mat->phys_addr), "r"((s8 << 29) | (batch << 16) | (head)), "r"((md << 28) | (mat->cols << 14) | mat->rows) : "memory")

#define xmr_u32(md, mat, head, batch) \
  asm volatile("xmr.w %0, %1, %2" : : "r"(mat->phys_addr), "r"((u32 << 29) | (batch << 16) | (head)), "r"((md << 28) | (mat->cols << 14) | mat->rows) : "memory")

#define xmr_u16(md, mat, head, batch) \
  asm volatile("xmr.w %0, %1, %2" : : "r"(mat->phys_addr), "r"((u16 << 29) | (batch << 16) | (head)), "r"((md << 28) | (mat->cols << 14) | mat->rows) : "memory")

#define xmr_u8(md, mat, head, batch) \
  asm volatile("xmr.w %0, %1, %2" : : "r"(mat->phys_addr), "r"((u8 << 29) | (batch << 16) | (head)), "r"((md << 28) | (mat->cols << 14) | mat->rows) : "memory")


// QLinearMatMul Macro
#define arcane_qlinear_matmul(md, ms1, ms2, a_zp, b_zp, y_zp, per_column_scaling, fixp_scaling_phys) \
  asm volatile("xmk4 %0, %1, %2" \
               : \
               : "r"(((per_column_scaling & 0b1) << 24 ) | ((b_zp & 0xFF) << 16 ) | ((a_zp & 0xFF) << 8 ) | (y_zp & 0xFF)), \
                "r"(fixp_scaling_phys), \
                "r"((md << 24) | (mNONE << 16) | (ms2 << 8) | ms1) \
               : "memory");


// ----------------------------------------------------------------------------
// B Scales (Weights)
// ----------------------------------------------------------------------------
double b_scales[] = {
    0.0007827079971320927, 0.0008477442315779626, 0.000569373311009258,
    0.0006590225966647267, 0.0009299524826928973, 0.0004416232113726437,
    0.0005919048562645912, 0.0009050461230799556, 0.0009350661421194673,
    0.0007095197797752917, 0.0007226725574582815, 0.001079560723155737,
    0.0012008633930236101, 0.0012920269509777427, 0.0007670963532291353,
    0.00133478210773319,   0.0007956771878525615, 0.0005932796630077064,
    0.00047644571168348193, 0.0008133362280204892, 0.0013107070699334145,
    0.001099059940315783,  0.00035744503838941455, 0.0007263034931384027,
    0.000492354913149029,  0.0007245244341902435, 0.0007156164501793683,
    0.0003897022397723049, 0.0007280810386873782, 0.0005493764765560627
};

typedef struct {
  uint32_t multipliers[sizeof(b_scales)/sizeof(b_scales[0])];    
  uint32_t shift;         
} fixed_point_scale_t;


// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------
static double get_time_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static inline elem_t saturate_generic(int64_t value) {
    if (value > MAX_VAL) return (elem_t)MAX_VAL;
    if (value < MIN_VAL) return (elem_t)MIN_VAL;
    return (elem_t)value;
}

static inline elem_t requantize_q31(int64_t acc, int32_t multiplier_q31, int32_t zp_out) {
    int64_t scaled = (acc * (int64_t)multiplier_q31) >> 31;
    int64_t res = scaled + zp_out;
    return saturate_generic(res);
}

static void compute_fixed_point_scale(fixed_point_scale_t *scale) {
  double a_scale = A_SCALE;
  double c_scale = C_SCALE;

  for (size_t i = 0; i < sizeof(b_scales)/sizeof(b_scales[0]); i++) {
    double combined_scale = (a_scale * b_scales[i]) / c_scale;
    double scale_fp = ldexp(combined_scale, FIXED_POINT_FRACTIONAL_BITS);
    scale->multipliers[i] = (uint32_t)(scale_fp + 0.5);
  }
  scale->shift = FIXED_POINT_FRACTIONAL_BITS;
}

// ----------------------------------------------------------------------------
// CPU Golden Model
// ----------------------------------------------------------------------------
void qlinear_matmul_cpu(
    const elem_t* a, int32_t batch, int32_t a_rows, int32_t a_cols,
    const int32_t a_zp,
    const elem_t* b, int32_t b_cols,
    int32_t b_batch_stride,
    const int32_t* b_zp,
    elem_t* output,
    const int32_t output_zp,
    const int32_t* scale_q31,
    int32_t b_zp_is_scalar,
    int32_t per_column_scale
) {
    const int32_t a_stride   = a_rows * a_cols;
    const int32_t out_stride = a_rows * b_cols;

    for (int32_t bidx = 0; bidx < batch; ++bidx) {
        const elem_t* a_batch = a + bidx * a_stride;
        const elem_t* b_batch = b + (b_batch_stride ? bidx * b_batch_stride : 0);
        elem_t* out_batch = output + bidx * out_stride;

        for (int32_t i = 0; i < a_rows; i++) {
            for (int32_t j = 0; j < b_cols; j++) {
                int32_t acc = 0;
                for (int32_t k = 0; k < a_cols; k++) {
                    int32_t av = (int32_t)a_batch[i * a_cols + k] - a_zp;
                    int32_t bz = 0;
                    if (b_zp != NULL) {
                        bz = b_zp_is_scalar ? (int32_t)(uintptr_t)b_zp : b_zp[j];
                    }
                    int32_t bv = (int32_t)b_batch[k * b_cols + j] - bz;
                    acc += (int32_t)av * (int32_t)bv;
                }

                int32_t mult_q31 = scale_q31 ? (per_column_scale ? scale_q31[j] : scale_q31[0]) : 0;

                out_batch[i * b_cols + j] = acc; //requantize_q31(acc, mult_q31, output_zp);
            }
        }
    }
}

void fill_inputs(elem_t *A, elem_t *B, int sizeA, int sizeB) {
    for(int i=0; i<sizeA; i++) A[i] = (elem_t)1;
    for(int i=0; i<sizeB; i++) B[i] = (elem_t)1;
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------
int main() {
    printf("==========================================\n");
    printf("Userspace ARCANE Test (Parametrized)\n");
    printf("DT Width: %d, Signed: %d\n", L1_DT_WIDTH, IS_SIGNED);
    printf("==========================================\n");

    if (arcane_init() != 0) return 1;

    // Allocate Matrices (A, B, C) + Scales in CMA
    size_t batch_head = BATCH * HEAD;
    
    // Alloc size = total elements * sizeof(elem_t)
    size_t size_A = BATCH * HEAD * M * K;
    size_t size_B = BATCH * HEAD * K * N;
    size_t size_C = BATCH * HEAD * M * N;

    printf("Allocating matrices...\n");
    arcane_matrix_t *mat_A = arcane_alloc_matrix(M, K * batch_head, sizeof(elem_t));
    arcane_matrix_t *mat_B = arcane_alloc_matrix(K, N * batch_head, sizeof(elem_t)); 
    arcane_matrix_t *mat_C = arcane_alloc_matrix(M, N * batch_head, sizeof(elem_t));

    // Scales Matrix (uint32)
    size_t num_scales = sizeof(b_scales)/sizeof(b_scales[0]);
    arcane_matrix_t *mat_S = arcane_alloc_matrix(1, num_scales, sizeof(uint32_t));

    if (!mat_A || !mat_B || !mat_C || !mat_S) {
        fprintf(stderr, "Allocation failed\n");
        return 1;
    }

    // Fixup logical dimensions for XMR
    mat_A->rows = M; mat_A->cols = K;
    mat_B->rows = K; mat_B->cols = N;
    mat_C->rows = M; mat_C->cols = N;

    // Prepare CPU Buffers
    elem_t *cpu_A = malloc(size_A * sizeof(elem_t));
    elem_t *cpu_B = malloc(size_B * sizeof(elem_t));
    elem_t *cpu_C = malloc(size_C * sizeof(elem_t));
    
    // Initialize Inputs
    fill_inputs(cpu_A, cpu_B, size_A, size_B);

    // Initialise HW Buffers
    // Copy directly since types match
    memcpy(mat_A->virt_addr, cpu_A, size_A * sizeof(elem_t));
    memcpy(mat_B->virt_addr, cpu_B, size_B * sizeof(elem_t));
    memset(mat_C->virt_addr, 0, size_C * sizeof(elem_t));

    // Compute Scales
    fixed_point_scale_t fp_scale;
    compute_fixed_point_scale(&fp_scale);

    // Copy scales to CMA
    uint32_t *hw_S = (uint32_t*)mat_S->virt_addr;
    for(size_t i=0; i<num_scales; i++) hw_S[i] = fp_scale.multipliers[i];

    // --- HW Execution ---
    printf("Starting HW Execution...\n");
    
    // Use the parameterized macro
    XMR_SETUP(m0, mat_A, HEAD, BATCH);
    XMR_SETUP(m1, mat_B, HEAD, BATCH);
    XMR_SETUP(m2, mat_C, HEAD, BATCH);

    printf("A virt: %p phys: %p\n", mat_A->virt_addr, mat_A->phys_addr);
    printf("B virt: %p phys: %p\n", mat_B->virt_addr, mat_B->phys_addr);
    printf("C virt: %p phys: %p\n", mat_C->virt_addr, mat_C->phys_addr);

    elem_t *hw_C = (elem_t*)mat_C->virt_addr;

    double start_hw = get_time_ns();
    arcane_qlinear_matmul(m2, m0, m1, A_ZP, B_ZP, C_ZP, 1 /* per_col */, mat_S->phys_addr);
    volatile elem_t tmp = hw_C[0];
    double end_hw = get_time_ns();
    double time_hw = end_hw - start_hw;
    printf("HW Time: %.2f ns\n", time_hw);

    // --- CPU Execution ---
    printf("Starting CPU Execution...\n");
    double start_cpu = get_time_ns();
    
    qlinear_matmul_cpu(
        cpu_A, BATCH*HEAD, M, K,
        A_ZP,
        cpu_B, N,
        (BATCH*HEAD > 1) ? K*N : 0, 
        (const int32_t*)(uintptr_t)B_ZP, 
        cpu_C,
        C_ZP,
        fp_scale.multipliers,
        1,
        1 
    );
    
    double end_cpu = get_time_ns();
    double time_cpu = end_cpu - start_cpu;
    printf("CPU Time: %.2f ns\n", time_cpu);
    printf("Speedup: %.2fx\n", time_cpu / time_hw);

    // --- Verify ---
    int errs = 0;
    
    for(int i=0; i<size_C; i++) {
        if (hw_C[i] != cpu_C[i]) {
            errs++;
            if (errs < 10) 
                printf("Mismatch @ %d: HW=%d CPU=%d\n", i, (int)hw_C[i], (int)cpu_C[i]);
        }
    }

    if (errs == 0) printf("[PASS] All %lu elements match.\n", size_C);
    else printf("[FAIL] %d mismatches.\n", errs);

    // Cleanup
    free(cpu_A); free(cpu_B); free(cpu_C);
    arcane_free_matrix(mat_A); arcane_free_matrix(mat_B); arcane_free_matrix(mat_C); arcane_free_matrix(mat_S);
    arcane_cleanup();
    
    return errs ? 1 : 0;
}
