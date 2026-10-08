"""Write a small MPQ v1 archive for tests, with PKWARE-compressed files (the
compression Diablo 2's archives use).

StormLib's SCompCompress does the compression; this file writes the container
(header, encrypted hash and block tables) itself, because StormLib's own archive
writing aborts on some distributions (Ubuntu noble's 9.22 package).

CLI: make_mpq.py <out.mpq> <expected-bytes file>  - writes NAME holding TEXT, prints NAME.
"""
import ctypes
import struct
import sys

from bundle_mpq import load_stormlib

NAME = "data\\global\\excel\\bundle.txt"
TEXT = b"Stay awhile and listen. " * 100

SECTOR_SHIFT = 3                  # sector size 512 << 3 = 4096 bytes
MPQ_FILE_COMPRESS = 0x00000200
MPQ_FILE_EXISTS = 0x80000000
MPQ_COMPRESSION_PKWARE = 0x08
KEY_HASH_TABLE = 0xC3AF3770       # HashString("(hash table)", 0x300)
KEY_BLOCK_TABLE = 0xEC83B3A3      # HashString("(block table)", 0x300)
MASK = 0xFFFFFFFF


def _crypt_table():
    table, seed = [0] * 0x500, 0x00100001
    for first in range(0x100):
        index = first
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            high = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            table[index] = high | (seed & 0xFFFF)
            index += 0x100
    return table


CRYPT_TABLE = _crypt_table()


def hash_string(name, kind):
    """MPQ name hash, as StormLib computes it: case-insensitive, slashes kept as-is."""
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in name.upper().encode("latin-1"):
        seed1 = (CRYPT_TABLE[kind + ch] ^ (seed1 + seed2)) & MASK
        seed2 = (ch + seed1 + seed2 + (seed2 << 5) + 3) & MASK
    return seed1


def encrypt(data, key):
    out, seed = [], 0xEEEEEEEE
    for (value,) in struct.iter_unpack("<I", data):
        seed = (seed + CRYPT_TABLE[0x400 + (key & 0xFF)]) & MASK
        out.append(value ^ ((key + seed) & MASK))
        key = ((((~key) << 0x15) + 0x11111111) & MASK) | (key >> 0x0B)
        seed = (value + seed + (seed << 5) + 3) & MASK
    return struct.pack(f"<{len(out)}I", *out)


def _pkware(lib, data):
    lib.SCompCompress.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.c_void_p,
                                  ctypes.c_int, ctypes.c_uint, ctypes.c_int, ctypes.c_int]
    lib.SCompCompress.restype = ctypes.c_int
    out = ctypes.create_string_buffer(len(data) * 2 + 64)
    size = ctypes.c_int(len(out))
    if not lib.SCompCompress(out, ctypes.byref(size), data, len(data), MPQ_COMPRESSION_PKWARE, 0, 0):
        raise RuntimeError("SCompCompress failed")
    return out.raw[:size.value]   # begins with the compression-type byte 0x08


def write_mpq(path, files):
    """Write files ({name: bytes}, each at most 4096 bytes) plus a (listfile) to path."""
    assert hash_string("(hash table)", 0x300) == KEY_HASH_TABLE
    assert hash_string("(block table)", 0x300) == KEY_BLOCK_TABLE
    lib = load_stormlib()
    files = dict(files)
    files["(listfile)"] = "".join(f"{n}\r\n" for n in files).encode("latin-1")
    hash_size, free = 16, b"\xff" * 16
    body, blocks, hashes = b"", [], [free] * hash_size
    for index, (name, data) in enumerate(files.items()):
        assert len(data) <= 512 << SECTOR_SHIFT, "single-sector files only"
        sector = _pkware(lib, data)
        if len(sector) < len(data):
            payload = struct.pack("<2I", 8, 8 + len(sector)) + sector   # sector offset table
            flags = MPQ_FILE_COMPRESS | MPQ_FILE_EXISTS
        else:                                                         # stored, as StormLib does
            payload, flags = data, MPQ_FILE_EXISTS
        blocks.append(struct.pack("<4I", 32 + len(body), len(payload), len(data), flags))
        body += payload
        slot = hash_string(name, 0x000) % hash_size
        while hashes[slot] != free:
            slot = (slot + 1) % hash_size
        hashes[slot] = struct.pack("<2I2HI", hash_string(name, 0x100), hash_string(name, 0x200),
                                   0, 0, index)
    hash_pos = 32 + len(body)
    block_pos = hash_pos + 16 * hash_size
    header = struct.pack("<4s2I2H4I", b"MPQ\x1a", 32, block_pos + 16 * len(blocks), 0,
                         SECTOR_SHIFT, hash_pos, block_pos, hash_size, len(blocks))
    with open(path, "wb") as f:
        f.write(header + body + encrypt(b"".join(hashes), KEY_HASH_TABLE)
                + encrypt(b"".join(blocks), KEY_BLOCK_TABLE))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: make_mpq.py <out.mpq> <expected-bytes file>")
    write_mpq(sys.argv[1], {NAME: TEXT})
    with open(sys.argv[2], "wb") as f:
        f.write(TEXT)
    print(NAME)
