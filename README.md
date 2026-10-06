# Ghidra Bundle

A fully self-contained, isolated Ghidra 12.1.4 installation bundled with [GhidraMCP](https://github.com/bethington/ghidra-mcp), [lx-loader](https://github.com/yetmorecode/ghidra-lx-loader), [GhidraDosToolbox](https://github.com/plaes/GhidraDosToolbox), and a local Model Context Protocol (MCP) bridge.

---

## Features

- **Strict Isolation**: Runs in full portable mode (`JAVA_HOME_OVERRIDE`, `application.settingsdir`, `application.cachedir`, and `application.tempdir` redirected to `dist/ghidra_12.1.4_PUBLIC/portable/`). Your system `~/.ghidra` remains completely untouched.
- **Pre-installed Extensions**: Built from source and installed into `<install>/Ghidra/Extensions/` for native discovery:
  - **GhidraMCP**: Exposes Ghidra's decompilation, disassembly, symbol, and analysis tools to AI assistants via HTTP and MCP.
  - **lx-loader**: Adds support for Linear Executable (`LX` / `LE`) binaries (OS/2, DOS extenders like DOS/4GW).
  - **GhidraDosToolbox**: Specialized DOS memory segmentation, Borland Pascal overlays, and interrupt vector analyzers.
- **Python Bridge in Dedicated Virtualenv**: Local Python environment (`.venv/`) with `bridge-mcp-ghidra` installed in editable mode.
- **Automated MCP Client Registration**: Atomically registers the server with `~/.config/opencode/opencode.json` under `mcp.ghidra`, and with Claude Code (user scope, server name `ghidra`) when the `claude` CLI is installed.
- **Reproducible Submodules**: Upstream repositories are tracked as shallow Git submodules pinned to stable commits and release tags.

---

## Prerequisites

| Tool | Version / Note | macOS | Linux (Debian/Ubuntu) |
| :--- | :--- | :--- | :--- |
| **JDK 21** | Required by Ghidra 12+ | `brew install --cask temurin@21` | `sudo apt install -y openjdk-21-jdk` |
| **Maven** | Checked by `make env`; the default build uses Gradle, so only needed for GhidraMCP's own Maven tooling | `brew install maven` | `sudo apt install -y maven` |
| **Clang** | Required to compile Ghidra native decompiler | `xcode-select --install` | `sudo apt install -y clang` |
| **Python** | 3.10 or newer | `brew install python@3.12` | `sudo apt install -y python3 python3-venv` |
| **uv** | Fast Python package manager | `brew install uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| **Git** | 2.25+ | `brew install git` | `sudo apt install -y git` |

> **Note:** You don't need to install these by hand. `make install` runs
> `make deps` first, which auto-installs only the missing packages
> (`sudo apt` on Linux, `brew` on macOS) plus `uv` via the official installer.

Verify all host prerequisites at any time:
```bash
make env
```

---

## Quickstart

### 1. Clone the Repository

```bash
git clone --recurse-submodules https://github.com/felipe-dos-santos81/ghidra-bundle.git
cd ghidra-bundle
```

*(If cloned without `--recurse-submodules`, run `make checkout` to fetch the submodules).*

### 2. Build & Install Everything

```bash
make install
```

This single command executes the complete pipeline:
1. Installs missing OS packages and `uv` (`00-deps`, uses `sudo apt` on Linux / `brew` on macOS)
2. Validates host dependencies (`00-env`)
3. Synchronizes submodules (`01-checkout`)
4. Builds Ghidra 12.1.4 from source (`02-build-ghidra`)
5. Extracts to `dist/` and configures portable mode (`03-install-ghidra`)
6. Builds and installs GhidraMCP (`04-install-mcp`)
7. Builds and installs lx-loader (`05-install-lx-loader`)
8. Builds and installs GhidraDosToolbox (`06-install-dos-toolbox`)
9. Creates Python `.venv` and installs `bridge-mcp-ghidra` (`07-venv`)
10. Registers the MCP bridge with opencode and Claude Code (`08-register-mcp`)

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

### Using with Claude Code
`make register-mcp` adds the bridge as the user-scoped `ghidra` MCP server, so it is available in every Claude Code session. With Ghidra running, `claude mcp get ghidra` should report it as connected; restart open Claude Code sessions to pick it up.

---

## Directory Structure

```text
ghidra-bundle/
├── Makefile                     # Unified pipeline orchestrator
├── build-ghidra.sh              # Headless Ghidra source build script
├── .gitmodules                  # Pinned upstream submodules
├── dist/                        # Extracted Ghidra distribution (ignored in git)
│   └── ghidra_12.1.4_PUBLIC/
│       ├── ghidraRun            # Launch executable
│       ├── Ghidra/Extensions/   # Installed extensions (GhidraMCP, lx-loader, GhidraDosToolbox)
│       └── portable/            # Isolated settings/, cache/, and temp/
├── .venv/                       # Python virtual environment (ignored in git)
├── ghidra/                      # NSA Ghidra submodule (tag Ghidra_12.1.4_build)
├── ghidra-mcp/                  # GhidraMCP submodule
├── lx-loader/                   # ghidra-lx-loader submodule
└── dos-toolbox/                 # GhidraDosToolbox submodule (branch wip-ghidra-12)
```

---

## Makefile Targets

| Target | Description |
| :--- | :--- |
| `make help` | Displays available targets with descriptions |
| `make deps` | Installs missing OS packages (`sudo apt` on Linux, `brew` on macOS) and `uv` |
| `make env` | Validates host prerequisites (JDK 21, Maven, Clang, Python, uv, Git) |
| `make checkout` | Initializes and updates Git submodules with `--depth 1` |
| `make build-ghidra` | Compiles Ghidra 12.1.4 distribution zip |
| `make install-ghidra` | Extracts Ghidra distribution into `dist/` and patches `launch.properties` |
| `make install-mcp` | Builds and installs GhidraMCP extension |
| `make install-lx-loader` | Builds and installs lx-loader extension |
| `make install-dos-toolbox`| Builds and installs GhidraDosToolbox extension |
| `make venv` | Configures Python virtualenv and installs `bridge-mcp-ghidra` |
| `make register-mcp` | Registers MCP bridge with opencode (`~/.config/opencode/opencode.json`) and Claude Code (`claude mcp add --scope user`) |
| `make install` | Installs OS deps, then runs the full pipeline end-to-end |
| `make run` | Starts the isolated Ghidra instance |
| `make run-bridge` | Runs the MCP bridge server |
| `make verify` | Tests HTTP connection to running GhidraMCP plugin |
| `make clean` | Removes `dist/`, `.venv/`, and extension build outputs |
| `make distclean` | Runs `clean` and de-initializes all submodules |
