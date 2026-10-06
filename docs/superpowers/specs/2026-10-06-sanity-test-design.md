# Sanity Test Suite — Design

Date: 2026-10-06
Status: approved and implemented (see section 10 for amendments)

## 1. Goal

One command, `make test`, that proves a `make install` actually works:
Ghidra imports real programs headlessly, each bundled extension parses its
format, the decompiler produces the expected results, and the GhidraMCP plugin
serves analysis over HTTP. `make install` runs it as its final stage, so an
install is not reported done until the suite passes.

### Success criteria

- `make test` exits 0 on a healthy install and 1 if any check fails.
- Each failure names the layer that broke (extension class loading, loader
  parsing, native decompiler, analysis results, GhidraMCP).
- The suite is shown to fail on deliberately broken inputs (section 8).
- It respects portable mode: no writes outside `dist/ghidra_<ver>_PUBLIC/portable/`;
  `~/.ghidra` stays absent; temporary files are removed on every exit path.
- Runtime is about 1–2 minutes.

### Out of scope

- Checks against the user's FIFA 96 binary (explicitly excluded).
- CI: building Ghidra in CI is too expensive; the suite runs locally after install.
- macOS verification: scripts are portable bash/Python 3, but only Linux arm64 is
  verified; the docs say so.

## 2. Decisions

| Question | Decision |
| :--- | :--- |
| Coverage | Core decompiler (ELF), extension formats (DOS MZ via GhidraDosToolbox, LE via lx-loader), GhidraMCP end-to-end |
| What "decompiles as expected" means | Fact assertions decide pass/fail; full decompiled C is snapshotted and diffed as a non-failing report |
| When it runs | `make test`, and as the last stage of `make install` (replacing `verify-extensions` in the pipeline; `test` runs `verify-extensions` first) |
| Approach | Generated fixtures + one generic Java checker (`SanityCheck.java`) + a bash runner. Rejected: PyGhidra/pytest (new dependencies, risk of bypassing the portable-mode `launch.properties` VMARGS); GhidraMCP-only testing (cannot attribute failures to Ghidra vs. the plugin) |

## 3. Architecture

```text
make test ──► tests/run-sanity.sh <install dir> <JDK home>
                │ 1. preflight: analyzeHeadless + clang present; make verify-extensions
                │ 2. WORK=$(mktemp -d <install>/portable/temp/sanity-XXXXXX); trap cleanup
                │ 3. fixtures → $WORK/fixtures
                │      clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c sample.c → sample.o
                │      python3 -I tests/make_fixtures.py → dos.exe, le.exe
                │ 4. per fixture: analyzeHeadless (throwaway project, forced loader)
                │      -postScript SanityCheck.java tests/expect/<f>.txt $WORK/out/<f>
                │ 5. GhidraMCP headless server on TEST_MCP_PORT (default 18089) with sample.o;
                │      curl /check_connection, /list_functions, /decompile_function
                │ 6. summary (PASS/FAIL per check, totals) + snapshot diff report
                └─ exit 1 if any FAIL
```

| Unit | Responsibility | Depends on |
| :--- | :--- | :--- |
| `tests/fixtures/sample.c` | Tiny C source with a known constant, a call and a global | clang (existing prerequisite) |
| `tests/make_fixtures.py` | Writes `dos.exe` and `le.exe` deterministically, byte by byte | Python 3 standard library |
| `tests/expect/<fixture>.txt` | Facts each fixture must satisfy | — |
| `ghidra_scripts/SanityCheck.java` | Generic fact checker; prints results; writes decompiled C | Ghidra API (`DecompInterface`) |
| `tests/snapshots/<fixture>/<function>.c` | Committed reference decompilation | — |
| `tests/run-sanity.sh` | Orchestration, timeouts, cleanup, summary | bash, `analyzeHeadless`, java, curl, python3 |

Adding a fixture means adding a generator (or source file), an expectations
file and a runner entry; `SanityCheck.java` does not change.

## 4. Fixtures

### 4.1 `sample.o` — core ELF loader, relocations, decompiler

```c
int counter;                                              /* global → relocation */
__attribute__((noinline)) int helper(int x) { return x * 3 + 7; }
int compute(int a) { counter++; return helper(a) ^ 0x1234abcd; }
```

Compiled with `clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c`. No
linker is needed (the host has no i386 linker); Ghidra imports relocatable ELF
and applies its relocations. Functions are addressed by symbol name.
Imported with Ghidra's default loader choice (expected: ELF).

### 4.2 `dos.exe` — 16-bit DOS MZ through GhidraDosToolbox

Built by `make_fixtures.py`; imported with `-loader DosLoader`.

- MZ header with a 1-entry relocation table.
- Code: `entry` loads the data segment into `AX` (the relocated word), sets
  `DS`, calls `helper`, stores `AX` to `[0]`, exits with `AX=0x4C00; INT 21h`.
- `helper`: `MOV AX,0xABCD; RET`.
- A data paragraph containing `"TESTDATA"`.

Required facts: `loader` (DosToolbox's MZ loader name), `entry`,
`relocations >= 1`, `bytes` for the relocated segment word, `function helper
contains 0xabcd` (or the entry-relative address if the loader does not name it),
and `function <entry> calls <helper>`. DosLoader chooses its own load segment,
so only the concrete addresses and the relocated value are filled in after one
observed run; the set of facts is fixed here.

### 4.3 `le.exe` — 32-bit LE through lx-loader

Built by `make_fixtures.py`: an MZ stub (`e_lfarlc = 0x40`, `e_lfanew` pointing
at the LE header) followed by a minimal LE; imported with `-loader LeLoader`.

| Object | Base | Flags | Contents |
| :--- | :--- | :--- | :--- |
| 1 | `0x10000` | readable, executable, 32-bit | `0x00: MOV EAX,[obj2+4]` (32-bit offset fixup at `0x01`), `0x05: CALL 0x10010`, `0x0A: XOR EAX,0x1234ABCD`, `0x0F: RET`, `0x10: MOV EAX,7`, `0x15: RET` |
| 2 | `0x20000` | readable, writable, 32-bit | 16 data bytes |

Entry point: object 1, offset 0. The LE must be accepted by lx-loader's parser
(object table, object page map, fixup page table, fixup record table, resident
name table); the implementation builds it incrementally and verifies each step
against lx-loader before writing expectations.

## 5. Expectations format

`tests/expect/<fixture>.txt`: one fact per line; blank lines and `#` comments
ignored; addresses are hex without `0x`; functions are a symbol name or an
address.

| Fact | Passes when |
| :--- | :--- |
| `loader <name>` | `program.getExecutableFormat()` equals `<name>` |
| `block <name> <start>` | a memory block `<name>` starts at `<start>` |
| `entry <addr>` | `<addr>` is an external entry point |
| `relocations >= <n>` | the relocation table has at least `n` entries |
| `bytes <addr> <hex>` | memory at `<addr>` equals the hex bytes |
| `reference <from> -> <to>` | a reference from `<from>` (instruction address) to `<to>` exists |
| `function <f> decompiles` | decompilation completes |
| `function <f> contains <text>` | decompiled C contains `<text>` |
| `function <f> calls <g>` | `<f>` has a call reference to function `<g>` |

Example (`le.txt`):

```text
loader Linear Executable (LE-Style DOS)
block .object1 00010000
block .object2 00020000
entry 00010000
relocations >= 1
bytes 00010001 04000200        # fixup applied: [obj2+4] -> 0x20004
reference 00010000 -> 00020004
function 00010000 contains 0x1234abcd
function 00010000 calls 00010010
```

## 6. `SanityCheck.java`

- Arguments: expectations file, output directory.
- For each fact prints exactly one line, `SANITY PASS <fact>` or
  `SANITY FAIL <fact> (got <observed>)`; an unparseable line is a FAIL.
- Decompiles through `DecompInterface` (open once per program, 60 s timeout per
  function). If `DecompileResults.failedToStart()` is true the FAIL reason says
  the native decompiler did not start.
- Writes the decompiled C of every function named in a `function` fact to
  `<out>/<function>.c`.
- Ends with `SANITY DONE <passed> <failed>` so the runner can detect a script
  that crashed before finishing.

## 7. Runner details (`tests/run-sanity.sh`)

- `set -euo pipefail`; arguments: install dir, JDK home. `TEST_MCP_PORT`
  (default `18089`) and `UPDATE_SNAPSHOTS` come from the environment.
- Each `analyzeHeadless` call is wrapped in `timeout 600`; a run whose log lacks
  `Import succeeded` or `SANITY DONE` is a FAIL showing the last 20 log lines.
  Remaining fixtures still run so all failures are reported together.
- GhidraMCP end-to-end: start `com.xebyte.headless.GhidraMCPHeadlessServer` with
  a classpath of the install's Framework/Features/Processors jars plus the
  installed GhidraMCP jar (as GhidraMCP's own `docker/entrypoint.sh` does),
  `--bind 127.0.0.1 --port $TEST_MCP_PORT --file sample.o`, and
  `-Duser.home`, `-Dapplication.settingsdir`, `-Dapplication.cachedir`,
  `-Dapplication.tempdir`, `-Djava.io.tmpdir` all inside `$WORK`. Wait up to
  120 s for `/check_connection`; check `/list_functions` lists `helper` and
  `compute`; take `compute`'s address from that list and check
  `/decompile_function` output contains `0x1234abcd` and `helper`. A port
  already in use is a FAIL with a hint to set `TEST_MCP_PORT`.
- `trap` on EXIT kills the server (if started) and removes `$WORK`.
- Snapshots: after normalization (strip trailing whitespace, drop decompiler
  `/* WARNING ... */` lines), `diff -u` against `tests/snapshots/<f>/<fn>.c`;
  differences are printed under "Snapshot changes" and never fail the run.
  `UPDATE_SNAPSHOTS=1` copies the normalized output over the snapshots instead.
- Summary: one line per check, then `N passed, M failed`; exit 1 if `M > 0`.

## 8. Testing the test

The implementation is not complete until each of these is demonstrated:

1. Bad expectation (`contains 0xdeadbeef`) → FAIL and exit 1.
2. Broken extension: in a throwaway hard-linked copy of the install with the
   lx-loader directory renamed, `verify-extensions` and the LE import both fail.
3. Snapshot drift: a hand-edited snapshot is reported without failing the run.
4. GhidraMCP unreachable (port occupied / server not started) → clean FAIL
   within the timeout.
5. After a passing and a failing run, `~/.ghidra` is absent and
   `portable/temp` holds no `sanity-*` directory.

## 9. Integration

- `Makefile`: `test: ## Run the sanity test suite (fixtures, decompiler, extensions, GhidraMCP)`
  → `tests/run-sanity.sh "$(INSTALL_DIR)" "$(JAVA21_HOME)"`. In `PIPELINE`,
  `verify-extensions` is replaced by `test` as the last stage. `verify-extensions`
  stays as a standalone target. `clean` is unchanged (temporary files live in `dist/`).
- `README.md`: a `test` row in the targets table and a short "Testing" note
  (what it proves, runtime, `UPDATE_SNAPSHOTS=1`).
- `AGENTS.md`: `make test` replaces `verify-extensions` in the pre-merge
  checklist; a short "adding a test fixture" note.

## 10. Amendments (2026-10-06, from reading the loaders while planning)

1. LE objects are `0x20` bytes each: lx-loader reads the final page of every object with the header's last-page size.
2. DOS adds `function entry contains DosTerminateErrorCode`, proving GhidraDosToolbox's `DosSyscallAnalyzer` runs (it names `INT 21h, AH=4Ch` from `data/x86_msdos6_interrupt_functions`).
3. ELF facts: `loader`, `relocations >= 2`, `function helper decompiles`, `function compute contains 0x1234abcd`, `function compute contains counter`, `function compute calls helper`.
4. The runner checks extensions with `make verify-extensions INSTALL_DIR=<install>` so it can test a copy of the install.
5. The GhidraMCP check calls `POST /run_analysis` first; the headless server imports without analyzing.
6. The runner and every headless run need the project directory to exist; the runner creates `$WORK/proj`.
7. A missing GhidraMCP jar is reported as a FAIL (the jar lookup uses a nullglob-guarded array), not a script abort.
8. Hardening from the final review:
   - A fixture import that exceeds `TEST_IMPORT_TIMEOUT` (default 600 s) is a FAIL; `pkill -f` on the work directory reaps the analysis JVM that `timeout` leaves behind, and `cleanup` does the same before deleting it.
   - The runner needs GNU `timeout` (`gtimeout` from Homebrew coreutils on macOS) and checks for it.
   - `UPDATE_SNAPSHOTS=1` leaves `tests/snapshots/` untouched when any check failed.
   - The `SANITY DONE <p> <f>` counts must be non-zero and match the PASS/FAIL lines parsed, so an empty expectations file or an unparsed line fails the fixture.
   - The GhidraMCP test server starts without `GHIDRA_MCP_AUTH_TOKEN`, `GHIDRA_MCP_PROJECT_FOLDER` and `GHIDRA_MCP_FILE_ROOT` from the caller's environment.
