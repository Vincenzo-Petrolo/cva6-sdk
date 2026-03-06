#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <dirent.h>
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#include "tvmgen_default.h"
#include "arcane_user.h"

// DINOv2 tensors
int8_t softmax12[396294];
uint8_t file_buf[150528]; // 224*224*3
float input[1*3*224*224];
float outputs[1*384]; // 1 x 384 DINO embedding

// DINOv2 attention tensor shape: (B, H, T, T)
#define ATTN_B        1
#define ATTN_H        6      // 6 heads
#define ATTN_TOKENS   257    // 1 CLS + 16x16 patches = 257 tokens
#define ATTN_NUM_PATCHES  (ATTN_TOKENS - 1)
#define ATTN_GRID_SIZE    16   // sqrt(256) = 16

float mean_cls_attn[ATTN_NUM_PATCHES];  // normalized to [0,1]

// Helpers for printing images using Kitty graphics protocol
void timgr_print_rgb_CHW_kitty(const uint8_t* img, int C, int H, int W);
static inline uint8_t timg_u8(float x);
void preprocess_input(float* input_arr, int N, int C, int H, int W);

// Base64 encoding for Kitty protocol
static const char base64_chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void base64_encode_chunk(const uint8_t* in, int len, char* out) {
    out[0] = base64_chars[(in[0] >> 2) & 0x3F];
    out[1] = base64_chars[((in[0] << 4) | (len > 1 ? (in[1] >> 4) : 0)) & 0x3F];
    out[2] = (len > 1) ? base64_chars[((in[1] << 2) | (len > 2 ? (in[2] >> 6) : 0)) & 0x3F] : '=';
    out[3] = (len > 2) ? base64_chars[in[2] & 0x3F] : '=';
}

static volatile int _inference_running = 1;
void* progress_bar_thread(void* arg) {
    const char spin[] = {'|', '/', '-', '\\'};
    int i = 0;
    while(_inference_running) {
        printf("\r\033[KRunning DINOv2 inference via ARCANE... %c", spin[i]);
        fflush(stdout);
        i = (i + 1) % 4;
        usleep(100000); // 100ms
    }
    printf("\r\033[KInference completed successfully!\n");
    return NULL;
}

// Global variables for arcane_runtime.c to translate TVM offsets to CMA pointers
void *g_cma_workspace_virt = NULL;
uint32_t g_cma_workspace_phys = 0;
void *g_cma_constant_virt = NULL;
uint32_t g_cma_constant_phys = 0;
// Scratch buffer for ARCANE fixp_scales (must be in CMA for DMA access)
void *g_cma_scales_virt = NULL;
uint32_t g_cma_scales_phys = 0;

int main(int argc, char** argv) {
    char selected_filename[256] = {0};
    
    printf("==========================================\n");
    printf("ARCANE DINOv2 Linux Inference App\n");
    printf("==========================================\n");

    if (arcane_init() != 0) {
        fprintf(stderr, "Failed to initialize ARCANE via UIO/CMA.\n");
        return -1;
    }
    
    // Allocate the TVM AOT workspace entirely within the contiguous CMA region
    arcane_matrix_t *cma_workspace;
    
    // Ensure the constant pool size is aligned to 64 bytes to prevent misaligned faults (e.g. fsd)
    size_t const_size = TVMGEN_DEFAULT_CMA_CONSTANT_POOL_CONSTANT_POOL_SIZE;
    size_t const_size_aligned = (const_size + 63) & ~63;
    size_t scales_scratch_size = 8096; // 4KB scratch for fixp_scales (reused per layer)
    size_t ws_size = const_size_aligned + TVMGEN_DEFAULT_WORKSPACE_SIZE + scales_scratch_size;

    cma_workspace = arcane_alloc_matrix(1, ws_size, 1);

    if ( !cma_workspace ) {
        fprintf(stderr, "Failed to allocate in CMA for TVM workspace\n");
        arcane_cleanup();
        return -1;
    }

    g_cma_constant_virt = cma_workspace->virt_addr;
    g_cma_constant_phys = cma_workspace->phys_addr;
    g_cma_workspace_virt = cma_workspace->virt_addr + const_size_aligned;
    g_cma_workspace_phys = cma_workspace->phys_addr + const_size_aligned;
    g_cma_scales_virt = cma_workspace->virt_addr + const_size_aligned + TVMGEN_DEFAULT_WORKSPACE_SIZE;
    g_cma_scales_phys = cma_workspace->phys_addr + const_size_aligned + TVMGEN_DEFAULT_WORKSPACE_SIZE;
    
    printf("Allocated TVM memory in CMA: %zu bytes at phys 0x%x\n", const_size_aligned, g_cma_constant_phys);
    printf("Allocated TVM workspace in CMA: %zu bytes at phys 0x%x\n", cma_workspace->size, g_cma_workspace_phys);
    printf("Allocated scales scratch in CMA: %zu bytes at phys 0x%x\n", scales_scratch_size, g_cma_scales_phys);

    // Load the weights into the constant workspace
    FILE *fw = fopen("/usr/share/dinov2_images/dinov2_weights.bin", "rb");
    if (!fw) {
        fw = fopen("dinov2_weights.bin", "rb"); // Fallback to current directory
    }
    if (!fw) {
        fprintf(stderr, "Failed to open dinov2_weights.bin\n");
        arcane_free_matrix(cma_workspace);
        arcane_cleanup();
        return -1;
    }
    size_t wread = fread(g_cma_constant_virt, 1, TVMGEN_DEFAULT_CMA_CONSTANT_POOL_CONSTANT_POOL_SIZE, fw);
    fclose(fw);
    if (wread != TVMGEN_DEFAULT_CMA_CONSTANT_POOL_CONSTANT_POOL_SIZE) {
        fprintf(stderr, "Warning: read %zu bytes for weights, expected %d\n", wread, TVMGEN_DEFAULT_CMA_CONSTANT_POOL_CONSTANT_POOL_SIZE);
    } else {
        printf("Loaded TVM constant pool into CMA: %zu bytes\n", wread);
    }
    
    // Attempt to load from /usr/share/dinov2_images first, fallback to current dir
    const char* image_paths[] = {"/usr/share/dinov2_images", "."};
    DIR *d;
    struct dirent *dir;
    char files[20][256];
    char full_paths[20][512];
    int count = 0;

    for (int p = 0; p < 2; p++) {
        d = opendir(image_paths[p]);
        if (d) {
            printf("\nAvailable .chw images in %s:\n", image_paths[p]);
            while ((dir = readdir(d)) != NULL) {
                if (strstr(dir->d_name, ".chw")) {
                     strcpy(files[count], dir->d_name);
                    snprintf(full_paths[count], sizeof(full_paths[count]), "%s/%s", image_paths[p], dir->d_name);
                    printf("  [%d] %s\n", count, files[count]);
                    count++;
                    if (count >= 20) break;
                }
            }
            closedir(d);
            if (count > 0) break; // Found files, stop searching
        }
    }
    
    if (count > 0) {
        printf("\nSelect an image [0-%d]: ", count - 1);
        int choice = 0;
        if (scanf("%d", &choice) == 1 && choice >= 0 && choice < count) {
            strcpy(selected_filename, full_paths[choice]);
        } else {
            printf("Invalid choice, defaulting to %s\n", files[0]);
            strcpy(selected_filename, full_paths[0]);
        }
    } else {
        printf("No .chw files found!\n");
        arcane_free_matrix(cma_workspace);
        arcane_cleanup();
        return -1;
    }

    FILE *f = fopen(selected_filename, "rb");
    if (!f) {
        printf("Error opening %s\n", selected_filename);
        arcane_free_matrix(cma_workspace);
        arcane_cleanup();
        return -1;
    }
    size_t nread = fread(file_buf, 1, sizeof(file_buf), f);
    fclose(f);
    printf("Image %s loaded (%zu bytes)\n", selected_filename, nread);

    // Copy the image to input buffer as float
    for (int i = 0; i < 150528; i++) {
        input[i] = (float)file_buf[i];
    }

    // Preprocess the input image
    preprocess_input(input, 1, 3, 224, 224);

    struct tvmgen_default_inputs tvm_inputs = {
        .pixel_values = input,
    };
    struct tvmgen_default_outputs tvm_outputs = {
        .output0 = outputs,
        .output1 = softmax12,
    };
    
    struct tvmgen_default_workspace_pools tvm_workspace = {
        .cma_constant_pool = g_cma_constant_virt, 
        .cma_workspace_pool = g_cma_workspace_virt,
    };

    // Start progress bar thread
    _inference_running = 1;
    pthread_t progress_thread;
    // pthread_create(&progress_thread, NULL, progress_bar_thread, NULL);

    printf("Running model inference\n");
    int32_t ret = tvmgen_default_run(&tvm_inputs, &tvm_outputs, &tvm_workspace);
    
    // Stop progress bar thread
    _inference_running = 0;
    // pthread_join(progress_thread, NULL);
    
    if (ret != 0) {
        printf("TVM run failed with err %d\n", ret);
        arcane_cleanup();
        return -1;
    }

    // Show the original input image
    printf("\nInput image:\n");
    timgr_print_rgb_CHW_kitty(file_buf, 3, 224, 224);

    // ---- Visualize last attention layer CLS→patch map projected on the input image ----
    {
        const int8_t (*attn)[ATTN_H][ATTN_TOKENS][ATTN_TOKENS] =
            (const int8_t (*)[ATTN_H][ATTN_TOKENS][ATTN_TOKENS])softmax12;

        for (int p = 0; p < ATTN_NUM_PATCHES; ++p) {
            mean_cls_attn[p] = 0.0f;
        }

        for (int h = 0; h < ATTN_H; ++h) {
            for (int p = 0; p < ATTN_NUM_PATCHES; ++p) {
                int32_t v = (int32_t)attn[0][h][0][p + 1]; 
                mean_cls_attn[p] += (float)v;
            }
        }

        for (int p = 0; p < ATTN_NUM_PATCHES; ++p) {
            mean_cls_attn[p] /= (float)ATTN_H;
        }

        float max_v = mean_cls_attn[0];
        for (int p = 1; p < ATTN_NUM_PATCHES; ++p) {
            if (mean_cls_attn[p] > max_v) {
                max_v = mean_cls_attn[p];
            }
        }
        if (max_v < 1e-6f) {
            max_v = 1.0f;  
        }
        for (int p = 0; p < ATTN_NUM_PATCHES; ++p) {
            mean_cls_attn[p] /= max_v; 
        }

        const int IMG_H = 224;
        const int IMG_W = 224;
        const int GRID  = ATTN_GRID_SIZE;              // 16
        const int PATCH_H = IMG_H / GRID;              // 14
        const int PATCH_W = IMG_W / GRID;              // 14
        const int PLANE_SIZE = IMG_H * IMG_W;

        if (PATCH_H * GRID != IMG_H || PATCH_W * GRID != IMG_W) {
            printf("[ATTN] Image size (%dx%d) not divisible by grid %d; skipping projection.\n", IMG_H, IMG_W, GRID);
        } else {
            uint8_t overlay[3 * PLANE_SIZE];

            for (int gy = 0; gy < GRID; ++gy) {
                for (int gx = 0; gx < GRID; ++gx) {
                    int p = gy * GRID + gx;
                    float a = mean_cls_attn[p];

                    float gain = 2*a;
                    if (gain > 1.0f) gain = 1.0f;
                    if (gain < 0.0f) gain = 0.0f;

                    for (int py = 0; py < PATCH_H; ++py) {
                        int y = gy * PATCH_H + py;
                        for (int px = 0; px < PATCH_W; ++px) {
                            int x = gx * PATCH_W + px;
                            int idx = y * IMG_W + x;

                            for (int c = 0; c < 3; ++c) {
                                uint8_t orig = file_buf[c * PLANE_SIZE + idx];
                                float val = (float)orig * gain;
                                if (val > 255.0f) val = 255.0f;
                                if (val < 0.0f)   val = 0.0f;
                                overlay[c * PLANE_SIZE + idx] = (uint8_t)(val + 0.5f);
                            }
                        }
                    }
                }
            }

            printf("Input image with CLS→patch attention mask:\n");
            timgr_print_rgb_CHW_kitty(overlay, 3, IMG_H, IMG_W);
        }
    }

    arcane_free_matrix(cma_workspace);
    arcane_cleanup();
    return 0;
}

static inline uint8_t timg_u8(float x) {
    if (x < 0.0f) x = 0.0f;
    if (x > 1.0f) x = 1.0f;
    return (uint8_t)(x * 255.0f + 0.5f);
}

void timgr_print_rgb_CHW_kitty(const uint8_t* img, int C, int H, int W) {
    static char kitty_b64_buffer[200704 + 4];
    
    if (C != 3) {
        printf("[timgr] expected C=3\n");
        return;
    }
    
    const int num_pixels = H * W;
    const int plane_size = H * W; 

    const uint8_t* r_plane = img;
    const uint8_t* g_plane = img + plane_size;
    const uint8_t* b_plane = img + 2 * plane_size;

    int b64_idx = 0;
    uint8_t chunk[3]; 
    
    for (int i = 0; i < num_pixels; i++) {
        chunk[0] = r_plane[i]; 
        chunk[1] = g_plane[i]; 
        chunk[2] = b_plane[i]; 
        base64_encode_chunk(chunk, 3, &kitty_b64_buffer[b64_idx]);
        b64_idx += 4;
    }
    
    kitty_b64_buffer[b64_idx] = '\0';
    printf("\x1b_Ga=T,f=24,s=%d,v=%d;%s\x1b\\\n", W, H, kitty_b64_buffer);
}

void preprocess_input(float* input_arr, int N, int C, int H, int W) {
    const float mean[3] = {0.485f, 0.456f, 0.406f};
    const float std[3]  = {0.229f, 0.224f, 0.225f};

    for (int n = 0; n < N; n++) {
        for (int c = 0; c < C; c++) {
            for (int h = 0; h < H; h++) {
                for (int w = 0; w < W; w++) {
                    int idx = n * (C * H * W) + c * (H * W) + h * W + w;
                    input_arr[idx] = (input_arr[idx] / 255.0f - mean[c]) / std[c];
                }
            }
        }
    }
}
