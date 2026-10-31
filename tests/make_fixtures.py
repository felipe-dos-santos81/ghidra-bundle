#!/usr/bin/env python3
"""Write the hand-built test programs used by `make test`.

Usage: python3 -I tests/make_fixtures.py OUTPUT_DIR

  dos.exe  16-bit DOS MZ with one segment relocation (GhidraDosToolbox DosLoader)
  le.exe   32-bit LE behind an MZ stub with one 32-bit fixup (lx-loader LeLoader)
  ee.elf   32-bit PS2 Emotion Engine ELF (Ghidra's ELF loader + R5900 language)
  ps4.elf  64-bit PS4-style ELF (GhidraPS4Loader; PT_LOAD + Sony dynamic data)

Every byte is fixed, so tests/expect/*.txt can name exact addresses.
"""
import struct
import sys
from pathlib import Path


def build_le() -> bytes:
    """Minimal LE: object 1 (code) at 0x10000, object 2 (data) at 0x20000.

    lx-loader reads the final page of *every* object with the header's
    last-page size, so each object is a single LAST-byte page.
    """
    le_offset = 0x80              # e_lfanew
    page_size = 0x1000
    last = 0x20                   # last-page size == each object's size
    data_pages = 0x200            # file offset of page 1
    # Table offsets, relative to the LE header (header is 0xC4 bytes).
    objtab, pagemap, resnames, entries = 0xC4, 0xF4, 0xFC, 0xFD
    fpagetab, frectab, impmod = 0x100, 0x10C, 0x115

    code = bytes([
        0xA1, 0x00, 0x00, 0x00, 0x00,  # 10000 mov eax, [obj2+4]  (fixup at +1)
        0xE8, 0x06, 0x00, 0x00, 0x00,  # 10005 call 0x10010
        0x35, 0xCD, 0xAB, 0x34, 0x12,  # 1000A xor eax, 0x1234ABCD
        0xC3,                          # 1000F ret
        0xB8, 0x07, 0x00, 0x00, 0x00,  # 10010 mov eax, 7        (helper)
        0xC3,                          # 10015 ret
    ])
    data = bytes(range(0x10, 0x20))    # obj2+4 holds 0x17161514

    stub = bytearray(le_offset)
    struct.pack_into("<2s13H", stub, 0, b"MZ", le_offset, 1, 0, 4, 0, 0xFFFF,
                     0, 0xB8, 0, 0, 0, 0x40, 0)
    struct.pack_into("<I", stub, 0x3C, le_offset)          # e_lfanew
    stub[0x40:0x44] = bytes([0xB4, 0x4C, 0xCD, 0x21])      # mov ah,4Ch; int 21h

    hdr = bytearray(0xC4)
    hdr[0:2] = b"LE"                                       # little-endian byte/word order
    struct.pack_into("<HH", hdr, 0x08, 2, 1)               # cpu 80386, os OS/2

    def dword(offset: int, value: int) -> None:
        struct.pack_into("<I", hdr, offset, value)

    dword(0x14, 2)                     # pages in module
    dword(0x18, 1)                     # entry object
    dword(0x1C, 0)                     # entry offset (eip)
    dword(0x20, 2)                     # stack object
    dword(0x24, last)                  # esp
    dword(0x28, page_size)
    dword(0x2C, last)                  # bytes on last page
    dword(0x30, impmod - fpagetab)     # fixup section size
    dword(0x38, fpagetab - objtab)     # loader section size
    dword(0x40, objtab)
    dword(0x44, 2)                     # object count
    dword(0x48, pagemap)
    dword(0x58, resnames)
    dword(0x5C, entries)
    dword(0x68, fpagetab)
    dword(0x6C, frectab)
    dword(0x70, impmod)                # import module table (empty)
    dword(0x78, impmod)                # import procedure table (empty)
    dword(0x80, data_pages)            # data pages, file offset

    objects = (struct.pack("<6I", last, 0x10000, 0x2005, 1, 1, 0)   # R X 32-bit
               + struct.pack("<6I", last, 0x20000, 0x2003, 2, 1, 0))  # R W 32-bit
    page_map = bytes([0, 0, 1, 0, 0, 0, 2, 0])            # big-endian page numbers 1, 2
    names_and_entries = bytes([0, 0, 0, 0])                # empty resident names, empty entry table, pad
    fixup_pages = struct.pack("<3I", 0, 9, 9)              # page 1 has 9 bytes of records, page 2 none
    fixup_record = bytes([0x07, 0x10, 0x01, 0x00, 0x02]) + struct.pack("<I", 4)
    # 0x07 = 32-bit offset; 0x10 = internal target, 32-bit target offset;
    # source offset 1; target object 2, offset 4.

    tables = objects + page_map + names_and_entries + fixup_pages + fixup_record
    assert len(hdr) + len(tables) == impmod, hex(len(hdr) + len(tables))

    image = bytearray(stub + hdr + tables)
    image += bytes(data_pages - len(image))
    image += code + bytes(page_size - len(code))           # page 1 (only `last` bytes are read)
    image += data + bytes(last - len(data))                # page 2
    return bytes(image)


def build_dos() -> bytes:
    """Old-style MZ (relocation table at 0x1C, so no NE/LE header is implied).

    Load module: code in paragraphs 0-1, data in paragraph 2.
    """
    code = bytes([
        0xB8, 0x02, 0x00,  # 0000 mov ax, 0x0002   (data segment; relocated)
        0x8E, 0xD8,        # 0003 mov ds, ax
        0xE8, 0x08, 0x00,  # 0005 call 0x0010      (helper)
        0xA3, 0x00, 0x00,  # 0008 mov [0x0000], ax
        0xB8, 0x00, 0x4C,  # 000B mov ax, 0x4C00   (terminate, exit code 0)
        0xCD, 0x21,        # 000E int 0x21
        0xB8, 0xCD, 0xAB,  # 0010 mov ax, 0xABCD   (helper)
        0xC3,              # 0013 ret
    ])
    module = code + bytes(0x20 - len(code)) + b"TESTDATA" + bytes(8)
    header_size = 0x20                                   # 0x1C header + one relocation
    size = header_size + len(module)
    header = struct.pack("<2s13H", b"MZ", size % 512, (size + 511) // 512,
                         1,            # relocations
                         header_size // 16,
                         0, 0xFFFF,    # min/max extra paragraphs
                         0x0002, 0x0010,  # ss:sp
                         0, 0, 0,      # checksum, ip, cs
                         0x1C, 0)      # relocation table offset, overlay
    relocation = struct.pack("<HH", 0x0001, 0x0000)      # patch the word at 0000:0001
    return header + relocation + module


def build_ee() -> bytes:
    """Minimal 32-bit PS2 EE ELF: one PT_LOAD code section at 0x00100000.

    e_flags combines EF_MIPS_ARCH_2 (0x20000000) with E_MIPS_MACH_5900
    (0x00920000), which selects the extension's r5900:LE:32:default language
    through data/languages/r5900.opinion.
    """
    code = struct.pack("<4I",
                       0x3C021234,  # 00100000 lui v0,0x1234
                       0x34425678,  # 00100004 ori v0,v0,0x5678
                       0x03E00008,  # 00100008 jr ra
                       0x00000000)  # 0010000C nop (delay slot)
    shstrtab = b"\0.text\0.shstrtab\0"
    shoff = 0x34 + 32                     # ELF header + one program header
    shstr_off = shoff + 3 * 40
    text_off = 0x1000

    elf = bytearray(text_off + len(code))
    elf[0:16] = b"\x7fELF\x01\x01\x01" + bytes(9)   # 32-bit, little-endian, v1
    struct.pack_into("<HHIIIIIHHHHHH", elf, 16,
                     2, 8, 1,           # ET_EXEC, EM_MIPS, EV_CURRENT
                     0x00100000,        # e_entry
                     0x34, shoff,       # e_phoff, e_shoff
                     0x20920000,        # EF_MIPS_ARCH_2 | E_MIPS_MACH_5900
                     52, 32, 1,         # e_ehsize, e_phentsize, e_phnum
                     40, 3, 2)          # e_shentsize, e_shnum, e_shstrndx
    struct.pack_into("<8I", elf, 0x34,
                     1, text_off, 0x00100000, 0x00100000,
                     len(code), len(code), 5, 0x1000)  # PT_LOAD, R+X, 4 KiB align
    struct.pack_into("<10I", elf, shoff + 40,
                     1, 1, 0x6, 0x00100000, text_off, len(code), 0, 0, 4, 0)
    struct.pack_into("<10I", elf, shoff + 80,
                     7, 3, 0, 0, shstr_off, len(shstrtab), 0, 0, 1, 0)
    elf[shstr_off:shstr_off + len(shstrtab)] = shstrtab
    elf[text_off:text_off + len(code)] = code
    return bytes(elf)


def build_ps4() -> bytes:
    """Minimal PS4-style ELF64: PT_LOAD, PT_DYNAMIC and PT_SCE_DYNLIBDATA.

    GhidraPS4Loader maps the raw file at address 0, labels the entry point at
    0x4000 + e_entry, and reads the Sony dynamic data for NID imports. e_entry is
    relative here (0x10) and the code sits at file offset 0x4010.
    """
    code = bytes([0xB8, 0x78, 0x56, 0x34, 0x12, 0xC3])  # mov eax,0x12345678; ret
    code_off = 0x4010
    dyn_off = 0x3000
    phnum, phoff = 3, 64
    shstrtab = b"\0.text\0.shstrtab\0"
    shoff = phoff + phnum * 56
    shstr_off = shoff + 3 * 64

    elf = bytearray(code_off + len(code))
    elf[0:16] = b"\x7fELF\x02\x01\x01" + bytes(9)   # 64-bit, little-endian, v1
    struct.pack_into("<HHIQQQIHHHHHH", elf, 16,
                     0xFE18, 62, 1,      # ET_SCE_DYNAMIC, EM_X86_64, EV_CURRENT
                     0x10,               # e_entry (relative to 0x4000)
                     phoff, shoff, 0,    # e_phoff, e_shoff, e_flags
                     64, 56, phnum,      # e_ehsize, e_phentsize, e_phnum
                     64, 3, 2)           # e_shentsize, e_shnum, e_shstrndx
    struct.pack_into("<IIQQQQQQ", elf, phoff,
                     1, 5, 0x4000, 0x400000, 0x400000, 0x20, 0x20, 0x1000)
    struct.pack_into("<IIQQQQQQ", elf, phoff + 56,
                     2, 4, dyn_off, 0x403000, 0x403000, 16, 16, 8)
    struct.pack_into("<IIQQQQQQ", elf, phoff + 112,
                     0x61000000, 4, dyn_off, 0x403000, 0x403000, 16, 16, 8)
    struct.pack_into("<QQ", elf, dyn_off, 0, 0)      # DT_NULL
    struct.pack_into("<IIQQQQIIQQ", elf, shoff + 64,
                     1, 1, 0x6, 0x400010, code_off, len(code), 0, 0, 16, 0)
    struct.pack_into("<IIQQQQIIQQ", elf, shoff + 128,
                     7, 3, 0, 0, shstr_off, len(shstrtab), 0, 0, 1, 0)
    elf[shstr_off:shstr_off + len(shstrtab)] = shstrtab
    elf[code_off:code_off + len(code)] = code
    return bytes(elf)


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, build in (("dos.exe", build_dos), ("le.exe", build_le), ("ee.elf", build_ee),
                        ("ps4.elf", build_ps4)):
        path = out / name
        path.write_bytes(build())
        print(f"wrote {path} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
