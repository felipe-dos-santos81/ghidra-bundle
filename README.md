# Ghidra Bundle

A reproducible, self-contained **Ghidra 12.2**, built from source with nine extensions, Jython, Diablo 2 scripts, PyGhidra with MPQ support, two MCP servers inside Ghidra (GhidraMCP and ReVa) plus REA, and an LLM4Decompile refine script. Ghidra runs in portable mode: settings, cache and temp files stay under `dist/`. Every built zip is moved to `dist/packages/`.

| Component | What it adds |
| :--- | :--- |
| [Ghidra](https://github.com/NationalSecurityAgency/ghidra) 12.2 | Built from the `Ghidra_12.2_build` tag |
| [GhidraMCP](https://github.com/bethington/ghidra-mcp) | Plugin serving Ghidra's analysis over HTTP on port 8089, plus the `bridge-mcp-ghidra` MCP server |
| [ReVa](https://github.com/cyberkaida/reverse-engineering-assistant) | MCP server inside Ghidra on 127.0.0.1:8080 (streamable HTTP) with small, context-sparing tools for AI assistants |
| [lx-loader](https://github.com/yetmorecode/ghidra-lx-loader) | Loader for Linear Executables (LE/LX: DOS/4GW, OS/2, VxD); built from [a fork](https://github.com/felipe-dos-santos81/ghidra-lx-loader/tree/fix-object-permissions) with an object-permissions fix |
| [GhidraDosToolbox](https://github.com/plaes/GhidraDosToolbox) | MS-DOS loader and analyzers (segmentation, Borland Pascal overlays, interrupt calls) |
| [GhidrAssist](https://github.com/symgraph/GhidrAssist) | LLM assistant; built from [a fork](https://github.com/felipe-dos-santos81/GhidrAssist/tree/portable-settings) that keeps its data in `portable/` |
| [RevEng.AI](https://github.com/RevEngAI/plugin-ghidra) | Cloud AI decompilation and similarity search; built from [a fork](https://github.com/felipe-dos-santos81/plugin-ghidra/tree/portable-settings) that keeps its API key in `portable/` |
| [ret-sync](https://github.com/bootleg/ret-sync) | Sync Ghidra with a debugger (x64dbg, WinDbg) |
| [GhidraFindcrypt](https://github.com/antoniovazquezblanco/GhidraFindcrypt) | Analyzer for crypto constants |
| [BinExport](https://github.com/google/binexport) | Exporter for BinDiff |
| [D2GridraTools](https://github.com/dzik87/D2GridraTools) | Diablo 2 1.14d scripts, run under Ghidra's Jython extension |
| PyGhidra + `bundle_mpq` | Python 3 scripting with MPQ archive access (StormLib) |
| [LLM4Decompile](https://github.com/albertan017/LLM4Decompile) | Ghidra script that refines a function's pseudo-C with the 9B-v2 model served by Ollama; `make install` pulls the model (about 10 GB) when Ollama is present |
| [REA](https://github.com/morluto/rea) 6.3.0 (optional) | CLI and MCP server that analyzes a file through this Ghidra without the GUI; needs Node.js |

## Quickstart

```bash
git clone --recurse-submodules https://github.com/felipe-dos-santos81/ghidra-bundle.git
cd ghidra-bundle
make install   # install dependencies, build, and test the bundle
make run       # launch Ghidra
```

`make install` installs missing prerequisites with `sudo apt` (Linux) or `brew` (macOS): JDK 25, Maven, Clang, Python 3.10+, uv, Git, curl, GNU `timeout` (`gtimeout` on macOS) and optional StormLib for MPQ support. REA also needs a supported Node.js/npm on `PATH` (checked by `make env`); Node.js is not installed automatically. Ollama is optional too: when it is installed and serving, `make install` pulls the LLM4Decompile model (about 10 GB); otherwise that pull is skipped with a warning. Java dependencies download on the first build, and completed stages are skipped.

On apt-based Linux distributions, `make deps` installs `openjdk-25-jdk` when available. If your distribution does not provide it, install a full JDK 25 yourself and export `JAVA25_HOME=/absolute/path/to/jdk` before running `make deps` or `make install`; no additional package repository is required. Ubuntu splits the GUI libraries into a separate package: a headless-only JDK (`openjdk-25-jdk-headless`) builds and tests the bundle but cannot open Ghidra, so `make deps` adds `openjdk-25-jre` when needed and `make run` explains the problem if it is still missing.

## Using the MCP servers

A successful `make install` registers `bridge-mcp-ghidra` as the `ghidra` MCP server and ReVa's endpoint as the `reva` MCP server with **opencode** (`~/.config/opencode/opencode.json`) and, if the `claude` CLI is installed, with **Claude Code** (user scope).

1. `make run`, then open a program in the CodeBrowser. This starts the GhidraMCP plugin on `127.0.0.1:8089`.
2. `make verify` confirms the plugin answers.
3. Restart your AI client. In Claude Code, `claude mcp get ghidra` should report it as connected.

### ReVa

ReVa runs inside Ghidra and listens on `127.0.0.1:8080` (`/mcp/message`, streamable HTTP) once its plugins are enabled. Enable them once: in the project window, File → Configure → the plug icon ("Configure all plugins") → check **ReVa Application Plugin**; in the CodeBrowser, the same path → check **ReVa Plugin**, then File → Save Tool. `make verify` warns until ReVa answers, and `claude mcp get reva` shows the connection. The port and an optional API key live in Ghidra's tool options (Edit → Tool Options → ReVa Server Options); the bundle registers the default port, so change both together. ReVa's own script tools run Python scripts only, and only when Ghidra was started through `pyghidraRun`; use the `ghidra` server to run Java scripts.

### Script execution

`make run` starts Ghidra with `GHIDRA_MCP_ALLOW_SCRIPTS=1`, so GhidraMCP's `run_ghidra_script` and `run_script_inline` tools run arbitrary Ghidra scripts for any client that can reach `127.0.0.1:8089`. That is code execution as your user: the port stays bound to localhost, but every local process can use it. To keep scripts off, start `dist/ghidra_12.2_PUBLIC/ghidraRun` directly instead of `make run`.

### REA

With Node.js available, `make install-rea` installs [REA](https://github.com/morluto/rea) into `.rea/` and registers it as the `rea` MCP server with the same two clients. REA needs no running Ghidra: it imports one file into a throwaway headless project and returns decompilation, references and strings.

The bundle's checked compatibility patch lets REA use this Ghidra 12.2 build as **compatible, not upstream-verified**. The `rea` sanity checks cover the policy, doctor and real decompilation.

```bash
.rea/rea function /path/to/program.exe entry --json   # the same wrapper the MCP server uses
```

The wrapper points REA at this bundle's Ghidra and JDK; re-run `make install-rea` after changing either. Sessions are read-only and deleted on close.

REA cannot analyze LE/LX programs. For DOS/4GW games it analyzes only the 16-bit extender stub without warning; use the `ghidra` server for those programs and persistent projects. REA adds about 150 tools to each client session.

### LLM4Decompile

`LLM4DecompileRefine.java` (Script Manager → LLM4Decompile) sends the current function's decompiled pseudo-C to an [LLM4Decompile-Ref](https://github.com/albertan017/LLM4Decompile) model and writes the refined C into the function's plate comment below a `--- LLM4Decompile (<model>) ---` marker, replacing an earlier block and keeping any text above it. It also prints the C to the console. Headlessly: `analyzeHeadless <project dir> <name> -import <file> -postScript LLM4DecompileRefine.java <function>`. From an agent on the `ghidra` server: `run_ghidra_script` with `script_name` `LLM4DecompileRefine.java` and `args` the function name; the refined C is in the captured output.

The model is `hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0` (`LLM4DECOMPILE_MODEL` in the `Makefile`), served by Ollama at `http://127.0.0.1:11434`; both are written to `Ghidra/Extensions/LLM4Decompile/llm4decompile.properties`, and the environment variables `LLM4DECOMPILE_MODEL` and `LLM4DECOMPILE_URL` override them (for example to use an Ollama on another machine, where the function's pseudo-C is then sent). `make install` pulls the model when Ollama is installed and serving; otherwise pull it later:

```bash
ollama pull hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0   # about 10 GB, in Ollama's own store
ollama rm   hf.co/mradermacher/llm4decompile-9b-v2-GGUF:Q8_0   # remove it; make clean does not
```

Notes: the GGUF is a third-party quantization of the authors' weights; the weights carry the DeepSeek Model License (use restrictions) on top of Yi-Coder's Apache-2.0, and the code is MIT. The authors' quality numbers are for GCC-compiled Linux x86-64 at O0–O3; on DOS, LE or Win32 targets treat the output as a readability aid, not ground truth. The model's context is 4096 tokens, so the script warns when a function's pseudo-C is very long.

## Make targets

`make help` lists the pipeline and runtime targets. Numbered stages also have aliases without their numeric prefix (`04-install-mcp` → `install-mcp`).

`make clean` removes generated outputs, including `dist/`, `.venv/` and REA's installed runtime. `make distclean` also de-initializes the submodules.

## Testing

`make test` (also the last stage of `make install`) builds three tiny programs: an i386 ELF object, a DOS MZ file and an LE file. It checks their loaders and decompilation, GhidraMCP over HTTP on port 18089 (`TEST_MCP_PORT`), the JDK 25 runtime, packages, BinExport, Jython and the D2 scripts, PyGhidra/MPQ, ReVa's MCP server (headless, random port), the LLM4Decompile script, REA and portable-path isolation. MPQ checks skip without StormLib, LLM4Decompile model checks skip without Ollama or the model, and REA integration checks skip when REA is unavailable.

`tests/run-sanity.sh` defines the test sections. Run a subset with `SANITY_ONLY`, for example `SANITY_ONLY=dist,pyghidra make test`.

Decompiled output is compared with `tests/snapshots/`; differences are reported but never fail the run. After a deliberate Ghidra or extension upgrade, review and record the new output with `UPDATE_SNAPSHOTS=1 make test`.

## Windows games

| Add-on | What it is for | Network |
| :--- | :--- | :--- |
| ret-sync (`retsync`) | Follow a running game in x32dbg/x64dbg/WinDbg from Ghidra. Build the debugger side from `ret-sync/ext_x64dbg` (or `ext_windbg`) on Windows; Ghidra listens on 127.0.0.1:9100 once you enable it in the CodeBrowser | local only |
| GhidraFindcrypt | Analyzer that labels crypto constants (SHA-1/SRP in Battle.net code, zlib/CRC tables) | none |
| BinExport | File → Export → BinExport, for BinDiff between game patches (e.g. Diablo 2 1.13c vs 1.14d). BinDiff itself runs on amd64 only | none |
| D2GridraTools | Diablo 2 1.14d scripts (Script Manager → Diablo 2), run under the Jython extension. Unlicensed upstream: fetched, never redistributed | none |
| GhidrAssist | LLM assistant (explain, rename, chat). Configure a provider in its Settings tab; its data stays under `portable/settings/.../GhidrAssist` | your LLM provider |
| RevEng.AI | Uploads the open binary to `api.reveng.ai` for AI decompilation and similarity search, **only after** you run its setup wizard with an API key (stored in `portable/settings/.../reai/reai.json`) | **uploads binaries** |
| PyGhidra + `bundle_mpq` | Python 3 scripts with MPQ access through StormLib | none |

Read a file from an MPQ in a PyGhidra script (run Ghidra with `dist/ghidra_12.2_PUBLIC/support/pyghidraRun`):

```python
from bundle_mpq import MpqArchive
with MpqArchive("/games/d2/d2data.mpq") as mpq:
    weapons = mpq.read("data/global/excel/weapons.txt")
```

Storm.dll FLIRT signatures are not included: none are public, and Storm.dll is Blizzard's code.

## Layout

```text
ghidra-bundle/
├── Makefile              # Build and install pipeline
├── build-ghidra.sh       # Ghidra source build (called by 02-build-ghidra)
├── scripts/              # Build, toolchain, REA compatibility, LLM4Decompile install and launcher helpers
├── python/bundle-mpq/    # bundle_mpq: ctypes StormLib MPQ reader, installed into PyGhidra's venv
├── ghidra_scripts/       # VerifyExtensions.java, SanityCheck.java (used by make), LLM4DecompileRefine.java
├── tests/                # make test: fixtures, probes/, expectations, snapshots, run-sanity.sh
├── ghidra/               # Submodule: NSA Ghidra, tag Ghidra_12.2_build
├── ghidra-mcp/           # Submodule: GhidraMCP
├── lx-loader/            # Submodule: ghidra-lx-loader (fork with the object-permissions fix)
├── dos-toolbox/          # Submodule: GhidraDosToolbox, branch wip-ghidra-12
├── GhidrAssist/          # Submodule: GhidrAssist (fork, branch portable-settings)
├── plugin-ghidra/        # Submodule: RevEng.AI plugin (fork, branch portable-settings)
├── ret-sync/             # Submodule: ret-sync (Ghidra extension in ext_ghidra/)
├── GhidraFindcrypt/      # Submodule: GhidraFindcrypt
├── binexport/            # Submodule: BinExport (Ghidra extension in java/)
├── D2GridraTools/        # Submodule: Diablo 2 scripts (unlicensed; fetched only)
├── reverse-engineering-assistant/  # Submodule: ReVa (pinned main commit; no 12.2 release yet)
├── .venv/                # Python venv with bridge-mcp-ghidra (git-ignored)
├── .rea/                 # REA's version pin and lockfile; node_modules/ and the rea wrapper are git-ignored
└── dist/                 # Generated installation and packages (git-ignored)
    ├── build/               # Disposable extension source copies for compatibility patches
    ├── packages/            # Every built zip: Ghidra and each extension
    └── ghidra_12.2_PUBLIC/
        ├── ghidraRun, support/pyghidraRun
        ├── Ghidra/Extensions/   # GhidraMCP/, lx-loader/, dos-toolbox/, GhidrAssist/, plugin-ghidra/,
        │                        # retsync/, GhidraFindcrypt/, BinExport/, Jython/, D2GridraTools/,
        │                        # reverse-engineering-assistant/, LLM4Decompile/ (scripts only)
        └── portable/            # settings/ (incl. PyGhidra's venv), cache/, temp/
```

## Notes

- **Changing the Ghidra version:** check out the new tag in the `ghidra` submodule and update `GHIDRA_VERSION` in the `Makefile`. Stage 02 refuses to build if they disagree. Upgrades do not migrate projects or settings; remove superseded installations explicitly when no longer needed.
- **Ghidra 12.2 compatibility patches:** six extensions need small API patches. `scripts/prepare-extension-source.py` applies them to disposable copies under `dist/build/`; submodule checkouts stay unchanged. ret-sync and BinExport build directly.
- **Directory names matter:** keep extension names from their zips and the `GhidrAssist`, `plugin-ghidra`, `GhidraFindcrypt` and `reverse-engineering-assistant` submodule paths. Ghidra requires each jar name to start with its extension directory name; `make verify-extensions` checks class loading.
- **Rebuilding:** stages skip existing outputs; extensions rebuild when their submodule commit or compatibility patch changes, or when their zip is missing. Run `make clean`, or delete one extension under `dist/.../Ghidra/Extensions/`, to rebuild. The LLM4Decompile extension is reassembled when its script, installer, model or URL changes; the model itself stays in Ollama's store across `make clean`.
