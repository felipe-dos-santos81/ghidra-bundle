# Sanity Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `make test`, a headless sanity suite that proves a bundle install imports, loads (ELF, DOS MZ via GhidraDosToolbox, LE via lx-loader), decompiles and serves (GhidraMCP) as expected, and run it as the last stage of `make install`.

**Architecture:** A bash runner (`tests/run-sanity.sh`) builds three tiny test programs into a temporary directory under the install's `portable/temp/`, imports each with `analyzeHeadless` into a throwaway project, and runs one generic, data-driven Ghidra script (`ghidra_scripts/SanityCheck.java`) that checks the facts listed in `tests/expect/<fixture>.txt`. It then starts GhidraMCP's headless server on a spare port and checks it over HTTP. Decompiled C is diffed against committed snapshots as a non-failing report.

**Tech Stack:** GNU Make, bash, Python 3 (standard library only), clang (i386 target, compile-only), Ghidra 12.1.4 headless + GhidraScript (Java 21), curl.

**Spec:** `docs/superpowers/specs/2026-10-06-sanity-test-design.md`

## Global Constraints

- All test files live under `dist/ghidra_12.1.4_PUBLIC/portable/temp/sanity-XXXXXX/` and are deleted on every exit path; nothing is written to `~/.ghidra`.
- GhidraMCP test server: `--bind 127.0.0.1`, port `TEST_MCP_PORT`, default `18089` (never 8089, which the user's GUI uses).
- Timeouts: `timeout --foreground 600` per `analyzeHeadless` run; 120 s for the GhidraMCP server to answer; 60 s per decompiled function.
- No new dependencies: only clang, python3, curl, java and Ghidra, which the bundle already requires.
- `make test` exits 0 when every check passes and 1 otherwise; snapshot differences never change the exit code.
- Makefile recipes use tabs and the `$(OK)` / `$(WARN)` / `$(ERR)` helpers; every user-facing target has a `## description`.
- Bash: `set -euo pipefail`, validate with `bash -n`. Python: run with `python3 -I`.
- Verified on Linux arm64 only; docs say macOS is untested.

## Spec Amendments (decided while reading the real parsers)

Record these in the spec in Task 6:

1. **LE objects are `0x20` bytes each** (not 16 for the data object): lx-loader reads the final page of *every* object with the header's last-page size (`LinearLoader.java:314-316`), so both objects are one `0x20`-byte page.
2. **DOS adds an analyzer fact:** `function entry contains DosTerminateErrorCode`. GhidraDosToolbox's `DosSyscallAnalyzer` names `INT 21h, AH=4Ch` after `data/x86_msdos6_interrupt_functions` (`21 4C -- DosTerminateErrorCode`); this proves the extension's analyzer runs, not just its loader.
3. **ELF facts:** `loader`, `relocations >= 2`, `function helper decompiles`, `function compute contains 0x1234abcd`, `function compute contains counter`, `function compute calls helper`.
4. **The runner checks extensions with `make verify-extensions INSTALL_DIR=<install>`**, so it can be pointed at a copy of the install (needed for the broken-extension test).
5. **The GhidraMCP check calls `POST /run_analysis` before listing functions:** the headless server imports without analyzing (observed: `function_count` 0 until `/run_analysis`).

## Review Focus

1. **Native decompiler missing or broken** (a real failed-install mode): the decompile facts must FAIL with "native decompiler did not start", not crash the script. Test added to Task 7.
2. **Interrupted run (Ctrl-C):** the GhidraMCP test server must be killed and `sanity-*` removed. Test added to Task 5.
3. **clang missing, or unable to target i386:** the runner must fail with a one-line explanation, not a bare `set -e` exit. Test added to Task 4.
4. **Malformed expectations** (unknown fact type, bad address, missing function): each must become one FAIL line, and the script must still print `SANITY DONE`. Test added to Task 1.
5. **Orphaned snapshot** (a function renamed or removed after a Ghidra upgrade): the report must list snapshots that no longer have output, not silently ignore them. Test added to Task 4.

---

## File Structure

| File | Responsibility |
| :--- | :--- |
| `ghidra_scripts/SanityCheck.java` (create) | Generic fact checker run as an `analyzeHeadless` post-script |
| `tests/fixtures/sample.c` (create) | C source for the ELF fixture |
| `tests/make_fixtures.py` (create) | Writes `dos.exe` and `le.exe` byte by byte |
| `tests/expect/sample.txt`, `dos.txt`, `le.txt` (create) | Facts per fixture |
| `tests/snapshots/<fixture>/<function>.c` (create, generated) | Reference decompilation |
| `tests/run-sanity.sh` (create) | Orchestration, GhidraMCP check, snapshot report, summary |
| `Makefile` (modify) | `test` target; `PIPELINE` ends with `test` |
| `README.md`, `AGENTS.md` (modify) | Testing docs |
| `docs/superpowers/specs/2026-10-06-sanity-test-design.md` (modify) | Amendments section |

Commands below run from the repository root. Shared shell variables used by the manual steps in Tasks 1–3 (paste once per shell):

```bash
INSTALL="$PWD/dist/ghidra_12.1.4_PUBLIC"
SCRATCH=$(mktemp -d "$INSTALL/portable/temp/plan-XXXXXX")
headless() {  # headless <name> <file> <expect file> [extra analyzeHeadless args...]
  local name=$1 file=$2 expect=$3; shift 3
  rm -rf "$SCRATCH/out/$name"; mkdir -p "$SCRATCH/out/$name"
  "$INSTALL/support/analyzeHeadless" "$SCRATCH/proj" "p-$name" -import "$file" "$@" -deleteProject \
    -scriptPath "$PWD/ghidra_scripts" -postScript SanityCheck.java "$expect" "$SCRATCH/out/$name" \
    > "$SCRATCH/$name.log" 2>&1
  grep -E 'SANITY|Import succeeded|Using Loader' "$SCRATCH/$name.log" | sed -E 's/ \(GhidraScript\) *$//; s/^.*(SANITY|INFO  Using)/\1/'
}
```

Remove the scratch directory at the end of Task 3: `rm -rf "$SCRATCH"`.

---

### Task 1: Fact checker script and ELF fixture

**Files:**
- Create: `ghidra_scripts/SanityCheck.java`
- Create: `tests/fixtures/sample.c`
- Create: `tests/expect/sample.txt`

**Interfaces:**
- Consumes: nothing.
- Produces: `SanityCheck.java <expectations file> <output dir>`. Prints exactly one `SANITY PASS <fact>` or `SANITY FAIL <fact> (got <observed>)` line per fact, then `SANITY DONE <passed> <failed>`. In the `analyzeHeadless` log each line ends with ` (GhidraScript)`. Writes `<output dir>/<function name with [^A-Za-z0-9_.-] replaced by _>.c` for every function named in a `function` fact. Fact grammar: spec section 5.

- [ ] **Step 1: Write the ELF fixture source and its expectations**

`tests/fixtures/sample.c`:

```c
/* Core-decompiler fixture for `make test` (see tests/expect/sample.txt).
 * Compiled with: clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c */
int counter;

__attribute__((noinline)) int helper(int x) { return x * 3 + 7; }

int compute(int a) {
  counter++;
  return helper(a) ^ 0x1234abcd;
}
```

`tests/expect/sample.txt`:

```text
# sample.o: i386 ELF relocatable, Ghidra's own ELF loader.
loader Executable and Linking Format (ELF)
relocations >= 2                    # counter (R_386_32) and the call to helper (R_386_PC32)
function helper decompiles
function compute contains 0x1234abcd
function compute contains counter   # relocation resolved to the global's symbol
function compute calls helper
```

- [ ] **Step 2: Run the checker before it exists and confirm the failure**

```bash
clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c tests/fixtures/sample.c -o "$SCRATCH/sample.o"
headless sample "$SCRATCH/sample.o" tests/expect/sample.txt
grep -c 'SANITY' "$SCRATCH/sample.log"; grep -iE 'not found|SanityCheck' "$SCRATCH/sample.log" | head -3
```

Expected: `Import succeeded` is printed, `0` SANITY lines, and the log reports that `SanityCheck.java` cannot be found.

- [ ] **Step 3: Write `ghidra_scripts/SanityCheck.java`**

```java
// Checks facts about the current program, listed one per line in an
// expectations file (see docs/superpowers/specs/2026-10-06-sanity-test-design.md).
// Usage (analyzeHeadless): -postScript SanityCheck.java <expectations file> <output dir>
// Prints "SANITY PASS <fact>" or "SANITY FAIL <fact> (got ...)" per fact and
// "SANITY DONE <passed> <failed>" last; writes the decompiled C of every
// function named in a "function" fact to <output dir>/<function>.c.
//@category Bundle

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Reference;

public class SanityCheck extends GhidraScript {

	private static final String DECOMPILE_FAILED = "DECOMPILE FAILED: ";

	private final Map<Function, String> decompiled = new HashMap<>();
	private DecompInterface decompiler;
	private File outDir;
	private int passed;
	private int failed;

	@Override
	public void run() throws Exception {
		String[] args = getScriptArgs();
		if (args.length != 2) {
			println("SANITY FAIL usage (got " + args.length + " arguments, want <expectations> <output dir>)");
			println("SANITY DONE 0 1");
			return;
		}
		outDir = new File(args[1]);
		outDir.mkdirs();
		decompiler = new DecompInterface();
		decompiler.openProgram(currentProgram);
		try {
			for (String line : Files.readAllLines(new File(args[0]).toPath(), StandardCharsets.UTF_8)) {
				String fact = line.replaceFirst("#.*$", "").trim();
				if (!fact.isEmpty()) {
					report(fact);
				}
			}
		}
		finally {
			decompiler.dispose();
		}
		println("SANITY DONE " + passed + " " + failed);
	}

	private void report(String fact) {
		String problem;
		try {
			problem = check(fact.split("\\s+"));
		}
		catch (Exception e) {
			problem = e.toString();
		}
		if (problem == null) {
			passed++;
			println("SANITY PASS " + fact);
		}
		else {
			failed++;
			println("SANITY FAIL " + fact + " (got " + problem.replaceAll("\\s+", " ") + ")");
		}
	}

	/** Returns null when the fact holds, otherwise a description of what was observed. */
	private String check(String[] t) throws Exception {
		switch (t[0]) {
			case "loader": {
				String got = currentProgram.getExecutableFormat();
				return join(t, 1).equals(got) ? null : got;
			}
			case "block": {
				MemoryBlock block = currentProgram.getMemory().getBlock(t[1]);
				if (block == null) {
					return "no block named " + t[1];
				}
				return block.getStart().equals(addr(t[2])) ? null : "starts at " + block.getStart();
			}
			case "entry": {
				if (currentProgram.getSymbolTable().isExternalEntryPoint(addr(t[1]))) {
					return null;
				}
				List<String> entries = new ArrayList<>();
				currentProgram.getSymbolTable().getExternalEntryPointIterator()
						.forEachRemaining(a -> entries.add(a.toString()));
				return "entry points " + entries;
			}
			case "relocations": {
				int count = 0;
				var it = currentProgram.getRelocationTable().getRelocations();
				while (it.hasNext()) {
					it.next();
					count++;
				}
				return count >= Integer.parseInt(t[2]) ? null : count + " relocations";
			}
			case "bytes": {
				byte[] want = HexFormat.of().parseHex(t[2]);
				byte[] got = getBytes(addr(t[1]), want.length);
				return Arrays.equals(want, got) ? null : HexFormat.of().formatHex(got);
			}
			case "reference": {
				Address to = addr(t[3]);
				Reference[] refs = getReferencesFrom(addr(t[1]));
				for (Reference ref : refs) {
					if (ref.getToAddress().equals(to)) {
						return null;
					}
				}
				return "references " + Arrays.toString(refs);
			}
			case "function":
				return checkFunction(t);
			default:
				return "unknown fact type '" + t[0] + "'";
		}
	}

	private String checkFunction(String[] t) throws Exception {
		Function f = function(t[1]);
		if (f == null) {
			return "no function " + t[1];
		}
		String c = decompile(f);
		switch (t[2]) {
			case "decompiles":
				return c.startsWith(DECOMPILE_FAILED) ? c : null;
			case "contains": {
				if (c.startsWith(DECOMPILE_FAILED)) {
					return c;
				}
				String want = join(t, 3);
				return c.contains(want) ? null : "decompiled C without '" + want + "', see " + fileFor(f);
			}
			case "calls": {
				Function callee = function(t[3]);
				if (callee == null) {
					return "no function " + t[3];
				}
				var called = f.getCalledFunctions(monitor);
				return called.contains(callee) ? null : "calls " + called;
			}
			default:
				return "unknown function check '" + t[2] + "'";
		}
	}

	private String decompile(Function f) throws Exception {
		String c = decompiled.get(f);
		if (c != null) {
			return c;
		}
		DecompileResults r = decompiler.decompileFunction(f, 60, monitor);
		if (r.failedToStart()) {
			c = DECOMPILE_FAILED + "native decompiler did not start: " + r.getErrorMessage();
		}
		else if (!r.decompileCompleted() || r.getDecompiledFunction() == null) {
			c = DECOMPILE_FAILED + r.getErrorMessage();
		}
		else {
			c = r.getDecompiledFunction().getC();
		}
		decompiled.put(f, c);
		Files.writeString(fileFor(f).toPath(), c, StandardCharsets.UTF_8);
		return c;
	}

	private File fileFor(Function f) {
		return new File(outDir, f.getName().replaceAll("[^A-Za-z0-9_.-]", "_") + ".c");
	}

	/** A function by global name, else by address. */
	private Function function(String nameOrAddress) {
		List<Function> byName = getGlobalFunctions(nameOrAddress);
		if (!byName.isEmpty()) {
			return byName.get(0);
		}
		Address a = currentProgram.getAddressFactory().getAddress(nameOrAddress);
		return a == null ? null : getFunctionAt(a);
	}

	/** Parses "00010000" (default space) or "1000:0001" (segmented). */
	private Address addr(String text) {
		Address a = currentProgram.getAddressFactory().getAddress(text);
		if (a == null) {
			throw new IllegalArgumentException("bad address '" + text + "'");
		}
		return a;
	}

	private static String join(String[] t, int from) {
		return String.join(" ", Arrays.copyOfRange(t, from, t.length));
	}
}
```

- [ ] **Step 4: Run it and confirm every ELF fact passes**

```bash
headless sample "$SCRATCH/sample.o" tests/expect/sample.txt
ls "$SCRATCH/out/sample"; cat "$SCRATCH/out/sample/compute.c"
```

Expected: `Using Loader: Executable and Linking Format (ELF)`, six `SANITY PASS` lines, `SANITY DONE 6 0`; `compute.c` and `helper.c` exist, and `compute.c` contains `0x1234abcd`, `counter` and `helper(`.

If a fact fails, read `compute.c` and the `(got ...)` text before changing anything. Change the expectation only if the observed output is correct for this source; otherwise fix the script.

- [ ] **Step 5: Malformed expectations become FAIL lines, not crashes (Review Focus 4)**

```bash
cat > "$SCRATCH/bad.txt" <<'EOF'
frobnicate 1 2
bytes zz:zz 00
function no_such_function decompiles
function compute contains 0xdeadbeef
function compute calls no_such_function
EOF
headless bad "$SCRATCH/sample.o" "$SCRATCH/bad.txt"
```

Expected: five `SANITY FAIL` lines, with `got` reasons `unknown fact type 'frobnicate'`, `bad address 'zz:zz'` (inside an `IllegalArgumentException`), `no function no_such_function`, `decompiled C without '0xdeadbeef'` and `no function no_such_function`; last line `SANITY DONE 0 5`.

- [ ] **Step 6: Commit**

```bash
git add ghidra_scripts/SanityCheck.java tests/fixtures/sample.c tests/expect/sample.txt
git commit -m "test: add SanityCheck.java fact checker and ELF fixture"
```

---

### Task 2: LE fixture through lx-loader

**Files:**
- Create: `tests/make_fixtures.py` (LE part; Task 3 adds DOS)
- Create: `tests/expect/le.txt`

**Interfaces:**
- Consumes: `SanityCheck.java` (Task 1).
- Produces: `python3 -I tests/make_fixtures.py OUT_DIR` writes `OUT_DIR/le.exe` (and, after Task 3, `OUT_DIR/dos.exe`); prints one line per file written.

- [ ] **Step 1: Write the expectations first**

`tests/expect/le.txt`:

```text
# le.exe: 32-bit LE behind an MZ stub, imported with lx-loader's LeLoader.
loader Linear Executable (LE-Style DOS)
block .object1 00010000
block .object2 00020000
entry 00010000
relocations >= 1
bytes 00010001 04000200             # fixup applied: [obj2+4] -> 0x00020004
reference 00010000 -> 00020004
function 00010000 contains 0x1234abcd
function 00010000 calls 00010010
```

- [ ] **Step 2: Run the import without a fixture and confirm it fails**

```bash
python3 -I tests/make_fixtures.py "$SCRATCH/fx"; echo "exit=$?"
```

Expected: `python3: can't open file .../tests/make_fixtures.py` and a non-zero exit.

- [ ] **Step 3: Write `tests/make_fixtures.py` with the LE builder**

```python
#!/usr/bin/env python3
"""Write the hand-built test programs used by `make test`.

Usage: python3 -I tests/make_fixtures.py OUTPUT_DIR

  le.exe   32-bit LE behind an MZ stub with one 32-bit fixup (lx-loader LeLoader)

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


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, build in (("le.exe", build_le),):
        path = out / name
        path.write_bytes(build())
        print(f"wrote {path} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Build it and check the header bytes**

```bash
python3 -I tests/make_fixtures.py "$SCRATCH/fx"
xxd -s 0x80 -l 4 "$SCRATCH/fx/le.exe"; xxd -s 0x18C -l 9 "$SCRATCH/fx/le.exe"; xxd -s 0x200 -l 22 "$SCRATCH/fx/le.exe"
```

Expected: `wrote .../le.exe (4640 bytes)`; `4c45 0000` (`LE..`) at 0x80; the fixup record `0710 0100 0204 0000 00` at 0x18C; the code bytes at 0x200.

- [ ] **Step 5: Import with lx-loader and confirm every fact passes**

```bash
headless le "$SCRATCH/fx/le.exe" tests/expect/le.txt -loader LeLoader
```

Expected: `Using Loader: Linear Executable (LE-Style DOS)`, nine `SANITY PASS` lines, `SANITY DONE 9 0`.

If the import fails, the log names the parser step (`grep -n -iE 'exception|error' "$SCRATCH/le.log" | head`). Compare the failing table against `lx-loader/src/main/java/yetmorecode/ghidra/format/lx/model/{Header,Executable,FixupRecord,LePageMapEntry,ObjectTableEntry}.java` and fix the builder, not the expectations.

- [ ] **Step 6: Commit**

```bash
git add tests/make_fixtures.py tests/expect/le.txt
git commit -m "test: add hand-built LE fixture for lx-loader"
```

---

### Task 3: DOS MZ fixture through GhidraDosToolbox

**Files:**
- Modify: `tests/make_fixtures.py` (add `build_dos`, register it in `main`, update the docstring)
- Create: `tests/expect/dos.txt`

**Interfaces:**
- Consumes: `SanityCheck.java`, `make_fixtures.py` (Tasks 1–2).
- Produces: `OUT_DIR/dos.exe`.

- [ ] **Step 1: Write the expectations first**

`tests/expect/dos.txt`:

```text
# dos.exe: 16-bit DOS MZ, imported with GhidraDosToolbox's DosLoader (load segment 0x1000).
loader Old-style DOS Executable (MZ)(Experimental)
entry 1000:0000
relocations >= 1
bytes 1000:0001 0210                         # data segment word 0x0002 relocated to 0x1002
function entry calls 1000:0010
function 1000:0010 contains 0xabcd
function entry contains DosTerminateErrorCode  # DosSyscallAnalyzer named INT 21h / AH=4Ch
```

- [ ] **Step 2: Confirm the fixture is missing**

```bash
python3 -I tests/make_fixtures.py "$SCRATCH/fx" && ls "$SCRATCH/fx/dos.exe"
```

Expected: only `le.exe` is written; `ls: cannot access '.../dos.exe'`.

- [ ] **Step 3: Add the DOS builder**

Add this function above `main()` in `tests/make_fixtures.py`:

```python
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
```

Then change the loop in `main()` to

```python
    for name, build in (("dos.exe", build_dos), ("le.exe", build_le)):
```

and add this line to the module docstring, above the `le.exe` line:

```text
  dos.exe  16-bit DOS MZ with one segment relocation (GhidraDosToolbox DosLoader)
```

- [ ] **Step 4: Build it and check the header**

```bash
python3 -I tests/make_fixtures.py "$SCRATCH/fx"
xxd -l 0x30 "$SCRATCH/fx/dos.exe"
```

Expected: `wrote .../dos.exe (80 bytes)`; the dump starts `4d5a 5000 0100 0100 0200`, and the relocation entry `0100 0000` sits at offset 0x1C.

- [ ] **Step 5: Import with DosLoader and confirm every fact passes**

```bash
headless dos "$SCRATCH/fx/dos.exe" tests/expect/dos.txt -loader DosLoader
cat "$SCRATCH/out/dos/entry.c"
```

Expected: `Using Loader: Old-style DOS Executable (MZ)(Experimental)`, seven `SANITY PASS` lines, `SANITY DONE 7 0`; `entry.c` contains `DosTerminateErrorCode`.

If only the `DosTerminateErrorCode` fact fails, open `entry.c`. If it shows `swi(0x21)`, the analyzer did not run: check `grep -i DosSyscall "$SCRATCH/dos.log"`, and confirm the program language is `x86:LE:16:Real Mode` (the analyzer only enables itself for that language). If the decompiler prints the constant as `-0x5433` rather than `0xabcd`, change that one expectation to the printed form; the fact is about the value, and both are the same 16-bit value.

- [ ] **Step 6: Commit and clean up**

```bash
git add tests/make_fixtures.py tests/expect/dos.txt
git commit -m "test: add hand-built DOS MZ fixture for GhidraDosToolbox"
rm -rf "$SCRATCH"
```

---

### Task 4: Runner, summary and snapshot report

**Files:**
- Create: `tests/run-sanity.sh`
- Create: `tests/snapshots/{sample,le,dos}/*.c` (generated in Step 6)

**Interfaces:**
- Consumes: `SanityCheck.java`, `make_fixtures.py`, `tests/expect/*.txt`; `make verify-extensions INSTALL_DIR=<dir>` (existing target, `INSTALL_DIR` overridable on the command line).
- Produces: `tests/run-sanity.sh <install dir> <JDK home>`, exit 0 or 1; env `UPDATE_SNAPSHOTS=1`. Task 5 adds the GhidraMCP check to this file via a `check_mcp` function called before the summary.

- [ ] **Step 1: Write the runner**

`tests/run-sanity.sh`:

```bash
#!/bin/bash
# Sanity test suite for the Ghidra bundle; run it with `make test`.
# Design: docs/superpowers/specs/2026-10-06-sanity-test-design.md
#
# Usage: tests/run-sanity.sh <ghidra install dir> <JDK 21 home>
# Env:   UPDATE_SNAPSHOTS=1  rewrite tests/snapshots/ from this run
set -euo pipefail

INSTALL_DIR=${1:?usage: run-sanity.sh <ghidra install dir> <JDK 21 home>}
export JAVA_HOME=${2:?usage: run-sanity.sh <ghidra install dir> <JDK 21 home>}
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS="$REPO_DIR/tests"
HEADLESS="$INSTALL_DIR/support/analyzeHeadless"

PASSED=0
FAILED=0
RESULTS=()
pass() { PASSED=$((PASSED + 1)); RESULTS+=("PASS  $1"); }
fail() { FAILED=$((FAILED + 1)); RESULTS+=("FAIL  $1"); }
die() { printf '\033[31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }
indent() { sed 's/^/    /'; }

[[ -x "$HEADLESS" ]] || die "$HEADLESS not found; run 'make install' first."
for tool in clang python3 curl; do
  command -v "$tool" >/dev/null || die "$tool not found on PATH (run 'make deps')."
done

WORK=$(mktemp -d "$INSTALL_DIR/portable/temp/sanity-XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# ── 1. Extension classes ──────────────────────────────────────────────────────
echo "Checking extension class discovery..."
if make -C "$REPO_DIR" -s verify-extensions INSTALL_DIR="$INSTALL_DIR" > "$WORK/verify.log" 2>&1; then
  pass "extensions: GhidraMCP, lx-loader and dos-toolbox classes load"
else
  fail "extensions: some classes are not loaded"
  indent < "$WORK/verify.log"
fi

# ── 2. Fixtures ───────────────────────────────────────────────────────────────
echo "Building fixtures..."
mkdir -p "$WORK/fixtures"
clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c "$TESTS/fixtures/sample.c" \
  -o "$WORK/fixtures/sample.o" 2> "$WORK/clang.log" \
  || die "clang could not build an i386 object: $(head -1 "$WORK/clang.log")"
python3 -I "$TESTS/make_fixtures.py" "$WORK/fixtures" > /dev/null

# ── 3. Headless import + SanityCheck.java per fixture ─────────────────────────
run_fixture() {  # run_fixture <name> <file> [loader]
  local name=$1 file=$2 loader=${3:-}
  local log="$WORK/$name.log" out="$WORK/out/$name" line
  local args=("$WORK/proj" "sanity-$name" -import "$file")
  [[ -n "$loader" ]] && args+=(-loader "$loader")
  args+=(-deleteProject -scriptPath "$REPO_DIR/ghidra_scripts"
         -postScript SanityCheck.java "$TESTS/expect/$name.txt" "$out")
  mkdir -p "$out"
  echo "Importing $name ($(basename "$file"), loader ${loader:-auto})..."
  # --foreground keeps analyzeHeadless in the terminal's process group so Ctrl-C reaches it.
  timeout --foreground 600 "$HEADLESS" "${args[@]}" > "$log" 2>&1 || echo "analyzeHeadless exit status $?" >> "$log"
  if ! grep -q 'Import succeeded' "$log"; then
    fail "$name: import failed (loader ${loader:-auto})"
    tail -20 "$log" | indent
    return
  fi
  while IFS= read -r line; do
    case "$line" in
      PASS\ *) pass "$name: ${line#PASS }" ;;
      FAIL\ *) fail "$name: ${line#FAIL }" ;;
    esac
  done < <(sed -nE 's/^.*SANITY (PASS|FAIL) (.*) \(GhidraScript\) *$/\1 \2/p' "$log")
  if ! grep -q 'SANITY DONE' "$log"; then
    fail "$name: SanityCheck.java did not finish"
    tail -20 "$log" | indent
  fi
}

run_fixture sample "$WORK/fixtures/sample.o"
run_fixture dos "$WORK/fixtures/dos.exe" DosLoader
run_fixture le "$WORK/fixtures/le.exe" LeLoader

# ── 4. Snapshot report (never fails the run) ──────────────────────────────────
normalize() {  # drop decompiler warning comments and trailing whitespace
  sed -E -e '/^[[:space:]]*\/\* WARNING.*\*\/[[:space:]]*$/d' -e 's/[[:space:]]+$//' "$1"
}

report_snapshots() {
  local f rel snap changed=0
  if [[ "${UPDATE_SNAPSHOTS:-}" == 1 ]]; then
    rm -rf "$TESTS/snapshots"
    for f in "$WORK"/out/*/*.c; do
      [[ -e "$f" ]] || continue
      rel=${f#"$WORK/out/"}
      mkdir -p "$(dirname "$TESTS/snapshots/$rel")"
      normalize "$f" > "$TESTS/snapshots/$rel"
    done
    echo "Snapshots rewritten in tests/snapshots/."
    return
  fi
  echo
  echo "Snapshot changes (informational):"
  for f in "$WORK"/out/*/*.c; do
    [[ -e "$f" ]] || continue
    rel=${f#"$WORK/out/"}
    snap="$TESTS/snapshots/$rel"
    if [[ ! -f "$snap" ]]; then
      echo "  new: $rel"
      changed=1
    elif ! diff -u --label "snapshot/$rel" --label "now/$rel" "$snap" <(normalize "$f") | indent; then
      changed=1
    fi
  done
  for snap in "$TESTS"/snapshots/*/*.c; do
    [[ -e "$snap" ]] || continue
    rel=${snap#"$TESTS/snapshots/"}
    if [[ ! -e "$WORK/out/$rel" ]]; then
      echo "  gone: $rel (no longer produced)"
      changed=1
    fi
  done
  if [[ $changed == 0 ]]; then
    echo "  none"
  else
    echo "  (after a deliberate upgrade, record them with: UPDATE_SNAPSHOTS=1 make test)"
  fi
}

report_snapshots

# ── 5. Summary ────────────────────────────────────────────────────────────────
echo
for r in "${RESULTS[@]}"; do
  case "$r" in
    PASS*) printf '  \033[32m%s\033[0m\n' "$r" ;;
    *) printf '  \033[31m%s\033[0m\n' "$r" ;;
  esac
done
echo "$PASSED passed, $FAILED failed"
[[ $FAILED == 0 ]]
```

Note on the snapshot `diff`: `diff ... | indent` returns `indent`'s status, so the `elif !` branch needs `set -o pipefail` (already set) to see `diff`'s exit code 1. With `pipefail`, the pipeline status is 1 when the files differ.

- [ ] **Step 2: Make it executable and syntax-check it**

```bash
chmod +x tests/run-sanity.sh && bash -n tests/run-sanity.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: First run: all facts pass, every snapshot is "new"**

```bash
tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$(make -s --eval 'j: ; @echo $(JAVA21_HOME)' j)"; echo "exit=$?"
```

Expected: `extensions: ...` PASS, 6 + 7 + 9 = 22 fixture PASS lines, `23 passed, 0 failed`, `exit=0`; the snapshot report lists every `.c` as `new:`.

- [ ] **Step 4: Record the snapshots and confirm the report is clean**

```bash
J="$(make -s --eval 'j: ; @echo $(JAVA21_HOME)' j)"
UPDATE_SNAPSHOTS=1 tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J"
ls tests/snapshots/*
tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J" | sed -n '/Snapshot changes/,/^$/p'
```

Expected: `tests/snapshots/{sample,dos,le}/` contain the decompiled functions; the second run prints `Snapshot changes (informational):` followed by `none`.

- [ ] **Step 5: Orphaned snapshot is reported (Review Focus 5)**

```bash
cp tests/snapshots/sample/helper.c tests/snapshots/sample/old_name.c
tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J" | grep -E 'gone:|passed'
rm tests/snapshots/sample/old_name.c
```

Expected: `  gone: sample/old_name.c (no longer produced)` and `23 passed, 0 failed` (the exit code is unaffected).

- [ ] **Step 6: clang unable to target i386 gives a one-line reason (Review Focus 3)**

```bash
mkdir -p "$PWD/dist/ghidra_12.1.4_PUBLIC/portable/temp/fakebin"
printf '#!/bin/sh\necho "error: unknown target triple" >&2\nexit 1\n' > "$PWD/dist/ghidra_12.1.4_PUBLIC/portable/temp/fakebin/clang"
chmod +x "$PWD/dist/ghidra_12.1.4_PUBLIC/portable/temp/fakebin/clang"
PATH="$PWD/dist/ghidra_12.1.4_PUBLIC/portable/temp/fakebin:$PATH" tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J"; echo "exit=$?"
rm -rf "$PWD/dist/ghidra_12.1.4_PUBLIC/portable/temp/fakebin"
ls "$PWD/dist/ghidra_12.1.4_PUBLIC/portable/temp/" | grep -c sanity- || true
```

Expected: `ERROR: clang could not build an i386 object: error: unknown target triple`, `exit=1`, and `0` leftover `sanity-` directories.

- [ ] **Step 7: Commit**

```bash
git add tests/run-sanity.sh tests/snapshots
git commit -m "test: add sanity runner with summary and snapshot report"
```

---

### Task 5: GhidraMCP end-to-end check and interrupt-safe cleanup

**Files:**
- Modify: `tests/run-sanity.sh`

**Interfaces:**
- Consumes: `$WORK/fixtures/sample.o`, `pass`/`fail`/`indent` helpers (Task 4); the installed `Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-*.jar`; GhidraMCP endpoints `GET /check_connection`, `POST /run_analysis`, `GET /list_functions` (JSON `{"functions":[{"name","address"}]}`), `GET /decompile_function?address=<addr>` (JSON with the C text).
- Produces: env `TEST_MCP_PORT` (default 18089).

- [ ] **Step 1: Interrupting the current runner leaves its temp dir behind (the failing case)**

```bash
J="$(make -s --eval 'j: ; @echo $(JAVA21_HOME)' j)"; T="$PWD/dist/ghidra_12.1.4_PUBLIC/portable/temp"
tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J" > /dev/null 2>&1 & PID=$!
until ls "$T" | grep -q sanity-; do sleep 1; done; sleep 5; kill -INT $PID; wait $PID; echo "exit=$?"
ls "$T" | grep sanity- || echo "no leftovers"
```

Record the result. A plain `trap cleanup EXIT` normally also runs on SIGINT in bash, so this may already print `no leftovers`. If a `sanity-*` directory or a Ghidra `java` process remains, remove it by hand (`rm -rf "$T"/sanity-*`; `pgrep -af analyzeHeadless`).

- [ ] **Step 2: Replace the cleanup trap and add the GhidraMCP check**

In `tests/run-sanity.sh`, replace

```bash
WORK=$(mktemp -d "$INSTALL_DIR/portable/temp/sanity-XXXXXX")
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
```

with

```bash
MCP_PORT="${TEST_MCP_PORT:-18089}"
WORK=$(mktemp -d "$INSTALL_DIR/portable/temp/sanity-XXXXXX")
MCP_PID=""
cleanup() {
  if [[ -n "$MCP_PID" ]]; then
    kill "$MCP_PID" 2>/dev/null || true
    wait "$MCP_PID" 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
```

and add this line to the usage comment at the top:

```bash
#        TEST_MCP_PORT=18089  port for the GhidraMCP test server (default 18089)
```

Then insert this block after the three `run_fixture` calls and before `# ── 4. Snapshot report`:

```bash
# ── 3b. GhidraMCP end to end ──────────────────────────────────────────────────
check_mcp() {
  local url="http://127.0.0.1:$MCP_PORT" cp jar i out compute
  if (exec 3<>"/dev/tcp/127.0.0.1/$MCP_PORT") 2>/dev/null; then
    fail "GhidraMCP: port $MCP_PORT is already in use (set TEST_MCP_PORT to a free port)"
    return
  fi
  cp=$(ls "$INSTALL_DIR"/Ghidra/Extensions/GhidraMCP/lib/GhidraMCP-*.jar 2>/dev/null | head -n 1)
  if [[ -z "$cp" ]]; then
    fail "GhidraMCP: no GhidraMCP jar in $INSTALL_DIR/Ghidra/Extensions/GhidraMCP/lib"
    return
  fi
  for jar in "$INSTALL_DIR"/Ghidra/{Framework,Features,Processors}/*/lib/*.jar; do
    cp+=":$jar"
  done
  mkdir -p "$WORK/mcp"/{home,settings,cache,temp}
  echo "Starting GhidraMCP headless server on 127.0.0.1:$MCP_PORT..."
  "$JAVA_HOME/bin/java" -Djava.awt.headless=true \
    -Duser.home="$WORK/mcp/home" -Djava.io.tmpdir="$WORK/mcp/temp" \
    -Dapplication.settingsdir="$WORK/mcp/settings" \
    -Dapplication.cachedir="$WORK/mcp/cache" \
    -Dapplication.tempdir="$WORK/mcp/temp" \
    -Dghidra.home="$INSTALL_DIR" -classpath "$cp" \
    com.xebyte.headless.GhidraMCPHeadlessServer \
    --bind 127.0.0.1 --port "$MCP_PORT" --file "$WORK/fixtures/sample.o" \
    > "$WORK/mcp.log" 2>&1 &
  MCP_PID=$!
  for ((i = 0; i < 120; i++)); do
    curl -sf -m 2 "$url/check_connection" > /dev/null 2>&1 && break
    kill -0 "$MCP_PID" 2>/dev/null || break
    sleep 1
  done
  if ! out=$(curl -sf -m 5 "$url/check_connection"); then
    fail "GhidraMCP: server did not answer on port $MCP_PORT within 120 s"
    tail -20 "$WORK/mcp.log" | indent
    return
  fi
  pass "GhidraMCP: /check_connection ($out)"

  if out=$(curl -sf -m 300 -X POST "$url/run_analysis") && [[ "$out" == *'"success":true'* ]]; then
    pass "GhidraMCP: /run_analysis"
  else
    fail "GhidraMCP: /run_analysis (got ${out:0:200})"
  fi

  out=$(curl -sf -m 30 "$url/list_functions" || true)
  compute=$(python3 -I -c '
import json, sys
funcs = json.load(sys.stdin).get("functions", [])
names = {f["name"]: f["address"] for f in funcs}
print(names["compute"] if {"compute", "helper"} <= names.keys() else "")
' <<< "$out" 2>/dev/null || true)
  if [[ -z "$compute" ]]; then
    fail "GhidraMCP: /list_functions lists helper and compute (got ${out:0:200})"
    return
  fi
  pass "GhidraMCP: /list_functions lists helper and compute"

  out=$(curl -sf -m 90 "$url/decompile_function?address=$compute" || true)
  if [[ "$out" == *0x1234abcd* && "$out" == *helper* ]]; then
    pass "GhidraMCP: /decompile_function compute"
  else
    fail "GhidraMCP: /decompile_function compute (got ${out:0:200})"
  fi

  kill "$MCP_PID" 2>/dev/null || true
  wait "$MCP_PID" 2>/dev/null || true
  MCP_PID=""
}

check_mcp
```

- [ ] **Step 3: Run it: the four GhidraMCP checks pass**

```bash
bash -n tests/run-sanity.sh && tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J" | grep -E 'GhidraMCP|passed'
```

Expected: four `PASS  GhidraMCP: ...` lines and `27 passed, 0 failed`.

- [ ] **Step 4: Interrupt during the GhidraMCP phase leaves nothing behind (Review Focus 2)**

```bash
tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J" > "$T/../int.log" 2>&1 & PID=$!
until grep -q 'Starting GhidraMCP' "$T/../int.log" 2>/dev/null; do sleep 1; done; sleep 3
kill -INT $PID; wait $PID; echo "exit=$?"
pgrep -af GhidraMCPHeadlessServer || echo "server stopped"
ls "$T" | grep sanity- || echo "no leftovers"; rm -f "$T/../int.log"
```

Expected: `exit=130`, `server stopped`, `no leftovers`.

- [ ] **Step 5: Occupied port fails cleanly**

```bash
python3 -I -m http.server 18089 --bind 127.0.0.1 > /dev/null 2>&1 & BLOCK=$!; sleep 1
tests/run-sanity.sh "$PWD/dist/ghidra_12.1.4_PUBLIC" "$J" | grep -E 'GhidraMCP|passed'; echo "exit=${PIPESTATUS[0]}"
kill $BLOCK
```

Expected: `FAIL  GhidraMCP: port 18089 is already in use (set TEST_MCP_PORT to a free port)`, `23 passed, 1 failed`, `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add tests/run-sanity.sh
git commit -m "test: add GhidraMCP end-to-end check and interrupt-safe cleanup"
```

---

### Task 6: `make test`, install pipeline and docs

**Files:**
- Modify: `Makefile` (`.PHONY`, `PIPELINE`, new `test` target)
- Modify: `README.md` (targets table, Testing section)
- Modify: `AGENTS.md` (pipeline table, pre-merge checklist, adding fixtures)
- Modify: `docs/superpowers/specs/2026-10-06-sanity-test-design.md` (amendments)

**Interfaces:**
- Consumes: `tests/run-sanity.sh <install dir> <JDK home>`.
- Produces: `make test`; `make install` runs `test` last.

- [ ] **Step 1: Confirm `make test` does not exist yet**

```bash
make -n test 2>&1 | head -1
```

Expected: `make: *** No rule to make target 'test'.  Stop.`

- [ ] **Step 2: Add the target and put it at the end of the pipeline**

In `Makefile`, add `test` to the `.PHONY` list (after `verify-extensions`). Replace

```make
PIPELINE := 00-deps 00-env 01-checkout 02-build-ghidra 03-install-ghidra 04-install-mcp \
	05-install-lx-loader 06-install-dos-toolbox verify-extensions 07-venv 08-register-mcp
```

with

```make
PIPELINE := 00-deps 00-env 01-checkout 02-build-ghidra 03-install-ghidra 04-install-mcp \
	05-install-lx-loader 06-install-dos-toolbox 07-venv 08-register-mcp test
```

and add, directly after the `verify-extensions` recipe:

```make
test: ## Run the sanity test suite (fixtures, decompiler, extensions, GhidraMCP)
	@tests/run-sanity.sh "$(INSTALL_DIR)" "$(JAVA21_HOME)"
```

Update the stage list in the header comment at the top of the `Makefile` to:

```make
#   04-install-mcp → 05-install-lx-loader → 06-install-dos-toolbox →
#   07-venv → 08-register-mcp → test
```

- [ ] **Step 3: Run it through make**

```bash
make help | grep -E ' test |verify-extensions'
make -n install | grep -c run-sanity
make test; echo "exit=$?"
```

Expected: both targets in the help; `1` (the install pipeline calls the runner once); `27 passed, 0 failed`, `exit=0`.

- [ ] **Step 4: Update the docs**

`README.md`: in the targets table, remove the `verify-extensions` row's position before `07-venv` and add both rows after `08-register-mcp`:

```markdown
| `verify-extensions` | Quick headless check that Ghidra loads every extension's classes |
| `test` | Run the sanity test suite (see Testing) |
```

and change the `install` row to `Run all of the above, in order (ends with \`test\`)`. Then add this section before `## Layout`:

```markdown
## Testing

`make test` (also the last stage of `make install`) builds three tiny programs and checks that Ghidra handles them: an i386 ELF object (core loader and decompiler), a DOS MZ file (GhidraDosToolbox loader and syscall analyzer) and an LE file (lx-loader, including an applied fixup). It then starts GhidraMCP's headless server on port 18089 (`TEST_MCP_PORT`) and checks it over HTTP. It takes about 1–2 minutes and leaves nothing behind.

Decompiled output is also compared with `tests/snapshots/`; differences are reported but never fail the run. After a deliberate Ghidra or extension upgrade, record the new output with `UPDATE_SNAPSHOTS=1 make test`. Verified on Linux arm64; macOS is untested.
```

Add `tests/` to the layout tree, after `ghidra_scripts/`:

```text
├── tests/                # make test: fixtures, expectations, snapshots, run-sanity.sh
```

and change the `ghidra_scripts/` line to `# VerifyExtensions.java, SanityCheck.java (used by make)`.

`AGENTS.md`: in the pipeline table replace the `verify-extensions` row with

```markdown
| — | `test` | Sanity suite (`tests/run-sanity.sh`): runs `verify-extensions`, imports the ELF/DOS/LE fixtures headlessly and checks them with `SanityCheck.java`, then checks GhidraMCP over HTTP on `TEST_MCP_PORT` (18089) |
```

move it after the `08` row, and change the runtime line to say `install` runs `$(PIPELINE)` ending with `test`, and that `verify-extensions` remains a standalone target. In section 4 replace the checklist item `make verify-extensions passes (needs an installed Ghidra).` with `make test passes (needs an installed Ghidra).` and add item 4:

```markdown
4. **Adding a test fixture:** build it in `tests/make_fixtures.py` (or add a C file compiled by `tests/run-sanity.sh`), list its facts in `tests/expect/<name>.txt` (grammar in the sanity-test spec, section 5), add a `run_fixture <name> <file> [loader]` line to `tests/run-sanity.sh`, then record snapshots with `UPDATE_SNAPSHOTS=1 make test`. `SanityCheck.java` needs no change.
```

In section 2.2, change "`make verify-extensions` (run by `make install`)" to "`make verify-extensions` (run by `make test`)".

`docs/superpowers/specs/2026-10-06-sanity-test-design.md`: append

```markdown
## 10. Amendments (2026-10-06, from reading the loaders while planning)

1. LE objects are `0x20` bytes each: lx-loader reads the final page of every object with the header's last-page size.
2. DOS adds `function entry contains DosTerminateErrorCode`, proving GhidraDosToolbox's `DosSyscallAnalyzer` runs (it names `INT 21h, AH=4Ch` from `data/x86_msdos6_interrupt_functions`).
3. ELF facts: `loader`, `relocations >= 2`, `function helper decompiles`, `function compute contains 0x1234abcd`, `function compute contains counter`, `function compute calls helper`.
4. The runner checks extensions with `make verify-extensions INSTALL_DIR=<install>` so it can test a copy of the install.
5. The GhidraMCP check calls `POST /run_analysis` first; the headless server imports without analyzing.
```

- [ ] **Step 5: Pre-merge checklist**

```bash
make help > /dev/null && make env | tail -1 && make -n install > /dev/null && echo "dry run OK"
bash -n tests/run-sanity.sh && echo "bash -n OK"
git status --short
```

Expected: `Environment check passed.`, `dry run OK`, `bash -n OK`; only the four modified files listed.

- [ ] **Step 6: Commit**

```bash
git add Makefile README.md AGENTS.md docs/superpowers/specs/2026-10-06-sanity-test-design.md
git commit -m "build: add make test and run it as the last install stage"
```

---

### Task 7: Prove the suite catches real failures (spec section 8)

**Files:** none changed permanently. Every scenario restores what it touches.

**Interfaces:**
- Consumes: `make test`, `tests/run-sanity.sh`.
- Produces: evidence for each scenario, pasted into the final report to the user.

Shared setup:

```bash
J="$(make -s --eval 'j: ; @echo $(JAVA21_HOME)' j)"
INSTALL="$PWD/dist/ghidra_12.1.4_PUBLIC"; T="$INSTALL/portable/temp"
```

- [ ] **Step 1: Bad expectation fails the run**

```bash
echo 'function compute contains 0xdeadbeef' >> tests/expect/sample.txt
make test | grep -E 'FAIL|passed'; echo "exit=${PIPESTATUS[0]}"
git checkout tests/expect/sample.txt
```

Expected: `FAIL  sample: function compute contains 0xdeadbeef (got decompiled C without '0xdeadbeef', ...)`, `27 passed, 1 failed`, `exit=2` (make reports the runner's exit 1 as `Error 1` and exits 2).

- [ ] **Step 2: Broken extension (renamed directory) fails both the class check and the LE import**

```bash
COPY="$T/broken-install"; cp -al "$INSTALL" "$COPY"
rm -rf "$COPY/portable" && mkdir -p "$COPY/portable"/{settings,cache,temp}
mv "$COPY/Ghidra/Extensions/lx-loader" "$COPY/Ghidra/Extensions/ghidra-lx-loader"
tests/run-sanity.sh "$COPY" "$J" | grep -E 'FAIL|passed'; echo "exit=${PIPESTATUS[0]}"
rm -rf "$COPY"
```

Expected: `FAIL  extensions: some classes are not loaded`, `FAIL  le: import failed (loader LeLoader)`, `exit=1`. Because of `cp -al`, the copy shares file contents with the real install; `portable/` is recreated empty first, so nothing in the real install is modified. Only directories are renamed, and only in the copy.

- [ ] **Step 3: Missing native decompiler fails with a clear reason (Review Focus 1)**

```bash
COPY="$T/nodecomp-install"; cp -al "$INSTALL" "$COPY"
rm -rf "$COPY/portable" && mkdir -p "$COPY/portable"/{settings,cache,temp}
rm "$COPY"/Ghidra/Features/Decompiler/os/*/decompile
tests/run-sanity.sh "$COPY" "$J" | grep -E 'native decompiler|passed'; echo "exit=${PIPESTATUS[0]}"
rm -rf "$COPY"
ls "$INSTALL"/Ghidra/Features/Decompiler/os/*/decompile
```

Expected: `function ...` facts FAIL with `got DECOMPILE FAILED: native decompiler did not start: ...`, `exit=1`; the final `ls` shows the real install's decompiler is still present (`rm` removed only the copy's hard link).

If `SanityCheck.java` throws instead of producing those lines (the run shows `SanityCheck.java did not finish`), handle the exception from `decompileFunction` in `decompile()` by returning `DECOMPILE_FAILED + e`, re-run this step, and commit the fix with `git commit -am "test: report a missing native decompiler as a FAIL"`.

- [ ] **Step 4: Snapshot drift is reported without failing**

```bash
echo '/* drift */' >> tests/snapshots/sample/compute.c
make test | sed -n '/Snapshot changes/,/after a deliberate/p'; make test > /dev/null; echo "exit=$?"
git checkout tests/snapshots
```

Expected: a `diff -u` hunk removing `/* drift */`, then the `UPDATE_SNAPSHOTS=1 make test` hint; `exit=0`.

- [ ] **Step 5: GhidraMCP unreachable fails within the timeout**

Already demonstrated in Task 5 Step 5 (occupied port → clean FAIL, exit 1). Re-run it here if `tests/run-sanity.sh` changed after Task 5.

- [ ] **Step 6: Nothing left behind**

```bash
ls -d ~/.ghidra 2>/dev/null || echo "~/.ghidra absent"
ls "$T" | grep -E 'sanity-|broken-install|nodecomp-install' || echo "portable/temp clean"
pgrep -af 'GhidraMCPHeadlessServer|AnalyzeHeadless' || echo "no test processes"
git status --short
```

Expected: `~/.ghidra absent`, `portable/temp clean`, `no test processes`, and a clean `git status`.

- [ ] **Step 7: Final full run, timed**

```bash
time make test; echo "exit=$?"
```

Expected: `27 passed, 0 failed`, snapshot report `none`, `exit=0`, and `real` around 1–2 minutes (spec success criterion). If it is much slower, note the slowest phase from the progress lines in the report rather than changing timeouts.
