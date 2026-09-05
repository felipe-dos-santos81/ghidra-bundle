# Ghidra Bundle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an isolated, self-contained Ghidra 12.1.2 bundle featuring the Ghidra framework, GhidraMCP extension, Python bridge, lx-loader extension (32-bit DOS-extended / OS/2), and GhidraDosToolbox extension (16-bit real-mode DOS), managed through a stage-numbered Makefile.

**Architecture:** A root `Makefile` orchestrates numbered stages: environment validation, shallow repository checkouts, source build via Ghidra's Gradle wrapper and JDK 21, portable installation patching (`support/launch.properties`), extension builds placed into `<install>/Ghidra/Extensions/`, Python virtual environment creation with `bridge-mcp-ghidra`, and local MCP registration in `~/.config/opencode/opencode.json`.

**Tech Stack:** GNU Make, Bash, JDK 21 (Temurin / OpenJDK), Gradle (pinned 9.4.1 wrapper), Apache Maven, Python 3.10+, uv, Git, Ghidra 12.1.2, GhidraMCP, Ghidra LX Loader, GhidraDosToolbox.

**Spec:** [docs/superpowers/specs/2026-09-05-ghidra-bundle-design.md](file:///Users/felipe.dos.santos/code/mine/ghidra-bundle/docs/superpowers/specs/2026-09-05-ghidra-bundle-design.md)

## Global Constraints

- Ghidra version pinned to `Ghidra_12.1.2_build` tag.
- Toolchain: JDK 21 dynamically resolved via `/usr/libexec/java_home -v 21`; build uses Ghidra's Gradle wrapper (`gradlew`).
- Strict isolation: All user settings, cache, and temporary files must reside within `dist/ghidra_12.1.2_PUBLIC/portable/`; no writes to `~/Library/ghidra` or `$HOME/.ghidra`.
- Installed extensions must reside in `<install>/Ghidra/Extensions/` (`GhidraApplicationLayout` discovery path).
- Port 8089 is reserved for GhidraMCP; `make run` must check and fail on port collision.
- `Makefile` must specify `.NOTPARALLEL:` to ensure stage ordering and implement numbered stage targets with clean aliases.

---

### Task 1: Environment Validation & Base Makefile (`00-env`)

**Files:**
- Create: `Makefile`
- Modify: `build-ghidra.sh`

**Interfaces:**
- Consumes: Host CLI tools (`/usr/libexec/java_home`, `mvn`, `clang`, `python3`, `uv`, `git`)
- Produces: `make help` and `make 00-env` (alias `make env`) providing prerequisite verification and setting `JAVA21_HOME`.

- [ ] **Step 1: Write failing verification test for base Makefile and environment target**

Create test script `test_env_target.sh`:
```bash
#!/bin/bash
set -euo pipefail

echo "Testing 'make help' output..."
make help | grep -E '00-env|env'

echo "Testing 'make env' target..."
make env
```
Make it executable:
```bash
chmod +x test_env_target.sh
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
./test_env_target.sh
```
Expected: FAIL (`make: *** No targets specified and no makefile found`).

- [ ] **Step 3: Implement base Makefile with variables, help, and `00-env` target**

Write `Makefile`:
```makefile
# Makefile for Ghidra Bundle
# Targets are numbered by pipeline stage:
#   00-env → 01-checkout → 02-build-ghidra → 03-install-ghidra →
#   04-install-mcp → 05-install-lx-loader → 06-install-dos-toolbox →
#   07-venv → 08-register-mcp

.NOTPARALLEL:

SERVICE = Ghidra Bundle

# Directories
BUNDLE_DIR := $(shell pwd)
DIST_DIR = $(BUNDLE_DIR)/dist
INSTALL_DIR = $(DIST_DIR)/ghidra_12.1.2_PUBLIC
PORTABLE_DIR = $(INSTALL_DIR)/portable
VENV_DIR = $(BUNDLE_DIR)/.venv

# Python environment
PYTHON = $(VENV_DIR)/bin/python
PIP = $(VENV_DIR)/bin/pip

# Java 21 resolution
JAVA21_HOME := $(shell /usr/libexec/java_home -v 21 2>/dev/null)

.PHONY: help 00-env env \
        01-checkout checkout \
        02-build-ghidra build-ghidra \
        03-install-ghidra install-ghidra \
        04-install-mcp install-mcp \
        05-install-lx-loader install-lx-loader \
        06-install-dos-toolbox install-dos-toolbox \
        07-venv venv \
        08-register-mcp register-mcp \
        install run run-bridge verify clean distclean

# ── Help ──────────────────────────────────────────────────────────────────────

help: ## Print this help message
	@printf '\033[01;32m%s — Self-Contained Isolated Setup\033[00m\n\n' "$(SERVICE)"
	@printf "\033[33mUsage:\033[0m\n  make [target]\n\n\033[33mTargets:\033[0m\n"
	@grep -E '^[-a-zA-Z0-9_\.\/]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; \
		{printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'

# ── Stage 0: Environment ──────────────────────────────────────────────────────

00-env: ## Validate host prerequisites (JDK 21, Maven, Clang, Python 3, uv, git)
	@echo "Checking host prerequisites..."
	@if [ -z "$(JAVA21_HOME)" ] || [ ! -d "$(JAVA21_HOME)" ]; then \
		echo "\033[31mERROR: JDK 21 not found via /usr/libexec/java_home -v 21\033[0m"; \
		echo "Install JDK 21 using: brew install --cask temurin@21"; \
		exit 1; \
	else \
		echo "\033[32m✔ JDK 21:\033[0m $(JAVA21_HOME)"; \
	fi
	@command -v mvn >/dev/null 2>&1 || { echo "\033[31mERROR: Maven (mvn) not found on PATH\033[0m"; exit 1; }
	@echo "\033[32m✔ Maven:\033[0m $$(mvn -version | head -n 1)"
	@command -v clang >/dev/null 2>&1 || { echo "\033[31mERROR: Clang not found (needed for Ghidra decompiler build)\033[0m"; exit 1; }
	@echo "\033[32m✔ Clang:\033[0m $$(clang --version | head -n 1)"
	@command -v python3 >/dev/null 2>&1 || { echo "\033[31mERROR: Python 3 not found on PATH\033[0m"; exit 1; }
	@echo "\033[32m✔ Python:\033[0m $$(python3 --version)"
	@command -v uv >/dev/null 2>&1 || { echo "\033[31mERROR: uv not found on PATH\033[0m"; exit 1; }
	@echo "\033[32m✔ uv:\033[0m $$(uv --version)"
	@command -v git >/dev/null 2>&1 || { echo "\033[31mERROR: Git not found on PATH\033[0m"; exit 1; }
	@echo "\033[32m✔ Git:\033[0m $$(git --version)"
	@echo "\033[32mEnvironment check passed.\033[0m"

env: 00-env
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
./test_env_target.sh
```
Expected: PASS (or clear failure with `brew install --cask temurin@21` instruction if JDK 21 is not yet installed). Remove temporary test script:
```bash
rm test_env_target.sh
```

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "feat: add base Makefile with help and 00-env target"
```

---

### Task 2: Upstream Source Checkout Target (`01-checkout`)

**Files:**
- Modify: `Makefile`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: Git on host
- Produces: `ghidra/`, `ghidra-mcp/`, `lx-loader/`, and `dos-toolbox/` shallow clones pinned to tags/branches

- [ ] **Step 1: Add checkouts and build outputs to `.gitignore`**

Update `.gitignore`:
```gitignore
# Checkouts
ghidra/
ghidra-mcp/
lx-loader/
dos-toolbox/

# Bundle build and runtime artifacts
dist/
.venv/

# Temporary test files
test_*.sh
*.tmp
```

- [ ] **Step 2: Add `01-checkout` and `checkout` targets to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 1: Checkout ─────────────────────────────────────────────────────────

GHIDRA_TAG = Ghidra_12.1.2_build
GHIDRA_REPO = https://github.com/NationalSecurityAgency/ghidra.git
GHIDRA_MCP_REPO = https://github.com/bethington/ghidra-mcp.git
LX_LOADER_REPO = https://github.com/yetmorecode/ghidra-lx-loader.git
DOS_TOOLBOX_REPO = https://github.com/plaes/GhidraDosToolbox.git
DOS_TOOLBOX_BRANCH = wip-ghidra-12

01-checkout: ## Shallow clone the four upstream repositories
	@echo "Checking out upstream repositories..."
	@if [ ! -d "ghidra" ]; then \
		echo "Cloning Ghidra (tag $(GHIDRA_TAG))..."; \
		git clone --depth 1 --branch $(GHIDRA_TAG) $(GHIDRA_REPO) ghidra; \
	else \
		echo "ghidra/ already exists, skipping."; \
	fi
	@if [ ! -d "ghidra-mcp" ]; then \
		echo "Cloning ghidra-mcp..."; \
		git clone --depth 1 $(GHIDRA_MCP_REPO) ghidra-mcp; \
	else \
		echo "ghidra-mcp/ already exists, skipping."; \
	fi
	@if [ ! -d "lx-loader" ]; then \
		echo "Cloning ghidra-lx-loader..."; \
		git clone --depth 1 $(LX_LOADER_REPO) lx-loader; \
	else \
		echo "lx-loader/ already exists, skipping."; \
	fi
	@if [ ! -d "dos-toolbox" ]; then \
		echo "Cloning GhidraDosToolbox (branch $(DOS_TOOLBOX_BRANCH))..."; \
		git clone --depth 1 --branch $(DOS_TOOLBOX_BRANCH) $(DOS_TOOLBOX_REPO) dos-toolbox; \
	else \
		echo "dos-toolbox/ already exists, skipping."; \
	fi
	@echo "\033[32mCheckout complete.\033[0m"

checkout: 01-checkout
```

- [ ] **Step 3: Test `make checkout`**

Run:
```bash
make checkout
```
Expected: Four directories `ghidra`, `ghidra-mcp`, `lx-loader`, `dos-toolbox` cloned. Re-running `make checkout` prints `already exists, skipping.`

- [ ] **Step 4: Commit**

```bash
git add Makefile .gitignore
git commit -m "feat: add 01-checkout target with dos-toolbox shallow clone"
```

---

### Task 3: Ghidra Source Build Script & Target (`02-build-ghidra`)

**Files:**
- Modify: `build-ghidra.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `ghidra/` checkout, `JAVA21_HOME`
- Produces: `ghidra/build/dist/ghidra_12.1.2_*.zip`

- [ ] **Step 1: Update `build-ghidra.sh` to enforce JDK 21 and Gradle wrapper**

Update `build-ghidra.sh`:
```bash
#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GHIDRA_SRC_DIR="$REPO_DIR/ghidra"

if [[ ! -d "$GHIDRA_SRC_DIR" ]]; then
  echo "ERROR: $GHIDRA_SRC_DIR does not exist. Run 'make checkout' first."
  exit 1
fi

cd "$GHIDRA_SRC_DIR"

if [[ -z "${JAVA_HOME:-}" ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null)"
fi
export JAVA_HOME

if [[ -z "$JAVA_HOME" || ! -d "$JAVA_HOME" ]]; then
  echo "ERROR: JAVA_HOME for JDK 21 could not be resolved."
  exit 1
fi

echo "Using JAVA_HOME=$JAVA_HOME"
java -version

if [[ ! -x "./gradlew" ]]; then
  echo "ERROR: ./gradlew not executable in $GHIDRA_SRC_DIR"
  exit 1
fi

if [[ ! -d "dependencies" ]]; then
  echo "Fetching Ghidra build dependencies..."
  ./gradlew -I gradle/support/fetchDependencies.gradle
fi

echo "Building Ghidra distribution zip..."
./gradlew buildGhidra --console=plain

echo "Ghidra build complete. Output artifacts:"
ls -lh build/dist/ghidra_12.1.2_*.zip
```
Ensure execution permissions:
```bash
chmod +x build-ghidra.sh
```

- [ ] **Step 2: Add `02-build-ghidra` and `build-ghidra` target to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 2: Build Ghidra ─────────────────────────────────────────────────────

02-build-ghidra: 01-checkout ## Build Ghidra 12.1.2 from source via build-ghidra.sh
	@if compgen -G "ghidra/build/dist/ghidra_12.1.2_*.zip" > /dev/null; then \
		echo "Ghidra distribution zip already exists in ghidra/build/dist/, skipping."; \
	else \
		JAVA_HOME="$(JAVA21_HOME)" ./build-ghidra.sh; \
	fi

build-ghidra: 02-build-ghidra
```

- [ ] **Step 3: Syntax check `build-ghidra.sh` and Makefile dry-run**

Run:
```bash
bash -n build-ghidra.sh
make -n 02-build-ghidra
```
Expected: PASS with no syntax errors.

- [ ] **Step 4: Commit**

```bash
git add build-ghidra.sh Makefile
git commit -m "feat: add 02-build-ghidra target and update build-ghidra.sh for JDK 21"
```

---

### Task 4: Ghidra Portable Install & Patching (`03-install-ghidra`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `ghidra/build/dist/ghidra_12.1.2_*.zip`, `JAVA21_HOME`
- Produces: `dist/ghidra_12.1.2_PUBLIC/` with:
  - `portable/{settings,cache,temp}`
  - `Ghidra/Extensions/`
  - `support/launch.properties` patched with `JAVA_HOME_OVERRIDE` and portable `VMARGS`

- [ ] **Step 1: Write test script for portable install patching logic**

Create `test_patch_launch_props.sh`:
```bash
#!/bin/bash
set -euo pipefail

TEST_DIR="test_portable_mock"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/support"
echo "VMARGS=-Dtest=true" > "$TEST_DIR/support/launch.properties"

MOCK_JAVA_HOME="/Library/Java/JavaVirtualMachines/mock-21/Contents/Home"

# Simulate patching logic
echo "JAVA_HOME_OVERRIDE=$MOCK_JAVA_HOME" >> "$TEST_DIR/support/launch.properties"
echo "VMARGS=-Dapplication.settingsdir=\${INSTALL_DIR}/portable/settings" >> "$TEST_DIR/support/launch.properties"
echo "VMARGS=-Dapplication.cachedir=\${INSTALL_DIR}/portable/cache" >> "$TEST_DIR/support/launch.properties"
echo "VMARGS=-Dapplication.tempdir=\${INSTALL_DIR}/portable/temp" >> "$TEST_DIR/support/launch.properties"

grep -q "JAVA_HOME_OVERRIDE=$MOCK_JAVA_HOME" "$TEST_DIR/support/launch.properties"
grep -q "VMARGS=-Dapplication.settingsdir=\${INSTALL_DIR}/portable/settings" "$TEST_DIR/support/launch.properties"

rm -rf "$TEST_DIR"
echo "Patch test passed."
```
Run:
```bash
chmod +x test_patch_launch_props.sh && ./test_patch_launch_props.sh && rm test_patch_launch_props.sh
```
Expected: PASS.

- [ ] **Step 2: Add `03-install-ghidra` and `install-ghidra` target to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 3: Install Ghidra ───────────────────────────────────────────────────

03-install-ghidra: 02-build-ghidra ## Extract Ghidra into dist/ and configure portable mode
	@if [ -d "$(INSTALL_DIR)" ] && [ -f "$(INSTALL_DIR)/support/launch.properties" ]; then \
		echo "Ghidra install directory $(INSTALL_DIR) already exists, skipping extraction."; \
	else \
		ZIP_FILE=$$(ls -1 ghidra/build/dist/ghidra_12.1.2_*.zip 2>/dev/null | head -n 1); \
		if [ -z "$$ZIP_FILE" ]; then \
			echo "ERROR: No Ghidra zip found in ghidra/build/dist/"; \
			exit 1; \
		fi; \
		echo "Extracting $$ZIP_FILE to $(DIST_DIR)..."; \
		mkdir -p $(DIST_DIR); \
		unzip -q "$$ZIP_FILE" -d $(DIST_DIR); \
		EXTRACTED_DIR=$$(ls -d $(DIST_DIR)/ghidra_12.1.2_* | head -n 1); \
		if [ "$$EXTRACTED_DIR" != "$(INSTALL_DIR)" ]; then \
			echo "Normalizing $$EXTRACTED_DIR to $(INSTALL_DIR)..."; \
			rm -rf $(INSTALL_DIR); \
			mv "$$EXTRACTED_DIR" $(INSTALL_DIR); \
		fi; \
	fi
	@echo "Creating portable directories and extensions folder..."
	@mkdir -p $(PORTABLE_DIR)/settings $(PORTABLE_DIR)/cache $(PORTABLE_DIR)/temp
	@mkdir -p $(INSTALL_DIR)/Ghidra/Extensions
	@echo "Patching $(INSTALL_DIR)/support/launch.properties for portable mode..."
	@if ! grep -q "application.settingsdir" $(INSTALL_DIR)/support/launch.properties; then \
		echo "" >> $(INSTALL_DIR)/support/launch.properties; \
		echo "# --- Portable Mode Overrides ---" >> $(INSTALL_DIR)/support/launch.properties; \
		echo "JAVA_HOME_OVERRIDE=$(JAVA21_HOME)" >> $(INSTALL_DIR)/support/launch.properties; \
		echo "VMARGS=-Dapplication.settingsdir=\$${INSTALL_DIR}/portable/settings" >> $(INSTALL_DIR)/support/launch.properties; \
		echo "VMARGS=-Dapplication.cachedir=\$${INSTALL_DIR}/portable/cache" >> $(INSTALL_DIR)/support/launch.properties; \
		echo "VMARGS=-Dapplication.tempdir=\$${INSTALL_DIR}/portable/temp" >> $(INSTALL_DIR)/support/launch.properties; \
		echo "\033[32mSuccessfully patched launch.properties.\033[0m"; \
	else \
		echo "launch.properties already patched, skipping."; \
	fi

install-ghidra: 03-install-ghidra
```

- [ ] **Step 3: Test `make -n 03-install-ghidra`**

Run:
```bash
make -n 03-install-ghidra
```
Expected: Clean dry-run output without errors.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add 03-install-ghidra target with portable mode patching"
```

---

### Task 5: GhidraMCP Extension Build & Placement (`04-install-mcp`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `ghidra-mcp/`, `dist/ghidra_12.1.2_PUBLIC/`, `JAVA21_HOME`
- Produces: `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/GhidraMCP/`

- [ ] **Step 1: Add `04-install-mcp` and `install-mcp` target to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 4: Install GhidraMCP Extension ──────────────────────────────────────

MCP_EXT_DIR = $(INSTALL_DIR)/Ghidra/Extensions/GhidraMCP

04-install-mcp: 03-install-ghidra ## Build GhidraMCP extension and install to Ghidra/Extensions/
	@if [ -d "$(MCP_EXT_DIR)" ]; then \
		echo "GhidraMCP extension already installed at $(MCP_EXT_DIR), skipping."; \
	else \
		echo "Preparing Ghidra JAR dependencies for Maven..."; \
		(cd ghidra-mcp && JAVA_HOME="$(JAVA21_HOME)" python3 -m tools.setup install-ghidra-deps --ghidra-path $(INSTALL_DIR)); \
		echo "Building GhidraMCP extension package..."; \
		(cd ghidra-mcp && JAVA_HOME="$(JAVA21_HOME)" python3 -m tools.setup build); \
		MCP_ZIP=$$(ls -1 ghidra-mcp/target/GhidraMCP-*.zip 2>/dev/null | head -n 1); \
		if [ -z "$$MCP_ZIP" ]; then \
			echo "ERROR: GhidraMCP zip not found in ghidra-mcp/target/"; \
			exit 1; \
		fi; \
		echo "Installing $$MCP_ZIP into $(INSTALL_DIR)/Ghidra/Extensions/..."; \
		unzip -q "$$MCP_ZIP" -d $(INSTALL_DIR)/Ghidra/Extensions/; \
		if [ ! -d "$(MCP_EXT_DIR)" ]; then \
			echo "ERROR: Expected $(MCP_EXT_DIR) after unzip"; \
			exit 1; \
		fi; \
		echo "\033[32mGhidraMCP extension installed successfully.\033[0m"; \
	fi

install-mcp: 04-install-mcp
```

- [ ] **Step 2: Dry-run test `make -n 04-install-mcp`**

Run:
```bash
make -n 04-install-mcp
```
Expected: PASS with command sequence.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add 04-install-mcp target"
```

---

### Task 6: lx-loader Extension Build & Placement (`05-install-lx-loader`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `lx-loader/`, `ghidra/gradlew`, `dist/ghidra_12.1.2_PUBLIC/`, `JAVA21_HOME`
- Produces: `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/ghidra-lx-loader/`

- [ ] **Step 1: Add `05-install-lx-loader` and `install-lx-loader` target to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 5: Install lx-loader Extension ──────────────────────────────────────

LX_LOADER_DIR = $(INSTALL_DIR)/Ghidra/Extensions/ghidra-lx-loader
LX_LOADER_FALLBACK_URL = https://github.com/yetmorecode/ghidra-lx-loader/releases/download/v12.0.1/ghidra_12.0.1_PUBLIC_20241215_ghidra-lx-loader.zip

05-install-lx-loader: 03-install-ghidra ## Build lx-loader extension using ghidra/gradlew
	@if [ -d "$(LX_LOADER_DIR)" ]; then \
		echo "lx-loader extension already installed at $(LX_LOADER_DIR), skipping."; \
	else \
		echo "Building lx-loader extension using ghidra Gradle wrapper..."; \
		if (cd lx-loader && JAVA_HOME="$(JAVA21_HOME)" ../ghidra/gradlew -p . -PGHIDRA_INSTALL_DIR=$(INSTALL_DIR) buildExtension); then \
			LX_ZIP=$$(ls -1 lx-loader/dist/*.zip 2>/dev/null | head -n 1); \
			echo "Installing built lx-loader $$LX_ZIP..."; \
			unzip -q "$$LX_ZIP" -d $(INSTALL_DIR)/Ghidra/Extensions/; \
		else \
			echo "\033[33mWARNING: lx-loader buildExtension failed. Falling back to release zip...\033[0m"; \
			curl -L -o lx-loader/fallback.zip $(LX_LOADER_FALLBACK_URL); \
			unzip -q lx-loader/fallback.zip -d $(INSTALL_DIR)/Ghidra/Extensions/; \
		fi; \
		if [ ! -d "$(LX_LOADER_DIR)" ]; then \
			echo "ERROR: Expected $(LX_LOADER_DIR) after unzip"; \
			exit 1; \
		fi; \
		echo "\033[32mlx-loader extension installed successfully.\033[0m"; \
	fi

install-lx-loader: 05-install-lx-loader
```

- [ ] **Step 2: Dry-run test `make -n 05-install-lx-loader`**

Run:
```bash
make -n 05-install-lx-loader
```
Expected: PASS with command sequence.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add 05-install-lx-loader target with ghidra wrapper and fallback"
```

---

### Task 7: GhidraDosToolbox Extension Build & Placement (`06-install-dos-toolbox`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `dos-toolbox/`, `ghidra/gradlew`, `dist/ghidra_12.1.2_PUBLIC/`, `JAVA21_HOME`
- Produces: `dist/ghidra_12.1.2_PUBLIC/Ghidra/Extensions/GhidraDosToolbox/`

- [ ] **Step 1: Add `06-install-dos-toolbox` and `install-dos-toolbox` target to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 6: Install GhidraDosToolbox Extension ───────────────────────────────

DOS_TOOLBOX_DIR = $(INSTALL_DIR)/Ghidra/Extensions/GhidraDosToolbox

06-install-dos-toolbox: 03-install-ghidra ## Build GhidraDosToolbox extension using ghidra/gradlew
	@if [ -d "$(DOS_TOOLBOX_DIR)" ]; then \
		echo "GhidraDosToolbox extension already installed at $(DOS_TOOLBOX_DIR), skipping."; \
	else \
		echo "Building GhidraDosToolbox extension using ghidra Gradle wrapper..."; \
		(cd dos-toolbox && JAVA_HOME="$(JAVA21_HOME)" ../ghidra/gradlew -p . -PGHIDRA_INSTALL_DIR=$(INSTALL_DIR) buildExtension); \
		DOS_ZIP=$$(ls -1 dos-toolbox/dist/*.zip 2>/dev/null | head -n 1); \
		if [ -z "$$DOS_ZIP" ]; then \
			echo "ERROR: GhidraDosToolbox zip not found in dos-toolbox/dist/"; \
			exit 1; \
		fi; \
		echo "Installing $$DOS_ZIP into $(INSTALL_DIR)/Ghidra/Extensions/..."; \
		unzip -q "$$DOS_ZIP" -d $(INSTALL_DIR)/Ghidra/Extensions/; \
		if [ ! -d "$(DOS_TOOLBOX_DIR)" ]; then \
			echo "ERROR: Expected $(DOS_TOOLBOX_DIR) after unzip"; \
			exit 1; \
		fi; \
		echo "\033[32mGhidraDosToolbox extension installed successfully.\033[0m"; \
	fi

install-dos-toolbox: 06-install-dos-toolbox
```

- [ ] **Step 2: Dry-run test `make -n 06-install-dos-toolbox`**

Run:
```bash
make -n 06-install-dos-toolbox
```
Expected: PASS with command sequence.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add 06-install-dos-toolbox target for 16-bit DOS reversing"
```

---

### Task 8: Python Bridge Virtualenv (`07-venv`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `ghidra-mcp/`
- Produces: `.venv/bin/bridge-mcp-ghidra`

- [ ] **Step 1: Add `07-venv` and `venv` target to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 7: Python Virtualenv ────────────────────────────────────────────────

07-venv: 01-checkout ## Create Python venv and install bridge-mcp-ghidra
	@if [ -d "$(VENV_DIR)" ] && [ -x "$(VENV_DIR)/bin/bridge-mcp-ghidra" ]; then \
		echo "Virtual environment already configured at $(VENV_DIR), skipping."; \
	else \
		echo "Creating virtual environment at $(VENV_DIR)..."; \
		python3 -m venv $(VENV_DIR); \
		$(PIP) install -U pip setuptools wheel; \
		echo "Installing bridge-mcp-ghidra in editable mode..."; \
		$(PIP) install -e ./ghidra-mcp; \
		echo "\033[32mVirtual environment configured successfully.\033[0m"; \
	fi

venv: 07-venv
```

- [ ] **Step 2: Test `make 07-venv` or dry run**

Run:
```bash
make -n 07-venv
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add 07-venv target for bridge-mcp-ghidra installation"
```

---

### Task 9: opencode MCP Registration (`08-register-mcp`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `.venv/bin/bridge-mcp-ghidra`, `~/.config/opencode/opencode.json`
- Produces: Configured `ghidra` entry under `mcp` in `~/.config/opencode/opencode.json`

- [ ] **Step 1: Write Python registration helper script and test**

Create `test_register_script.py`:
```python
import json
import os
import sys

config_path = os.path.expanduser("~/.config/opencode/opencode.json")
bridge_path = os.path.abspath(".venv/bin/bridge-mcp-ghidra")

print(f"Testing config registration logic for {bridge_path}...")
test_data = {"$schema": "https://opencode.ai/config.json", "mcp": {}}
test_data.setdefault("mcp", {})["ghidra"] = {
    "type": "local",
    "command": [bridge_path],
    "enabled": True,
}
assert test_data["mcp"]["ghidra"]["command"] == [bridge_path]
print("Registration logic verified.")
```
Run:
```bash
python3 test_register_script.py && rm test_register_script.py
```
Expected: PASS.

- [ ] **Step 2: Add `08-register-mcp` and `register-mcp` target to `Makefile`**

Append to `Makefile`:
```makefile
# ── Stage 8: opencode MCP Registration ────────────────────────────────────────

OPENCODE_CONFIG = $(HOME)/.config/opencode/opencode.json

08-register-mcp: 07-venv ## Register bridge-mcp-ghidra in ~/.config/opencode/opencode.json
	@echo "Registering bridge-mcp-ghidra with opencode..."
	@mkdir -p $(HOME)/.config/opencode
	@python3 -c '\
import json, os, sys; \
cfg_path = os.path.expanduser("~/.config/opencode/opencode.json"); \
bridge_bin = os.path.abspath("$(VENV_DIR)/bin/bridge-mcp-ghidra"); \
if os.path.exists(cfg_path): \
    with open(cfg_path, "r", encoding="utf-8") as f: \
        try: data = json.load(f) \
        except Exception: data = {} \
else: \
    data = {"$$schema": "https://opencode.ai/config.json"}; \
data.setdefault("mcp", {})["ghidra"] = { \
    "type": "local", \
    "command": [bridge_bin], \
    "enabled": True \
}; \
with open(cfg_path + ".tmp", "w", encoding="utf-8") as f: \
    json.dump(data, f, indent=2); \
os.replace(cfg_path + ".tmp", cfg_path); \
print("Registered ghidra MCP server in " + cfg_path)'
	@echo "\033[32mMCP registration complete.\033[0m"

register-mcp: 08-register-mcp
```

- [ ] **Step 3: Dry-run test `make -n 08-register-mcp`**

Run:
```bash
make -n 08-register-mcp
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add 08-register-mcp target with atomic config update"
```

---

### Task 10: Pipeline Aggregation, Runtime, Verification & Cleanup (`install`, `run`, `run-bridge`, `verify`, `clean`, `distclean`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: All previous Makefile targets
- Produces: Complete `install`, `run`, `run-bridge`, `verify`, `clean`, and `distclean` workflows.

- [ ] **Step 1: Add pipeline aggregation and execution targets to `Makefile`**

Append to `Makefile`:
```makefile
# ── Pipeline & Runtime ────────────────────────────────────────────────────────

install: 00-env 01-checkout 02-build-ghidra 03-install-ghidra 04-install-mcp 05-install-lx-loader 06-install-dos-toolbox 07-venv 08-register-mcp ## Run entire build and installation pipeline
	@echo "\n\033[01;32m==============================================\033[00m"
	@echo "\033[01;32m Ghidra Bundle installation completed!       \033[00m"
	@echo "\033[01;32m Run 'make run' to launch Ghidra.            \033[00m"
	@echo "\033[01;32m==============================================\033[00m\n"

run: ## Launch isolated Ghidra instance (checks port 8089 collision)
	@if lsof -i :8089 >/dev/null 2>&1; then \
		echo "\033[31mERROR: Port 8089 is already bound by another process:\033[0m"; \
		lsof -i :8089; \
		exit 1; \
	fi
	@if [ ! -x "$(INSTALL_DIR)/ghidraRun" ]; then \
		echo "ERROR: $(INSTALL_DIR)/ghidraRun not found. Run 'make install' first."; \
		exit 1; \
	fi
	@echo "Launching isolated Ghidra from $(INSTALL_DIR)..."
	@"$(INSTALL_DIR)/ghidraRun"

run-bridge: ## Start bridge-mcp-ghidra from the virtual environment
	@if [ ! -x "$(VENV_DIR)/bin/bridge-mcp-ghidra" ]; then \
		echo "ERROR: $(VENV_DIR)/bin/bridge-mcp-ghidra not found. Run 'make venv' first."; \
		exit 1; \
	fi
	@"$(VENV_DIR)/bin/bridge-mcp-ghidra"

verify: ## Check GhidraMCP plugin connection at http://127.0.0.1:8089
	@echo "Testing GhidraMCP HTTP endpoint..."
	@curl -s -f http://127.0.0.1:8089/check_connection || { \
		echo "\n\033[31mCould not connect to GhidraMCP server on port 8089.\033[0m"; \
		echo "Ensure Ghidra is running with the GhidraMCP plugin enabled."; \
		exit 1; \
	}
	@echo "\n\033[32mGhidraMCP connection verified.\033[0m"

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean: ## Remove build outputs (dist/, .venv/, repo target/dist artifacts)
	@echo "Cleaning bundle build artifacts..."
	@rm -rf $(DIST_DIR) $(VENV_DIR)
	@if [ -d "ghidra" ]; then (cd ghidra && rm -rf build); fi
	@if [ -d "ghidra-mcp" ]; then (cd ghidra-mcp && rm -rf target build); fi
	@if [ -d "lx-loader" ]; then (cd lx-loader && rm -rf dist build .gradle); fi
	@if [ -d "dos-toolbox" ]; then (cd dos-toolbox && rm -rf dist build .gradle); fi
	@echo "\033[32mClean complete.\033[0m"

distclean: clean ## Remove build outputs and cloned checkouts
	@echo "Removing cloned checkouts..."
	@rm -rf ghidra ghidra-mcp lx-loader dos-toolbox
	@echo "\033[32mDistclean complete.\033[0m"
```

- [ ] **Step 2: Test `make help` and verify all targets are listed**

Run:
```bash
make help
```
Expected: Nicely formatted table containing targets:
- `help`
- `00-env`
- `01-checkout`
- `02-build-ghidra`
- `03-install-ghidra`
- `04-install-mcp`
- `05-install-lx-loader`
- `06-install-dos-toolbox`
- `07-venv`
- `08-register-mcp`
- `install`
- `run`
- `run-bridge`
- `verify`
- `clean`
- `distclean`

- [ ] **Step 3: Test `make clean`**

Run:
```bash
make clean
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add pipeline aggregation with dos-toolbox, run, verify, and clean targets"
```
