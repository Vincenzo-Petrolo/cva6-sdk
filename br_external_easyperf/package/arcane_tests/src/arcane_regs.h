#ifndef ARCANE_CTL_REG_DEFS_USER_H
#define ARCANE_CTL_REG_DEFS_USER_H

// Control register for the eCPU
#define ARCANE_CTL_ECPU_CTL_REG_OFFSET 0x0
#define ARCANE_CTL_ECPU_CTL_CPU_FETCH_EN_BIT 0
#define ARCANE_CTL_ECPU_CTL_BOOT_PC_MASK 0x7fffffff
#define ARCANE_CTL_ECPU_CTL_BOOT_PC_OFFSET 1

// Boot PC
#define ARCANE_EMEM_BASE_ADDR 0x0 // Relative to eMEM base

// Arcane Controller <-> Bridge control and status register
#define ARCANE_CTL_OP_CTL_REG_OFFSET 0x4
#define ARCANE_CTL_OP_CTL_NO_OFFLOAD_BIT 7
#define ARCANE_CTL_OP_CTL_EXCEPTION_EN_BIT 16

#endif
