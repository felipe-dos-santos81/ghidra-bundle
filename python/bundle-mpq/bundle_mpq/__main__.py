"""python -m bundle_mpq --check: report whether StormLib (libstorm) can be used."""
import sys

from bundle_mpq import MpqError, load_stormlib

if sys.argv[1:] != ["--check"]:
    sys.exit("usage: python -m bundle_mpq --check")
try:
    lib = load_stormlib()
except MpqError as e:
    sys.exit(str(e))
print(f"StormLib OK: {lib._name}")
