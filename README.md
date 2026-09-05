# Ghidra Bundle

A fully self-contained, isolated Ghidra 12.1.2 installation bundled with [GhidraMCP](https://github.com/bethington/ghidra-mcp), [lx-loader](https://github.com/yetmorecode/ghidra-lx-loader), [GhidraDosToolbox](https://github.com/plaes/GhidraDosToolbox), and a local Model Context Protocol (MCP) bridge.

---

## Features

- **Strict Isolation**: Runs in full portable mode (`JAVA_HOME_OVERRIDE`, `application.settingsdir`, `application.cachedir`, and `application.tempdir` redirected to `dist/ghidra_12.1.2_PUBLIC/portable/`). Your system `~/.ghidra` remains completely untouched.
- **Pre-installed Extensions**: Built from source and installed into `<install>/Ghidra/Extensions/` for native discovery:
  - **GhidraMCP**: Exposes Ghidra's decompilation, disassembly, symbol, and analysis tools to AI assistants via HTTP and MCP.
  - **lx-loader**: Adds support for Linear Executable (`LX` / `LE`) binaries (OS/2, DOS extenders like DOS/4GW).
  - **GhidraDosToolbox**: Specialized DOS memory segmentation, Borland Pascal overlays, and interrupt vector analyzers.
- **Python Bridge in Dedicated Virtualenv**: Local Python environment (`.venv/`) with `bridge-mcp-ghidra` installed in editable mode.
- **Automated MCP Client Registration**: Atomically registers the server with `~/.config/opencode/opencode.json` under `mcp.ghidra`.
- **Reproducible Submodules**: Upstream repositories are tracked as shallow Git submodules pinned to stable commits and release tags.

---

## Prerequisites

| Tool | Version / Note | Recommended Install (macOS) |
| :--- | :--- | :--- |
| **JDK 21** | Required by Ghidra 12+ | `brew install --cask temurin@21` |
| **Maven** | Required to stage Ghidra JAR dependencies for MCP | `brew install maven` |
| **Clang** | Required to compile Ghidra native decompiler | `xcode-select --install` |
| **Python** | 3.10 or newer | `brew install python@3.12` |
| **uv** | Fast Python package manager | `brew install uv` |
| **Git** | 2.25+ | `brew install git` |

Verify all host prerequisites at any time:
```bash
make env
```

---

## Quickstart

### 1. Clone the Repository

```bash
git clone --recurse-submodules https://github.com/username/ghidra-bundle.git
cd ghidra-bundle
```

*(If cloned without `--recurse-submodules`, run `make checkout` to fetch the submodules).*

### 2. Build & Install Everything

```bash
make install
```

This single command executes the complete pipeline:
1. Validates host dependencies (`00-env`)
2. Synchronizes submodules (`01-checkout`)
3. Builds Ghidra 12.1.2 from source (`02-build-ghidra`)
4. Extracts to `dist/` and configures portable mode (`03-install-ghidra`)
5. Builds and installs GhidraMCP (`04-install-mcp`)
6. Builds and installs lx-loader (`05-install-lx-loader`)
7. Builds and installs GhidraDosToolbox (`06-install-dos-toolbox`)
8. Creates Python `.venv` and installs `bridge-mcp-ghidra` (`07-venv`)
9. Registers the MCP bridge in `~/.config/opencode/opencode.json` (`08-register-mcp`)

---

## Usage

### Launch Ghidra
```bash
make run
```
*Checks for port collisions on 8089 and starts the isolated Ghidra instance.*

### Launch the MCP Bridge
```bash
make run-bridge
```
*Starts `bridge-mcp-ghidra` over stdio from `.venv`.*

### Verify MCP Connection
Once Ghidra is running with the GhidraMCP plugin enabled in the CodeBrowser:
```bash
make verify
```
*Probes `http://127.0.0.1:8089/check_connection`.*

---

## Directory Structure

```text
ghidra-bundle/
├── Makefile                     # Unified pipeline orchestrator
├── build-ghidra.sh              # Headless Ghidra source build script
├── .gitmodules                  # Pinned upstream submodules
├── dist/                        # Extracted Ghidra distribution (ignored in git)
│   └── ghidra_12.1.2_PUBLIC/
│       ├── ghidraRun            # Launch executable
│       ├── Ghidra/Extensions/   # Installed extensions (GhidraMCP, lx-loader, GhidraDosToolbox)
│       └── portable/            # Isolated settings/, cache/, and temp/
├── .venv/                       # Python virtual environment (ignored in git)
├── ghidra/                      # NSA Ghidra submodule (tag Ghidra_12.1.2_build)
├── ghidra-mcp/                  # GhidraMCP submodule
├── lx-loader/                   # ghidra-lx-loader submodule
└── dos-toolbox/                 # GhidraDosToolbox submodule (branch wip-ghidra-12)
```

---

## Makefile Targets

| Target | Description |
| :--- | :--- |
| `make help` | Displays available targets with descriptions |
| `make env` | Validates host prerequisites (JDK 21, Maven, Clang, Python, uv, Git) |
| `make checkout` | Initializes and updates Git submodules with `--depth 1` |
| `make build-ghidra` | Compiles Ghidra 12.1.2 distribution zip |
| `make install-ghidra` | Extracts Ghidra distribution into `dist/` and patches `launch.properties` |
| `make install-mcp` | Builds and installs GhidraMCP extension |
| `make install-lx-loader` | Builds and installs lx-loader extension (with release fallback) |
| `make install-dos-toolbox`| Builds and installs GhidraDosToolbox extension |
| `make venv` | Configures Python virtualenv and installs `bridge-mcp-ghidra` |
| `make register-mcp` | Atomically registers MCP bridge in `~/.config/opencode/opencode.json` |
| `make install` | Runs the full pipeline end-to-end |
| `make run` | Starts the isolated Ghidra instance |
| `make run-bridge` | Runs the MCP bridge server |
| `make verify` | Tests HTTP connection to running GhidraMCP plugin |
| `make clean` | Removes `dist/`, `.venv/`, and extension build outputs |
| `make distclean` | Runs `clean` and de-initializes all submodules |
