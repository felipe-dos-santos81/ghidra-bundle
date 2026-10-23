# Ghidra 12.2 Upgrade — Design

Date: 2026-10-23
Status: approved; not yet implemented

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

- Migrating or deleting an existing `dist/ghidra_12.1.4_PUBLIC/` installation,
  user projects or user settings. The old installation may remain on disk but is
  no longer selected by the Makefile.
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

If Ghidra 12.2 exposes additional extension API breaks that require editing
submodule source files, implementation stops and this design is revised rather
than silently expanding scope.

## 4. Version and JDK selection

- Change `GHIDRA_VERSION` in `Makefile` to `12.2` and update the `ghidra`
  gitlink to the confirmed tag commit.
- Add `JAVA_MAJOR := 25` as the bundle's Java toolchain pin. Replace
  `JAVA21_HOME` with `JAVA25_HOME`; continue exporting the selected JDK as
  `JAVA_HOME` and placing its `bin` first on `PATH`.
- Resolve JDK 25 through `JAVA25_HOME`, macOS `java_home`, the existing Linux
  search strategy updated for 25, or `javac` on `PATH`.
- Install `temurin@25` through Homebrew or `openjdk-25-jdk` through apt when
  missing, matching the existing dependency-stage behavior. On an apt-based
  distribution that does not offer `openjdk-25-jdk`, the user instead installs a
  full JDK 25 in advance and sets `JAVA25_HOME`; stage 00 then skips that package.
  No additional package repository is introduced.
- Update `build-ghidra.sh`, stage `00-env`, portable `JAVA_HOME_OVERRIDE`, REA's
  generated wrapper and test-script usage text to require/use JDK 25.

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
- Leave historical specs and implementation plans unchanged.
- Update JDK usage text in `tests/run-sanity.sh`; retain its existing checks.
- Review snapshot differences caused by Ghidra 12.2, record intentional output
  with `UPDATE_SNAPSHOTS=1 make test`, then run the suite normally again.

## 8. Error handling and compatibility boundaries

- Existing tag/version disagreement and missing-prerequisite checks remain
  fatal, now with JDK 25 messages.
- An invalid toolchain property or unexpected REA package/policy source is
  fatal; neither compatibility shim falls back to an untested substitution.
- The new install directory keeps the previous installation untouched. No user
  project or settings migration is attempted.
- Portable-mode behavior is unchanged: all settings, caches, temporary files,
  PyGhidra state and REA sessions remain under the new install's `portable/`.
- Optional StormLib and Node/npm behavior remains as documented. Optional REA
  skipping is allowed only for the existing missing-runtime/npm-install cases,
  not as a substitute for the 12.2 compatibility patch.

## 9. Verification

Run the repository's standard checks on the resulting install:

1. `make help`, `make env` and `make -n install`.
2. `bash -n` for the changed shell scripts and Python byte-compilation for the
   new patch script.
3. Full `make install`, including the Ghidra source build, every extension,
   extension discovery and the sanity suite.
4. `make test` after snapshot refresh, with all sections passing or only the
   documented optional StormLib skips. REA must not be skipped on this machine,
   where its Node runtime is available.
5. Confirm the installed `application.version` is `12.2`, the selected runtime
  is JDK 25, `git diff --check` passes and version-control status contains only
  the intended upgrade changes.

A failed real build or test is fixed before completion; compilation, imports or
a successful text patch alone do not establish the upgrade.
