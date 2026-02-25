;*
;* My RISC-V RV32I CPU
;*   Test Code : load store test
;*    RV32I code
;* @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
;* @copylight	2025 Yoshiki Kurokawa
;* @license		https://opensource.org/licenses/MIT     MIT license
;* @version		0.1
;*

nop
nop
addi x1, x0, 7 ; LED value
lui x2, 0xc0010 ; LED address
addi x2, x2, 0xe00 ;
sw x1, 0x0(x2) ; set LED

lui x4, 0x00002 ; address A
lui x5, 0x00003 ; address B

addi x3, x0, 0
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x0, 0

lbu x7, 0x0(x4)
lw x8, 0x0(x5)

beq x3, x0, label_jmp1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
addi x3, x3, 1
jalr x0, x0, label_fail1
nop
nop
nop
:label_jmp1
jalr x0, x0, label_pass

:label_fail1
addi x1, x0, 0x11 ; LED value
sw x1, 0x0(x2) ; set LED
jalr x0, x0, label_fail1
nop
nop


:label_pass
;lui x2, 01000 ; loop max
addi x2, x0, 0x10
and x3, x0, x3 ; LED value
and x4, x0, x4 ; 
lui x4, 0xc0010 ; LED address
addi x4, x4, 0xe00 ;
:label_led
and x1, x0, x1 ; loop counter
:label_waitloop
addi x1, x1, 1 
blt x1, x2, label_waitloop
addi x3, x3, 1 
sw x3, 0x0(x4)
jalr x0, x0, label_led
nop
nop
nop
nop
