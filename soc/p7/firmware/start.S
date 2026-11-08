.section .text.init
.globl _start
_start:
    lui sp, 0x80040
    addi sp, sp, -16
    la t0, trap_handler
    csrw mtvec, t0
    call main
1:  j 1b

.balign 4
trap_handler:
    addi sp, sp, -16
    sw t0, 0(sp)
    sw t1, 4(sp)
    sw t2, 8(sp)
    csrr t1, mcause
    li t0, 4
    beq t1, t0, misaligned_load_trap
    li t0, 0x80000003
    bne t1, t0, unexpected_trap
    li t0, 0x02000000
    sw zero, 0(t0)
    li t0, 0xa0000000
    lw t2, 60(t0)
    addi t2, t2, 1
    sw t2, 60(t0)
    j return_from_trap
misaligned_load_trap:
    csrr t0, mepc
    la t2, misaligned_load_instruction
    bne t0, t2, unexpected_trap
    csrr t0, mtval
    li t2, 0x90000101
    bne t0, t2, unexpected_trap
    li t0, 0xa0000000
    lw t2, 56(t0)
    addi t2, t2, 1
    sw t2, 56(t0)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
return_from_trap:
    lw t0, 0(sp)
    lw t1, 4(sp)
    lw t2, 8(sp)
    addi sp, sp, 16
    mret
unexpected_trap:
    lui t0, 0xa0000
    csrr t1, mcause
    sw t1, 12(t0)
    csrr t2, mepc
    sw t2, 16(t0)
    lui t2, 0x80000
    or t1, t1, t2
    sw t1, 8(t0)
    sw t1, 24(t0)
    lw t2, 0(t0)
    fence rw, rw
    sw t2, 4(t0)
2:  j 2b

.globl misaligned_load_test
.balign 4
misaligned_load_test:
    li a0, 0x90000101
    .option push
    .option norvc
misaligned_load_instruction:
    lw a1, 0(a0)
    .option pop
    li a0, 0x204
    ret

.globl cross_lane_test
.balign 8
cross_lane_test:
    li a0, 0
    li t0, 32
    .balign 8
3:
    c.nop
    c.nop
    c.nop
    .option push
    .option norvc
    addi a0, a0, 3
    .option pop
    c.addi a0, 1
    c.addi t0, -1
    bnez t0, 3b
    ret
