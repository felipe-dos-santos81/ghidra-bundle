#!/usr/bin/env python3
import json
import sys
from pathlib import Path

REA_VERSION = "6.3.0"
GHIDRA_VERSION = "12.2"
POLICY_RELATIVE_PATH = Path("dist/ghidra/GhidraInstallationPolicy.js")


class PatchError(RuntimeError):
    pass


def _replacements(ghidra_version):
    supported = 'export const SUPPORTED_GHIDRA_VERSION = "12.1.4";'
    compatibility_before = """    return version.major === verified.major && version.minor === verified.minor
        ? { status: "compatible", version, raw }
        : { status: "unsupported", version, raw };"""
    compatibility_after = """    const sameVerifiedLine = version.major === verified.major && version.minor === verified.minor;
    return sameVerifiedLine || raw === BUNDLE_GHIDRA_VERSION
        ? { status: "compatible", version, raw }
        : { status: "unsupported", version, raw };"""
    return (
        (
            supported,
            supported + f'\nconst BUNDLE_GHIDRA_VERSION = "{ghidra_version}";',
        ),
        (compatibility_before, compatibility_after),
        (
            "/** Release line accepted by this bridge, such as `12.1.x`. */",
            "/** Accepted release selector text used in diagnostics and limitations. */",
        ),
        (
            "    return `${String(verified.major)}.${String(verified.minor)}.x`;",
            "    return `${String(verified.major)}.${String(verified.minor)}.x or ${BUNDLE_GHIDRA_VERSION}`;",
        ),
    )


def patch_policy(source: str, ghidra_version: str) -> str:
    if ghidra_version != GHIDRA_VERSION:
        raise PatchError(
            f"refusing Ghidra {ghidra_version}: this patch only supports {GHIDRA_VERSION}"
        )
    replacements = _replacements(ghidra_version)
    if all(source.count(new) == 1 for _, new in replacements):
        return source
    if any(new in source for _, new in replacements):
        raise PatchError("REA policy is partially patched or contains duplicate anchors")
    for old, _ in replacements:
        if source.count(old) != 1:
            raise PatchError(f"unexpected REA policy source; anchor was not unique: {old!r}")
    patched = source
    for old, new in replacements:
        patched = patched.replace(old, new, 1)
    return patched


def patch_package(package_root: Path, ghidra_version: str) -> bool:
    metadata = json.loads((package_root / "package.json").read_text(encoding="utf-8"))
    if metadata.get("name") != "rea-agents" or metadata.get("version") != REA_VERSION:
        raise PatchError(
            f"refusing rea-agents {metadata.get('version')!r}: expected exactly {REA_VERSION}"
        )
    policy_path = package_root / POLICY_RELATIVE_PATH
    original = policy_path.read_text(encoding="utf-8")
    patched = patch_policy(original, ghidra_version)
    if patched == original:
        return False
    policy_path.write_text(patched, encoding="utf-8")
    return True


def main(argv=None) -> int:
    arguments = sys.argv[1:] if argv is None else argv
    if len(arguments) != 2:
        print(
            "usage: patch-rea-ghidra.py <rea-agents package dir> <Ghidra version>",
            file=sys.stderr,
        )
        return 2
    try:
        changed = patch_package(Path(arguments[0]), arguments[1])
    except (OSError, json.JSONDecodeError, PatchError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    state = "patched" if changed else "already patched"
    print(f"REA Ghidra policy {state}: Ghidra {GHIDRA_VERSION} is compatible, not upstream-verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
