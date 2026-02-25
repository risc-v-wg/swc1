.option norelax
.globl _start


_start:
        nop ;
        nop ;
        nop ;
        nop ;
	lui sp,0x00040
	lui gp,0x00020
	lui tp,0x00018
    lui ra,0x00000
    lui s0,0x00040

	la a0, _bss
	la a1, _ebss
_loop_bss:
	sw zero, (a0)
	addi a0, a0, 4
	bltu a0, a1,  _loop_bss

        j main
        nop ;
        nop ;
        nop ;
