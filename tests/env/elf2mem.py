#!/usr/bin/env python3
"""Convert a 32-bit little-endian RISC-V ELF into the memory image read by
tb_verilator.sv.

Output format (all hex):
    <entry point>
    <word address> <word data>
    ...

Every PT_LOAD segment is emitted; the part of a segment beyond its file size
(.bss) is emitted as zeros.
"""
import struct
import sys


def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <elf> <out.mem>")

    with open(sys.argv[1], "rb") as f:
        elf = f.read()

    if elf[:4] != b"\x7fELF" or elf[4] != 1 or elf[5] != 1:
        sys.exit("error: expected a 32-bit little-endian ELF")

    entry, phoff = struct.unpack_from("<II", elf, 0x18)
    phentsize, phnum = struct.unpack_from("<HH", elf, 0x2A)

    mem = {}  # byte address -> byte value
    for i in range(phnum):
        p_type, p_offset, _, p_paddr, p_filesz, p_memsz = struct.unpack_from(
            "<IIIIII", elf, phoff + i * phentsize)
        if p_type != 1 or p_memsz == 0:  # PT_LOAD only
            continue
        data = elf[p_offset:p_offset + p_filesz] + bytes(p_memsz - p_filesz)
        for off, byte in enumerate(data):
            mem[p_paddr + off] = byte

    # Bytes of a partially covered word default to zero
    word_addrs = sorted({addr & ~3 for addr in mem})
    with open(sys.argv[2], "w") as f:
        f.write(f"{entry:08x}\n")
        for addr in word_addrs:
            word = sum(mem.get(addr + b, 0) << (8 * b) for b in range(4))
            f.write(f"{addr:08x} {word:08x}\n")


if __name__ == "__main__":
    main()
