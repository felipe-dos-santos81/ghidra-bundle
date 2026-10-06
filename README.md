# Ghidra Bundle

A reproducible, self-contained **Ghidra 12.1.4**, built from source with three extensions and an MCP bridge for AI assistants. Ghidra runs in portable mode: settings, cache and temp files stay in `dist/`, and `~/.ghidra` is never touched.

| Component | What it adds |
| :--- | :--- |
| [Ghidra](https://github.com/NationalSecurityAgency/ghidra) 12.1.4 | Built from the `Ghidra_12.1.4_build` tag |
| [GhidraMCP](https://github.com/bethington/ghidra-mcp) | Plugin serving Ghidra's analysis over HTTP on port 8089, plus the `bridge-mcp-ghidra` MCP server |
| [lx-loader](https://github.com/yetmorecode/ghidra-lx-loader) | Loader for Linear Executables (LE/LX: DOS/4GW, OS/2, VxD) |
| [GhidraDosToolbox](https://github.com/plaes/GhidraDosToolbox) | MS-DOS loader and analyzers (segmentation, Borland Pascal overlays, interrupt calls) |

## Quickstart

```bash
git clone --recurse-submodules https://github.com/felipe-dos-santos81/ghidra-bundle.git
cd ghidra-bundle
make install   # installs missing packages, builds and installs everything
make run       # launches Ghidra
```

`make install` installs any missing prerequisites with `sudo apt` (Linux) or `brew` (macOS): JDK 21, Maven, Clang, Python 3.10+, uv and Git. Run `make env` to check them. The Ghidra source build takes several minutes; every stage skips work that is already done.

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
| `07-venv` (`venv`) | Create `.venv` with `bridge-mcp-ghidra` |
| `08-register-mcp` (`register-mcp`) | Register the MCP server with opencode and Claude Code |
| `verify-extensions` | Quick headless check that Ghidra loads every extension's classes |
| `test` | Run the sanity test suite (see Testing) |
| `install` | Run all of the above, in order (ends with `test`) |
| `run` | Launch Ghidra (fails if port 8089 is in use) |
| `run-bridge` | Run the MCP bridge over stdio |
| `verify` | Check the GhidraMCP plugin answers on port 8089 |
| `clean` | Remove `dist/`, `.venv/` and build outputs |
| `distclean` | `clean`, then de-initialize the submodules |

## Testing

`make test` (also the last stage of `make install`) builds three tiny programs and checks that Ghidra handles them: an i386 ELF object (core loader and decompiler), a DOS MZ file (GhidraDosToolbox loader and syscall analyzer) and an LE file (lx-loader, including an applied fixup). It then starts GhidraMCP's headless server on port 18089 (`TEST_MCP_PORT`) and checks it over HTTP. It takes about 1–2 minutes and leaves nothing behind.

Decompiled output is also compared with `tests/snapshots/`; differences are reported but never fail the run. After a deliberate Ghidra or extension upgrade, record the new output with `UPDATE_SNAPSHOTS=1 make test`. Verified on Linux arm64; macOS is untested.

## Layout

```text
ghidra-bundle/
├── Makefile              # Build and install pipeline
├── build-ghidra.sh       # Ghidra source build (called by 02-build-ghidra)
├── ghidra_scripts/       # VerifyExtensions.java, SanityCheck.java (used by make)
├── tests/                # make test: fixtures, expectations, snapshots, run-sanity.sh
├── ghidra/               # Submodule: NSA Ghidra, tag Ghidra_12.1.4_build
├── ghidra-mcp/           # Submodule: GhidraMCP
├── lx-loader/            # Submodule: ghidra-lx-loader
├── dos-toolbox/          # Submodule: GhidraDosToolbox, branch wip-ghidra-12
├── .venv/                # Python venv with bridge-mcp-ghidra (git-ignored)
└── dist/                 # Built Ghidra (git-ignored)
    └── ghidra_12.1.4_PUBLIC/
        ├── ghidraRun
        ├── Ghidra/Extensions/   # GhidraMCP/, lx-loader/, dos-toolbox/
        └── portable/            # settings/, cache/, temp/
```

## Notes

- **Changing the Ghidra version:** check out the new tag in the `ghidra` submodule and update `GHIDRA_VERSION` in the `Makefile`. Stage 02 refuses to build if the two disagree.
- **Extension directory names matter:** Ghidra only loads an extension's classes when its jar name starts with the extension's directory name, so the extensions keep the names from their zips. `make verify-extensions` catches a mismatch.
- **Rebuilding:** stages skip when their output exists. Run `make clean` (or delete the specific extension under `dist/.../Ghidra/Extensions/`) to rebuild.
