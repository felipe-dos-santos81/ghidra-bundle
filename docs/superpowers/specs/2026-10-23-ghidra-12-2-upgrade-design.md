# Ghidra 12.2 Upgrade — Design

Date: 2026-10-23
Status: approved; implemented and verified

## 1. Goal

Upgrade the bundle from Ghidra 12.1.4 to the exact Ghidra 12.2 public source tag
while preserving the existing extensions, Jython, D2GridraTools, PyGhidra, MCP
bridge and optional REA integration.

### Success criteria

- The `ghidra` submodule is pinned to `Ghidra_12.2_build`, commit
  `8ca9077040cc43cd790babcfccf19475622a3e9a`, and `GHIDRA_VERSION` is `12.2`.
- The source build, all eight third-party extensions and the bundled Jython
  extension install into `dist/ghidra_12.2_PUBLIC/` using JDK 25.
- `make install` and a final `make test` pass, including extension discovery,
  GhidraMCP over HTTP, BinExport, Jython, PyGhidra/MPQ, REA doctor and real REA
  decompilation, and portable-path isolation.
- Decompiler snapshots deliberately record Ghidra 12.2 output.
- Third-party submodule source files remain unchanged; compatibility machinery
  lives in the bundle repository.

### Out of scope

- Migrating user projects or user settings between releases; no migration is
  attempted or planned. The generated 12.1.4 installations and archives were
  removed from both build checkouts after the full 12.2 pipeline passed
  verification; no 12.1.4 artifact remains selected by the Makefile.
- Upgrading REA or other third-party components for reasons unrelated to Ghidra
  12.2 compatibility.
- Claiming upstream REA support for Ghidra 12.2, or disabling REA's version
  checks without recording the build as unverified by upstream.
- Ghidra Server, BSim PostgreSQL Server and their new TLS requirements; the
  bundle does not configure either service.

## 2. Confirmed upstream constraints

- Ghidra 12.2 requires JDK 25 or later and uses Java compiler level 25. Its full
  source build requires Python 3 and the existing native toolchain.
- Ghidra 12.2 reads projects from earlier releases, but projects and data type
  archives modified by 12.2 might not open in earlier releases.
- GhidraMCP and BinExport currently hard-code a Java 21 Gradle toolchain. A Java
  21 compiler cannot consume Ghidra 12.2's Java 25 classes.
- Ghidra 12.2 also removed or changed extension APIs used by six bundled
  extensions: the two-argument `DataTypeManager.remove`, the `Writeable`
  bin-format interface, `OldDOSHeader.hasNewExeHeader()`/`hasPeHeader()`, the
  deprecated `TaskMonitor.checkCanceled()`/`clearCanceled()` aliases (surviving
  as `checkCancelled()`/`clearCancelled()`), and the one-argument
  `BrowserLoader.display(URL)` overload.
- REA 6.3.0 accepts Ghidra 12.1.x only. The latest published REA 6.7.0 and the
  upstream `master` policy checked during design still verify 12.1.4 and accept
  only that release line. No supported override was found.
- REA already reads `application.java.min` and `application.java.max`, so its
  Java admission check accepts JDK 25 from Ghidra 12.2's own properties once the
  Ghidra release-policy check admits 12.2.

Sources: [Ghidra 12.2 release](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.2_build),
[Ghidra 12.2 release notes](https://github.com/NationalSecurityAgency/ghidra/blob/Ghidra_12.2_build/Ghidra/Configurations/Public_Release/src/global/docs/WhatsNew.md),
[REA release policy](https://github.com/morluto/rea/blob/master/src/ghidra/GhidraReleasePolicy.ts).

## 3. Chosen approach and alternatives

Use root-managed compatibility. The bundle already owns version selection,
toolchain setup and integration tests, so the compatibility shims stay in the
same repository and are exercised by the same pipeline.

Rejected alternatives:

- **Fork GhidraMCP, BinExport and REA:** cleaner if upstream maintenance becomes
  a long-term requirement, but creates three new maintenance/publishing efforts
  for a small compatibility surface.
- **Disable REA:** avoids the REA patch but removes an existing optional feature.
  It is a fallback requiring a new user decision, not part of this design.

Extension API breaks are handled by root-managed build copies (see §5): exact,
fail-closed 12.2 compatibility patches are applied to fresh ignored copies under
`dist/build/` while third-party submodule sources stay byte-identical, and the
rebuild identity is versioned. A break without an exact, tested transformation
still stops implementation rather than silently expanding scope.

## 4. Version and JDK selection

- Change `GHIDRA_VERSION` in `Makefile` to `12.2` and update the `ghidra`
  gitlink to the confirmed tag commit.
- Add `JAVA_MAJOR := 25` as the bundle's Java toolchain pin. Replace
  `JAVA21_HOME` with `JAVA25_HOME`; continue exporting the selected JDK as
  `JAVA_HOME` and placing its `bin` first on `PATH`.
- Resolve JDK 25 through `JAVA25_HOME`, macOS `java_home`, the existing Linux
  search strategy updated for 25, or `javac` on `PATH`. Every resolution and
  guard requires a full JDK: `bin/java` and `bin/javac` must both exist and
  report major 25 (the reusable `jdk_usable` check in the Makefile, mirrored in
  `build-ghidra.sh`), so a JRE-only or wrong-major home is rejected, not used.
- Install `temurin@25` through Homebrew or `openjdk-25-jdk` through apt when
  missing, matching the existing dependency-stage behavior. On an apt-based
  distribution that does not offer `openjdk-25-jdk`, the user instead installs a
  full JDK 25 in advance and sets `JAVA25_HOME`; stage 00 then skips that package.
  No additional package repository is introduced.
- Update `build-ghidra.sh`, stage `00-env`, portable `JAVA_HOME_OVERRIDE`, REA's
  generated wrapper and test-script usage text to require/use JDK 25.
- `build-ghidra.sh` keeps the dependency cache (`ghidra/dependencies/flatRepo`)
  in sync with the source checkout: it fetches only when the cache is missing or
  `flatRepo/.bundle-source` differs from the submodule's `git rev-parse HEAD`
  (a missing marker is a mismatch), writes the marker only after a successful
  fetch, and relies on the submodule's `.gitignore` (`flatRepo/`) so the marker
  never dirties the checkout. This stops an existing checkout upgraded to a new
  Ghidra version from silently reusing the previous version's dependencies.

The bundle deliberately selects JDK 25 even though Ghidra accepts later JDKs;
this keeps the tested toolchain explicit and reproducible.

## 5. Extension toolchain override

Add `scripts/gradle-toolchain.init.gradle`. The script receives the
`bundleJavaMajor` Gradle project property from `install_extension` and, after
each project's build script has been evaluated, sets its Java toolchain to that
major when the Java plugin is present.

`install_extension` invokes Ghidra's wrapper with this init script and
`-PbundleJavaMajor=$(JAVA_MAJOR)` for every third-party extension. This gives
all extensions one consistent toolchain and overrides GhidraMCP's and
BinExport's Java 21 declarations without modifying their submodules.

The init script requires an explicit positive integer major. Missing or invalid
input fails the build instead of silently selecting a host JDK. Extension
archives keep their existing names and locations, and `VerifyExtensions.java`
remains the class-discovery check.

### Extension source compatibility (implemented build copies)

Stages 04–08 and 10 do not build the third-party checkouts directly. They first
run `scripts/prepare-extension-source.py <extension> <source-dir>
<destination-dir> <ghidra-version>`, which copies the extension's source into a
fresh directory under `dist/build/<ext>/` (excluding `.git`, `.gradle`,
`build`, `target`, `dist` and `__pycache__`) and applies that extension's exact
anchor-based 12.2 replacements there. The original submodule is never modified.
The script is fail-closed: it accepts only the pinned version `12.2` (12.2.1
and others are rejected), requires every anchor at its exact occurrence count,
recognizes an already-patched source so reruns are idempotent, rejects
missing/duplicated/mixed/partial forms, and replaces the destination only after
every patch validates. The guarantee is deliberately narrower than atomic
replacement: no original is modified and a failed run stops the stage before
the destination is replaced, but deleting/copying/writing the generated
destination is not atomic, so an interrupted run can leave it missing or
partial until the stage reruns and rebuilds it from the pristine source.

The six covered transformations: GhidraMCP drops the removed second
`DataTypeManager.remove` argument; lx-loader removes the removed `Writeable`
interface from `DOSHeader` while retaining its public `write` method;
GhidraDosToolbox simplifies a `DosLoader` condition whose
`OldDOSHeader.hasNewExeHeader()`/`hasPeHeader()` checks were always false;
GhidrAssist removes two obsolete `@Override` annotations on the removed
`TaskMonitor.checkCanceled`/`clearCanceled` aliases; GhidraFindcrypt renames
`checkCanceled()` to `checkCancelled()`; RevEng.AI injects the `PluginTool` as
the `ServiceProvider` for `BrowserLoader.display` and `GhidraRevengService`,
including a real provider assertion in its existing plugin test. Ret-sync and
BinExport build directly, without source patches.

Rebuild identity is versioned rather than assumed. `install_extension` gained
optional sixth (original source directory, whose `git rev-parse HEAD` is
recorded) and seventh (patch identity) arguments. Patched stages pass
`<extension>-$(git hash-object scripts/prepare-extension-source.py)`; the stage
writes the original commit to `<ext>/.bundle-source` and the patch identity to
`<ext>/.bundle-patch`, and rebuilds when either changes. The build copy is
regenerated on every stage run, so patched sources cannot go stale after a
script edit.

Tests: `tests/test_prepare_extension_source.py` covers every transformation,
idempotence, fail-closed anchor rejection and read-only application against the
real pinned submodule sources. `tests/run-sanity.sh`'s `BUILD_OUTPUTS` guards
both the original build-output directories and the actual `dist/build/` copies,
so the packages-move check covers the trees that really build.

## 6. REA compatibility patch

Keep `rea-agents` pinned to 6.3.0 and its existing lockfile unchanged. Add a
Python standard-library script, `scripts/patch-rea-ghidra.py`, which operates on
`.rea/node_modules/rea-agents` after `npm ci` and before REA registration.

The patch has narrow semantics:

- `SUPPORTED_GHIDRA_VERSION` remains `12.1.4`, and Ghidra 12.1.x retains its
  existing behavior.
- The exact bundle version `12.2` becomes an additional **compatible**, not
  **verified**, release. REA therefore continues to report its upstream
  verification limitation for this build. A future `12.2.1` remains rejected
  until the patch and its tests are deliberately updated; patch releases are not
  accepted automatically.
- User-facing accepted-release and limitation text includes both 12.1.x and
  12.2 rather than claiming that only 12.1.x is accepted.
- Java admission continues to come from each installation's
  `application.properties`; no Java check is bypassed. For Ghidra 12.2 this
  requires JDK 25 or later.

The script is idempotent and fail-closed. It verifies the package version and
exact expected policy source, recognizes an already-applied patch, and refuses
unknown package versions or source layouts. Stage 16 runs it on every eligible
invocation so a reinstall cannot silently lose the patch. A patch failure stops
that stage; missing suitable Node/npm retains the existing optional REA skip.

The REA wrapper is regenerated as today, now pointing to the 12.2 installation
and JDK 25. The existing sanity test must prove both `rea doctor` admission and
actual DOS MZ decompilation through Ghidra; a text substitution alone is not
evidence of compatibility.

## 7. Documentation and generated expectations

- Update current-version references in `README.md` and `AGENTS.md`, including
  JDK 25, the 12.2 tag/install path, the extension toolchain init script and
  REA's bundle-managed compatible-but-unverified status.
- Document the build-copy compatibility mechanism: one short user-facing note
  in `README.md`, operational invariants for extending it in `AGENTS.md`.
  Remove the temporary upgrade-blocker notes once the full pipeline passes; do
  not replace them with a success banner.
- Leave historical specs and implementation plans unchanged.
- Update JDK usage text in `tests/run-sanity.sh`; retain its existing checks.
- Review snapshot differences caused by Ghidra 12.2 and record intentional
  output with `UPDATE_SNAPSHOTS=1 make test`. The real 12.2 runs produced no
  snapshot differences, so `tests/snapshots/` and `tests/expect/` remain
  unchanged.

## 8. Error handling and compatibility boundaries

- Existing tag/version disagreement and missing-prerequisite checks remain
  fatal, now with JDK 25 messages.
- An invalid toolchain property or unexpected REA package/policy source is
  fatal; neither compatibility shim falls back to an untested substitution.
- The new install directory keeps the previous installation untouched while
  both exist; after full 12.2 verification the generated 12.1.4 artifacts were
  removed explicitly (§1). No user project or settings migration is attempted.
- Portable-mode behavior is unchanged: all settings, caches, temporary files,
  PyGhidra state and REA sessions remain under the new install's `portable/`.
- Optional StormLib and Node/npm behavior remains as documented. Optional REA
  skipping is allowed only for the existing missing-runtime/npm-install cases,
  not as a substitute for the 12.2 compatibility patch.

## 9. Verification

Run the repository's standard checks on the resulting install:

1. `make help`, `make env` and `make -n install`.
2. `bash -n` for the changed shell scripts and Python byte-compilation of both
   compatibility scripts (`scripts/patch-rea-ghidra.py`,
   `scripts/prepare-extension-source.py`) and both test modules
   (`tests/test_patch_rea_ghidra.py`, `tests/test_prepare_extension_source.py`),
   plus a standalone run of the 32 prepare-source unit tests.
3. Full `make install`, including the Ghidra source build, every extension,
   extension discovery and the sanity suite.
4. `make test` normally and with `UPDATE_SNAPSHOTS=1` (requiring no snapshot
   changes), with all sections passing and no skips — including the REA policy
   unit tests, REA doctor and a real REA DOS MZ decompilation on this machine.
5. Confirm the installed `application.version` is `12.2`, the selected runtime
   is JDK 25, neither checkout retains `dist/ghidra_12.1.4_PUBLIC` or
   `dist/packages/*12.1.4*`, all submodules are clean, `git diff --check`
   passes and version-control status contains only the intended upgrade
   changes.

A failed real build or test is fixed before completion; compilation, imports or
a successful text patch alone do not establish the upgrade.
