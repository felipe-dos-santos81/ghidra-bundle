# Agent Instructions: Ghidra Bundle

This document provides operational context, architectural invariants, and development guidelines for AI coding agents working in this repository.

---

## 1. Project Overview

`ghidra-bundle` provides an automated, completely isolated, reproducible build and runtime environment for **Ghidra 12.1.2** with three pre-installed extensions and a local Model Context Protocol (MCP) bridge:
- **Ghidra 12.1.2**: Built from source via headless Gradle (`Ghidra_12.1.2_build` tag).
- **GhidraMCP**: AI reverse-engineering server plugin (port 8089) and Python bridge (`bridge-mcp-ghidra`).
- **lx-loader**: Linear Executable (`LX`/`LE`) binary loader (OS/2, DOS/4GW).
- **GhidraDosToolbox**: MS-DOS memory segmentation, Borland Pascal overlays, and interrupt vector analyzers (`wip-ghidra-12` branch).

---

## 2. Core Architectural Invariants

Agents modifying or extending this codebase must strictly adhere to the following rules:

### 2.1 Portable Mode & Filesystem Isolation
- **NEVER write to `~/.ghidra`**: Ghidra must run in strictly portable mode.
- In [`Makefile`](file:///Users/felipe.dos.santos/code/mine/ghidra-bundle/Makefile) (`03-install-ghidra`), `support/launch.properties` is patched with:
  ```properties
  JAVA_HOME_OVERRIDE=<JAVA21_HOME>
  VMARGS=-Dapplication.settingsdir=${INSTALL_DIR}/portable/settings
  VMARGS=-Dapplication.cachedir=${INSTALL_DIR}/portable/cache
  VMARGS=-Dapplication.tempdir=${INSTALL_DIR}/portable/temp
  ```
- All user preferences, project caches, and temporary files must reside under `dist/ghidra_12.1.2_PUBLIC/portable/`.
- When verifying the patch idempotency, grep specifically for `^# --- Portable Mode Overrides ---` (do not grep for `application.settingsdir`, which matches upstream commented lines).

### 2.2 Extension Placement
- All installed extensions must reside under `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/<ExtensionName>`:
  - `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/GhidraMCP`
  - `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/ghidra-lx-loader`
  - `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/GhidraDosToolbox`
- Ghidra's `GhidraApplicationLayout` automatically discovers extensions in this directory.

### 2.3 Submodule Tracking
- Upstream repositories are tracked as shallow Git submodules:
  - `ghidra` (NSA, tag `Ghidra_12.1.2_build`)
  - `ghidra-mcp` (bethington/ghidra-mcp, `main`)
  - `lx-loader` (yetmorecode/ghidra-lx-loader, `master`)
  - `dos-toolbox` (plaes/GhidraDosToolbox, `wip-ghidra-12`)
- Always synchronize submodules with:
  ```bash
  git submodule update --init --recursive --depth 1
  ```
- Use `git submodule deinit -f --all` for `distclean` rather than deleting `.git` references.

### 2.4 Dedicated Python Virtualenv
- Python virtual environment is located at `.venv/` (Python 3.10+ required).
- `ghidra-mcp` is installed in editable mode:
  ```bash
  $(PIP) install -e ./ghidra-mcp
  ```
- The entry point binary is `$(VENV_DIR)/bin/bridge-mcp-ghidra` (`BRIDGE_BIN`).

### 2.5 Port 8089 & Runtime Checks
- Port `8089` is reserved for GhidraMCP's HTTP server.
- `make run` pre-checks port collision using `lsof -i :8089` and fails fast if occupied.

---

## 3. Makefile Pipeline Reference

The build pipeline is sequenced using numbered targets:

| Stage | Target | Description |
| :--- | :--- | :--- |
| `00` | `00-env` (`env`) | Validates JDK 21, Maven, Clang, Python 3, uv, Git |
| `01` | `01-checkout` (`checkout`) | Fetches submodules (`--depth 1`) |
| `02` | `02-build-ghidra` (`build-ghidra`) | Runs headless build script `build-ghidra.sh` |
| `03` | `03-install-ghidra` (`install-ghidra`) | Extracts zip to `dist/`, patches `launch.properties` |
| `04` | `04-install-mcp` (`install-mcp`) | Staged Maven deps, builds GhidraMCP, installs zip |
| `05` | `05-install-lx-loader` (`install-lx-loader`) | Builds lx-loader via `ghidra/gradlew` (with release fallback) |
| `06` | `06-install-dos-toolbox` (`install-dos-toolbox`)| Builds GhidraDosToolbox via `ghidra/gradlew` |
| `07` | `07-venv` (`venv`) | Creates `.venv` and installs `bridge-mcp-ghidra` |
| `08` | `08-register-mcp` (`register-mcp`) | Atomically writes to `~/.config/opencode/opencode.json` |

### Runtime & Maintenance Targets
- `make install`: Executes stages 00 through 08 sequentially.
- `make run`: Starts isolated Ghidra (`dist/.../ghidraRun`).
- `make run-bridge`: Runs `bridge-mcp-ghidra` from `.venv`.
- `make verify`: Probes `http://127.0.0.1:8089/check_connection`.
- `make clean`: Deletes `dist/`, `.venv/`, and build artifacts in subproject directories.
- `make distclean`: Runs `clean` and `git submodule deinit -f --all`.

---

## 4. Development Standards for Agents

When editing code or recipes in this repository:
1. **Makefile Rules**:
   - Always use **tabs** for recipe indentation.
   - Use `SHELL := /bin/bash` (defined at top).
   - Enforce error propagation in shell pipelines (`set -e` or `(cd ... && ...) || exit 1`).
   - Use `unzip -q -o` and `rm -rf` to ensure non-interactive, idempotent execution.
   - Keep ANSI escape sequences in `printf` rather than `echo` for portability.
2. **Bash Scripts**:
   - Validate any `.sh` script changes with `bash -n <script>`.
   - Maintain strict error checking (`set -euo pipefail`).
3. **Verification Checklist Before Merging**:
   - `make help` renders cleanly.
   - `make env` validates all tools.
   - `make -n install` expands without syntax errors.
   - `git status` reflects clean working tree.
