# ReVa and LLM4Decompile — Design

Date: 2026-11-03
Status: approved 2026-11-03; implemented (see amendments in sections 2 and 3.4)

## 1. Goal

Add two of the AI-assisted reverse-engineering projects from a Reddit round-up
("AI agents can now work inside Ghidra, radare2, and IDA. Here are 7 repos that
explain how") to the bundle:

- **ReVa** (cyberkaida/reverse-engineering-assistant): a Ghidra extension that
  serves an MCP endpoint over streamable HTTP, with small, context-sparing
  tools. Installed as the ninth extension and registered as a third MCP server.
- **LLM4Decompile** (albertan017/LLM4Decompile): a model family that refines
  Ghidra's pseudo-C into readable C. Nothing upstream plugs into Ghidra, so the
  bundle gains a Ghidra script that sends the current function's decompilation
  to a locally served LLM4Decompile model and writes the refined C back, plus a
  pipeline stage that pulls the model into Ollama automatically.

The other five repos in the post are out (section 1.2).

### 1.1 Success criteria

- `make install` builds ReVa from a pinned submodule against this Ghidra 12.2,
  installs it under `Ghidra/Extensions/reverse-engineering-assistant/`, verifies
  its plugin class loads, and registers `reva` as an HTTP MCP server with
  opencode and Claude Code (when the `claude` CLI exists).
- `make install` pulls the LLM4Decompile model into Ollama when Ollama is
  installed and running, installs the refine script where Ghidra's Script
  Manager finds it, and otherwise warns and skips, as the REA stage does without
  Node.js.
- In the GUI, a user opens a function, runs the refine script, and the
  function's plate comment gains the refined C. Headlessly, the same script
  refines a named function and prints the result. Agents reach it through
  GhidraMCP's `run_ghidra_script` tool, which `make run` enables (section 4.3).
- `make test` covers both: ReVa's MCP endpoint answers an `initialize`
  request headlessly, and the refine script produces C for a fixture function
  when the model is available (SKIP otherwise).
- Portable mode holds: ReVa's settings land under `portable/settings`; the
  only new state outside `portable/` is the model inside Ollama's own store,
  which is Ollama's, not Ghidra's (section 4.5).
- `make help`, `make env`, `make -n install`, `make test` and the standalone
  Python tests pass; `git status` is clean.

### 1.2 Out of scope

- radare2, r2ai and ida-pro-mcp: not Ghidra (the user chose ReVa and
  LLM4Decompile only). IDA Pro is proprietary.
- ReVa's headless Python package (`mcp-reva` on PyPI) and its Claude Code
  marketplace plugin. REA already covers headless, project-less analysis, and
  the marketplace plugin installs skills under `~`, outside the bundle.
- LLM4Decompile-End models (v1.5, work from raw assembly), sk2decompile, and
  the 22B model. The V2 "Ref" line is the one trained on Ghidra output.
- Batch refinement of every function, a decompiler-window integration, and
  wiring LLM4Decompile into GhidrAssist. One function per run is the core job.
- Installing Ollama. It is optional, like Node.js and StormLib; `make env`
  reports it.

## 2. Decisions

| Question | Decision |
| :--- | :--- |
| ReVa source | Shallow submodule of upstream `main`, pinned to a commit at or after `4d2fc5b` (2026-11-03). Upstream CI tests Ghidra 12.2 but the latest release (v7.3.1) only ships 12.1.3 zips, so there is no tag to pin. No fork: it needs no patches. |
| ReVa submodule path | `reverse-engineering-assistant`, because the project has no `settings.gradle` and Gradle names the zip, directory and jar after the checkout directory (same rule as GhidrAssist). Release assets confirm the name: `ghidra_12.1.3_PUBLIC_<date>_reverse-engineering-assistant.zip`. |
| ReVa 12.2 source patches | None. Its commit "Update ReVa for Ghidra 12.2" and CI matrix cover 12.2, so it builds directly like ret-sync and BinExport, with no `prepare-extension-source.py` entry. |
| Library collision | ReVa ships MCP SDK 2.1.0 and Jackson 2.22; GhidrAssist already ships MCP SDK 0.17.1 and Jackson 2.19, and Ghidra loads every `<ext>/lib/*.jar` on one flat class loader. Coexistence is verified, not assumed: the `reva` sanity check starts ReVa on the real installed Ghidra class path (section 3.4), and `check_portable_paths`-style probes already load GhidrAssist. A conflict found during implementation is a stop that comes back to the user (shading or a source patch would be new scope), not a guess. |
| ReVa port | Keep its default, 127.0.0.1:8080, as `REVA_PORT` in the Makefile. The port is a Ghidra tool option, so the Makefile cannot set it; `REVA_PORT` only names what the bundle registers and checks. `make run` keeps failing for a busy 8089 and only warns for a busy 8080 (ReVa listens only once enabled, and 8080 is a common dev port). `make verify` fails without GhidraMCP and warns without ReVa. Amendment: `make test` uses ReVa's random-port mode, not 18080. |
| MCP server name | `reva`, lowercase like `ghidra` and `rea`. |
| Registration | A new `register_mcp_http,name,url` macro beside `register_mcp`. Claude Code: `claude mcp add --scope user --transport http reva http://127.0.0.1:8080/mcp/message`. opencode: `{"type": "remote", "url": ...}` through the same atomic JSON writer. |
| Stage numbering | ReVa becomes `13-install-reva` (before `verify-extensions`), and the later stages shift: `14-pyghidra`, `15-venv`, `16-register-mcp`, `17-install-rea`, `18-install-llm4decompile`. The unnumbered aliases keep working, so users see no change. Stage numbers appear only in the Makefile and AGENTS.md. |
| LLM4Decompile model | `llm4decompile-9b-v2`: the best-scoring Ref model (64.9% re-executability on the authors' benchmark). Served by Ollama from the GGUF at `hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0` (about 10 GB, near-lossless). Rejected: official safetensors through `ollama create` (18 GB download plus an 18 GB blob copy, and more steps for the same model); vLLM or transformers in a venv (CUDA wheels and a GPU-only path). |
| Model identity | One Makefile variable, `LLM4DECOMPILE_MODEL`, written into a properties file the script reads, so the pull and the script never disagree. |
| Model pull | Automatic inside `make install` (the user's choice), skipped when the model is already present (`ollama show` succeeds) or when Ollama is absent or not serving. The script extension is always assembled, like D2GridraTools; only the pull is gated, so a host without Ollama can still point the script at a remote one. |
| Script language | Java (`LLM4DecompileRefine.java`). Ghidra compiles it on demand in the GUI and headlessly, it needs no PyGhidra at runtime, and Java 25's `HttpClient` makes the one HTTP call. |
| Script placement | A minimal extension directory `Ghidra/Extensions/LLM4Decompile/` with `extension.properties`, an empty `Module.manifest`, `ghidra_scripts/LLM4DecompileRefine.java` and `llm4decompile.properties`, assembled by the stage the way `install-d2gridratools.sh` assembles D2GridraTools. The Script Manager scans every extension's `ghidra_scripts/`; no `~/ghidra_scripts` is touched. |
| Script output | The function's plate comment, below a marker line naming the model, with any earlier LLM4Decompile block replaced and other plate text kept. Also printed to the console (the only output that headless and agent callers see). |
| Agent access to the script | On by default: `make run` exports `GHIDRA_MCP_ALLOW_SCRIPTS=1` into Ghidra's environment, so GhidraMCP's `run_ghidra_script` runs any Ghidra script for any client on 127.0.0.1:8089. The user chose this over an opt-in. ReVa's own script tool cannot run it: it runs Python only and only under a PyGhidra-launched GUI. Rejected: a native refine tool in GhidraMCP (a fork plus source patch of ghidra-mcp). |
| Where the model lives | Ollama's store (`~/.ollama` by default). Not under `portable/`: the bundle's portable invariant covers Ghidra, extension and REA state, and the model is Ollama's data like Node's is npm's. `make clean` and `make distclean` leave it; the README gives the `ollama rm` line. |

## 3. ReVa

### 3.1 Build and install

Stage `13-install-reva` calls
`install_extension,reverse-engineering-assistant,reverse-engineering-assistant,reverse-engineering-assistant/dist/ghidra_$(GHIDRA_VERSION)_*_reverse-engineering-assistant.zip`
with the commit directory `reverse-engineering-assistant` and no patch
identity. The build pulls MCP SDK 2.1.0, Jetty 12.1 and Jackson 2.22 from Maven
Central and Spring's milestone/snapshot repositories, like the other Gradle
extensions. Both `ghidra/gradlew` and the toolchain init script apply.

`reverse-engineering-assistant/{dist,build,.gradle}` join `clean`,
`BUILD_OUTPUTS` and `PACKAGE_PATTERNS`.

### 3.2 Verification

`VerifyExtensions.java` gains
`check("reverse-engineering-assistant", Plugin.class, "RevaPlugin")`.

### 3.3 Runtime

ReVa in GUI mode stores its options in Ghidra tool options
(`ToolOptionsBackend`), which live under `portable/settings`. Its file-backed
configuration only exists in headless mode with a caller-supplied path. No
portable patch is needed; the sanity leak check covers it as for every
extension.

ReVa's `RevaApplicationPlugin` and `RevaPlugin` must be enabled once in the
project window and the CodeBrowser (File → Configure → Configure all plugins),
then the tool saved. The README documents this next to the GhidraMCP steps.
Pre-seeding tool configuration is left out: Ghidra's default tool files are
Ghidra's, and GhidraMCP has the same one-time step today.

ReVa's scripting tools expose PyGhidra scripting on the MCP port. The default
binding is localhost without an API key. Correction (review): this is weaker
than GhidraMCP's posture, which rejects cross-origin and non-loopback `Host`
requests; ReVa allows any origin and checks neither header, so the README
recommends its API key and shows the header a client then needs.

### 3.4 Sanity section `reva`

A new section in `tests/run-sanity.sh`, between `mcp` and `dist`:

- The extension directory, jar and zip exist, and the jar name starts with
  the directory name.
- Start ReVa headlessly on `TEST_REVA_PORT` (18080) and POST an MCP
  `initialize` request to `/mcp/message`; expect HTTP 200 and a JSON-RPC
  result naming the server. ReVa ships `reva.headless.RevaHeadlessLauncher`
  for this. Drive it from the PyGhidra venv (`import pyghidra;
  pyghidra.start()` then the launcher class), not from a hand-built class
  path: PyGhidra loads the installed extensions exactly as `ghidraRun` does,
  which is what proves ReVa's jars coexist with GhidrAssist's (section 2,
  "Library collision"). Same work directory, settings and cache isolation as
  `check_mcp`, and the process is killed in `cleanup`.
- `make run` warns for a busy 8080; `make verify` additionally probes ReVa's
  endpoint and warns when it does not answer.

Amendment (implementation): the probe (`tests/probes/reva_probe.py`) starts the
launcher in random-port mode and reads `getPort()`, so there is no
`TEST_REVA_PORT` and nothing can collide. It runs under `pyghidraRun -H` with a
throwaway project, like the PyGhidra MPQ probe.

## 4. LLM4Decompile

### 4.1 Stage `18-install-llm4decompile`

Runs last, after REA, because it is the longest optional download and nothing
depends on it.

1. Assemble the extension directory (section 4.4) from the files in the repo,
   writing `.bundle-source` with the hash of the script and the model name, and
   skip when unchanged. This always happens, so the script works against a
   model the user pulls later or serves elsewhere.
2. If `ollama` is not on `PATH` or `ollama list` fails: `$(WARN)` and skip
   the pull. `make test` then reports SKIP for the model checks.
3. `ollama show $(LLM4DECOMPILE_MODEL)` succeeds → "already pulled, skipping";
   otherwise `ollama pull $(LLM4DECOMPILE_MODEL)`. A failed pull (no network,
   no disk) warns and continues, the same policy as a failed `npm ci` for REA.

`00-env` gains an optional-tool line for Ollama (found / not found, with the
serving state), like StormLib and Node.js. `00-deps` does not install it.

### 4.2 The script

`ghidra_scripts/LLM4DecompileRefine.java`, category `LLM4Decompile`, lives in
the repo next to `SanityCheck.java` and is copied into the extension at install.

Behaviour:

- Target function: the one containing `currentAddress` in the GUI; headlessly,
  the first script argument is a function name or address. No function → error
  message and exit code 1 (headless) or a `popup` (GUI).
- Decompile with `DecompInterface` using the program's default options and the
  decompiler's C output (`getDecompiledFunction().getC()`), the same text the
  upstream `decompile.py` fed the model.
- Prompt: exactly the upstream V2 format,
  `"# This is the assembly code:\n" + C + "\n# What is the source code?\n"`.
- Request: `POST <url>/api/generate` with `{"model", "prompt", "raw": true,
  "stream": false, "options": {"temperature": 0, "num_ctx": 4096,
  "num_predict": 2048}}`. `raw` skips Ollama's chat template, which this
  completion model was not trained with; temperature 0 matches the authors'
  greedy generation; the model's context is 4096 tokens. A prompt longer than
  roughly 2000 tokens cannot fit with its answer, so the script warns when the
  pseudo-C exceeds a character budget the builder picks (about 6000) and
  proceeds.
- Response: the `response` field, trimmed. Empty or non-200 → error with the
  server's message, nothing written.
- Output: print the refined C to the console; set the function's plate comment
  to `[existing plate text, minus any previous LLM4Decompile block]` followed by
  `--- LLM4Decompile (<model>) ---` and the C. `GhidraScript` wraps the run in a
  transaction, so the comment is undoable.
- Configuration: `llm4decompile.properties` next to the extension root (found
  from the script's own source file), with `model=` and `url=`. Environment
  variables `LLM4DECOMPILE_MODEL` and `LLM4DECOMPILE_URL` override it, which
  is how a user points Ghidra at an Ollama on another machine. Defaults in the
  code match the Makefile for the case where the properties file is missing
  (script run straight from the repo).
- Timeout: 10 minutes per request; the model loads on first call.

Agents: see section 4.3.

### 4.3 Agent access

GhidraMCP's `run_ghidra_script` tool refuses every script unless Ghidra's
environment carries `GHIDRA_MCP_ALLOW_SCRIPTS=1`. `make run` exports it, so an
agent on the `ghidra` server can call
`run_ghidra_script("LLM4DecompileRefine.java", "<function>")` and read the
refined C from the script's console output. This is a posture change the
README states plainly: with Ghidra running from `make run`, any client that can
reach 127.0.0.1:8089 can run arbitrary Ghidra scripts, which is code execution
as the user. The port stays bound to localhost. A user who wants scripts off
runs `ghidraRun` directly or clears the variable; the README says how.

ReVa's script tool is not a route: it runs Python scripts only and refuses
under a GUI not launched through PyGhidra. The README says so, so nobody
expects it to work.

The `mcp` sanity section already starts GhidraMCP's headless server; the
builder may add the variable there and run the refine script through the tool
when the model is present, as an end-to-end check. Not required: the
`llm4decompile` section covers the script and the `mcp` section covers the
tool surface.

### 4.4 Extension directory

```text
Ghidra/Extensions/LLM4Decompile/
├── extension.properties       # name=LLM4Decompile, version=<Ghidra version>
├── Module.manifest            # empty
├── llm4decompile.properties   # model=<LLM4DECOMPILE_MODEL>, url=http://127.0.0.1:11434
├── ghidra_scripts/LLM4DecompileRefine.java
└── .bundle-source
```

The directory name and the absence of a `lib/` jar keep it clear of the
`ClassSearcher` naming rule; it contributes scripts only, as D2GridraTools does.

### 4.5 State and licences

- The model sits in Ollama's store, about 10 GB. `make clean`/`distclean` do
  not remove it; README: `ollama rm <model>`.
- Code is MIT; the 9B-v2 weights are under the DeepSeek Model License (use
  restrictions) on top of Yi-Coder's Apache-2.0 base. The repo redistributes
  neither; the user's `make install` downloads from Hugging Face through
  Ollama. The README states this as it does for D2GridraTools.
- The GGUF comes from a third-party quantiser (mradermacher), not the model
  authors. The README says so; swapping `LLM4DECOMPILE_MODEL` to another tag is
  a one-line change.
- Nothing leaves the machine: Ollama serves locally. If a user sets
  `LLM4DECOMPILE_URL` to a remote host, the function's pseudo-C goes there.

### 4.6 Sanity section `llm4decompile`

- Always: the extension directory, properties file and script exist, and the
  model in the properties file equals the Makefile's.
- Ollama not reachable at the properties file's URL, or `ollama show` fails for
  the model → SKIP the remaining checks with the reason.
- Otherwise run the script headlessly (`analyzeHeadless ... -postScript
  LLM4DecompileRefine.java <function>`) on an existing C fixture against a
  throwaway project under the suite's work directory, with the same settings,
  cache and temp isolation as `check_mcp`, and assert the console output has a
  function body (`{` and `}` after the marker). Generation on this machine
  takes seconds; a 10-minute timeout guards slower hosts. The result is not
  snapshotted: model output is not byte-stable across Ollama versions.

## 5. Documentation

- AGENTS.md: project overview (two new bullets), invariants 2.2 (new
  directory names), 2.3 (new submodule), new 2.10 "ReVa" and 2.11
  "LLM4Decompile" sections, the stage table, and the test-section list.
- README: "Using the MCP server" gains ReVa (port, enabling the plugins,
  `claude mcp get reva`), the script-execution note for `make run`, and an
  "LLM4Decompile" subsection (what the script does, the one-line pull, the
  `ollama rm` line, the licence note, agent use through `run_ghidra_script`).
  Layout and Notes sections list the new directories.

## 6. Left to the builder

- Exact ReVa pin commit (latest `main` at implementation time that builds on
  12.2) and whether `register_mcp_http` shares the Python JSON writer with
  `register_mcp` by parameter or by a second heredoc.
- The exact JSON of the `initialize` request for MCP SDK 2.1's streamable
  HTTP transport (it requires `Accept: application/json, text/event-stream`).
- The character budget for the prompt warning and the plate-comment marker
  text.
- Which existing fixture function the sanity run refines.
- `.gitmodules` ordering and `make help` wording.

## 7. Risks

- ReVa's `main` moves daily and has no 12.2 release; a later bump may need a
  `prepare-extension-source.py` entry if upstream breaks on 12.2.x. The pin
  protects today's build.
- The 9B-v2 model's quality claims hold for GCC-compiled Linux x86-64 at O0–O3.
  On DOS, LE or Win32 targets the refined C is a readability aid, not ground
  truth, and the README says so.
- A first GUI run blocks the Swing thread while the model loads. Ghidra scripts
  run in a task thread with a progress monitor, so the UI stays responsive;
  the builder confirms the monitor is checked between steps.
