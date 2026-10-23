# Ghidra 12.2 Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the complete bundle to Ghidra 12.2 and JDK 25 while preserving every existing integration and passing the full sanity suite.

**Architecture:** Pin Ghidra's new source tag and select JDK 25 centrally. A bundle-owned Gradle init script aligns third-party extension toolchains without editing submodules, and a fail-closed postinstall patch lets the pinned REA release accept Ghidra 12.2 as compatible but not upstream-verified. Existing headless, HTTP, decompilation and portable-mode checks validate the real installation.

**Tech Stack:** GNU Make, bash, Gradle 9.1+ init scripts, JDK 25, Python 3 standard library and `unittest`, Ghidra 12.2, `rea-agents` 6.3.0, Node.js/npm.

**Spec:** `docs/superpowers/specs/2026-10-23-ghidra-12-2-upgrade-design.md`

## Global Constraints

- Pin `ghidra` to `Ghidra_12.2_build`, commit `8ca9077040cc43cd790babcfccf19475622a3e9a`; set `GHIDRA_VERSION := 12.2` and `JAVA_MAJOR := 25`.
- Replace `JAVA21_HOME` with `JAVA25_HOME`; the Makefile continues to export the selected JDK as `JAVA_HOME`. On apt systems without `openjdk-25-jdk`, require a preinstalled full JDK 25 through `JAVA25_HOME` rather than adding a package repository.
- Keep `rea-agents` exactly `6.3.0` and leave `.rea/package.json` and `.rea/package-lock.json` unchanged.
- Ghidra 12.2 is an additional REA **compatible**, never **verified**, release. Ghidra 12.1.x behavior and Java admission through `application.java.min`/`application.java.max` stay intact. The patch accepts exactly `12.2`; `12.2.1` and other versions remain rejected.
- Do not edit any third-party submodule source file. If compilation requires such an edit, stop and request a design revision.
- Do not migrate or delete `dist/ghidra_12.1.4_PUBLIC/`, user projects or user settings.
- Preserve portable mode: Ghidra, extensions, PyGhidra and REA write settings, caches and temporary state only below the active install's `portable/`.
- Keep D2GridraTools untouched; its upstream files are unlicensed and must never be modified or committed.
- Makefile recipes use tabs and propagate errors. Bash uses `set -euo pipefail`; new Python uses only the standard library.
- Historical specs and plans stay unchanged. No test may remain red at completion; REA must run rather than skip on this machine.
- Do not push branches or tags, open pull requests, create forks or publish packages.

## File Map

- Create `scripts/gradle-toolchain.init.gradle`: apply the requested Java major to every Java project after project evaluation.
- Create `scripts/patch-rea-ghidra.py`: validate and idempotently patch the pinned REA policy.
- Create `tests/test_patch_rea_ghidra.py`: unit-test patch semantics, idempotence and rejection cases.
- Modify `Makefile`: Ghidra/Java pins, JDK 25 discovery and installation, extension init-script arguments, REA patch invocation.
- Modify `build-ghidra.sh`: require JDK 25.
- Modify `tests/run-sanity.sh`: JDK 25 usage text, runtime/compiler-level check, REA patch unit-test integration.
- Modify `ghidra`: gitlink only, at the confirmed 12.2 tag commit.
- Modify `README.md` and `AGENTS.md`: current version, toolchain and compatibility documentation.
- Modify `tests/snapshots/`: intentionally recorded Ghidra 12.2 decompiler output.
- Modify `docs/superpowers/specs/2026-10-23-ghidra-12-2-upgrade-design.md`: mark implemented only after final verification.

---

### Task 1: REA policy patch and unit tests

**Files:**
- Create: `scripts/patch-rea-ghidra.py`
- Create: `tests/test_patch_rea_ghidra.py`

**Interfaces:**
- Consumes: existing `.rea/node_modules/rea-agents/dist/ghidra/GhidraInstallationPolicy.js` from `rea-agents` 6.3.0.
- Produces:
  - `PatchError(RuntimeError)`.
  - `patch_policy(source: str, ghidra_version: str) -> str`.
  - `patch_package(package_root: Path, ghidra_version: str) -> bool`; returns whether the file changed.
  - CLI `python3 -I scripts/patch-rea-ghidra.py <package-root> <ghidra-version>`.

- [ ] **Step 1: Write the failing unit tests**

Create `tests/test_patch_rea_ghidra.py` exactly as follows. The minimal policy fixture contains every source anchor the patch is allowed to touch.

```python
import json
import runpy
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "patch-rea-ghidra.py"
NAMESPACE = runpy.run_path(str(SCRIPT))
PatchError = NAMESPACE["PatchError"]
patch_package = NAMESPACE["patch_package"]
patch_policy = NAMESPACE["patch_policy"]

POLICY = """export const SUPPORTED_GHIDRA_VERSION = "12.1.4";
export const ghidraReleaseCompatibility = (raw) => {
    const version = parseGhidraRelease(raw);
    if (version === undefined) return { status: "unresolved", raw };
    if (raw === SUPPORTED_GHIDRA_VERSION)
        return { status: "verified", version, raw };
    const verified = verifiedGhidraRelease();
    return version.major === verified.major && version.minor === verified.minor
        ? { status: "compatible", version, raw }
        : { status: "unsupported", version, raw };
};
/** Release line accepted by this bridge, such as `12.1.x`. */
export const ghidraReleaseLine = () => {
    const verified = verifiedGhidraRelease();
    return `${String(verified.major)}.${String(verified.minor)}.x`;
};
"""


class ReaPolicyPatchTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.temporary.cleanup()

    def make_package(self, version="6.3.0", policy=POLICY):
        root = Path(self.temporary.name)
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        policy_path.parent.mkdir(parents=True)
        (root / "package.json").write_text(
            json.dumps({"name": "rea-agents", "version": version}), encoding="utf-8"
        )
        policy_path.write_text(policy, encoding="utf-8")
        return root

    def test_adds_compatible_release_and_is_idempotent(self):
        root = self.make_package()
        self.assertTrue(patch_package(root, "12.2"))
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        first = policy_path.read_text(encoding="utf-8")
        self.assertIn('export const SUPPORTED_GHIDRA_VERSION = "12.1.4";', first)
        self.assertIn('const BUNDLE_GHIDRA_VERSION = "12.2";', first)
        self.assertIn("sameVerifiedLine || raw === BUNDLE_GHIDRA_VERSION", first)
        self.assertIn(".x or ${BUNDLE_GHIDRA_VERSION}`", first)
        self.assertFalse(patch_package(root, "12.2"))
        self.assertEqual(first, policy_path.read_text(encoding="utf-8"))

    def test_rejects_another_ghidra_version_without_writing(self):
        root = self.make_package()
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        with self.assertRaises(PatchError):
            patch_package(root, "12.2.1")
        self.assertEqual(POLICY, policy_path.read_text(encoding="utf-8"))

    def test_rejects_another_rea_version(self):
        root = self.make_package(version="6.7.0")
        with self.assertRaises(PatchError):
            patch_package(root, "12.2")

    def test_rejects_unexpected_policy_source_without_writing(self):
        changed = POLICY.replace(
            "version.minor === verified.minor", "version.minor !== verified.minor"
        )
        root = self.make_package(policy=changed)
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        with self.assertRaises(PatchError):
            patch_package(root, "12.2")
        self.assertEqual(changed, policy_path.read_text(encoding="utf-8"))

    def test_rejects_a_partial_patch(self):
        root = self.make_package()
        policy_path = root / "dist" / "ghidra" / "GhidraInstallationPolicy.js"
        partial = patch_policy(POLICY, "12.2").replace(
            "    const sameVerifiedLine = version.major === verified.major && version.minor === verified.minor;\n",
            "",
        )
        policy_path.write_text(partial, encoding="utf-8")
        with self.assertRaises(PatchError):
            patch_package(root, "12.2")
        self.assertEqual(partial, policy_path.read_text(encoding="utf-8"))

    def test_real_installed_policy_when_available(self):
        policy_path = (
            Path(__file__).resolve().parents[1]
            / ".rea" / "node_modules" / "rea-agents" / "dist" / "ghidra"
            / "GhidraInstallationPolicy.js"
        )
        if not policy_path.is_file():
            self.skipTest("rea-agents is not installed")
        original = policy_path.read_text(encoding="utf-8")
        patched = patch_policy(original, "12.2")
        self.assertIn('export const SUPPORTED_GHIDRA_VERSION = "12.1.4";', patched)
        self.assertIn("sameVerifiedLine || raw === BUNDLE_GHIDRA_VERSION", patched)
        self.assertIn(".x or ${BUNDLE_GHIDRA_VERSION}`", patched)
        self.assertEqual(patched, patch_policy(patched, "12.2"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests and confirm the expected failure**

Run:

```bash
python3 -I tests/test_patch_rea_ghidra.py -v
```

Expected: FAIL during test-module loading with `FileNotFoundError` for `scripts/patch-rea-ghidra.py`.

- [ ] **Step 3: Implement the fail-closed patch script**

Create `scripts/patch-rea-ghidra.py`:

```python
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
```

- [ ] **Step 4: Run the unit tests and syntax check**

Run:

```bash
python3 -I tests/test_patch_rea_ghidra.py -v
python3 -I - <<'PY'
from pathlib import Path
for name in ("scripts/patch-rea-ghidra.py", "tests/test_patch_rea_ghidra.py"):
    path = Path(name)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
```

Expected: six tests PASS on this checkout and the syntax check exits 0. The real-policy test reports SKIP only when `.rea/node_modules/rea-agents` is absent.

- [ ] **Step 5: Commit the independently tested patch**

```bash
git add scripts/patch-rea-ghidra.py tests/test_patch_rea_ghidra.py
git commit -m "feat: admit Ghidra 12.2 in bundled REA"
```

---

### Task 2: Gradle Java toolchain override

**Files:**
- Create: `scripts/gradle-toolchain.init.gradle`
- Modify: `Makefile` (`JAVA_MAJOR` and the `install_extension` Gradle invocation)
- Create temporarily, never commit: `dist/toolchain-probe/settings.gradle` and `dist/toolchain-probe/build.gradle`

**Interfaces:**
- Consumes: `-PbundleJavaMajor=<positive integer>` from the Makefile.
- Produces: `scripts/gradle-toolchain.init.gradle`, which sets `JavaPluginExtension.toolchain.languageVersion` after all projects are evaluated.
- Produces: `JAVA_MAJOR := 25`, consumed by the core migration in Task 3.

- [ ] **Step 1: Create the focused probe**

Create `dist/toolchain-probe/settings.gradle`:

```groovy
rootProject.name = 'toolchain-probe'
```

Create `dist/toolchain-probe/build.gradle`:

```groovy
plugins {
    id 'java'
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

tasks.register('printToolchain') {
    doLast {
        println "TOOLCHAIN=${java.toolchain.languageVersion.get()}"
    }
}
```

- [ ] **Step 2: Confirm the probe fails before the init script exists**

Run:

```bash
ghidra/gradlew -p "$PWD/dist/toolchain-probe" \
  -I "$PWD/scripts/gradle-toolchain.init.gradle" \
  -PbundleJavaMajor=25 printToolchain --console=plain
```

Expected: FAIL because Gradle cannot read the not-yet-created init script.

- [ ] **Step 3: Implement the init script**

Create `scripts/gradle-toolchain.init.gradle`:

```groovy
import org.gradle.api.plugins.JavaPluginExtension
import org.gradle.jvm.toolchain.JavaLanguageVersion

def requestedMajor = gradle.startParameter.projectProperties['bundleJavaMajor']
if (requestedMajor == null || !(requestedMajor ==~ /[1-9]\d*/)) {
    throw new GradleException('bundleJavaMajor must be a positive integer (for example, 25)')
}
def javaMajor = requestedMajor.toInteger()

gradle.projectsEvaluated {
    allprojects { project ->
        def javaExtension = project.extensions.findByType(JavaPluginExtension)
        if (javaExtension != null) {
            javaExtension.toolchain.languageVersion.set(JavaLanguageVersion.of(javaMajor))
        }
    }
}
```

- [ ] **Step 4: Verify override and rejection behavior**

Run the successful probe:

```bash
ghidra/gradlew -p "$PWD/dist/toolchain-probe" \
  -I "$PWD/scripts/gradle-toolchain.init.gradle" \
  -PbundleJavaMajor=25 printToolchain --console=plain
```

Expected: `TOOLCHAIN=25`, overriding the probe's Java 21 declaration.

Run the invalid-input probe:

```bash
ghidra/gradlew -p "$PWD/dist/toolchain-probe" \
  -I "$PWD/scripts/gradle-toolchain.init.gradle" \
  -PbundleJavaMajor=abc printToolchain --console=plain
```

Expected: FAIL with `bundleJavaMajor must be a positive integer`.

- [ ] **Step 5: Wire the override into every extension build**

In `Makefile`, immediately after `GHIDRA_VERSION`, add:

```make
JAVA_MAJOR := 25
```

The current `install_extension` Gradle subshell is:

```make
	(cd "$(2)/$(or $(5),.)" && "$(BUNDLE_DIR)/ghidra/gradlew" -p . \
		-PGHIDRA_INSTALL_DIR="$(INSTALL_DIR)" buildExtension) || exit 1; \
```

Replace it with:

```make
	(cd "$(2)/$(or $(5),.)" && "$(BUNDLE_DIR)/ghidra/gradlew" -p . \
		-I "$(BUNDLE_DIR)/scripts/gradle-toolchain.init.gradle" \
		-PbundleJavaMajor=$(JAVA_MAJOR) \
		-PGHIDRA_INSTALL_DIR="$(INSTALL_DIR)" buildExtension) || exit 1; \
```

The Makefile recipe line must begin with a literal tab, and continuation lines must retain tabs as in the surrounding macro.

Run the expansion checks:

```bash
make -n install-mcp | grep -F -- '-PbundleJavaMajor=25'
make -n install-mcp | grep -F -- 'scripts/gradle-toolchain.init.gradle'
```

Expected: each command prints the matching expanded build argument.

Exercise the two real projects that declare Java 21 toolchains. These are compile-only probes against the current 12.1.4 install: they do not install extensions or edit submodule sources, and Task 3/4 later builds and installs them against 12.2.

```bash
export JAVA_HOME="$(printf 'print-java-home: ; @echo $(JAVA21_HOME)\n' | make -s -f Makefile -f - print-java-home)"
export PATH="$JAVA_HOME/bin:$PATH"
ghidra/gradlew -p "$PWD/ghidra-mcp" \
  -I "$PWD/scripts/gradle-toolchain.init.gradle" \
  -PbundleJavaMajor=25 \
  -PGHIDRA_INSTALL_DIR="$PWD/dist/ghidra_12.1.4_PUBLIC" \
  buildExtension --console=plain
ghidra/gradlew -p "$PWD/binexport/java" \
  -I "$PWD/scripts/gradle-toolchain.init.gradle" \
  -PbundleJavaMajor=25 \
  -PGHIDRA_INSTALL_DIR="$PWD/dist/ghidra_12.1.4_PUBLIC" \
  buildExtension --console=plain
```

Expected: both real builds report `BUILD SUCCESSFUL` with the override active. A `value is final and cannot be changed` error would mean the project finalizes its toolchain before `projectsEvaluated`; stop and revise the override rather than proceeding to the full pipeline.

Remove the generated probe and probe-only archives so the later dist checks see only pipeline artifacts:

```bash
rm -rf dist/toolchain-probe
rm -f ghidra-mcp/build/distributions/GhidraMCP-*.zip
rm -f binexport/java/dist/ghidra_12.1.4_*_BinExport.zip
```

- [ ] **Step 6: Commit the toolchain override**

```bash
git add Makefile scripts/gradle-toolchain.init.gradle
git commit -m "build: align extension Java toolchains"
```

---

### Task 3: Ghidra 12.2 and JDK 25 core migration

**Files:**
- Modify: `Makefile`
- Modify: `build-ghidra.sh`
- Modify: `tests/run-sanity.sh`
- Modify: `ghidra` gitlink

**Interfaces:**
- Consumes: `JAVA_MAJOR := 25` and the init-script integration from Task 2.
- Produces: `JAVA25_HOME`, exported as `JAVA_HOME`, for every build, launcher, test and REA wrapper.
- Produces: installed Ghidra at `dist/ghidra_12.2_PUBLIC/`.
- Produces: `check_runtime` in `tests/run-sanity.sh`, called by the `dist` section.

- [ ] **Step 1: Confirm the old version fails the new expectation**

Use a stdin makefile fragment rather than `--eval`, which macOS's GNU Make 3.81 does not support:

```bash
test "$(printf 'print-version: ; @echo $(GHIDRA_VERSION)\n' | make -s -f Makefile -f - print-version)" = "12.2"
```

Expected now: FAIL because the value is `12.1.4`, not because of an unsupported make option. This check must succeed after the Makefile edit.

- [ ] **Step 2: Pin and commit the confirmed Ghidra tag**

Run:

```bash
git -C ghidra fetch --depth 1 origin tag Ghidra_12.2_build
git -C ghidra checkout 8ca9077040cc43cd790babcfccf19475622a3e9a
sed -n 's/^application\.version=//p' ghidra/Ghidra/application.properties
git add ghidra
git commit -m "build: pin Ghidra submodule to 12.2"
```

Expected: the version print is `12.2` and the gitlink is committed immediately. Do not edit any file inside the submodule. The immediate commit is required before any Make target that depends on `01-checkout`; otherwise `git submodule update` restores the superproject's old 12.1.4 gitlink before stage 02 checks the version.

- [ ] **Step 3: Migrate Makefile version and JDK selection**

Use exact replacements in `Makefile`:

- Replace `GHIDRA_VERSION := 12.1.4` with `GHIDRA_VERSION := 12.2`.
- Replace every `JAVA21_HOME` with `JAVA25_HOME`.
- Replace every `JDK 21` with `JDK 25`.
- In `/usr/libexec/java_home -F -v 21`, replace `-v 21` with `-v 25`.
- Replace `temurin@21` with `temurin@25`.
- Replace `openjdk-21-jdk` with `openjdk-25-jdk`.
- In the Linux search glob only, replace `/usr/lib/jvm/*21*` with `/usr/lib/jvm/*25*`.
- In the Linux Java probe only, replace `version "21` with `version "25`.

Retain `JAVA_MAJOR := 25` from Task 2 and the existing exports:

```make
export JAVA_HOME := $(JAVA25_HOME)
export PATH := $(JAVA25_HOME)/bin:$(HOME)/.local/bin:$(HOME)/.cargo/bin:$(PATH)
```

Add this check to `00-env` immediately after the existing `JAVA25_HOME` directory check and before its `$(TICK)` line:

```make
	@"$(JAVA25_HOME)/bin/java" -version 2>&1 | grep -q 'version "$(JAVA_MAJOR)' || \
		{ $(ERR) "JAVA25_HOME is not a JDK $(JAVA_MAJOR) install: $(JAVA25_HOME)"; exit 1; }
```

This makes `make env` reject a directory that exists but contains the wrong JDK major. Use a literal recipe tab.

Confirm the version checks and the post-edit literal sweep:

```bash
test "$(printf 'print-version: ; @echo $(GHIDRA_VERSION)\n' | make -s -f Makefile -f - print-version)" = "12.2"
test "$(printf 'print-java: ; @echo $(JAVA_MAJOR)\n' | make -s -f Makefile -f - print-java)" = "25"
! grep -nE -- '-v 21|version "21|\*21\*|temurin@21|openjdk-21|JDK 21|JAVA21_HOME' Makefile
```

Expected: the two tests exit 0 and the grep prints nothing (its no-match status is inverted).

- [ ] **Step 4: Require JDK 25 in the source-build script**

In `build-ghidra.sh`, replace every `JDK 21` with `JDK 25` and change the version probe to:

```bash
if [[ -z "${JAVA_HOME:-}" ]] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q 'version "25'; then
  echo "ERROR: JAVA_HOME must point to a JDK 25 (got '${JAVA_HOME:-}'). Run 'make build-ghidra'." >&2
  exit 1
fi
```

Precondition: JDK 25 is already installed on this host. On a fresh host, run `make deps` after the Makefile edit; on an apt distribution without `openjdk-25-jdk`, install a full JDK 25 through another trusted package and export `JAVA25_HOME` before running `make deps` or `make env`.

Run:

```bash
bash -n build-ghidra.sh
make env
make env JAVA25_HOME=/definitely-missing
```

Expected: syntax succeeds, normal environment check reports JDK 25, and the final command fails with `JDK 25 not found` without changing files.

- [ ] **Step 5: Add the runtime/compiler-level sanity check**

In `tests/run-sanity.sh`, replace all three `JDK 21` usage strings with `JDK 25`.

Insert this function immediately before `check_dist`:

```bash
check_runtime() {
  local expected actual
  expected=$(sed -n 's/^application\.java\.compiler=//p' "$INSTALL_DIR/Ghidra/application.properties")
  actual=$("$JAVA_HOME/bin/java" -version 2>&1 |
    sed -n 's/^.*version "\([0-9][0-9]*\).*/\1/p' | head -n 1)
  if [[ -n "$expected" && "$actual" == "$expected" ]]; then
    pass "runtime: JDK $actual matches Ghidra compiler level $expected"
  else
    fail "runtime: JDK major '${actual:-unknown}' does not match Ghidra compiler level '${expected:-unknown}'"
  fi
}
```

Replace:

```bash
if want dist; then check_dist; fi
```

with:

```bash
if want dist; then
  check_runtime
  check_dist
fi
```

Run:

```bash
bash -n tests/run-sanity.sh
make -n install >/dev/null
! grep -nE -- '-v 21|version "21|\*21\*|temurin@21|openjdk-21|JDK 21|JAVA21_HOME' \
  Makefile build-ghidra.sh tests/run-sanity.sh
```

Expected: both build checks succeed and the version-literal grep prints nothing.

- [ ] **Step 6: Refresh source dependencies and build/install Ghidra 12.2**

Run the dependency fetch explicitly even when `dependencies/flatRepo` already exists so changed 12.2 dependencies are refreshed without deleting the old installation or dependency cache. Use the portable stdin-makefile form to resolve the selected JDK.

```bash
export JAVA_HOME="$(printf 'print-java-home: ; @echo $(JAVA25_HOME)\n' | make -s -f Makefile -f - print-java-home)"
export PATH="$JAVA_HOME/bin:$PATH"
(cd ghidra && ./gradlew -I gradle/support/fetchDependencies.gradle --console=plain)
make install-ghidra
```

Expected: dependency fetch and source build succeed, `dist/packages/` contains one Ghidra 12.2 platform zip, and stage 03 creates `dist/ghidra_12.2_PUBLIC/` with portable paths pointing to JDK 25. The `01-checkout` dependency retains the 12.2 commit already committed in Step 2.

Confirm:

```bash
test "$(sed -n 's/^application\.version=//p' dist/ghidra_12.2_PUBLIC/Ghidra/application.properties)" = "12.2"
test "$(sed -n 's/^application\.java\.compiler=//p' dist/ghidra_12.2_PUBLIC/Ghidra/application.properties)" = "25"
grep -F "JAVA_HOME_OVERRIDE=$JAVA_HOME" dist/ghidra_12.2_PUBLIC/support/launch.properties
make 02-build-ghidra GHIDRA_VERSION=12.1.4
```

Expected: the first three commands confirm 12.2/JDK 25; the last fails at the existing version guard with `ghidra submodule is not Ghidra 12.1.4`, before rebuilding anything.

- [ ] **Step 7: Commit the core migration**

The gitlink is already committed. Commit only the remaining core files:

```bash
git add Makefile build-ghidra.sh tests/run-sanity.sh
git commit -m "build: require JDK 25 for Ghidra 12.2"
```

---

### Task 4: REA wiring and complete pipeline integration

**Files:**
- Modify: `Makefile` (stage 16)
- Modify: `tests/run-sanity.sh` (REA section)

**Interfaces:**
- Consumes: `patch_package` CLI from Task 1, the extension toolchain from Task 2 and the 12.2/JDK 25 install from Task 3.
- Produces: stage 16 always applies the idempotent policy patch before writing/registering REA.
- Produces: `check_rea_patch` in the sanity suite, run for every `rea` section even when the optional runtime is absent.

- [ ] **Step 1: Reproduce REA's unpatched 12.2 rejection**

Run:

```bash
make install-rea
SANITY_ONLY=rea make test
```

Expected before wiring the patch: stage 16 writes the new wrapper, but the sanity suite reports FAIL for `REA: doctor does not accept this install's Ghidra and JDK` because the stock 6.3.0 policy accepts only 12.1.x. The command must not be treated as a successful verification.

- [ ] **Step 2: Apply the patch from stage 16**

In `Makefile`, in `16-install-rea`, insert these lines after the `npm ci`/lockfile `fi;` and before `NODE=$$(node -p process.execPath)`:

```make
	python3 -I scripts/patch-rea-ghidra.py \
		"$(REA_DIR)/node_modules/rea-agents" "$(GHIDRA_VERSION)" || exit 1; \
```

Use literal Makefile tabs. Do not move this call into the `skip` path and do not catch its failure.

- [ ] **Step 3: Add the patch tests to the standard REA section**

In `tests/run-sanity.sh`, insert before `check_rea`:

```bash
check_rea_patch() {
  local log="$WORK/rea-policy-tests.log"
  if python3 -I "$TESTS/test_patch_rea_ghidra.py" > "$log" 2>&1; then
    pass "REA: Ghidra policy patch unit tests pass"
  else
    fail_with_log "REA: Ghidra policy patch unit tests failed" "$log"
  fi
}
```

Replace:

```bash
if want rea; then check_rea; fi
```

with:

```bash
if want rea; then
  check_rea_patch
  check_rea
fi
```

- [ ] **Step 4: Verify REA doctor and actual decompilation**

Run:

```bash
bash -n tests/run-sanity.sh
python3 -I tests/test_patch_rea_ghidra.py -v
make install-rea
make install-rea
SANITY_ONLY=rea make test
```

Expected: all six unit tests pass, including the real installed policy; the first stage-16 invocation reports `patched` and the second reports `already patched`; `REA: doctor accepts this install's Ghidra and JDK` and `REA: decompiles the DOS MZ fixture through Ghidra` both PASS. No REA SKIP is accepted on this machine.

- [ ] **Step 5: Build and test the complete bundle**

Run:

```bash
make install
```

Expected: Ghidra and all eight third-party extensions build against 12.2/JDK 25; Jython and D2GridraTools install; extension discovery, MCP HTTP, fixtures, dist, BinExport, portable paths, Jython, PyGhidra and REA pass. Only an actually unavailable optional StormLib may produce SKIP. Snapshot differences may be reported for Task 5, but no sanity check may FAIL.

If an extension error requires editing a third-party submodule's source, stop and request a design revision. Do not broaden this task into dependency forks or upgrades.

- [ ] **Step 6: Commit the integration changes**

```bash
git add Makefile tests/run-sanity.sh
git commit -m "feat: integrate REA with Ghidra 12.2"
```

---

### Task 5: Documentation, snapshots and final verification

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `tests/snapshots/` as produced by the real 12.2 run
- Modify: `docs/superpowers/specs/2026-10-23-ghidra-12-2-upgrade-design.md`

**Interfaces:**
- Consumes: the fully installed and tested bundle from Task 4.
- Produces: user/agent documentation matching actual behavior and reproducible Ghidra 12.2 snapshot expectations.

- [ ] **Step 1: Update current documentation**

In `README.md` and `AGENTS.md`, use exact replacements for current-version references only:

- Replace every `12.1.4` with `12.2`.
- Replace every `JDK 21` with `JDK 25`.
- In `AGENTS.md`, replace `<JAVA21_HOME>` with `<JAVA25_HOME>`.

Complete these replacements before inserting the new REA text below; those paragraphs intentionally retain `12.1.4` when describing REA's upstream verification. Do not edit files under `docs/superpowers/specs/` other than this upgrade's spec, and do not edit earlier implementation plans.

In `AGENTS.md`, replace the extension-build invariant with:

```markdown
- All Gradle extensions are built with `ghidra/gradlew -I scripts/gradle-toolchain.init.gradle -PbundleJavaMajor=$(JAVA_MAJOR) ... buildExtension` against the installed Ghidra. The init script aligns upstream toolchain declarations with the bundle's JDK 25, so their `extension.properties` carry the installed version and no submodule source edits are needed.
```

In `AGENTS.md`, add this REA invariant immediately after the lockfile/pin bullet:

```markdown
- REA 6.3.0 upstream verifies Ghidra 12.1.4 and accepts only 12.1.x. `scripts/patch-rea-ghidra.py` validates that exact package and adds Ghidra 12.2 as compatible but not upstream-verified; it does not bypass Java bounds read from `application.properties`. Exactly 12.2 is accepted: 12.2.1 and other versions remain rejected until a deliberate patch update. Stage 16 applies the idempotent patch on every eligible run and fails on unexpected package versions or policy source. `tests/test_patch_rea_ghidra.py` covers the transformation and the real installed policy, while `make test` checks doctor and real decompilation.
```

Update the stage-16 row in `AGENTS.md` so its description reads:

```markdown
| `16` | `16-install-rea` (`install-rea`) | Installs REA 6.3.0 from its lockfile (`npm ci`), applies the Ghidra 12.2 compatibility patch, writes the `.rea/rea` wrapper and registers `rea` (`register_mcp`); warns and skips without suitable Node.js or when npm fails |
```

In `README.md`, add this paragraph to the REA section after the introductory REA paragraph:

```markdown
REA 6.3.0 upstream verifies Ghidra 12.1.4 and accepts only 12.1.x. The bundle applies a checked, idempotent patch to its installed policy so exactly Ghidra 12.2 is accepted as compatible but not upstream-verified; 12.2.1 and other versions remain rejected. Java requirements still come from Ghidra's own `application.properties`. The sanity suite runs both REA doctor and a real decompilation to validate this integration.
```

In `README.md`, add this paragraph immediately after the Quickstart prerequisite paragraph and before `## Using the MCP server`:

```markdown
On apt-based Linux distributions, `make deps` installs `openjdk-25-jdk` when available. If your distribution does not provide that package, install a full JDK 25 yourself and export `JAVA25_HOME=/absolute/path/to/jdk` before running `make deps` or `make install`; the dependency stage then leaves that package out. No additional package repository is required.
```

- [ ] **Step 2: Review real snapshot changes before recording them**

Run:

```bash
make test
```

Expected: every check passes; any Ghidra 12.2 decompiler differences are reported as snapshot changes. Review those reported differences against the fixture behavior before rewriting snapshots. A loader, function-name, fixup, expectation or portable-path failure is not a snapshot-only difference and must be resolved before continuing.

- [ ] **Step 3: Record and inspect Ghidra 12.2 snapshots**

Run:

```bash
UPDATE_SNAPSHOTS=1 make test
git diff --check -- tests/snapshots
git diff --stat -- tests/snapshots
git diff -- tests/snapshots
```

Expected: the suite passes and only decompiler snapshot text changes are staged for the final documentation/expectation commit. `tests/expect/` remains unchanged.

- [ ] **Step 4: Run all final checks on the deliverable**

Run:

```bash
bash -n build-ghidra.sh tests/run-sanity.sh scripts/install-d2gridratools.sh
python3 -I - <<'PY'
from pathlib import Path
for name in ("scripts/patch-rea-ghidra.py", "tests/test_patch_rea_ghidra.py"):
    path = Path(name)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
make help >/dev/null
make env
make -n install >/dev/null
make test
git diff --check
```

Expected: all commands succeed. The final `make test` includes `runtime: JDK 25 matches Ghidra compiler level 25`, all extension/integration sections, the REA policy tests, REA doctor and real REA decompilation, with no REA SKIP and no portable-path leak.

- [ ] **Step 5: Mark the spec implemented and commit**

Change the spec's status line to:

```markdown
Status: approved; implemented and verified
```

Then run:

```bash
git add README.md AGENTS.md tests/snapshots \
  docs/superpowers/specs/2026-10-23-ghidra-12-2-upgrade-design.md
git commit -m "chore: finalize Ghidra 12.2 upgrade"
git status --short
```

Expected: `git status --short` prints nothing. The repository contains the exact Ghidra 12.2 gitlink, JDK 25 build configuration, bundle-owned compatibility scripts and tests, updated documentation and verified snapshots.
