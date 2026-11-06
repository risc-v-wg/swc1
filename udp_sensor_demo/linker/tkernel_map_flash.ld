/*
 *----------------------------------------------------------------------
 *    micro T-Kernel 3.00.07
 *
 *    Linker script: JASA1 / SWC1 RV32I  (XIP flash + PSRAM, split memory)
 *
 *    Code executes in place from the cs0 QSPI flash region
 *    (0x0000_0000-0x00FF_FFFF), data lives in the cs1 QSPI PSRAM region
 *    (0x0100_0000-0x01FF_FFFF). Requires the board's init_qspicmd reset
 *    strap to select "cs0 = Flash" (see Jasa1web全部.html section 2.2/2.4.1
 *    -- 0: cs0=PSRAM, cs1/cs2=PSRAM; 1: cs0=Flash, cs1/cs2=PSRAM). cs1/cs2
 *    always default to PSRAM regardless of the strap, so no extra QSPI
 *    timing-register setup is needed for the RAM region.
 *
 *    Layout:
 *      FLASH (cs0, 0x00000000+)
 *        0x00000000  .boot_entry   "j _start"
 *        0x00000040  .vector       interrupt table (64-byte aligned)
 *        0x00000084+ .text / .rodata
 *                    _data_lma     (.data load image, copied to RAM at boot)
 *      RAM   (cs1, 0x01000000+)
 *        0x01000000  .data         (copied from FLASH by reset_hdl.S)
 *                    .noinit       (survives warm reset)
 *                    .bss          (zero-init, NOLOAD)
 *                    stack (64 KB)
 *                    _end          (heap base, used by knl_startup_hw)
 *
 *    Since LMA != VMA for .data here, reset_hdl.S's ROM->RAM copy loop
 *    (skipped in the unified-memory tkernel_map.ld because LMA==VMA there)
 *    actually runs on this build -- no startup-code changes needed, it
 *    already handles this case.
 *----------------------------------------------------------------------
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 1M
    RAM   (rwx) : ORIGIN = 0x01000000, LENGTH = 1M
}

SECTIONS
{
    . = 0x00000000;

    /* Boot trampoline: single "j _start" at reset vector */
    .boot_entry :
    {
        KEEP(*(.boot_entry))
    } > FLASH

    /* Vectored interrupt table — 64-byte aligned */
    . = ALIGN(64);
    .vector :
    {
        _vector_table = .;
        KEEP(*(.vector))
        KEEP(*(.vector.*))
    } > FLASH

    /* Code */
    .text :
    {
        *(.text.startup)
        *(.text)
        *(.text.*)
        *(.gnu.linkonce.t.*)
    } > FLASH

    /* Read-only data */
    .rodata :
    {
        *(.rodata)
        *(.rodata.*)
        *(.gnu.linkonce.r.*)
        *(.srodata)             /* RV32 small read-only data */
        *(.srodata.*)
        . = ALIGN(4);           /* keep _data_lma word aligned: the copy  */
                                /* loop in reset_hdl.S uses lw/sw         */
    } > FLASH

    . = ALIGN(4);

    /* Initialised data: load image stays in FLASH, runtime copy lives in
     * RAM at 0x01000000+. reset_hdl.S copies [_data_lma, _data_lma+size)
     * to [_data_start, _data_end) before calling main(). */
    .data :
    {
        _data_start = .;
        *(.data_vector)         /* dynamic interrupt vector table */
        *(.data)
        *(.data.*)
        *(.gnu.linkonce.d.*)
        *(.sdata)               /* RV32 small-data (gp-relative) initialised */
        *(.sdata.*)             /* globals: must be inside the copy range   */
        . = ALIGN(4);           /* copy loop in reset_hdl.S moves words     */
        _data_end = .;
    } > RAM AT> FLASH

    _data_lma = LOADADDR(.data);

    /* Non-initialised persistent data (survives warm reset) */
    .noinit (NOLOAD) :
    {
        *(.noinit)
        *(.noinit.*)
    } > RAM

    /* Zero-initialised data. Includes .sbss/.sbss.* (RV32 small-data BSS,
     * used by gp-relative globals under the ilp32 small-data threshold) --
     * see tkernel_map.ld for why this must be listed explicitly. */
    .bss (NOLOAD) :
    {
        _bss_start = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        _bss_end = .;
    } > RAM

    . = ALIGN(16);

    /* Initial system stack (64 KB) */
    _stack_bottom = .;
    . += 0x10000;
    _stack_top = .;

    . = ALIGN(16);

    /* Heap / kernel work area starts here */
    _end = .;
}
