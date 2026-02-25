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

lui x11, 0x00001 ; address 0x1000
lui x3, 0x00001 ; value A
lui x4, 0x00002 ; value B
lui x5, 0x00100 ; address 0x100000
lui x6, 0x00200 ; address 0x200000

; write A
lui x7, 0x00001 ; loop 0x1000
;addi x7, x7, 0x800 ; loop 0x100
lui x8, 0x0 ; loop
:label_loop1
sw x3, 0x0(x5) ; store value A to (0x100000)
addi x3, x3, 1;
addi x5, x5, 16;

addi x8, x8, 1;
bne x8, x7, label_loop1

addi x1, x0, 6 ; LED value
lui x2, 0xc0010 ; LED address
addi x2, x2, 0xe00 ;
sw x1, 0x0(x2) ; set LED

; write B
lui x7, 0x00001 ; loop 0x1000
;addi x7, x7, 0x800 ; loop 0x100
lui x8, 0x0 ; loop
:label_loop2
sw x4, 0x0(x6) ; store value B to (0x200000)
addi x4, x4, 1;
addi x6, x6, 16;

addi x8, x8, 1;
bne x8, x7, label_loop2

addi x1, x0, 5 ; LED value
lui x2, 0xc0010 ; LED address
addi x2, x2, 0xe00 ;
sw x1, 0x0(x2) ; set LED

; read A B
lui x3, 0x00001 ; value A
lui x4, 0x00002 ; value B
lui x5, 0x00100 ; address 0x100000
lui x6, 0x00200 ; address 0x200000

lui x7, 0x00001 ; loop 0x1000
;addi x7, x7, 0x800 ; loop 0x100
lui x8, 0x0 ; loop
sw x8, 0x0(x11) ; store loop value 
:label_loop3
; read A
; read B
lw x9, 0x0(x5) ; load A
lw x10, 0x0(x6) ; load B
bne x10, x4, label_fail1
bne x9, x3, label_fail2
addi x3, x3, 1;
addi x5, x5, 16;
addi x4, x4, 1;
addi x6, x6, 16;

lw x16, 0x0(x11) ; load loop value 
bne x16, x8, label_fail3
addi x8, x8, 1;
sw x8, 0x0(x11) ; store loop value 
bne x8, x7, label_loop3
jalr x0, x0, label_pass

:label_fail1
addi x1, x0, 0x11 ; LED value
sw x1, 0x0(x2) ; set LED
jalr x0, x0, label_fail1
nop
nop

:label_fail2
addi x1, x0, 0x12 ; LED value
sw x1, 0x0(x2) ; set LED
jalr x0, x0, label_fail2
nop
nop

:label_fail3
addi x1, x0, 0x13 ; LED value
;sw x1, 0x0(x2) ; set LED
sw x16, 0x0(x2) ; set LED
jalr x0, x0, label_fail3
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
