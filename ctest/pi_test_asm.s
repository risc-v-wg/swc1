#*
#* My RISC-V RV32I CPU
#*   pi_test.c rewritten in assembler (RV32I only, no M)
#*   Code + data + work + stack fit in 12KB, position independent
#*   (PC relative addressing only : can be loaded at any address)
#*
#*   Build : ./cmpl_asm.sh pi_test_asm        (FPGA, UART output)
#*           ./cmpl_asm.sh pi_test_asm sim    (riscv32-unknown-elf-run, ecall output)
#*
#*   Spigot algorithm same as pi_test.c except :
#*     f[] is 16bit (f[b] < 2b-1 < 2^16) and c = NC (pi_test.c : 8400)
#*     to fit in 12KB -> NC/14*4 digits are printed
#*
#* @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
#* @license		https://opensource.org/licenses/MIT     MIT license
#*

	.option norelax
	.equ NC,        5194          # c initial value (multiple of 14)
	.equ A,         10000
	.equ LP,        1000000
	.equ LP2,       200
	.equ UART_OUT,  0xc000fc00
	.equ LED,       0xc000fe00
	.equ FRC_BASE,  0xc000f800    # +0:val_lo +4:val_hi +0x10:ctrl

	.text
	.globl _start
_start:
	la   sp, _stack_end       # PC relative : load address + 12KB
	j    main

#---------------------------------------------------------------
# main
#   s0:e s1:c s2:d s3:b s4:&f[b] s5:g s6:d%a
#---------------------------------------------------------------
main:
.ifndef SIM
	li   t0, FRC_BASE         # frc : clear counter and start
	li   t1, 3
	sw   t1, 0x10(t0)
.endif
	la   t0, f                # for (b = 0; b < c; b++) f[b] = a / 5
	li   t1, NC
	li   t2, A/5
1:	sh   t2, 0(t0)
	addi t0, t0, 2
	addi t1, t1, -1
	bnez t1, 1b
	li   s0, 0                # e = 0
	li   s1, NC               # c
.Louter:                          # for (c = NC; c > 0; c -= 14)
	blez s1, .Ldone
	li   s2, 0                # d = 0
	addi s3, s1, -1           # b = c - 1
	la   s4, f
	slli t0, s3, 1
	add  s4, s4, t0           # &f[b]
.Linner:                          # for (; b > 0; b--)
	blez s3, .Linner_end
	slli s5, s3, 1            # g = 2 * b - 1
	addi s5, s5, -1
	mv   a0, s2               # d = d * b + f[b] * a
	mv   a1, s3
	jal  umul
	lhu  t0, 0(s4)            # f[b] * 10000 = f*(8192+1024+512+256+16)
	slli t1, t0, 4
	slli t2, t0, 8
	add  t1, t1, t2
	slli t2, t0, 9
	add  t1, t1, t2
	slli t2, t0, 10
	add  t1, t1, t2
	slli t2, t0, 13
	add  t1, t1, t2
	add  a0, a0, t1
	mv   a1, s5
	jal  udivmod
	sh   a1, 0(s4)            # f[b] = d % g
	mv   s2, a0               # d /= g
	addi s4, s4, -2
	addi s3, s3, -1
	j    .Linner
.Linner_end:
	mv   a0, s2               # sprintf(cbuf, "%04d", e + d / a)
	li   a1, A
	jal  udivmod
	mv   s6, a1
	add  a0, a0, s0
	jal  dec4
	li   a2, 0
	jal  uprint
	mv   s0, s6               # e = d % a
.ifndef SIM
	li   t0, LED              # *led = c
	sw   s1, 0(t0)
.endif
	addi s1, s1, -14
	j    .Louter
.Ldone:
	la   a0, cbuf             # CR LF
	li   a1, 0
	li   a2, 2
	jal  uprint
	jal  time_print
	j    pass

#---------------------------------------------------------------
# umul : a0 = a0 * a1  (low 32bit, loop count = bit length of a1)
#---------------------------------------------------------------
umul:
	li   t0, 0
1:	andi t1, a1, 1
	beqz t1, 2f
	add  t0, t0, a0
2:	slli a0, a0, 1
	srli a1, a1, 1
	bnez a1, 1b
	mv   a0, t0
	ret

#---------------------------------------------------------------
# udivmod : a0 = a0 / a1, a1 = a0 % a1  (unsigned, a1 < 2^31)
#---------------------------------------------------------------
udivmod:
	li   t0, 0                # remainder
	li   t1, 32
1:	srli t2, a0, 31
	slli t0, t0, 1
	or   t0, t0, t2
	slli a0, a0, 1
	bltu t0, a1, 2f
	sub  t0, t0, a1
	ori  a0, a0, 1
2:	addi t1, t1, -1
	bnez t1, 1b
	mv   a1, t0
	ret

#---------------------------------------------------------------
# dec4 : "%04d" (a0 >= 0)  return a0:string ptr a1:length
#   digits are written backward from cbuf+16
#---------------------------------------------------------------
dec4:
	addi sp, sp, -16
	sw   ra, 12(sp)
	sw   s0, 8(sp)
	sw   s1, 4(sp)
	sw   s2, 0(sp)
	mv   s0, a0               # value
	la   s1, cbuf+16          # write ptr
	li   s2, 0                # length
1:	mv   a0, s0
	li   a1, 10
	jal  udivmod
	mv   s0, a0
	addi a1, a1, '0'
	addi s1, s1, -1
	sb   a1, 0(s1)
	addi s2, s2, 1
	bnez s0, 1b
	li   t0, 4
	blt  s2, t0, 1b           # zero padding up to 4 digits
	mv   a0, s1
	mv   a1, s2
	lw   ra, 12(sp)
	lw   s0, 8(sp)
	lw   s1, 4(sp)
	lw   s2, 0(sp)
	addi sp, sp, 16
	ret

#---------------------------------------------------------------
# time_print : stop frc and print 64bit counter value in hex
#   "time = 0x" hhhhhhhh_llllllll CR LF   (SIM : always 0)
#---------------------------------------------------------------
time_print:
.ifdef SIM
	li   t1, 0
	li   t2, 0
.else
	li   t0, FRC_BASE
	sw   zero, 0x10(t0)       # stop counter (value is kept)
	lw   t2, 0(t0)            # lo
	lw   t1, 4(t0)            # hi
.endif
	la   a0, cbuf
	la   t3, str_time
	li   t4, 9
1:	lbu  t5, 0(t3)            # copy "time = 0x"
	sb   t5, 0(a0)
	addi t3, t3, 1
	addi a0, a0, 1
	addi t4, t4, -1
	bnez t4, 1b
	li   t4, 16               # 16 hex digits, hi first
2:	srli t5, t1, 28
	slli t1, t1, 4
	srli t6, t2, 28
	or   t1, t1, t6
	slli t2, t2, 4
	addi t5, t5, '0'
	li   t6, '9'
	ble  t5, t6, 3f
	addi t5, t5, 'a'-'9'-1
3:	sb   t5, 0(a0)
	addi a0, a0, 1
	addi t4, t4, -1
	bnez t4, 2b
	la   a0, cbuf
	li   a1, 25
	li   a2, 2
	j    uprint

#---------------------------------------------------------------
# uprint(a0:buf, a1:length, a2:ret)  ret 0:none 1:' ' 2:CR LF
#---------------------------------------------------------------
uprint:
.ifdef SIM
	mv   t3, a2
	li   a7, 64              # write(1, buf, length)
	mv   a2, a1
	mv   a1, a0
	li   a0, 1
	ecall
	beqz t3, 1f
	li   a7, 64
	li   a0, 1
	la   a1, str_crlf
	li   a2, 2
	li   t0, 2
	beq  t3, t0, 2f
	la   a1, str_sp
	li   a2, 1
2:	ecall
1:	ret
.else
	li   t0, UART_OUT
	li   t1, LED
	add  t2, a1, a2          # length + ret
	li   t3, 0               # i
1:	bge  t3, t2, 9f
2:	lw   t4, 4(t0)           # wait while uart_status == 1
	li   t5, 1
	beq  t4, t5, 2b
	blt  t3, a1, 3f
	li   t4, 0x0a            # i == length+1
	bne  t3, a1, 4f
	li   t4, 0x20            # i == length
	beq  a2, t5, 4f
	li   t4, 0x0d
	j    4f
3:	add  t4, a0, t3
	lbu  t4, 0(t4)
4:	sw   t4, 0(t0)
	sw   t3, 0(t1)
	addi t3, t3, 1
	j    1b
9:	ret
.endif

#---------------------------------------------------------------
# wait / pass
#---------------------------------------------------------------
wait:
	li   t0, 0               # timer
	li   t1, 0               # timer2
	li   t2, LP
	li   t3, LP2
1:	bgeu t1, t3, 3f
2:	bgeu t0, t2, 4f
	addi t0, t0, 1
	j    2b
4:	addi t1, t1, 1
	j    1b
3:	ret

pass:
.ifdef SIM
	li   a7, 93              # exit(0)
	li   a0, 0
	ecall
.endif
	li   s0, LED
	li   s1, 0
	li   s2, 0x7777
1:	jal  wait
	addi s1, s1, 1
	and  t0, s1, s2
	sw   t0, 0(s0)
	j    1b

#---------------------------------------------------------------
# constant data
#---------------------------------------------------------------
str_time:	.ascii "time = 0x"
.ifdef SIM
str_crlf:	.byte 0x0d,0x0a
str_sp:		.byte 0x20
.endif

#---------------------------------------------------------------
# work area
#---------------------------------------------------------------
	.bss
	.align 3
cbuf:	.space 32
f:	.space NC*2
