OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x03000000, LENGTH = 12K
}

_stack_len = 0x400;

SECTIONS
{
  .text : {
    *(.text)
    *(.rodata .rodata.*)
  } > RAM
  .bss (NOLOAD) : {
    . = ALIGN(8);
    _bss_start = .;
    *(.bss)
    _bss_end = .;
  } > RAM
  _end = .;
  _stack_end = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(_end + _stack_len <= _stack_end, "code + work + stack exceeds 12KB")
}
