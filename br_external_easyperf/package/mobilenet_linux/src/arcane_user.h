#ifndef ARCANE_USER_H
#define ARCANE_USER_H

#include <stdint.h>
#include <stddef.h>

// ARCANE matrix structure for userspace
typedef struct {
    void *virt_addr;       // Virtual address (mmap base + offset)
    unsigned long phys_addr; // Physical address (CMA base + offset)
    size_t size;           // Size in bytes
    int rows;
    int cols;
    int type;              // tensor_type_t
} arcane_matrix_t;

/**
 * @brief Initialize ARCANE driver.
 *        Finds UIO device, maps registers, flashes firmware, resets eCPU.
 *        Also maps the CMA memory region.
 * @return 0 on success, -1 on failure.
 */
int arcane_init(void);

/**
 * @brief Cleanup ARCANE driver resources (unmap, close FDs).
 */
void arcane_cleanup(void);

/**
 * @brief Allocate a matrix in the shared CMA region.
 * @param rows Number of rows
 * @param cols Number of columns
 * @param element_size Size of each element in bytes
 * @return Pointer to arcane_matrix_t (must be freed), or NULL on failure.
 */
arcane_matrix_t* arcane_alloc_matrix(int rows, int cols, size_t element_size);

/**
 * @brief Free a matrix (release tracking, does not actually free CMA memory in this simple implementation).
 */
void arcane_free_matrix(arcane_matrix_t *mat);

/**
 * @brief Get the virtual address of the program memory (for debugging/advanced loading).
 */
void* arcane_get_prog_mem(void);

/**
 * @brief Get the virtual address of the control registers.
 */
void* arcane_get_ctrl_regs(void);

#endif // ARCANE_USER_H
