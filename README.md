# Ghidra Bundle

A reproducible, self-contained **Ghidra 12.1.4**, built from source with eight extensions, Jython, Diablo 2 scripts, PyGhidra with MPQ support and an MCP bridge for AI assistants. Ghidra runs in portable mode: settings, cache and temp files stay in `dist/`, and `~/.ghidra` is never touched. Every built zip is collected in `dist/packages/`.

| Component | What it adds |
| :--- | :--- |
| [Ghidra](https://github.com/NationalSecurityAgency/ghidra) 12.1.4 | Built from the `Ghidra_12.1.4_build` tag |
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

## Quickstart

```bash
git clone --recurse-submodules https://github.com/felipe-dos-santos81/ghidra-bundle.git
cd ghidra-bundle
make install   # installs missing packages, builds and installs everything
make run       # launches Ghidra
```

`make install` installs any missing prerequisites with `sudo apt` (Linux) or `brew` (macOS): JDK 21, Maven, Clang, Python 3.10+, uv, Git, curl, GNU `timeout` (`gtimeout` on macOS) and, optionally, StormLib (`libstorm-dev`) for MPQ support. Run `make env` to check them. GhidrAssist, RevEng.AI and BinExport download their Java dependencies on the first build. The Ghidra source build takes several minutes; every stage skips work that is already done.

## Using the MCP server

`make install` registers `bridge-mcp-ghidra` as the `ghidra` MCP server with **opencode** (`~/.config/opencode/opencode.json`) and, if the `claude` CLI is installed, with **Claude Code** (user scope).

1. `make run`, then open a program in the CodeBrowser. This starts the GhidraMCP plugin on `127.0.0.1:8089`.
2. `make verify` confirms the plugin answers.
3. Restart your AI client. In Claude Code, `claude mcp get ghidra` should report it as connected.

## Make targets

Run `make help` for the same list.

| Target | What it does |
| :--- | :--- |
| `00-deps` (`deps`) | Install missing OS packages and uv |
| `00-env` (`env`) | Check host prerequisites |
| `01-checkout` (`checkout`) | Fetch the pinned submodules |
| `02-build-ghidra` (`build-ghidra`) | Build the Ghidra zip from source (`build-ghidra.sh`) |
| `03-install-ghidra` (`install-ghidra`) | Extract Ghidra into `dist/` and enable portable mode |
| `04-install-mcp` (`install-mcp`) | Build and install GhidraMCP |
| `05-install-lx-loader` (`install-lx-loader`) | Build and install lx-loader |
| `06-install-dos-toolbox` (`install-dos-toolbox`) | Build and install GhidraDosToolbox |
| `07-install-ghidrassist` (`install-ghidrassist`) | Build and install GhidrAssist |
| `08-install-reveng` (`install-reveng`) | Build and install the RevEng.AI plugin |
| `09-install-retsync` (`install-retsync`) | Build and install ret-sync |
| `10-install-findcrypt` (`install-findcrypt`) | Build and install GhidraFindcrypt |
| `11-install-binexport` (`install-binexport`) | Build and install BinExport |
| `12-install-scripts` (`install-scripts`) | Install Jython and the D2GridraTools scripts |
| `verify-extensions` | Quick headless check that Ghidra loads every extension's classes |
| `13-pyghidra` (`pyghidra`) | Set up PyGhidra's venv (in `portable/`) with `bundle_mpq` |
| `14-venv` (`venv`) | Create `.venv` with `bridge-mcp-ghidra` |
| `15-register-mcp` (`register-mcp`) | Register the MCP server with opencode and Claude Code |
| `test` | Run the sanity test suite (see Testing) |
| `install` | Run all of the above, in order (ends with `test`) |
| `run` | Launch Ghidra (fails if port 8089 is in use) |
| `run-bridge` | Run the MCP bridge over stdio |
| `verify` | Check the GhidraMCP plugin answers on port 8089 |
| `clean` | Remove `dist/`, `.venv/` and build outputs |
| `distclean` | `clean`, then de-initialize the submodules |

## Testing

`make test` (also the last stage of `make install`) builds three tiny programs and checks that Ghidra handles them: an i386 ELF object (core loader and decompiler), a DOS MZ file (GhidraDosToolbox loader and syscall analyzer) and an LE file (lx-loader, including an applied fixup). It then starts GhidraMCP's headless server on port 18089 (`TEST_MCP_PORT`) and checks it over HTTP. It also checks `dist/packages/`, a headless BinExport export, Jython and the D2 scripts, PyGhidra reading a PKWARE-compressed MPQ, and that nothing was written outside `portable/`. It takes about a minute and leaves nothing behind. Run a subset with `SANITY_ONLY`, e.g. `SANITY_ONLY=dist,pyghidra make test`.

Decompiled output is also compared with `tests/snapshots/`; differences are reported but never fail the run. After a deliberate Ghidra or extension upgrade, record the new output with `UPDATE_SNAPSHOTS=1 make test`. Verified on Linux arm64; macOS is untested.

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

Read a file from an MPQ in a PyGhidra script (run Ghidra with `dist/ghidra_12.1.4_PUBLIC/support/pyghidraRun`):

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
├── scripts/              # install-d2gridratools.sh, pyghidra-venv-dir.py (used by make)
├── python/bundle-mpq/    # bundle_mpq: ctypes StormLib MPQ reader, installed into PyGhidra's venv
├── ghidra_scripts/       # VerifyExtensions.java, SanityCheck.java (used by make)
├── tests/                # make test: fixtures, probes/, expectations, snapshots, run-sanity.sh
├── ghidra/               # Submodule: NSA Ghidra, tag Ghidra_12.1.4_build
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
└── dist/                 # Built Ghidra (git-ignored)
    ├── packages/            # Every built zip: Ghidra and each extension
    └── ghidra_12.1.4_PUBLIC/
        ├── ghidraRun, support/pyghidraRun
        ├── Ghidra/Extensions/   # GhidraMCP/, lx-loader/, dos-toolbox/, GhidrAssist/, plugin-ghidra/,
        │                        # retsync/, GhidraFindcrypt/, BinExport/, Jython/, D2GridraTools/
        └── portable/            # settings/ (incl. PyGhidra's venv), cache/, temp/
```

## Notes

- **Changing the Ghidra version:** check out the new tag in the `ghidra` submodule and update `GHIDRA_VERSION` in the `Makefile`. Stage 02 refuses to build if the two disagree.
- **Extension directory names matter:** Ghidra only loads an extension's classes when its jar name starts with the extension's directory name, so the extensions keep the names from their zips. `make verify-extensions` catches a mismatch.
- **Built zips** are collected in `dist/packages/`, one per artifact; the subprojects' own `dist/` folders are emptied of current-version zips.
- **Extension directory names matter** for the forks and GhidraFindcrypt too: their submodule paths (`GhidrAssist`, `plugin-ghidra`, `GhidraFindcrypt`) name the built jar, so don't rename them.
- **Rebuilding:** stages skip when their output exists; extensions rebuild when their submodule commit changes or their zip is missing from `dist/packages/`. Run `make clean` (or delete the specific extension under `dist/.../Ghidra/Extensions/`) to rebuild.
