#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <errno.h>
#include <dirent.h>
#include "arcane_user.h"
#include "arcane_regs.h"
#include "arcane_loader.h" 

// Defines
#define CMA_BASE_ADDR 0xd0000000
#define CMA_SIZE      0x01000000 // 16MB mapped
#define UIO_MAP_SIZE  0x10000    // 64KB

// Global State
static int uio_fd = -1;
static int mem_fd = -1;
static void *prog_mem_ptr = NULL;
static void *ctrl_regs_ptr = NULL;
static void *cma_base_ptr = NULL;
static size_t cma_alloc_offset = 0; 
static size_t saved_prog_size = 0;
static size_t saved_ctrl_size = 0;

// Helper: Find UIO device
static int find_uio_device(const char *name) {
    char path[256];
    char name_buf[256];
    FILE *f;
    
    for (int i = 0; i < 255; i++) {
        snprintf(path, sizeof(path), "/sys/class/uio/uio%d/name", i);
        if (access(path, F_OK) != 0) break; 

        f = fopen(path, "r");
        if (!f) continue;
        
        if (fgets(name_buf, sizeof(name_buf), f)) {
            name_buf[strcspn(name_buf, "\n")] = 0;
            if (strcmp(name_buf, name) == 0) {
                fclose(f);
                return i;
            }
        }
        fclose(f);
    }
    return -1;
}

int arcane_init(void) {
    if (uio_fd >= 0) return 0; // Already initialized

    // 1. UIO Setup
    int uio_num = find_uio_device("ARCANE");
    if (uio_num < 0) {
        fprintf(stderr, "Error: Could not find UIO device 'ARCANE'\n");
        return -1;
    }
    printf("[ARCANE] Found UIO device at /dev/uio%d\n", uio_num);

    char uio_dev_path[64];
    snprintf(uio_dev_path, sizeof(uio_dev_path), "/dev/uio%d", uio_num);
    uio_fd = open(uio_dev_path, O_RDWR);
    if (uio_fd < 0) {
        perror("[ARCANE] open uio");
        return -1;
    }

    // Helper to get map size
    size_t get_uio_map_size(int uio_num, int map_index) {
        char path[256];
        snprintf(path, sizeof(path), "/sys/class/uio/uio%d/maps/map%d/size", uio_num, map_index);
        FILE *f = fopen(path, "r");
        if (!f) return 0;
        size_t size = 0;
        fscanf(f, "0x%zx", &size);
        fclose(f);
        return size;
    }

    // Map Regions (0=Prog, 1=Ctrl)
    size_t prog_size = get_uio_map_size(uio_num, 0);
    size_t ctrl_size = get_uio_map_size(uio_num, 1);

    if (prog_size == 0) prog_size = 0x4000; // Fallback
    if (ctrl_size == 0) ctrl_size = 0x1000; // Fallback

    prog_mem_ptr = mmap(NULL, prog_size, PROT_READ | PROT_WRITE, MAP_SHARED, uio_fd, 0 * getpagesize());
    if (prog_mem_ptr == MAP_FAILED) { perror("[ARCANE] mmap prog_mem"); return -1; }
    
    ctrl_regs_ptr = mmap(NULL, ctrl_size, PROT_READ | PROT_WRITE, MAP_SHARED, uio_fd, 1 * getpagesize());
    if (ctrl_regs_ptr == MAP_FAILED) { perror("[ARCANE] mmap ctrl_regs"); return -1; }

    // Store sizes for unmap
    saved_prog_size = prog_size;
    saved_ctrl_size = ctrl_size;

    // 2. Firmware Flashing
    printf("[ARCANE] Flashing firmware (%d bytes)...\n", ARCANE_LOADER_SIZE);
    memcpy(prog_mem_ptr, arcane_loader, ARCANE_LOADER_SIZE);

    // 3. Reset/Enable using arcane_bare logic
    volatile uint32_t *ecpu_ctl = (volatile uint32_t *)((uintptr_t)ctrl_regs_ptr + ARCANE_CTL_ECPU_CTL_REG_OFFSET);
    uint32_t boot_pc = ARCANE_EMEM_BASE_ADDR; 

    // Reset: fetch_en = 0
    uint32_t val_reset = ((0 & 0x1) << ARCANE_CTL_ECPU_CTL_CPU_FETCH_EN_BIT) |
                         ((boot_pc) << ARCANE_CTL_ECPU_CTL_BOOT_PC_OFFSET);
    
    *ecpu_ctl = val_reset;
    // asm volatile("fence iorw, iorw" ::: "memory"); // Userspace fence if needed, usu. handled by kernel/hw
    usleep(1000);

    // Enable: fetch_en = 1
    uint32_t val_enable = ((1 & 0x1) << ARCANE_CTL_ECPU_CTL_CPU_FETCH_EN_BIT) |
                          ((boot_pc) << ARCANE_CTL_ECPU_CTL_BOOT_PC_OFFSET);
    
    *ecpu_ctl = val_enable;
    printf("[ARCANE] Device enabled (Control Val: 0x%08x)\n", val_enable);

    // Wait for FW initialization (no_offload bit to clear)
    volatile uint32_t *op_ctl = (volatile uint32_t *)((uintptr_t)ctrl_regs_ptr + ARCANE_CTL_OP_CTL_REG_OFFSET);
    printf("[ARCANE] Waiting for FW initialization...\n");
    int timeout = 1000000;
    while ((*op_ctl >> ARCANE_CTL_OP_CTL_NO_OFFLOAD_BIT) & 0x1) {
        if (--timeout <= 0) {
            fprintf(stderr, "[ARCANE] Timeout waiting for FW init (no_offload bit)\n");
            return -1;
        }
        usleep(1);
    }
    printf("[ARCANE] FW Initialized (no_offload check passed)\n");

    // Enable exception mode
    *op_ctl |= (1 << ARCANE_CTL_OP_CTL_EXCEPTION_EN_BIT);

    printf("[ARCANE] Enabling exception mode\n");

    // 4. CMA Setup
    mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (mem_fd < 0) { perror("[ARCANE] open /dev/mem"); return -1; }

    cma_base_ptr = mmap(NULL, CMA_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, CMA_BASE_ADDR);
    if (cma_base_ptr == MAP_FAILED) { perror("[ARCANE] mmap /dev/mem (CMA)"); return -1; }
    
    printf("[ARCANE] CMA mapped at %p (Phys: 0x%08x)\n", cma_base_ptr, CMA_BASE_ADDR);
    cma_alloc_offset = 0; 

    return 0;
}

void arcane_cleanup(void) {
    if (cma_base_ptr) munmap(cma_base_ptr, CMA_SIZE);
    if (mem_fd >= 0) close(mem_fd);
    if (prog_mem_ptr) munmap(prog_mem_ptr, saved_prog_size);
    if (ctrl_regs_ptr) munmap(ctrl_regs_ptr, saved_ctrl_size);
    if (uio_fd >= 0) close(uio_fd);
    
    cma_base_ptr = NULL; 
    prog_mem_ptr = NULL; 
    ctrl_regs_ptr = NULL;
    uio_fd = -1; 
    mem_fd = -1;
}

arcane_matrix_t* arcane_alloc_matrix(int rows, int cols, size_t element_size) {
    if (!cma_base_ptr) {
        fprintf(stderr, "[ARCANE] Error: Driver not initialized or CMA map failed.\n");
        return NULL;
    }

    size_t size = rows * cols * element_size;
    // Align to 64 bytes
    size_t size_aligned = (size + 63) & ~63;
    size_t offset_aligned = (cma_alloc_offset + 63) & ~63;

    if (offset_aligned + size_aligned > CMA_SIZE) {
        fprintf(stderr, "[ARCANE] Error: OOM in CMA region.\n");
        return NULL;
    }

    arcane_matrix_t *mat = (arcane_matrix_t*)malloc(sizeof(arcane_matrix_t));
    if (!mat) return NULL;

    mat->virt_addr = (void*)((uintptr_t)cma_base_ptr + offset_aligned);
    mat->phys_addr = CMA_BASE_ADDR + offset_aligned;
    mat->size = size;
    mat->rows = rows;
    mat->cols = cols;

    cma_alloc_offset = offset_aligned + size_aligned;

    // Zero out memory
    memset(mat->virt_addr, 0, size);

    return mat;
}

void arcane_free_matrix(arcane_matrix_t *mat) {
    if (mat) free(mat);
}

void* arcane_get_prog_mem(void) { return prog_mem_ptr; }
void* arcane_get_ctrl_regs(void) { return ctrl_regs_ptr; }
