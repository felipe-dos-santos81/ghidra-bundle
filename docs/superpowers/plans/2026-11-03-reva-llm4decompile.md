# ReVa and LLM4Decompile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ReVa as the bundle's ninth Ghidra extension and third MCP server, and add an LLM4Decompile refine script backed by a model that `make install` pulls into Ollama.

**Architecture:** ReVa is a pinned shallow submodule built and installed through the existing `install_extension` macro, verified by `VerifyExtensions.java`, probed headlessly through PyGhidra, and registered over HTTP by a new `register_mcp_http` macro. LLM4Decompile has no upstream Ghidra code, so the bundle ships one Java `GhidraScript` inside a scripts-only extension directory assembled by a bash script that also pulls the model with `ollama pull`. Agents reach the script through GhidraMCP's `run_ghidra_script`, which `make run` now enables.

**Tech Stack:** GNU Make, bash, Gradle (via `ghidra/gradlew`), JDK 25 (`java.net.http.HttpClient`), Ghidra 12.2 scripting API, PyGhidra, Ollama HTTP API (`/api/generate`, `raw: true`), Python 3 standard library.

**Spec:** `docs/superpowers/specs/2026-11-03-reva-llm4decompile-design.md`

## Global Constraints

- ReVa submodule path is `reverse-engineering-assistant` (upstream `https://github.com/cyberkaida/reverse-engineering-assistant.git`, branch `main`, shallow), pinned to commit `4d2fc5b4c5f4ce00d95f0bd6bdf0c64b67e65fc2`. No source patches; a 12.2 compile failure is a stop, not a guess.
- Extension directory, zip and jar are all named `reverse-engineering-assistant`; never rename.
- `REVA_PORT := 8080`, MCP server name `reva`, endpoint `http://127.0.0.1:8080/mcp/message`.
- `LLM4DECOMPILE_MODEL := hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0`; `OLLAMA_URL := http://127.0.0.1:11434`. The model identity appears in the Makefile only and reaches the script through `llm4decompile.properties`.
- Prompt format is byte-exact: `"# This is the assembly code:\n" + C + "\n# What is the source code?\n"`. Request options: `raw: true`, `stream: false`, `temperature: 0`, `num_ctx: 4096`, `num_predict: 2048`.
- Stage order after renumbering: `12-install-scripts 13-install-reva verify-extensions 14-pyghidra 15-venv 16-register-mcp 17-install-rea 18-install-llm4decompile test`. Unnumbered aliases keep their names.
- `make run` exports `GHIDRA_MCP_ALLOW_SCRIPTS=1`; the README owns that posture.
- Portable mode: nothing new under `~` except Ollama's own model store. The sanity leak check must stay green.
- Makefile recipes use tabs, `$(OK)/$(WARN)/$(ERR)`, `|| exit 1`. Bash: `set -euo pipefail`, passes `bash -n`. New Python: standard library only, run with `-I`.
- Do not push, tag, fork or publish. Do not touch D2GridraTools.

## Review Focus

Inputs the spec implies but no task's happy path exercises; each has its test pinned to the owning task.

1. **The refine script with no reachable model server** (Task 5, Task 7): a user runs it before Ollama is up. Expected: one `LLM4DECOMPILE FAIL cannot reach <url>: <reason>` line, no plate comment written, no stack trace in the GUI.
2. **Re-running the refine script on the same function** (Task 5): the plate comment must contain one LLM4Decompile block, with any user-written text above the marker preserved.
3. **A script argument naming a function that does not exist** (Task 5, Task 7): an agent passes a typo. Expected: one `LLM4DECOMPILE FAIL no function ...` line and no request to the model.
4. **A host with the script installed but Ollama absent** (Task 6, Task 7): `make install` must finish with a warning, the extension directory must exist, and `make test` must SKIP the model checks instead of failing.
5. **ReVa's jars next to GhidrAssist's older MCP SDK and Jackson** (Task 4): the ReVa probe runs inside a PyGhidra process that has every installed extension on the class path, so a class-loading clash fails the `reva` section.

## File Map

- Modify `.gitmodules`, add gitlink `reverse-engineering-assistant/`: the ReVa submodule.
- Modify `Makefile`: variables, `.PHONY`, stage `13-install-reva`, renumbered stages 14–17, stage `18-install-llm4decompile`, `register_mcp_http`, `REGISTER_OPENCODE` remote entry, `run`, `verify`, `clean`, `00-env` Ollama line, `PIPELINE`.
- Modify `ghidra_scripts/VerifyExtensions.java`: ReVa plugin check.
- Create `ghidra_scripts/LLM4DecompileRefine.java`: the refine script (source of truth; copied into the extension at install).
- Create `scripts/install-llm4decompile.sh`: assembles `Ghidra/Extensions/LLM4Decompile/` and pulls the model.
- Create `tests/probes/reva_probe.py`: starts ReVa's headless launcher under PyGhidra and performs an MCP `initialize`.
- Modify `tests/run-sanity.sh`: `PACKAGE_PATTERNS`, `BUILD_OUTPUTS`, new sections `reva` and `llm4decompile`.
- Modify `README.md`, `AGENTS.md`: components, MCP servers, stage table, invariants, notes.
- Modify `docs/superpowers/specs/2026-11-03-reva-llm4decompile-design.md`: status line and the random-port amendment, at the end.

---

### Task 1: ReVa submodule and install stage

**Files:**
- Modify: `.gitmodules` (append after the `plugin-ghidra` entry)
- Modify: `Makefile:104-112` (`.PHONY`), `:243` (section banner), `:347-379` (stage 13 and aliases), `:381-440` (stages 14–16), `:442-471` (stage 17), `:475-479` (`PIPELINE`), `:512-521` (`clean`)

**Interfaces:**
- Produces: target `13-install-reva` (alias `install-reva`), extension at `$(EXT_DIR)/reverse-engineering-assistant/lib/reverse-engineering-assistant.jar`, zip `dist/packages/ghidra_12.2_*_reverse-engineering-assistant.zip`.

- [ ] **Step 1: Add the submodule**

```bash
git submodule add --depth 1 -b main https://github.com/cyberkaida/reverse-engineering-assistant.git reverse-engineering-assistant
git -C reverse-engineering-assistant fetch --depth 1 origin 4d2fc5b4c5f4ce00d95f0bd6bdf0c64b67e65fc2
git -C reverse-engineering-assistant checkout 4d2fc5b4c5f4ce00d95f0bd6bdf0c64b67e65fc2
```

Then add `shallow = true` to its `.gitmodules` entry, matching the other entries.

- [ ] **Step 2: Verify the pin**

Run: `git -C reverse-engineering-assistant rev-parse HEAD && git diff --cached --stat`
Expected: `4d2fc5b4c5f4ce00d95f0bd6bdf0c64b67e65fc2`, and `.gitmodules` plus the new gitlink staged.

- [ ] **Step 3: Renumber stages 13–16 in the Makefile**

Rename targets, their `## ` help lines, aliases, `.PHONY` entries, section banners and `PIPELINE`: `13-pyghidra`→`14-pyghidra`, `14-venv`→`15-venv`, `15-register-mcp`→`16-register-mcp`, `16-install-rea`→`17-install-rea`. Prerequisites that name a stage (`16-register-mcp: 15-venv`) move with them. The aliases `pyghidra`, `venv`, `register-mcp`, `install-rea` keep their names.

- [ ] **Step 4: Add stage 13 after `12-install-scripts`**

```make
13-install-reva: 03-install-ghidra ## Build and install ReVa (MCP server on port 8080)
	$(call install_extension,reverse-engineering-assistant,reverse-engineering-assistant,reverse-engineering-assistant/dist/ghidra_$(GHIDRA_VERSION)_*_reverse-engineering-assistant.zip,,,reverse-engineering-assistant)
```

Add `install-reva: 13-install-reva` to the alias block, `13-install-reva install-reva` to `.PHONY`, and `reverse-engineering-assistant/dist reverse-engineering-assistant/build reverse-engineering-assistant/.gradle` to `clean`. Insert `13-install-reva` into `PIPELINE` between `12-install-scripts` and `verify-extensions`.

- [ ] **Step 5: Check the Makefile expands**

Run: `make help && make -n install >/dev/null && make -n 13-install-reva | head -5`
Expected: help lists `13-install-reva`; no `*** missing` errors; the dry run shows a `gradlew ... buildExtension` line for `reverse-engineering-assistant`.

- [ ] **Step 6: Build and install ReVa**

Run: `make 13-install-reva 2>&1 | tail -5`
Expected: ends with `reverse-engineering-assistant installed (ghidra_12.2_PUBLIC_<date>_reverse-engineering-assistant.zip in .../dist/packages).` If Gradle reports Java compile errors against Ghidra 12.2, stop and report; do not patch.

- [ ] **Step 7: Confirm the jar naming rule and idempotence**

Run: `ls dist/ghidra_12.2_PUBLIC/Ghidra/Extensions/reverse-engineering-assistant/lib/ && make 13-install-reva`
Expected: `reverse-engineering-assistant.jar` is listed; the second run prints `reverse-engineering-assistant already installed from 4d2fc5b, skipping.`

- [ ] **Step 8: Commit**

```bash
git add .gitmodules reverse-engineering-assistant Makefile
git commit -m "feat: add ReVa as the ninth extension"
```

---

### Task 2: Verify ReVa loads, and guard its packages

**Files:**
- Modify: `ghidra_scripts/VerifyExtensions.java:33`
- Modify: `tests/run-sanity.sh:360-382` (`PACKAGE_PATTERNS`, `BUILD_OUTPUTS`)

- [ ] **Step 1: Add the ReVa plugin check**

After the `plugin-ghidra` line in `VerifyExtensions.run()`:

```java
check("reverse-engineering-assistant", Plugin.class, "RevaPlugin");
```

- [ ] **Step 2: Run the verifier**

Run: `make verify-extensions`
Expected: a line `OK reverse-engineering-assistant: RevaPlugin` and `All extension classes loaded.`

- [ ] **Step 3: Add the package and build-output guards**

Append `"ghidra_{v}_*_reverse-engineering-assistant.zip"` to `PACKAGE_PATTERNS` and `reverse-engineering-assistant/dist` to `BUILD_OUTPUTS`.

- [ ] **Step 4: Run the dist and extensions sections**

Run: `SANITY_ONLY=extensions,dist make test 2>&1 | tail -20`
Expected: `PASS dist: packages/ has ghidra_12.2_*_reverse-engineering-assistant.zip`, `PASS dist: reverse-engineering-assistant/dist holds no current zip`, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add ghidra_scripts/VerifyExtensions.java tests/run-sanity.sh
git commit -m "test: verify ReVa's plugin class and package"
```

---

### Task 3: HTTP MCP registration, ports and script execution

**Files:**
- Modify: `Makefile:14` (after `MCP_PORT`), `:394-437` (`REGISTER_OPENCODE`, `register_mcp`, stage 16), `:492-508` (`run`, `verify`)

**Interfaces:**
- Produces: `REVA_PORT := 8080`; macro `$(call register_mcp_http,name,url)`; `16-register-mcp` registers both `ghidra` and `reva`.

- [ ] **Step 1: Add the port variable**

`REVA_PORT := 8080` directly below `MCP_PORT := 8089`.

- [ ] **Step 2: Teach `REGISTER_OPENCODE` about remote servers**

Replace the `entry = ...` line so that `MCP_URL`, when set in the environment, wins:

```python
url = os.environ.get("MCP_URL")
entry = ({"type": "remote", "url": url, "enabled": True} if url
         else {"type": "local", "command": json.loads(os.environ["MCP_COMMAND"]), "enabled": True})
```

- [ ] **Step 3: Add `register_mcp_http` below `register_mcp`**

```make
# $(call register_mcp_http,name,url): register a streamable-HTTP MCP server with opencode and Claude Code.
define register_mcp_http
	mkdir -p "$(dir $(OPENCODE_CONFIG))"; \
	MCP_NAME=$(1) MCP_URL='$(2)' python3 -c "$$REGISTER_OPENCODE" || exit 1; \
	if ! command -v claude >/dev/null 2>&1; then \
		$(WARN) "claude CLI not found, skipping Claude Code registration."; \
	elif claude mcp get $(1) 2>/dev/null | grep -qF "$(2)"; then \
		echo "Claude Code: $(1) MCP server already registered"; \
	else \
		claude mcp remove $(1) --scope user >/dev/null 2>&1; \
		claude mcp add --scope user --transport http $(1) "$(2)" || exit 1; \
	fi
endef
```

- [ ] **Step 4: Register `reva` in stage 16**

```make
16-register-mcp: 15-venv ## Register the "ghidra" and "reva" MCP servers with opencode and Claude Code
	@$(call register_mcp,ghidra,$(BRIDGE_BIN))
	@$(call register_mcp_http,reva,http://127.0.0.1:$(REVA_PORT)/mcp/message)
```

- [ ] **Step 5: Run the registration twice**

Run: `make 16-register-mcp && make 16-register-mcp && claude mcp get reva && python3 -c 'import json, os; print(json.load(open(os.path.expanduser("~/.config/opencode/opencode.json")))["mcp"]["reva"])'`
Expected: the second run prints `already registered` for both clients; `claude mcp get reva` shows type http and the URL; the opencode entry is `{'type': 'remote', 'url': 'http://127.0.0.1:8080/mcp/message', 'enabled': True}`.

- [ ] **Step 6: Change `run` and `verify`**

In `run`: keep the 8089 check as an error; add a second check of `$(REVA_PORT)` that only calls `$(WARN) "port $(REVA_PORT) is already in use; ReVa will not be able to listen (see above)"`; launch with `GHIDRA_MCP_ALLOW_SCRIPTS=1 "$(INSTALL_DIR)/ghidraRun"`. Update the `## ` line to `Launch Ghidra with script execution enabled for GhidraMCP (fails if port 8089 is in use)`.

In `verify`: after the GhidraMCP probe, add
```make
	@curl -sf -m 10 -o /dev/null -X POST -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
		-d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"make-verify","version":"0"}}}' \
		http://127.0.0.1:$(REVA_PORT)/mcp/message && $(OK) "ReVa is answering on port $(REVA_PORT)." || \
		$(WARN) "no ReVa on port $(REVA_PORT): enable the ReVa plugins in Ghidra (see README)"
```

- [ ] **Step 7: Check the dry runs**

Run: `make -n run | grep -c GHIDRA_MCP_ALLOW_SCRIPTS; make -n verify | grep -c mcp/message`
Expected: `1` and `1`.

- [ ] **Step 8: Commit**

```bash
git add Makefile
git commit -m "feat: register ReVa over HTTP and enable GhidraMCP scripts in make run"
```

---

### Task 4: ReVa sanity section

**Files:**
- Create: `tests/probes/reva_probe.py`
- Modify: `tests/run-sanity.sh:9-10,36` (section list), after `check_pyghidra` (new `check_reva` and its `want` block)

**Interfaces:**
- Consumes: `pyghidraRun -H` invocation shape from `check_pyghidra` (`tests/run-sanity.sh:551-557`).
- Produces: section `reva`; probe prints `REVA OK port <n>` or `REVA FAIL <reason>`.

- [ ] **Step 1: Write the probe**

`tests/probes/reva_probe.py`, header comment in the style of `mpq_probe.py` with `# @category Bundle` and `# @runtime PyGhidra`. Body: start `RevaHeadlessLauncher(None, True)` (in-memory config, random port) so no port collides; `waitForServer(60000)` else print `REVA FAIL server did not start`; POST to `http://127.0.0.1:{launcher.getPort()}/mcp/message` with `urllib.request`, headers `Content-Type: application/json` and `Accept: application/json, text/event-stream`, body the `initialize` JSON-RPC request from Task 3 step 6 with `clientInfo.name` `"sanity"`; read the body as text; print `REVA OK port <n>` when it contains `"protocolVersion"`, otherwise `REVA FAIL HTTP <status>: <first 200 chars>`; always `launcher.stop()` in `finally`.

Import: `from reva.headless import RevaHeadlessLauncher` (ReVa's documented PyGhidra usage). If that import fails under `pyghidraRun`, use `jpype.JClass("reva.headless.RevaHeadlessLauncher", loader=jpype.JClass("java.lang.ClassLoader").getSystemClassLoader())` — the class lives in an extension jar that Ghidra's loader, not the JVM default, knows.

- [ ] **Step 2: Add the section**

Add `reva` to the usage comment and to `SECTIONS` after `pyghidra`. Then:

```bash
# ── 3h. ReVa ──────────────────────────────────────────────────────────────────
check_reva() {
  local log="$WORK/reva.log" ext="$INSTALL_DIR/Ghidra/Extensions/reverse-engineering-assistant" venv path status=0
  if [[ ! -f "$ext/lib/reverse-engineering-assistant.jar" ]]; then
    fail "ReVa: $ext/lib/reverse-engineering-assistant.jar is missing (run 'make install-reva')"
    return
  fi
  venv=$(python3 -I "$REPO_DIR/scripts/pyghidra-venv-dir.py" "$INSTALL_DIR") || { fail "ReVa: no PyGhidra venv"; return; }
  path=$PATH
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then path=${path//"$VIRTUAL_ENV/bin:"/}; fi
  (cd "$WORK" && env -u VIRTUAL_ENV PATH="$path" "$TIMEOUT" --foreground "${TEST_IMPORT_TIMEOUT:-600}" \
    "$INSTALL_DIR/support/pyghidraRun" -H "$WORK/proj" "reva-$RANDOM" \
    -import "$WORK/probe.bin" -loader BinaryLoader -processor x86:LE:32:default -noanalysis \
    -deleteProject -scriptPath "$TESTS/probes" -preScript reva_probe.py < /dev/null > "$log" 2>&1) || status=$?
  ((status == 0)) || echo "pyghidraRun exit status $status" >> "$log"
  if grep -q 'REVA OK' "$log"; then
    pass "ReVa: headless MCP server answers initialize ($(grep -o 'REVA OK port [0-9]*' "$log" | head -n 1))"
  else
    fail_with_log "ReVa: headless MCP server did not answer initialize" "$log"
  fi
}

if want reva; then check_reva; fi
```

Place it after the `pyghidra` block and renumber the later banners (`3i. REA`).

- [ ] **Step 3: Run it**

Run: `SANITY_ONLY=reva make test 2>&1 | tail -8`
Expected: `PASS ReVa: headless MCP server answers initialize (REVA OK port <n>)`, 0 failed. A `NoSuchMethodError`, `ClassCastException` or Jackson/MCP-SDK linkage error in the log is the GhidrAssist jar clash: stop and report it with the log excerpt.

- [ ] **Step 4: Run the leak check alongside**

Run: `SANITY_ONLY=reva,portable make test 2>&1 | grep -E 'portable:|failed'`
Expected: `PASS portable: no writes outside portable/ were detected`, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add tests/probes/reva_probe.py tests/run-sanity.sh
git commit -m "test: probe ReVa's headless MCP server through PyGhidra"
```

---

### Task 5: The refine script

**Files:**
- Create: `ghidra_scripts/LLM4DecompileRefine.java`

**Interfaces:**
- Produces: a `GhidraScript` named `LLM4DecompileRefine`, `//@category LLM4Decompile`, script argument `[function name or address]`. Console lines: `LLM4DECOMPILE OK <function> <chars> chars`, `LLM4DECOMPILE WARN ...`, `LLM4DECOMPILE FAIL <reason>`. Configuration: `llm4decompile.properties` two directories above the script source file (`model=`, `url=`), overridden by env `LLM4DECOMPILE_MODEL` and `LLM4DECOMPILE_URL`, defaulting to `hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0` and `http://127.0.0.1:11434`.
- Consumed by: Task 6 (copied into the extension), Task 7 (run headlessly).

- [ ] **Step 1: Write the script**

Structure, one private method each:

- `Function target()`: headless with an argument → `getFunction(arg)` then `getFunctionAt(parseAddress(arg))`; otherwise `getFunctionContaining(currentAddress)`. Null → `fail("no function at ...")`.
- `String decompile(Function f)`: `DecompInterface` with `openProgram(currentProgram)`, `decompileFunction(f, 60, monitor)`, return `getDecompiledFunction().getC()`; dispose in `finally`. Null or failed → `fail("decompiler: " + errorMessage)`.
- `String[] config()`: returns `{model, url}` from env, else the properties file at `getSourceFile().getParentFile().getParentFile()` + `/llm4decompile.properties`, else the defaults.
- `String refine(String url, String model, String pseudoC)`: warn when `pseudoC.length() > 6000` (`LLM4DECOMPILE WARN pseudo-C is <n> chars; the model's 4096-token context may truncate the answer`); POST JSON to `url + "/api/generate"` with `HttpClient` (connect timeout 10 s, request timeout 10 min); non-200 → `fail("HTTP <code>: <body>")`; connection error → `fail("cannot reach " + url + ": " + e.getMessage())`; return the `response` string. Build the request JSON with `java.util.Map` and the escaping Ghidra ships (`com.google.gson.Gson`, on Ghidra's class path), and parse the reply with `JsonParser`. Empty response → `fail("empty response from " + model)`.
- `void writeComment(Function f, String model, String c)`: marker `"--- LLM4Decompile (" + model + ") ---"`; existing plate comment with the marker → keep text before the marker's line, trimmed, and print `LLM4DECOMPILE REPLACED`; new comment = kept text + (blank line if non-empty) + marker + `\n` + c; `f.setComment(...)` is not plate: use `currentProgram.getListing().setComment(f.getEntryPoint(), CodeUnit.PLATE_COMMENT, text)`.
- `run()`: wire them, print `LLM4DECOMPILE OK <name> <c.length()> chars` then the C, and `monitor.checkCancelled()` between steps.
- `fail(String reason)`: `printerr("LLM4DECOMPILE FAIL " + reason)`; headless (`isRunningHeadless()`) → `throw new RuntimeException(reason)`; GUI → `popup(reason)` then throw `CancelledException` so nothing is written.

- [ ] **Step 2: Compile it the way Ghidra will**

Nothing compiles this file before Ghidra does, so run it headlessly on a raw two-byte program (no functions) with a bogus function name:
```bash
S=/tmp/claude-1000/-home-felipe-code-ghidra-bundle/1d0acf15-6c4c-4181-b470-d7d421e3f2ee/scratchpad; mkdir -p "$S/l4d"; printf '\x90\xc3' > "$S/l4d/probe.bin"
LLM4DECOMPILE_URL=http://127.0.0.1:1 dist/ghidra_12.2_PUBLIC/support/analyzeHeadless "$S/l4d" proj -import "$S/l4d/probe.bin" -loader BinaryLoader -processor x86:LE:32:default -noanalysis -deleteProject -scriptPath ghidra_scripts -postScript LLM4DecompileRefine.java nosuchfn 2>&1 | grep -E 'LLM4DECOMPILE|error:|Exception'
```
Expected: no `error:` compile lines; exactly one `LLM4DECOMPILE FAIL no function nosuchfn` line and no `cannot reach` (the request is never sent). Adjust until that is the output.

- [ ] **Step 3: Exercise the unreachable-server path on a real function**

Run the same command against the compiled ELF fixture: first `clang --target=i386-unknown-linux-gnu -O1 -fno-pic -c tests/fixtures/sample.c -o <scratchpad>/sample.o`, then `analyzeHeadless ... -import <scratchpad>/sample.o -deleteProject -scriptPath ghidra_scripts -postScript LLM4DecompileRefine.java compute` with `LLM4DECOMPILE_URL=http://127.0.0.1:1`.
Expected: `LLM4DECOMPILE FAIL cannot reach http://127.0.0.1:1: ...` and no `LLM4DECOMPILE OK`.

- [ ] **Step 4: Exercise the happy path against the local Ollama (if the model is present)**

Run the step 3 command without the URL override and with the script listed twice, `-postScript LLM4DecompileRefine.java compute -postScript LLM4DecompileRefine.java compute`, piped to `grep -E 'LLM4DECOMPILE|^[{}]'`.
Expected: two `LLM4DECOMPILE OK compute <n> chars` lines, one `LLM4DECOMPILE REPLACED` line (the second run replaced the first block rather than stacking it), and C containing `{`. Skip this step when `ollama show hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0` fails (Task 6 pulls the model); Task 7 covers it in the suite.

- [ ] **Step 5: Commit**

```bash
git add ghidra_scripts/LLM4DecompileRefine.java
git commit -m "feat: add LLM4DecompileRefine Ghidra script"
```

---

### Task 6: LLM4Decompile install stage and model pull

**Files:**
- Create: `scripts/install-llm4decompile.sh`
- Modify: `Makefile:14-16` (variables), `:104-112` (`.PHONY`), `:159-182` (`00-env`), after stage 17 (new stage 18 and alias), `:475-479` (`PIPELINE`), `:512-521` (`clean`)

**Interfaces:**
- Consumes: `ghidra_scripts/LLM4DecompileRefine.java` (Task 5).
- Produces: `$(EXT_DIR)/LLM4Decompile/{extension.properties,Module.manifest,llm4decompile.properties,ghidra_scripts/LLM4DecompileRefine.java,.bundle-source}`; target `18-install-llm4decompile` (alias `install-llm4decompile`); Makefile variables `LLM4DECOMPILE_MODEL`, `OLLAMA_URL`.

- [ ] **Step 1: Write the install script**

`scripts/install-llm4decompile.sh <script file> <Ghidra Extensions dir> <Ghidra version> <model> <ollama url>`, modelled on `install-d2gridratools.sh`:

1. `stamp="$(git hash-object "$SCRIPT") $(git hash-object "${BASH_SOURCE[0]}") $MODEL $URL"`; when `$DEST/.bundle-source` equals it, print `LLM4Decompile scripts already installed, skipping.` and go to step 3.
2. Assemble into a `mktemp -d "$EXT_DIR/.LLM4Decompile-XXXXXX"`: `extension.properties` (`name=LLM4Decompile`, description naming the model and `github.com/albertan017/LLM4Decompile`, `author=ghidra-bundle`, `version=$VERSION`), empty `Module.manifest`, `llm4decompile.properties` with `model=$MODEL` and `url=$URL`, `ghidra_scripts/LLM4DecompileRefine.java` copied, `.bundle-source`; `rm -rf "$DEST"; mv`.
3. Pull: `command -v ollama` fails or `ollama list >/dev/null 2>&1` fails → print a yellow `WARNING: Ollama not found or not serving; skipping the LLM4Decompile model pull (optional). Pull it later with: ollama pull $MODEL` and `exit 0`. `ollama show "$MODEL" >/dev/null 2>&1` → `already pulled, skipping.` Else `ollama pull "$MODEL"` ; on failure warn `could not pull $MODEL (no network or disk?)` and `exit 0`.

- [ ] **Step 2: Lint it**

Run: `bash -n scripts/install-llm4decompile.sh && chmod +x scripts/install-llm4decompile.sh`
Expected: no output.

- [ ] **Step 3: Wire the Makefile**

Variables under `REVA_PORT`:
```make
LLM4DECOMPILE_MODEL := hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0
OLLAMA_URL := http://127.0.0.1:11434
```
Stage after `install-rea: 17-install-rea`:
```make
# ── Stage 18: LLM4Decompile ───────────────────────────────────────────────────

18-install-llm4decompile: 03-install-ghidra ## Install the LLM4Decompile refine script and pull its model into Ollama (optional)
	@scripts/install-llm4decompile.sh ghidra_scripts/LLM4DecompileRefine.java "$(EXT_DIR)" "$(GHIDRA_VERSION)" \
		"$(LLM4DECOMPILE_MODEL)" "$(OLLAMA_URL)"

install-llm4decompile: 18-install-llm4decompile
```
Append `18-install-llm4decompile` to `PIPELINE` after `17-install-rea` and before `test`; add both names to `.PHONY`. In `00-env`, after the Node.js block:
```make
	@if command -v ollama >/dev/null 2>&1 && ollama list >/dev/null 2>&1; then \
		$(TICK) "Ollama" "$$(ollama --version 2>&1 | head -n 1) (LLM4Decompile)"; \
	else \
		$(WARN) "Ollama not found or not serving: optional, needed to run the LLM4Decompile model"; \
	fi
```
Update the `00-env` `## ` line to `Check host prerequisites (StormLib, Node.js and Ollama optional)`. In the `test` target, add `LLM4DECOMPILE_MODEL="$(LLM4DECOMPILE_MODEL)"` to the environment given to `tests/run-sanity.sh`, next to `PACKAGES_DIR` and `REA_BIN`. `clean` already removes `dist/`, which holds the extension; nothing to add.

- [ ] **Step 4: Run the stage (this pulls about 10 GB)**

Run: `make env | tail -3 && make 18-install-llm4decompile && make 18-install-llm4decompile`
Expected: `✔ Ollama`; first run assembles the extension and pulls the model (Ollama shows progress); the second run prints both `already installed` and `already pulled` lines.

- [ ] **Step 5: Confirm the extension contents and the Ollama-absent path**

Run: `ls -a dist/ghidra_12.2_PUBLIC/Ghidra/Extensions/LLM4Decompile dist/ghidra_12.2_PUBLIC/Ghidra/Extensions/LLM4Decompile/ghidra_scripts && cat dist/ghidra_12.2_PUBLIC/Ghidra/Extensions/LLM4Decompile/llm4decompile.properties && PATH=/usr/bin:/bin scripts/install-llm4decompile.sh ghidra_scripts/LLM4DecompileRefine.java dist/ghidra_12.2_PUBLIC/Ghidra/Extensions 12.2 x http://127.0.0.1:1; echo "exit $?"`
Expected: the five files; `model=hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0` and `url=http://127.0.0.1:11434`; the stripped-PATH run (no `ollama`) rewrites the extension for model `x`, prints the WARNING and exits 0. Then rerun `make 18-install-llm4decompile` to restore the real properties.

- [ ] **Step 6: Commit**

```bash
git add scripts/install-llm4decompile.sh Makefile
git commit -m "feat: install the LLM4Decompile script and pull its model into Ollama"
```

---

### Task 7: LLM4Decompile sanity section

**Files:**
- Modify: `tests/run-sanity.sh:9-10,36` (section list), after `check_reva` (new `check_llm4decompile` and its `want` block)

**Interfaces:**
- Consumes: `run_script` (`tests/run-sanity.sh:170-179`), `$SAMPLE`, the extension layout from Task 6, console lines from Task 5.

- [ ] **Step 1: Add the section**

Add `llm4decompile` to the usage comment and `SECTIONS` after `reva`.

```bash
# ── 3j. LLM4Decompile ─────────────────────────────────────────────────────────
check_llm4decompile() {
  local ext="$INSTALL_DIR/Ghidra/Extensions/LLM4Decompile" log="$WORK/llm4decompile.log"
  local script="$ext/ghidra_scripts/LLM4DecompileRefine.java" model url want_model
  if [[ ! -f "$script" || ! -f "$ext/llm4decompile.properties" ]]; then
    fail "LLM4Decompile: $ext is incomplete (run 'make install-llm4decompile')"
    return
  fi
  model=$(sed -n 's/^model=//p' "$ext/llm4decompile.properties")
  url=$(sed -n 's/^url=//p' "$ext/llm4decompile.properties")
  want_model=${LLM4DECOMPILE_MODEL:-}  # exported by the Makefile's test target
  if [[ -n "$model" && ( -z "$want_model" || "$model" == "$want_model" ) ]]; then
    pass "LLM4Decompile: properties name the Makefile's model ($model)"
  else
    fail "LLM4Decompile: properties model '$model' differs from the Makefile's '$want_model'"
  fi
  if [[ -z "$SAMPLE" ]]; then
    fail "LLM4Decompile: not checked (needs sample.o, which clang could not build)"
    return
  fi
  # Unknown function, then unreachable server: the script must compile, print one FAIL
  # line each and never an OK line. run_script returns 0 even when a script throws.
  LLM4DECOMPILE_URL=http://127.0.0.1:1 run_script "$log" "$SAMPLE" LLM4DecompileRefine.java nosuchfn \
    -postScript LLM4DecompileRefine.java compute || true
  if grep -q 'LLM4DECOMPILE FAIL no function nosuchfn' "$log" \
      && grep -q 'LLM4DECOMPILE FAIL cannot reach http://127.0.0.1:1' "$log" \
      && ! grep -q 'LLM4DECOMPILE OK' "$log"; then
    pass "LLM4Decompile: script compiles and reports a bad function and an unreachable server"
  else
    fail_with_log "LLM4Decompile: error runs did not report cleanly" "$log"
    return
  fi
  if ! curl -sf -m 5 "$url/api/version" >/dev/null 2>&1; then
    skip "LLM4Decompile: Ollama is not serving at $url (optional)"
    return
  fi
  if ! ollama show "$model" >/dev/null 2>&1; then
    skip "LLM4Decompile: model $model is not pulled (run 'make install-llm4decompile')"
    return
  fi
  run_script "$log" "$SAMPLE" LLM4DecompileRefine.java compute -postScript LLM4DecompileRefine.java compute || true
  if (($(grep -c 'LLM4DECOMPILE OK compute' "$log") == 2)) && grep -q 'LLM4DECOMPILE REPLACED' "$log" \
      && sed -n '/LLM4DECOMPILE OK compute/,$p' "$log" | grep -q '{'; then
    pass "LLM4Decompile: refined compute twice through $model ($(grep -o 'LLM4DECOMPILE OK compute [0-9]* chars' "$log" | head -n 1))"
  else
    fail_with_log "LLM4Decompile: refining compute failed" "$log"
  fi
}

if want llm4decompile; then check_llm4decompile; fi
```

`run_script` resolves scripts from `ghidra_scripts/` and `tests/probes/`; the installed extension copy is identical to the repo file (Task 6 stamps its hash), so running the repo copy is the same code. `run_script` appends its remaining arguments verbatim after `-postScript <script>`, so a caller can pass `-postScript B.java y` to run a second post-script in the same import; no change to `run_script` is needed.

- [ ] **Step 2: Run it**

Run: `SANITY_ONLY=llm4decompile make test 2>&1 | tail -8`
Expected: three PASS lines (`properties name`, `compiles and reports`, `refined compute twice`), 0 failed. Generation takes seconds on this machine.

- [ ] **Step 3: Run it with the model hidden to see the SKIP path**

Run: `OLLAMA_HOST=127.0.0.1:1 SANITY_ONLY=llm4decompile make test 2>&1 | tail -6`
Expected: two PASS lines and `SKIP LLM4Decompile: model ... is not pulled` (Ollama's CLI honours `OLLAMA_HOST`, so `ollama show` fails while the properties URL still answers). 0 failed.

- [ ] **Step 4: Commit**

```bash
git add tests/run-sanity.sh
git commit -m "test: cover the LLM4Decompile script and model"
```

---

### Task 8: Documentation

**Files:**
- Modify: `README.md:3,5-18` (intro and table), `:33-53` (MCP section), `:63` (testing), `:91-121` (layout), `:123-128` (notes)
- Modify: `AGENTS.md:9-21` (overview), `:36-45` (2.2 placement), `:46-66` (2.3 submodules), `:76-79` (2.5 ports), `:86` and `:127-130` (stage numbers and table), after 2.9 (new 2.10 and 2.11), `:144` (standards)

- [ ] **Step 1: README**

- Intro: "nine extensions" and "two MCP servers inside Ghidra plus REA". Table rows for `ReVa` (link, "MCP server on 127.0.0.1:8080 for AI assistants; small tools that spare context") and `LLM4Decompile` (link, "Ghidra script that refines a function's pseudo-C with the 9B-v2 model served by Ollama; `make install` pulls the model (about 10 GB) when Ollama is present").
- Quickstart paragraph: Ollama is optional and not installed automatically; without it the LLM4Decompile pull is skipped.
- "Using the MCP server" becomes "Using the MCP servers": keep the GhidraMCP steps; add a "ReVa" subsection: enable `ReVa Application Plugin` (project window) and `ReVa Plugin` (CodeBrowser) once via File → Configure → the plug icon, Save Tool; it listens on 127.0.0.1:8080; `claude mcp get reva`; `make verify` warns until it answers; its script tools run Python under PyGhidra only; an API key can be enabled in its options if the port is ever exposed.
- New paragraph "Script execution": `make run` sets `GHIDRA_MCP_ALLOW_SCRIPTS=1`, so GhidraMCP's `run_ghidra_script` and `run_script_inline` run arbitrary Ghidra scripts for any client on 127.0.0.1:8089, as the user. To keep them off, start `dist/ghidra_12.2_PUBLIC/ghidraRun` directly.
- New "LLM4Decompile" subsection: what the script does (plate comment + console), GUI use (Script Manager → LLM4Decompile → `LLM4DecompileRefine.java` with the cursor in a function), headless use (`analyzeHeadless ... -postScript LLM4DecompileRefine.java <function>`), agent use (`run_ghidra_script` with `script_name` `LLM4DecompileRefine.java` and `args` the function name), overrides `LLM4DECOMPILE_URL` / `LLM4DECOMPILE_MODEL`, the pull line `ollama pull hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0`, removal `ollama rm ...`, and the notes: third-party GGUF, DeepSeek Model License on the weights, quality claims hold for GCC Linux x86-64, the function's pseudo-C goes wherever the URL points.
- Testing paragraph: add ReVa and LLM4Decompile to the list; LLM4Decompile model checks skip without Ollama or the model.
- Layout: add `reverse-engineering-assistant/` submodule line, `Ghidra/Extensions/` comment gains `reverse-engineering-assistant/, LLM4Decompile/`; `scripts/` comment mentions LLM4Decompile.
- Notes: "Directory names matter" adds `reverse-engineering-assistant`; "Rebuilding" adds that the LLM4Decompile extension rebuilds when the script, installer, model or URL changes, and that the model stays in Ollama's store across `make clean`.

- [ ] **Step 2: AGENTS.md**

- Overview: "nine extensions"; bullets for **ReVa** and **LLM4Decompile** (one line each, as in README).
- 2.2: add `reverse-engineering-assistant/` (`lib/reverse-engineering-assistant.jar`) and `LLM4Decompile/` (scripts only, assembled by `scripts/install-llm4decompile.sh`) to the list; the "submodule paths must not change" line gains `reverse-engineering-assistant`.
- 2.3: submodule bullet `reverse-engineering-assistant` (cyberkaida/reverse-engineering-assistant, `main`, pinned to commit `4d2fc5b`; no 12.2 release exists yet; builds without source patches).
- 2.5 becomes "Ports": 8089 GhidraMCP (error), 8080 ReVa (`REVA_PORT`, warning only, set in ReVa's tool options), `make run` exports `GHIDRA_MCP_ALLOW_SCRIPTS=1`, `make test` uses 18089 and a random ReVa port.
- 2.7 and the table: renumber 13→14 (pyghidra), 14→15, 15→16, 16→17; `verify-extensions` row stays before `14-pyghidra`; add rows `13` (`13-install-reva`, `install-reva`), `18` (`18-install-llm4decompile`, `install-llm4decompile`); the `test` row lists `reva` and `llm4decompile` sections; the `16-register-mcp` row registers `ghidra` and `reva` (`register_mcp_http`).
- New **2.10 ReVa**: GUI settings are tool options under `portable/settings`; headless probe via `tests/probes/reva_probe.py` on a random port; ReVa's script tool is Python-only and needs a PyGhidra-launched GUI; MCP SDK/Jackson coexistence with GhidrAssist is verified by the `reva` section, and a clash is a stop.
- New **2.11 LLM4Decompile**: one Makefile variable `LLM4DECOMPILE_MODEL`, written to `llm4decompile.properties`; `ghidra_scripts/LLM4DecompileRefine.java` is the source of truth; prompt format and request options verbatim; model in Ollama's store, outside `portable/` by design; stage and section skip semantics; never run the pull in tests.
- Standards 1: "Add new extensions ..." stays; add "scripts-only extensions follow `install-llm4decompile.sh`/`install-d2gridratools.sh`".

- [ ] **Step 3: Check rendering and references**

Run: `grep -n -E '1[3-8]-[a-z-]+' AGENTS.md README.md | grep -v -E '13-install-reva|14-pyghidra|15-venv|16-register-mcp|17-install-rea|18-install-llm4decompile'`
Expected: no output (no stale stage numbers).

- [ ] **Step 4: Commit**

```bash
git add README.md AGENTS.md
git commit -m "docs: describe ReVa, LLM4Decompile and script execution"
```

---

### Task 9: Full verification and spec closure

**Files:**
- Modify: `docs/superpowers/specs/2026-11-03-reva-llm4decompile-design.md:4` (status) and section 3.4 (random port amendment)

- [ ] **Step 1: Pre-merge checklist**

Run, in order:
```bash
make help
make env
make -n install > /dev/null && echo expands
python3 -I tests/test_prepare_extension_source.py
make test 2>&1 | tail -40
git status --short
```
Expected: help lists stages 00–18 in order; env passes with `✔ Ollama`; `expands`; the Python tests pass; `make test` ends `N passed, 0 failed, M skipped` with the `reva` and `llm4decompile` sections PASS and `portable: no writes outside portable/`; `git status` shows only the spec file.

- [ ] **Step 2: Amend the spec**

Set `Status: approved 2026-11-03; implemented` and add to section 3.4: "Amendment: the probe uses ReVa's random-port mode and reads `getPort()`, so no `TEST_REVA_PORT` exists." Add the same to section 2's port row in one clause.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-11-03-reva-llm4decompile-design.md docs/superpowers/plans/2026-11-03-reva-llm4decompile.md
git commit -m "docs: mark the ReVa and LLM4Decompile design implemented"
```
