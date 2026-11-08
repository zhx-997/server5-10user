OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { ITCM (rwx) : ORIGIN = 0x80000000, LENGTH = 256K }
SECTIONS {
    .text : { KEEP(*(.text.init)) *(.text*) } > ITCM
    .rodata : { *(.rodata*) } > ITCM
    .data : { *(.sdata*) *(.data*) } > ITCM
    .bss : { *(.sbss*) *(.bss*) *(COMMON) } > ITCM
    ASSERT(SIZEOF(.bss) == 0, "此验证固件不使用未初始化的静态变量")
    ASSERT(. < 0x8003f000, "程序与栈之间必须保留空间")
}
