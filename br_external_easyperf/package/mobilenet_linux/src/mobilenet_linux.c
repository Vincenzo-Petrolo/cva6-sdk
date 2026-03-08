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

// Globals used by arcane_byoc.py wrappers to calculate physical DMA addresses
void *g_cma_workspace_virt = NULL;
uint32_t g_cma_workspace_phys = 0;

void *g_cma_constant_virt = NULL;
uint32_t g_cma_constant_phys = 0;

void *g_cma_scales_virt = NULL;
uint32_t g_cma_scales_phys = 0;

void *g_cma_pw_args_virt = NULL;
uint32_t g_cma_pw_args_phys = 0;

uint32_t g_cma_scratchpad_phys = 0;

// MobileNetV2 I/O buffers
uint8_t file_buf[150528]; // 224*224*3
float input[1*3*224*224];
float outputs[1*1000];

// Helpers
void print_imagenet_label(size_t idx, const char *filename);
void timgr_print_rgb_CHW_kitty(const uint8_t* img, int C, int H, int W);
void preprocess_input(const uint8_t* raw_chw, float* input_nchw, int N, int C, int H, int W);

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
        printf("\r\033[KRunning MobileNetV2 inference via ARCANE... %c", spin[i]);
        fflush(stdout);
        i = (i + 1) % 4;
        usleep(100000); // 100ms
    }
    printf("\r\033[KInference completed successfully!\n");
    return NULL;
}

int main(int argc, char** argv) {
    char selected_filename[256] = {0};
    
    printf("==========================================\n");
    printf("ARCANE MobileNetV2 Linux Inference App\n");
    printf("==========================================\n");

    if (arcane_init() != 0) {
        fprintf(stderr, "Failed to initialize ARCANE via UIO/CMA.\n");
        return -1;
    }
    
    // Allocate the TVM AOT workspace entirely within the contiguous CMA region
    arcane_matrix_t *cma_workspace;
    
    // Align boundaries to 64 bytes to prevent misaligned vector/FPU faults
    size_t const_size = TVMGEN_DEFAULT_CMA_CONSTANT_POOL_CONSTANT_POOL_SIZE;
    size_t const_size_aligned = (const_size + 63) & ~63;
    size_t ws_size = TVMGEN_DEFAULT_WORKSPACE_SIZE;
    size_t ws_size_aligned = (ws_size + 63) & ~63;
    
    // Pointwise and Scales Scratchpads
    size_t scales_scratch_size = 8192;           // 8KB for fixp_scales
    size_t pw_args_size = 4096;                  // 4KB for arcane_pw_args_t structs
    size_t pw_scratchpad_size = 2 * 1024 * 1024; // 2MB max pointwise activation scratchpad
    
    size_t total_cma_size = const_size_aligned + ws_size_aligned + scales_scratch_size + pw_args_size + pw_scratchpad_size;

    cma_workspace = arcane_alloc_matrix(1, total_cma_size, 1);

    if ( !cma_workspace ) {
        fprintf(stderr, "Failed to allocate %zu bytes in CMA for TVM workspace\n", total_cma_size);
        arcane_cleanup();
        return -1;
    }

    // Partition the CMA memory block
    g_cma_constant_virt   = cma_workspace->virt_addr;
    g_cma_constant_phys   = cma_workspace->phys_addr;
    
    g_cma_workspace_virt  = (uint8_t*)g_cma_constant_virt + const_size_aligned;
    g_cma_workspace_phys  = g_cma_constant_phys + const_size_aligned;
    
    g_cma_scales_virt     = (uint8_t*)g_cma_workspace_virt + ws_size_aligned;
    g_cma_scales_phys     = g_cma_workspace_phys + ws_size_aligned;
    
    g_cma_pw_args_virt    = (uint8_t*)g_cma_scales_virt + scales_scratch_size;
    g_cma_pw_args_phys    = g_cma_scales_phys + scales_scratch_size;
    
    g_cma_scratchpad_phys = g_cma_pw_args_phys + pw_args_size;
    
    printf("Allocated Total TVM CMA: %zu bytes at phys 0x%x\n", cma_workspace->size, g_cma_constant_phys);

    // Load the weights into the constant workspace
    FILE *fw = fopen("/usr/share/mobilenet_images/mobilenet_weights.bin", "rb");
    if (!fw) {
        fw = fopen("mobilenet_weights.bin", "rb"); // Fallback
    }
    if (!fw) {
        fprintf(stderr, "Failed to open mobilenet_weights.bin\n");
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
    
    // Attempt to load images from /usr/share first, fallback to current dir
    const char* image_paths[] = {"/usr/share/mobilenet_images", "."};
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

    
    // Preprocess the input image into NCHW floats
    preprocess_input(file_buf, input, 1, 3, 224, 224);
    
    struct tvmgen_default_inputs tvm_inputs = {
        .input = input,
    };
    struct tvmgen_default_outputs tvm_outputs = {
        .output = outputs,
    };
    
    // Pass the CMA USMP pointers to TVM
    struct tvmgen_default_workspace_pools tvm_workspace = {
        .cma_constant_pool = g_cma_constant_virt, 
        .cma_workspace_pool = g_cma_workspace_virt,
    };
    
    // Start progress bar thread
    _inference_running = 1;
    pthread_t progress_thread;
    // pthread_create(&progress_thread, NULL, progress_bar_thread, NULL);
    
    int32_t ret = tvmgen_default_run(&tvm_inputs, &tvm_outputs, &tvm_workspace);
    
    // Stop progress bar thread
    _inference_running = 0;
    // pthread_join(progress_thread, NULL);
    
    if (ret != 0) {
        printf("TVM run failed with err %d\n", ret);
        arcane_free_matrix(cma_workspace);
        arcane_cleanup();
        return -1;
    }
    
    // Identify highest probability class
    int max_i = 0;
    float max_v = outputs[0];
    for (int i = 1; i < 1000; i++) {
        if (outputs[i] > max_v) {
            max_v = outputs[i];
            max_i = i;
        }
    }
    // Show the original input image
    printf("Input image:\n");
    timgr_print_rgb_CHW_kitty(file_buf, 3, 224, 224);
    
    printf("\nClassification Result:\n");
    printf("This is a "); 
    // Fallback attempt to open labels
    if (access("/usr/share/mobilenet_images/labels.txt", F_OK) == 0) {
        print_imagenet_label(max_i, "/usr/share/mobilenet_images/labels.txt"); 
    } else {
        print_imagenet_label(max_i, "labels.txt"); 
    }
    printf("Probability: %f\n", max_v);

    arcane_free_matrix(cma_workspace);
    arcane_cleanup();
    return 0;
}

void print_imagenet_label(size_t idx, const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) {
        printf("Error: Could not open labels file %s\n", filename);
        return;
    }
    char line[256];
    size_t i = 0;
    while (fgets(line, sizeof(line), fp)) {
        if (i == idx) {
            printf("%s", line); // fgets includes the newline
            fclose(fp);
            return;
        }
        i++;
    }
    fclose(fp);
}

// Convert CHW (3xHxW) image to RGB24 format for Kitty protocol using safe chunking
void timgr_print_rgb_CHW_kitty(const uint8_t* img, int C, int H, int W) {
    if (C != 3) {
        printf("[timgr] expected C=3\n");
        return;
    }
    
    const int num_pixels = H * W;
    const int plane_size = H * W;

    const uint8_t* r_plane = img;
    const uint8_t* g_plane = img + plane_size;
    const uint8_t* b_plane = img + 2 * plane_size;

    char chunk_buf[4096]; 
    int buf_idx = 0;
    int is_first = 1;
    
    for (int i = 0; i < num_pixels; i++) {
        uint8_t rgb[3] = { r_plane[i], g_plane[i], b_plane[i] };
        base64_encode_chunk(rgb, 3, &chunk_buf[buf_idx]);
        buf_idx += 4;

        int is_last_pixel = (i == num_pixels - 1);

        if (buf_idx >= 4096 || is_last_pixel) {
            int m = is_last_pixel ? 0 : 1;
            if (is_first) {
                printf("\x1b_Ga=T,f=24,s=%d,v=%d,m=%d;", W, H, m);
                is_first = 0;
            } else {
                printf("\x1b_Gm=%d;", m);
            }
            for(int k = 0; k < buf_idx; k++) {
                printf("%c", chunk_buf[k]);
            }
            printf("\x1b\\"); 
            buf_idx = 0; 
        }
    }
    printf("\n");
}

// Preprocess CHW to CHW Float (Leaves layout as NCHW!)
void preprocess_input(const uint8_t* raw_chw, float* input_nchw, int N, int C, int H, int W) {
    const float mean[3] = {0.485f, 0.456f, 0.406f};
    const float std[3]  = {0.229f, 0.224f, 0.225f};

    int total_pixels = N * C * H * W;
    for (int i = 0; i < total_pixels; i++) {
        int c = (i / (H * W)) % C;
        float pixel = (float)raw_chw[i];
        float norm = (pixel / 255.0f - mean[c]) / std[c];
        input_nchw[i] = norm;
    }
}