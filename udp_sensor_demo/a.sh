#!/bin/bash

NAME=`basename $1 .elf`
echo $NAME

riscv32-unknown-elf-objdump -b elf32-littleriscv -D ${NAME}.elf > ${NAME}.elf.dump
riscv32-unknown-elf-objcopy -O binary ${NAME}.elf ${NAME}.bin2
od -An -tx4 -w4 -v ${NAME}.bin2 > ${NAME}.hex
cat ${NAME}.hex zero >  ${NAME}.2.hex

