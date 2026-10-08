"""Print where pyghidraRun keeps Ghidra's virtualenv (or, with --settings, its user
settings directory) for a Ghidra install. Uses Ghidra's own pyghidra_launcher, so the
answer always matches what pyghidraRun does.

Usage: python3 -I scripts/pyghidra-venv-dir.py <ghidra install dir> [--settings]
"""
import sys
from pathlib import Path

if len(sys.argv) < 2:
    sys.exit(__doc__)
install_dir = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(install_dir / "Ghidra" / "Features" / "PyGhidra" / "support"))
import pyghidra_launcher  # noqa: E402

if "--settings" in sys.argv[2:]:
    print(pyghidra_launcher.get_user_settings_dir(install_dir, False))
else:
    print(pyghidra_launcher.get_ghidra_venv(install_dir, False))
