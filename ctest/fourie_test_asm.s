#*
#* My RISC-V RV32I CPU
#*   fourie_test.c rewritten in assembler (RV32I only, no M/F/D)
#*   Code + data + work + stack fit in 12KB, position independent
#*   (PC relative addressing only : can be loaded at any address)
#*
#*   Build : ./cmpl_asm.sh fourie_test_asm        (FPGA, UART output)
#*           ./cmpl_asm.sh fourie_test_asm sim    (riscv32-unknown-elf-run, ecall output)
#*
#*   Double precision soft-float (IEEE754 binary64, round to nearest even)
#*     X = (a0:lo, a1:hi)  Y = (a2:lo, a3:hi)  result = (a0:lo, a1:hi)
#*     denormal is flushed to zero, NaN is not supported
#*   sin/cos : fdlibm style (reduction by pi/2 + kernel polynomial)
#*
#* @auther		Yoshiki Kurokawa <yoshiki.k963@gmail.com>
#* @license		https://opensource.org/licenses/MIT     MIT license
#*

	.option norelax
	.equ N,         128
	.equ LP,        1000
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
#   x[n] = {r, i} 16byte  R[n] 8byte
#   work on stack : 0(sp):sin 8(sp):cos 16(sp):temp
#---------------------------------------------------------------
main:
	addi sp, sp, -32
.ifndef SIM
	li   t0, FRC_BASE         # frc : clear counter and start
	li   t1, 3
	sw   t1, 0x10(t0)
.endif
	la   a0, str_t            # uprint("t", 1, 2)
	li   a1, 1
	li   a2, 2
	jal  uprint

	# x[n].r = 0.5 + sin(0.1*n) + 0.3*sin(0.3*n) + 0.15*sin(0.5*n), x[n].i = 0
	#   s0:n s1:&x[n] s2/s3:(double)n s4/s5:sum
	li   s0, 0
	la   s1, x
.Lgen:
.ifndef SIM
	li   t0, LED              # *led = n & 0x7777
	li   t1, 0x7777
	and  t1, s0, t1
	sw   t1, 0(t0)
.endif
	mv   a0, s0
	jal  fitod
	mv   s2, a0
	mv   s3, a1
	la   t0, c_0_1            # 0.5 + sin(0.1*n)
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	jal  sincos
	li   a2, 0
	lui  a3, 0x3fe00
	jal  fadd
	mv   s4, a0
	mv   s5, a1
	mv   a0, s2               # + 0.3*sin(0.3*n)
	mv   a1, s3
	la   t0, c_0_3
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	jal  sincos
	la   t0, c_0_3
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	mv   a0, s4
	mv   a1, s5
	jal  fadd
	mv   s4, a0
	mv   s5, a1
	mv   a0, s2               # + 0.15*sin(0.5*n)
	mv   a1, s3
	li   a2, 0
	lui  a3, 0x3fe00
	jal  fmul
	jal  sincos
	la   t0, c_0_15
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	mv   a0, s4
	mv   a1, s5
	jal  fadd
	sw   a0, 0(s1)
	sw   a1, 4(s1)
	sw   zero, 8(s1)
	sw   zero, 12(s1)
	addi s1, s1, 16
	addi s0, s0, 1
	li   t0, N
	blt  s0, t0, .Lgen

	# print "sin[n]=x[n].r"
	li   s0, 0
	la   s1, x
.Lsin:
	la   a0, str_sin
	li   a1, 4
	li   a2, 0
	jal  uprint
	mv   a0, s0
	jal  print_int
	la   a0, str_eq
	li   a1, 2
	li   a2, 0
	jal  uprint
	li   a1, 3
	lw   a2, 0(s1)
	lw   a3, 4(s1)
	jal  print_double
	jal  print_nl
	addi s1, s1, 16
	addi s0, s0, 1
	li   t0, N
	blt  s0, t0, .Lsin
	jal  print_nl

	# for (k = 0; k < 30 + x[n].r * 25; k++) "*"
	li   s0, 0
	la   s1, x
.Lwave:
	lw   a0, 0(s1)
	lw   a1, 4(s1)
	li   a2, 0
	lui  a3, 0x40390          # 25.0
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	li   a0, 0
	lui  a1, 0x403e0          # 30.0
	jal  fadd
	mv   a2, a0
	mv   a3, a1
	jal  print_bar
	addi s1, s1, 16
	addi s0, s0, 1
	li   t0, N
	blt  s0, t0, .Lwave

	# DFT
	#   s0:n s1:&R[n] s2/s3:max s4:k s5:&x[k] s6/s7:X.r s8/s9:X.i s10/s11:2.0*PI*n
	la   a0, str_out
	li   a1, 26
	li   a2, 0
	jal  uprint
	li   s2, 0                # max = 0.0
	li   s3, 0
	li   s0, 0
	la   s1, R
.Ldft:
	li   s6, 0                # X.r = 0
	li   s7, 0
	li   s8, 0                # X.i = 0
	li   s9, 0
	mv   a0, s0
	jal  fitod
	la   t0, c_2pi
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	mv   s10, a0
	mv   s11, a1
	li   s4, 0
	la   s5, x
.Ldft_k:
	mv   a0, s4               # 2.0*PI*n*k/N
	jal  fitod
	mv   a2, a0
	mv   a3, a1
	mv   a0, s10
	mv   a1, s11
	jal  fmul
	li   a2, 0
	lui  a3, 0x40600          # 128.0
	jal  fdiv
	jal  sincos
	sw   a0, 0(sp)            # sin
	sw   a1, 4(sp)
	sw   a2, 8(sp)            # cos
	sw   a3, 12(sp)
	lw   a0, 0(s5)            # X.r += x[k].r*cos + x[k].i*sin
	lw   a1, 4(s5)
	jal  fmul
	sw   a0, 16(sp)
	sw   a1, 20(sp)
	lw   a0, 8(s5)
	lw   a1, 12(s5)
	lw   a2, 0(sp)
	lw   a3, 4(sp)
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	lw   a0, 16(sp)
	lw   a1, 20(sp)
	jal  fadd
	mv   a2, a0
	mv   a3, a1
	mv   a0, s6
	mv   a1, s7
	jal  fadd
	mv   s6, a0
	mv   s7, a1
	lw   a0, 8(s5)            # X.i += x[k].i*cos - x[k].r*sin
	lw   a1, 12(s5)
	lw   a2, 8(sp)
	lw   a3, 12(sp)
	jal  fmul
	sw   a0, 16(sp)
	sw   a1, 20(sp)
	lw   a0, 0(s5)
	lw   a1, 4(s5)
	lw   a2, 0(sp)
	lw   a3, 4(sp)
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	lw   a0, 16(sp)
	lw   a1, 20(sp)
	jal  fsub
	mv   a2, a0
	mv   a3, a1
	mv   a0, s8
	mv   a1, s9
	jal  fadd
	mv   s8, a0
	mv   s9, a1
	addi s5, s5, 16
	addi s4, s4, 1
	li   t0, N
	blt  s4, t0, .Ldft_k
	mv   a0, s6               # R[n] = sqrt(X.r*X.r + X.i*X.i)
	mv   a1, s7
	mv   a2, s6
	mv   a3, s7
	jal  fmul
	sw   a0, 16(sp)
	sw   a1, 20(sp)
	mv   a0, s8
	mv   a1, s9
	mv   a2, s8
	mv   a3, s9
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	lw   a0, 16(sp)
	lw   a1, 20(sp)
	jal  fadd
	jal  fsqrt
	sw   a0, 0(s1)
	sw   a1, 4(s1)
	mv   a2, a0               # if (R[n] > max) max = R[n]
	mv   a3, a1
	mv   a0, s2
	mv   a1, s3
	jal  flt
	beqz a0, 1f
	lw   s2, 0(s1)
	lw   s3, 4(s1)
1:	la   a0, str_xr           # "X.r=" X.r ", X.i=" X.i ", R[" n "]=" R[n]
	li   a1, 4
	li   a2, 0
	jal  uprint
	li   a1, 8
	mv   a2, s6
	mv   a3, s7
	jal  print_double
	la   a0, str_xi
	li   a1, 6
	li   a2, 0
	jal  uprint
	li   a1, 8
	mv   a2, s8
	mv   a3, s9
	jal  print_double
	la   a0, str_rn
	li   a1, 4
	li   a2, 0
	jal  uprint
	mv   a0, s0
	jal  print_int
	la   a0, str_eq
	li   a1, 2
	li   a2, 0
	jal  uprint
	li   a1, 8
	lw   a2, 0(s1)
	lw   a3, 4(s1)
	jal  print_double
	jal  print_nl
	addi s1, s1, 8
	addi s0, s0, 1
	li   t0, N
	blt  s0, t0, .Ldft
	jal  print_nl

	# for (k = 0; k < R[n]*60/max; k++) "*"
	la   a0, str_graph
	li   a1, 25
	li   a2, 0
	jal  uprint
	li   s0, 0
	la   s1, R
.Lgraph:
	lw   a0, 0(s1)
	lw   a1, 4(s1)
	li   a2, 0
	lui  a3, 0x404e0          # 60.0
	jal  fmul
	mv   a2, s2
	mv   a3, s3
	jal  fdiv
	mv   a2, a0
	mv   a3, a1
	jal  print_bar
	addi s1, s1, 8
	addi s0, s0, 1
	li   t0, N
	blt  s0, t0, .Lgraph
	jal  time_print
	j    pass

#---------------------------------------------------------------
# print_bar(a2/a3:limit) : for (k = 0; k < limit; k++) "*" ; "\n"
#---------------------------------------------------------------
print_bar:
	addi sp, sp, -16
	sw   ra, 12(sp)
	sw   s0, 8(sp)
	sw   s1, 4(sp)
	sw   s2, 0(sp)
	mv   s0, a2
	mv   s1, a3
	li   s2, 0                # k
1:	mv   a0, s2
	jal  fitod
	mv   a2, s0
	mv   a3, s1
	jal  flt
	beqz a0, 2f
	la   a0, str_star
	li   a1, 1
	li   a2, 0
	jal  uprint
	addi s2, s2, 1
	j    1b
2:	lw   ra, 12(sp)
	lw   s0, 8(sp)
	lw   s1, 4(sp)
	lw   s2, 0(sp)
	addi sp, sp, 16
	j    print_nl

#---------------------------------------------------------------
# print_nl : uprint("\n", 2, 0)  (same as C : LF + NUL)
#---------------------------------------------------------------
print_nl:
	la   a0, str_nl
	li   a1, 2
	li   a2, 0
	j    uprint

#---------------------------------------------------------------
# print_double(a1:digit, a2/a3:value) : double_print to cbuf and uprint
#---------------------------------------------------------------
print_double:
	addi sp, sp, -16
	sw   ra, 12(sp)
	la   a0, cbuf
	jal  double_print
	j    1f
#---------------------------------------------------------------
# print_int(a0:value) : int_print to cbuf and uprint
#---------------------------------------------------------------
print_int:
	addi sp, sp, -16
	sw   ra, 12(sp)
	mv   a1, a0
	la   a0, cbuf
	jal  int_print
1:	mv   a1, a0
	la   a0, cbuf
	li   a2, 0
	lw   ra, 12(sp)
	addi sp, sp, 16
	j    uprint

#---------------------------------------------------------------
# int int_print(a0:cbuf, a1:value)  return length  (type 0 only)
#   same as C : value 0 -> "" (length 0)
#---------------------------------------------------------------
int_print:
	addi sp, sp, -32
	sw   ra, 28(sp)
	sw   s0, 24(sp)
	sw   s1, 20(sp)
	sw   s2, 16(sp)
	mv   s0, a0               # write ptr
	mv   s1, a0               # cbuf
	bgez a1, 1f
	li   t0, '-'
	sb   t0, 0(s0)
	addi s0, s0, 1
	sub  a1, zero, a1
1:	mv   s2, sp               # digits (reverse order) at 0..15(sp)
	mv   a0, a1
2:	beqz a0, 3f
	li   a1, 10
	jal  udivmod
	sb   a1, 0(s2)
	addi s2, s2, 1
	j    2b
3:	beq  s2, sp, 4f
	addi s2, s2, -1
	lbu  t0, 0(s2)
	addi t0, t0, '0'
	sb   t0, 0(s0)
	addi s0, s0, 1
	j    3b
4:	sub  a0, s0, s1
	lw   ra, 28(sp)
	lw   s0, 24(sp)
	lw   s1, 20(sp)
	lw   s2, 16(sp)
	addi sp, sp, 32
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
# int double_print(a0:cbuf, a1:digit, a2/a3:value)  return length
#   s0:write ptr s1:cbuf s2:digit s3/s4:value s5/s6:mug
#---------------------------------------------------------------
double_print:
	addi sp, sp, -32
	sw   ra, 28(sp)
	sw   s0, 24(sp)
	sw   s1, 20(sp)
	sw   s2, 16(sp)
	sw   s3, 12(sp)
	sw   s4, 8(sp)
	sw   s5, 4(sp)
	sw   s6, 0(sp)
	mv   s0, a0
	mv   s1, a0
	mv   s2, a1
	bgez a3, 1f              # value < 0 ?
	slli t0, a3, 1
	or   t0, t0, a2
	beqz t0, 1f
	li   t0, '-'
	sb   t0, 0(s0)
	addi s0, s0, 1
1:	mv   s3, a2              # value = |value|
	slli s4, a3, 1
	srli s4, s4, 1
	li   s5, 0               # mug = 1.0
	lui  s6, 0x3ff00
.Ldp_w1:                         # while (value >= mug) mug *= 10.0
	bltu s4, s6, .Ldp_w1e
	bne  s4, s6, 2f
	bltu s3, s5, .Ldp_w1e
2:	mv   a0, s5
	mv   a1, s6
	li   a2, 0
	lui  a3, 0x40240
	jal  fmul
	mv   s5, a0
	mv   s6, a1
	j    .Ldp_w1
.Ldp_w1e:
	jal  .Ldp_is1
	bnez t0, 3f
	li   t0, '0'
	sb   t0, 0(s0)
	li   t0, '.'
	sb   t0, 1(s0)
	addi s0, s0, 2
3:	jal  .Ldp_div10
.Ldp_for:
	beqz s2, .Ldp_w2
	jal  .Ldp_digit
	jal  .Ldp_is1
	bnez t0, 4f
	li   t0, '.'
	sb   t0, 0(s0)
	addi s0, s0, 1
4:	jal  .Ldp_div10
	addi s2, s2, -1
	j    .Ldp_for
.Ldp_w2:                         # while (mug >= 1.0)
	lui  t0, 0x3ff00
	bltu s6, t0, .Ldp_end
	jal  .Ldp_digit
	jal  .Ldp_div10
	sub  t0, s0, s1
	li   t1, 64
	blt  t0, t1, .Ldp_w2
.Ldp_end:
	sub  a0, s0, s1
	lw   ra, 28(sp)
	lw   s0, 24(sp)
	lw   s1, 20(sp)
	lw   s2, 16(sp)
	lw   s3, 12(sp)
	lw   s4, 8(sp)
	lw   s5, 4(sp)
	lw   s6, 0(sp)
	addi sp, sp, 32
	ret

.Ldp_is1:                        # t0 = (mug == 1.0) ? 0 : nonzero
	lui  t0, 0x3ff00
	xor  t0, t0, s6
	or   t0, t0, s5
	ret

.Ldp_div10:                      # mug /= 10.0
	addi sp, sp, -16
	sw   ra, 12(sp)
	mv   a0, s5
	mv   a1, s6
	li   a2, 0
	lui  a3, 0x40240
	jal  fdiv
	mv   s5, a0
	mv   s6, a1
	lw   ra, 12(sp)
	addi sp, sp, 16
	ret

.Ldp_digit:                      # a = (uchar)(value/mug); *s0++ = a+'0'; value -= a*mug
	addi sp, sp, -16
	sw   ra, 12(sp)
	mv   a0, s3
	mv   a1, s4
	mv   a2, s5
	mv   a3, s6
	jal  fdiv
	jal  fdtou
	andi a0, a0, 0xff
	addi t0, a0, '0'
	sb   t0, 0(s0)
	addi s0, s0, 1
	jal  fitod
	mv   a2, s5
	mv   a3, s6
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	mv   a0, s3
	mv   a1, s4
	jal  fsub
	mv   s3, a0
	mv   s4, a1
	lw   ra, 12(sp)
	addi sp, sp, 16
	ret

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

#===============================================================
# soft-float double
#===============================================================

#---------------------------------------------------------------
# fpack : normalize, round (nearest even) and pack
#   a0:sign(bit31) a1:E a2:Mhi a3:Mlo a4:sticky
#   value = M * 2^(E-1086)   (M 64bit, leading 1 normalized to bit63)
#---------------------------------------------------------------
fpack:
	or   t0, a2, a3
	beqz t0, .Lpk_zero
.Lpk_norm:
	bltz a2, .Lpk_round
	slli a2, a2, 1
	srli t0, a3, 31
	or   a2, a2, t0
	slli a3, a3, 1
	addi a1, a1, -1
	j    .Lpk_norm
.Lpk_round:
	andi t0, a3, 0x3ff
	or   a4, a4, t0          # sticky
	srli t1, a3, 10
	andi t1, t1, 1           # round bit
	slli t2, a2, 21          # mant = M >> 11
	srli a3, a3, 11
	or   a3, a3, t2
	srli a2, a2, 11
	beqz t1, .Lpk_pack
	andi t0, a3, 1
	or   t0, t0, a4
	beqz t0, .Lpk_pack
	addi a3, a3, 1
	bnez a3, 1f
	addi a2, a2, 1
1:	srli t0, a2, 21          # carry out to 2^53 ?
	beqz t0, .Lpk_pack
	srli a2, a2, 1
	addi a1, a1, 1
.Lpk_pack:
	blez a1, .Lpk_zero
	li   t0, 2047
	bge  a1, t0, .Lpk_inf
	slli t0, a1, 20
	slli a2, a2, 12
	srli a2, a2, 12
	or   a1, a2, t0
	or   a1, a1, a0
	mv   a0, a3
	ret
.Lpk_inf:
	lui  a1, 0x7ff00
	or   a1, a1, a0
	li   a0, 0
	ret
.Lpk_zero:
	mv   a1, a0
	li   a0, 0
	ret

#---------------------------------------------------------------
# fitod : a0 (unsigned int) -> double
#---------------------------------------------------------------
fitod:
	mv   a3, a0
	li   a2, 0
	li   a0, 0
	li   a1, 1086
	li   a4, 0
	j    fpack

#---------------------------------------------------------------
# fdtou : double -> unsigned int (truncate, negative -> 0)
#---------------------------------------------------------------
fdtou:
	bltz a1, 9f
	srli t0, a1, 20
	addi t0, t0, -1023       # e
	bltz t0, 9f
	slli a1, a1, 12
	srli a1, a1, 12
	lui  t1, 0x100
	or   a1, a1, t1
	li   t1, 52
	sub  t1, t1, t0          # k = 52 - e
	li   t2, 32
	blt  t1, t2, 1f
	addi t1, t1, -32
	srl  a0, a1, t1
	ret
1:	srl  a0, a0, t1
	sub  t2, t2, t1
	sll  a1, a1, t2
	or   a0, a0, a1
	ret
9:	li   a0, 0
	ret

#---------------------------------------------------------------
# fsub / fadd : X - Y / X + Y
#---------------------------------------------------------------
fsub:
	lui  t0, 0x80000
	xor  a3, a3, t0
fadd:
	slli t0, a1, 1           # make |X| >= |Y|
	slli t1, a3, 1
	bltu t1, t0, 1f
	bne  t1, t0, 2f
	bgeu a0, a2, 1f
2:	mv   t0, a0
	mv   a0, a2
	mv   a2, t0
	mv   t0, a1
	mv   a1, a3
	mv   a3, t0
1:	srli t5, a3, 20
	andi t5, t5, 0x7ff       # Ey
	beqz t5, 9f              # Y == 0 -> X
	srli t4, a1, 20
	andi t4, t4, 0x7ff       # Ex
	srli t6, a1, 31
	slli t6, t6, 31          # result sign
	xor  t3, a1, a3          # bit31 : sign differs
	lui  t2, 0x100
	slli a1, a1, 12          # mx << 10 (leading 1 at bit62)
	srli a1, a1, 12
	or   a1, a1, t2
	slli a1, a1, 10
	srli t0, a0, 22
	or   a1, a1, t0
	slli a0, a0, 10
	slli a3, a3, 12          # my << 10
	srli a3, a3, 12
	or   a3, a3, t2
	slli a3, a3, 10
	srli t0, a2, 22
	or   a3, a3, t0
	slli a2, a2, 10
	sub  t0, t4, t5          # my >>= (Ex-Ey) with sticky
	li   t1, 64
	bltu t0, t1, 3f
	mv   t0, t1
3:	li   a4, 0
4:	beqz t0, 5f
	andi t1, a2, 1
	or   a4, a4, t1
	srli a2, a2, 1
	slli t1, a3, 31
	or   a2, a2, t1
	srli a3, a3, 1
	addi t0, t0, -1
	j    4b
5:	or   a2, a2, a4
	bltz t3, 6f
	add  a0, a0, a2          # mx + my
	sltu t1, a0, a2
	add  a1, a1, a3
	add  a1, a1, t1
	j    7f
6:	sltu t1, a0, a2          # mx - my
	sub  a0, a0, a2
	sub  a1, a1, a3
	sub  a1, a1, t1
7:	or   t1, a0, a1
	beqz t1, 8f
	mv   a2, a1
	mv   a3, a0
	mv   a0, t6
	addi a1, t4, 1
	li   a4, 0
	j    fpack
8:	li   a1, 0               # exact zero -> +0
9:	ret

#---------------------------------------------------------------
# fmul : X * Y
#---------------------------------------------------------------
fmul:
	xor  t6, a1, a3
	srli t6, t6, 31
	slli t6, t6, 31          # sign
	srli t4, a1, 20
	andi t4, t4, 0x7ff
	srli t5, a3, 20
	andi t5, t5, 0x7ff
	beqz t4, 9f
	beqz t5, 9f
	lui  t0, 0x100
	slli a1, a1, 12
	srli a1, a1, 12
	or   a1, a1, t0          # m1 = (a1,a0)
	slli a3, a3, 12
	srli a3, a3, 12
	or   a3, a3, t0          # m2 = (a3,a2)
	slli a1, a1, 2           # m1 <<= 2 : keep round bit in acc
	srli t0, a0, 30
	or   a1, a1, t0
	slli a0, a0, 2
	li   t1, 0               # acc = (t1,t2) = (m1*m2) >> 51
	li   t2, 0
	li   t3, 0               # sticky
	li   t0, 53
1:	andi a4, a2, 1
	beqz a4, 2f
	add  t2, t2, a0
	sltu a4, t2, a0
	add  t1, t1, a1
	add  t1, t1, a4
2:	andi a4, t2, 1
	or   t3, t3, a4
	srli t2, t2, 1
	slli a4, t1, 31
	or   t2, t2, a4
	srli t1, t1, 1
	srli a2, a2, 1
	slli a4, a3, 31
	or   a2, a2, a4
	srli a3, a3, 1
	addi t0, t0, -1
	bnez t0, 1b
	add  a1, t4, t5
	addi a1, a1, -1013
	mv   a0, t6
	mv   a2, t1
	mv   a3, t2
	mv   a4, t3
	j    fpack
9:	mv   a1, t6
	li   a0, 0
	ret

#---------------------------------------------------------------
# fdiv : X / Y
#---------------------------------------------------------------
fdiv:
	xor  t6, a1, a3
	srli t6, t6, 31
	slli t6, t6, 31          # sign
	srli t4, a1, 20
	andi t4, t4, 0x7ff
	srli t5, a3, 20
	andi t5, t5, 0x7ff
	beqz t4, 8f              # 0 / Y
	beqz t5, 9f              # X / 0
	lui  t0, 0x100
	slli a1, a1, 12
	srli a1, a1, 12
	or   a1, a1, t0          # r  = (a1,a0)
	slli a3, a3, 12
	srli a3, a3, 12
	or   a3, a3, t0          # m2 = (a3,a2)
	li   t1, 0               # q = (t1,t2)
	li   t2, 0
	li   t0, 63
1:	slli t1, t1, 1
	srli a4, t2, 31
	or   t1, t1, a4
	slli t2, t2, 1
	bltu a1, a3, 3f
	bne  a1, a3, 2f
	bltu a0, a2, 3f
2:	sltu a4, a0, a2
	sub  a0, a0, a2
	sub  a1, a1, a3
	sub  a1, a1, a4
	ori  t2, t2, 1
3:	slli a1, a1, 1
	srli a4, a0, 31
	or   a1, a1, a4
	slli a0, a0, 1
	addi t0, t0, -1
	bnez t0, 1b
	or   a4, a0, a1          # sticky = (r != 0)
	sub  a1, t4, t5
	addi a1, a1, 1024
	mv   a0, t6
	mv   a2, t1
	mv   a3, t2
	j    fpack
8:	mv   a1, t6
	li   a0, 0
	ret
9:	lui  a1, 0x7ff00
	or   a1, a1, t6
	li   a0, 0
	ret

#---------------------------------------------------------------
# fsqrt : sqrt(X)   (X >= 0)
#---------------------------------------------------------------
fsqrt:
	srli t4, a1, 20
	andi t4, t4, 0x7ff
	beqz t4, 9f
	lui  t0, 0x100
	slli a1, a1, 12
	srli a1, a1, 12
	or   a1, a1, t0          # m = (a1,a0)
	addi t4, t4, -1023       # e
	andi t0, t4, 1
	beqz t0, 1f
	slli a1, a1, 1           # e odd : m <<= 1, e -= 1
	srli t0, a0, 31
	or   a1, a1, t0
	slli a0, a0, 1
	addi t4, t4, -1
1:	slli a1, a1, 10          # m << 10 : top bit pair at bit63-62
	srli t0, a0, 22
	or   a1, a1, t0
	slli a0, a0, 10
	li   t1, 0               # rem  = (t1,t2)
	li   t2, 0
	li   a2, 0               # root = (a2,a3)
	li   a3, 0
	li   t0, 55
2:	slli t1, t1, 2           # rem = rem<<2 | top 2 bits of m
	srli t3, t2, 30
	or   t1, t1, t3
	slli t2, t2, 2
	srli t3, a1, 30
	or   t2, t2, t3
	slli a1, a1, 2           # m <<= 2
	srli t3, a0, 30
	or   a1, a1, t3
	slli a0, a0, 2
	slli a2, a2, 1           # root <<= 1
	srli t3, a3, 31
	or   a2, a2, t3
	slli a3, a3, 1
	slli t5, a2, 1           # trial = 2*root + 1 = (t5,t3)
	srli t3, a3, 31
	or   t5, t5, t3
	slli t3, a3, 1
	ori  t3, t3, 1
	bltu t1, t5, 4f
	bne  t1, t5, 3f
	bltu t2, t3, 4f
3:	sltu t6, t2, t3          # rem -= trial, root |= 1
	sub  t2, t2, t3
	sub  t1, t1, t5
	sub  t1, t1, t6
	ori  a3, a3, 1
4:	addi t0, t0, -1
	bnez t0, 2b
	or   a4, t1, t2          # sticky = (rem != 0)
	srai t4, t4, 1
	addi a1, t4, 1032
	li   a0, 0
	j    fpack
9:	ret


#---------------------------------------------------------------
# flt : a0 = (X < Y) ? 1 : 0   (-0.0 == +0.0)
#   map to unsigned order : positive -> flip sign bit, negative -> invert
#---------------------------------------------------------------
flt:
	slli t0, a1, 1
	or   t0, t0, a0
	bnez t0, 1f
	li   a1, 0
1:	slli t0, a3, 1
	or   t0, t0, a2
	bnez t0, 2f
	li   a3, 0
2:	lui  t1, 0x80000
	bltz a1, 3f
	xor  a1, a1, t1
	j    4f
3:	not  a1, a1
	not  a0, a0
4:	bltz a3, 5f
	xor  a3, a3, t1
	j    6f
5:	not  a3, a3
	not  a2, a2
6:	bltu a1, a3, 7f
	bne  a1, a3, 8f
	bltu a0, a2, 7f
8:	li   a0, 0
	ret
7:	li   a0, 1
	ret

#---------------------------------------------------------------
# fpoly(a0/a1:z, a2:table, a3:count) : Horner c[0]*z^(n-1) + ... + c[n-1]
#---------------------------------------------------------------
fpoly:
	addi sp, sp, -32
	sw   ra, 28(sp)
	sw   s0, 24(sp)
	sw   s1, 20(sp)
	sw   s2, 16(sp)
	sw   s3, 12(sp)
	mv   s0, a0
	mv   s1, a1
	mv   s2, a2
	mv   s3, a3
	lw   a0, 0(s2)
	lw   a1, 4(s2)
1:	addi s3, s3, -1
	beqz s3, 2f
	addi s2, s2, 8
	mv   a2, s0
	mv   a3, s1
	jal  fmul
	lw   a2, 0(s2)
	lw   a3, 4(s2)
	jal  fadd
	j    1b
2:	lw   ra, 28(sp)
	lw   s0, 24(sp)
	lw   s1, 20(sp)
	lw   s2, 16(sp)
	lw   s3, 12(sp)
	addi sp, sp, 32
	ret

#---------------------------------------------------------------
# sincos(a0/a1:x) : a0/a1 = sin(x)  a2/a3 = cos(x)
#   q = (int)(|x| * 2/pi + 0.5)
#   r = |x| - q*PIO2_1 - q*PIO2_1T          (|r| <= pi/4)
#   z = r*r
#   s = r + z*r*(S1 + z*(S2 + ... + z*S6))
#   c = 1 - (z/2 - z*z*(C1 + z*(C2 + ... + z*C6)))
#   q&3 = 0:( s, c) 1:( c,-s) 2:(-s,-c) 3:(-c, s)
#   s0/s1:r s2:q s3/s4:z s5/s6:s s8:sign of x
#---------------------------------------------------------------
sincos:
	addi sp, sp, -48
	sw   ra, 44(sp)
	sw   s0, 40(sp)
	sw   s1, 36(sp)
	sw   s2, 32(sp)
	sw   s3, 28(sp)
	sw   s4, 24(sp)
	sw   s5, 20(sp)
	sw   s6, 16(sp)
	sw   s8, 12(sp)
	srli s8, a1, 31           # sin(-x) = -sin(x), cos(-x) = cos(x)
	slli a1, a1, 1
	srli a1, a1, 1
	mv   s0, a0
	mv   s1, a1
	la   t0, c_2opi           # q
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	li   a2, 0
	lui  a3, 0x3fe00
	jal  fadd
	jal  fdtou
	mv   s2, a0
	jal  fitod
	mv   s3, a0
	mv   s4, a1
	la   t0, c_pio2_1         # r
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	mv   a0, s0
	mv   a1, s1
	jal  fsub
	mv   s0, a0
	mv   s1, a1
	mv   a0, s3
	mv   a1, s4
	la   t0, c_pio2_1t
	lw   a2, 0(t0)
	lw   a3, 4(t0)
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	mv   a0, s0
	mv   a1, s1
	jal  fsub
	mv   s0, a0
	mv   s1, a1
	mv   a2, a0               # z
	mv   a3, a1
	jal  fmul
	mv   s3, a0
	mv   s4, a1
	la   a2, tbl_sin          # s
	li   a3, 6
	jal  fpoly
	mv   s5, a0
	mv   s6, a1
	mv   a0, s3
	mv   a1, s4
	mv   a2, s0
	mv   a3, s1
	jal  fmul
	mv   a2, s5
	mv   a3, s6
	jal  fmul
	mv   a2, a0
	mv   a3, a1
	mv   a0, s0
	mv   a1, s1
	jal  fadd
	mv   s5, a0
	mv   s6, a1
	mv   a0, s3               # c
	mv   a1, s4
	la   a2, tbl_cos
	li   a3, 6
	jal  fpoly
	mv   a2, s3
	mv   a3, s4
	jal  fmul
	mv   a2, s3
	mv   a3, s4
	jal  fmul
	mv   s0, a0
	mv   s1, a1
	mv   a0, s3
	mv   a1, s4
	li   a2, 0
	lui  a3, 0x3fe00
	jal  fmul
	mv   a2, s0
	mv   a3, s1
	jal  fsub
	mv   a2, a0
	mv   a3, a1
	li   a0, 0
	lui  a1, 0x3ff00
	jal  fsub
	mv   a2, a0               # quadrant
	mv   a3, a1
	mv   a0, s5
	mv   a1, s6
	lui  t1, 0x80000
	andi t0, s2, 1
	beqz t0, 1f
	mv   t2, a0
	mv   a0, a2
	mv   a2, t2
	mv   t2, a1
	mv   a1, a3
	xor  a3, t2, t1
1:	andi t0, s2, 2
	beqz t0, 2f
	xor  a1, a1, t1
	xor  a3, a3, t1
2:	beqz s8, 3f
	xor  a1, a1, t1
3:	lw   ra, 44(sp)
	lw   s0, 40(sp)
	lw   s1, 36(sp)
	lw   s2, 32(sp)
	lw   s3, 28(sp)
	lw   s4, 24(sp)
	lw   s5, 20(sp)
	lw   s6, 16(sp)
	lw   s8, 12(sp)
	addi sp, sp, 48
	ret

#---------------------------------------------------------------
# constant data
#---------------------------------------------------------------
	.align 3
c_0_1:		.double 0.1
c_0_3:		.double 0.3
c_0_15:		.double 0.15
c_2pi:		.double 6.28318530716          # 2.0*PI (PI = 3.14159265358)
c_2opi:		.word 0x6dc9c883, 0x3fe45f30   # 2/pi
c_pio2_1:	.word 0x54400000, 0x3ff921fb   # first 33 bits of pi/2
c_pio2_1t:	.word 0x1a626331, 0x3dd0b461   # pi/2 - c_pio2_1
tbl_sin:	.double  1.58969099521155010221e-10
		.double -2.50507602534068634195e-08
		.double  2.75573137070700676789e-06
		.double -1.98412698298579493134e-04
		.double  8.33333333332248946124e-03
		.double -1.66666666666666324348e-01
tbl_cos:	.double -1.13596475577881948265e-11
		.double  2.08757232129817482790e-09
		.double -2.75573143513906633035e-07
		.double  2.48015872894767294178e-05
		.double -1.38888888888741095749e-03
		.double  4.16666666666666019037e-02
str_t:		.ascii "t"
str_sin:	.ascii "sin["
str_eq:		.ascii "]="
str_nl:		.byte 0x0a,0
str_star:	.ascii "*"
str_xr:		.ascii "X.r="
str_xi:		.ascii ", X.i="
str_rn:		.ascii ", R["
str_out:	.ascii "Fourie transform output\n"
		.byte 0,0                       # C : length 26 (over the string)
str_graph:	.ascii "Fourie transform graph\n"
		.byte 0,0                       # C : length 25 (over the string)
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
x:	.space N*16
R:	.space N*8
cbuf:	.space 80
