# Opens an MPQ with bundle_mpq inside PyGhidra and compares one file with the expected
# bytes. Prints "MPQ OK <n> bytes" or "MPQ FAIL <reason>".
# Script arguments: <archive.mpq> <name in archive> <file holding the expected bytes>
# @category Bundle
# @runtime PyGhidra
from bundle_mpq import MpqArchive

archive, name, expected_path = getScriptArgs()
with open(expected_path, "rb") as f:
    expected = f.read()
with MpqArchive(archive) as mpq:
    names = mpq.names()
    data = mpq.read(name)
if name not in names:
    print(f"MPQ FAIL {name} not listed (names: {names})")
elif data != expected:
    print(f"MPQ FAIL {name}: {len(data)} bytes differ from the expected {len(expected)}")
else:
    print(f"MPQ OK {len(data)} bytes")
