# Ghidra Bundle

A reproducible, self-contained **Ghidra 12.2**, built from source with eight extensions, Jython, Diablo 2 scripts, PyGhidra with MPQ support and an MCP bridge for AI assistants. Ghidra runs in portable mode: settings, cache and temp files stay under `dist/`. Every built zip is moved to `dist/packages/`.

| Component | What it adds |
| :--- | :--- |
| [Ghidra](https://github.com/NationalSecurityAgency/ghidra) 12.2 | Built from the `Ghidra_12.2_build` tag |
| [GhidraMCP](https://github.com/bethington/ghidra-mcp) | Plugin serving Ghidra's analysis over HTTP on port 8089, plus the `bridge-mcp-ghidra` MCP server |
| [lx-loader](https://github.com/yetmorecode/ghidra-lx-loader) | Loader for Linear Executables (LE/LX: DOS/4GW, OS/2, VxD); built from [a fork](https://github.com/felipe-dos-santos81/ghidra-lx-loader/tree/fix-object-permissions) with an object-permissions fix |
| [GhidraDosToolbox](https://github.com/plaes/GhidraDosToolbox) | MS-DOS loader and analyzers (segmentation, Borland Pascal overlays, interrupt calls) |
| [GhidrAssist](https://github.com/symgraph/GhidrAssist) | LLM assistant; built from [a fork](https://github.com/felipe-dos-santos81/GhidrAssist/tree/portable-settings) that keeps its data in `portable/` |
| [RevEng.AI](https://github.com/RevEngAI/plugin-ghidra) | Cloud AI decompilation and similarity search; built from [a fork](https://github.com/felipe-dos-santos81/plugin-ghidra/tree/portable-settings) that keeps its API key in `portable/` |
| [ret-sync](https://github.com/bootleg/ret-sync) | Sync Ghidra with a debugger (x64dbg, WinDbg) |
| [GhidraFindcrypt](https://github.com/antoniovazquezblanco/GhidraFindcrypt) | Analyzer for crypto constants |
| [BinExport](https://github.com/google/binexport) | Exporter for BinDiff |
| [D2GridraTools](https://github.com/dzik87/D2GridraTools) | Diablo 2 1.14d scripts, run under Ghidra's Jython extension |
| PyGhidra + `bundle_mpq` | Python 3 scripting with MPQ archive access (StormLib) |
| [REA](https://github.com/morluto/rea) 6.3.0 (optional) | CLI and MCP server that analyzes a file through this Ghidra without the GUI; needs Node.js |

## Quickstart

```bash
git clone --recurse-submodules https://github.com/felipe-dos-santos81/ghidra-bundle.git
cd ghidra-bundle
make install   # install dependencies, build, and test the bundle
make run       # launch Ghidra
```

`make install` installs missing prerequisites with `sudo apt` (Linux) or `brew` (macOS): JDK 25, Maven, Clang, Python 3.10+, uv, Git, curl, GNU `timeout` (`gtimeout` on macOS) and optional StormLib for MPQ support. REA also needs a supported Node.js/npm on `PATH` (checked by `make env`); Node.js is not installed automatically. Java dependencies download on the first build, and completed stages are skipped.

On apt-based Linux distributions, `make deps` installs `openjdk-25-jdk` when available. If your distribution does not provide it, install a full JDK 25 yourself and export `JAVA25_HOME=/absolute/path/to/jdk` before running `make deps` or `make install`; no additional package repository is required.

## Using the MCP server

A successful `make install` registers `bridge-mcp-ghidra` as the `ghidra` MCP server with **opencode** (`~/.config/opencode/opencode.json`) and, if the `claude` CLI is installed, with **Claude Code** (user scope).

1. `make run`, then open a program in the CodeBrowser. This starts the GhidraMCP plugin on `127.0.0.1:8089`.
2. `make verify` confirms the plugin answers.
3. Restart your AI client. In Claude Code, `claude mcp get ghidra` should report it as connected.

### REA

With Node.js available, `make install-rea` installs [REA](https://github.com/morluto/rea) into `.rea/` and registers it as the `rea` MCP server with the same two clients. REA needs no running Ghidra: it imports one file into a throwaway headless project and returns decompilation, references and strings.

The bundle's checked compatibility patch lets REA use this Ghidra 12.2 build as **compatible, not upstream-verified**. The `rea` sanity checks cover the policy, doctor and real decompilation.

```bash
.rea/rea function /path/to/program.exe entry --json   # the same wrapper the MCP server uses
```

The wrapper points REA at this bundle's Ghidra and JDK; re-run `make install-rea` after changing either. Sessions are read-only and deleted on close.

REA cannot analyze LE/LX programs. For DOS/4GW games it analyzes only the 16-bit extender stub without warning; use the `ghidra` server for those programs and persistent projects. REA adds about 150 tools to each client session.

## Make targets

`make help` lists the pipeline and runtime targets. Numbered stages also have aliases without their numeric prefix (`04-install-mcp` → `install-mcp`).

`make clean` removes generated outputs, including `dist/`, `.venv/` and REA's installed runtime. `make distclean` also de-initializes the submodules.

## Testing

`make test` (also the last stage of `make install`) builds three tiny programs: an i386 ELF object, a DOS MZ file and an LE file. It checks their loaders and decompilation, GhidraMCP over HTTP on port 18089 (`TEST_MCP_PORT`), the JDK 25 runtime, packages, BinExport, Jython and the D2 scripts, PyGhidra/MPQ, REA and portable-path isolation. MPQ checks skip without StormLib, and REA integration checks skip when REA is unavailable.

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
├── scripts/              # Build, toolchain, REA compatibility, and launcher helpers
├── python/bundle-mpq/    # bundle_mpq: ctypes StormLib MPQ reader, installed into PyGhidra's venv
├── ghidra_scripts/       # VerifyExtensions.java, SanityCheck.java (used by make)
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
├── .venv/                # Python venv with bridge-mcp-ghidra (git-ignored)
├── .rea/                 # REA's version pin and lockfile; node_modules/ and the rea wrapper are git-ignored
└── dist/                 # Generated installation and packages (git-ignored)
    ├── build/               # Disposable extension source copies for compatibility patches
    ├── packages/            # Every built zip: Ghidra and each extension
    └── ghidra_12.2_PUBLIC/
        ├── ghidraRun, support/pyghidraRun
        ├── Ghidra/Extensions/   # GhidraMCP/, lx-loader/, dos-toolbox/, GhidrAssist/, plugin-ghidra/,
        │                        # retsync/, GhidraFindcrypt/, BinExport/, Jython/, D2GridraTools/
        └── portable/            # settings/ (incl. PyGhidra's venv), cache/, temp/
```

## Notes

- **Changing the Ghidra version:** check out the new tag in the `ghidra` submodule and update `GHIDRA_VERSION` in the `Makefile`. Stage 02 refuses to build if they disagree. Upgrades do not migrate projects or settings; remove superseded installations explicitly when no longer needed.
- **Ghidra 12.2 compatibility patches:** six extensions need small API patches. `scripts/prepare-extension-source.py` applies them to disposable copies under `dist/build/`; submodule checkouts stay unchanged. ret-sync and BinExport build directly.
- **Directory names matter:** keep extension names from their zips and the `GhidrAssist`, `plugin-ghidra`, and `GhidraFindcrypt` submodule paths. Ghidra requires each jar name to start with its extension directory name; `make verify-extensions` checks class loading.
- **Rebuilding:** stages skip existing outputs; extensions rebuild when their submodule commit or compatibility patch changes, or when their zip is missing. Run `make clean`, or delete one extension under `dist/.../Ghidra/Extensions/`, to rebuild.
