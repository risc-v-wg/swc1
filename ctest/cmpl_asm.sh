#!/bin/bash
# usage: ./cmpl_asm.sh [name] [sim]    (name default : det_test_asm)
NAME=det_test_asm
SIM=
for arg in "$@"; do
    if [ "$arg" == "sim" ]; then
        SIM=1
    else
        NAME=${arg%.s}
    fi
done
DEF=
if [ -n "$SIM" ]; then
    DEF="--defsym SIM=1"
    NAME_OUT=${NAME}_sim
else
    NAME_OUT=${NAME}
fi

riscv32-unknown-elf-as -march=rv32i -mabi=ilp32 ${DEF} -o ${NAME_OUT}.o ${NAME}.s
riscv32-unknown-elf-ld -b elf32-littleriscv ${NAME_OUT}.o -T det_asm.ld -Map=${NAME_OUT}.map -o ${NAME_OUT} --no-warn-rwx-segments --no-relax
riscv32-unknown-elf-objdump -b elf32-littleriscv -D ${NAME_OUT} > ${NAME_OUT}.elf.dump
riscv32-unknown-elf-objcopy -O binary ${NAME_OUT} ${NAME_OUT}.bin
od -An -tx4 -w4 -v ${NAME_OUT}.bin > ${NAME_OUT}.hex
