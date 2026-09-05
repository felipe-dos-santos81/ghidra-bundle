# Makefile for Ghidra Bundle
# Targets are numbered by pipeline stage:
#   00-env → 01-checkout → 02-build-ghidra → 03-install-ghidra →
#   04-install-mcp → 05-install-lx-loader → 06-install-dos-toolbox →
#   07-venv → 08-register-mcp

.NOTPARALLEL:
.DEFAULT_GOAL := help

SHELL := /bin/bash

SERVICE = Ghidra Bundle

# Directories
BUNDLE_DIR := $(CURDIR)
DIST_DIR = $(BUNDLE_DIR)/dist
INSTALL_DIR = $(DIST_DIR)/ghidra_12.1.2_PUBLIC
PORTABLE_DIR = $(INSTALL_DIR)/portable
VENV_DIR = $(BUNDLE_DIR)/.venv

# Python environment
PIP = $(VENV_DIR)/bin/pip
BRIDGE_BIN = $(VENV_DIR)/bin/bridge-mcp-ghidra

# Java 21 resolution and environment propagation
JAVA21_HOME ?= $(shell /usr/libexec/java_home -F -v 21 2>/dev/null)
export JAVA_HOME := $(JAVA21_HOME)
export PATH := $(JAVA21_HOME)/bin:$(PATH)

# Reusable Macros

define install_extension_zip
	ZIP=$$(ls -1t $(1) 2>/dev/null | head -n 1); \
	if [ -z "$$ZIP" ]; then \
		echo "ERROR: Extension zip not found in $(1)"; \
		exit 1; \
	fi; \
	echo "Installing $$ZIP into $(INSTALL_DIR)/Ghidra/Extensions/..."; \
	unzip -q -o "$$ZIP" -d "$(INSTALL_DIR)/Ghidra/Extensions/"; \
	if [ -n "$(3)" ] && [ -d "$(INSTALL_DIR)/Ghidra/Extensions/$(3)" ] && [ ! -d "$(2)" ]; then \
		mv "$(INSTALL_DIR)/Ghidra/Extensions/$(3)" "$(2)"; \
	fi; \
	if [ ! -d "$(2)" ]; then \
		echo "ERROR: Expected $(2) after unzip"; \
		exit 1; \
	fi
endef

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
		printf '\033[31mERROR: JDK 21 not found via /usr/libexec/java_home -F -v 21\033[0m\n'; \
		echo "Install JDK 21 using: brew install --cask temurin@21"; \
		exit 1; \
	else \
		printf '\033[32m✔ JDK 21:\033[0m %s\n' "$(JAVA21_HOME)"; \
	fi
	@command -v mvn >/dev/null 2>&1 || { printf '\033[31mERROR: Maven (mvn) not found on PATH\033[0m\n'; exit 1; }
	@printf '\033[32m✔ Maven:\033[0m %s\n' "$$(mvn -version | head -n 1)"
	@command -v clang >/dev/null 2>&1 || { printf '\033[31mERROR: Clang not found (needed for Ghidra decompiler build)\033[0m\n'; exit 1; }
	@printf '\033[32m✔ Clang:\033[0m %s\n' "$$(clang --version | head -n 1)"
	@command -v python3 >/dev/null 2>&1 || { printf '\033[31mERROR: Python 3 not found on PATH\033[0m\n'; exit 1; }
	@printf '\033[32m✔ Python:\033[0m %s\n' "$$(python3 --version)"
	@command -v uv >/dev/null 2>&1 || { printf '\033[31mERROR: uv not found on PATH\033[0m\n'; exit 1; }
	@printf '\033[32m✔ uv:\033[0m %s\n' "$$(uv --version)"
	@command -v git >/dev/null 2>&1 || { printf '\033[31mERROR: Git not found on PATH\033[0m\n'; exit 1; }
	@printf '\033[32m✔ Git:\033[0m %s\n' "$$(git --version)"
	@printf '\033[32mEnvironment check passed.\033[0m\n'

env: 00-env

# ── Stage 1: Checkout ─────────────────────────────────────────────────────────
 
01-checkout: ## Initialize and update git submodules
	@echo "Updating git submodules..."
	git submodule update --init --recursive --depth 1
	@printf '\033[32mSubmodule checkout complete.\033[0m\n'

checkout: 01-checkout

# ── Stage 2: Build Ghidra ─────────────────────────────────────────────────────

02-build-ghidra: 01-checkout ## Build Ghidra 12.1.2 from source via build-ghidra.sh
	@if compgen -G "ghidra/build/dist/ghidra_12.1.2_*.zip" > /dev/null; then \
		echo "Ghidra distribution zip already exists in ghidra/build/dist/, skipping."; \
	else \
		./build-ghidra.sh; \
	fi

build-ghidra: 02-build-ghidra

# ── Stage 3: Install Ghidra ───────────────────────────────────────────────────

03-install-ghidra: 02-build-ghidra ## Extract Ghidra into dist/ and configure portable mode
	@if [ -d "$(INSTALL_DIR)" ] && [ -f "$(INSTALL_DIR)/support/launch.properties" ] && grep -q "^# --- Portable Mode Overrides ---" "$(INSTALL_DIR)/support/launch.properties"; then \
		echo "Ghidra install directory $(INSTALL_DIR) already exists and configured, skipping."; \
	else \
		ZIP_FILE=$$(ls -1t ghidra/build/dist/ghidra_12.1.2_*.zip 2>/dev/null | head -n 1); \
		if [ -z "$$ZIP_FILE" ]; then \
			echo "ERROR: No Ghidra zip found in ghidra/build/dist/"; \
			exit 1; \
		fi; \
		echo "Extracting $$ZIP_FILE to $(DIST_DIR)..."; \
		mkdir -p "$(DIST_DIR)"; \
		unzip -q -o "$$ZIP_FILE" -d "$(DIST_DIR)"; \
		EXTRACTED_DIR=$$(ls -d $(DIST_DIR)/ghidra_12.1.2_* | head -n 1); \
		if [ "$$EXTRACTED_DIR" != "$(INSTALL_DIR)" ]; then \
			echo "Normalizing $$EXTRACTED_DIR to $(INSTALL_DIR)..."; \
			rm -rf "$(INSTALL_DIR)"; \
			mv "$$EXTRACTED_DIR" "$(INSTALL_DIR)"; \
		fi; \
		echo "Creating portable directories and extensions folder..."; \
		mkdir -p "$(PORTABLE_DIR)/settings" "$(PORTABLE_DIR)/cache" "$(PORTABLE_DIR)/temp"; \
		mkdir -p "$(INSTALL_DIR)/Ghidra/Extensions"; \
		echo "Patching $(INSTALL_DIR)/support/launch.properties for portable mode..."; \
		{ \
			echo ""; \
			echo "# --- Portable Mode Overrides ---"; \
			echo "JAVA_HOME_OVERRIDE=$(JAVA21_HOME)"; \
			echo "VMARGS=-Dapplication.settingsdir=\$${INSTALL_DIR}/portable/settings"; \
			echo "VMARGS=-Dapplication.cachedir=\$${INSTALL_DIR}/portable/cache"; \
			echo "VMARGS=-Dapplication.tempdir=\$${INSTALL_DIR}/portable/temp"; \
		} >> "$(INSTALL_DIR)/support/launch.properties"; \
		printf '\033[32mSuccessfully patched launch.properties.\033[0m\n'; \
	fi

install-ghidra: 03-install-ghidra

# ── Stage 4: Install GhidraMCP Extension ──────────────────────────────────────

MCP_EXT_DIR = $(INSTALL_DIR)/Ghidra/Extensions/GhidraMCP

04-install-mcp: 03-install-ghidra ## Build GhidraMCP extension and install to Ghidra/Extensions/
	@if [ -d "$(MCP_EXT_DIR)" ]; then \
		echo "GhidraMCP extension already installed at $(MCP_EXT_DIR), skipping."; \
	else \
		echo "Preparing Ghidra JAR dependencies for Maven..."; \
		(cd ghidra-mcp && python3 -m tools.setup install-ghidra-deps --ghidra-path "$(INSTALL_DIR)") || exit 1; \
		echo "Building GhidraMCP extension package..."; \
		(cd ghidra-mcp && python3 -m tools.setup build) || exit 1; \
		$(call install_extension_zip,ghidra-mcp/target/GhidraMCP-*.zip,$(MCP_EXT_DIR)); \
		printf '\033[32mGhidraMCP extension installed successfully.\033[0m\n'; \
	fi

install-mcp: 04-install-mcp

# ── Stage 5: Install lx-loader Extension ──────────────────────────────────────

LX_LOADER_DIR = $(INSTALL_DIR)/Ghidra/Extensions/ghidra-lx-loader
LX_LOADER_FALLBACK_URL = https://github.com/yetmorecode/ghidra-lx-loader/releases/download/v12.0.1/ghidra_12.0.1_PUBLIC_20260129_ghidra-lx-loader.zip

05-install-lx-loader: 03-install-ghidra ## Build lx-loader extension using ghidra/gradlew
	@if [ -d "$(LX_LOADER_DIR)" ]; then \
		echo "lx-loader extension already installed at $(LX_LOADER_DIR), skipping."; \
	else \
		echo "Building lx-loader extension using ghidra Gradle wrapper..."; \
		if (cd lx-loader && ../ghidra/gradlew -p . -PGHIDRA_INSTALL_DIR="$(INSTALL_DIR)" buildExtension); then \
			$(call install_extension_zip,lx-loader/dist/*.zip,$(LX_LOADER_DIR),lx-loader); \
		else \
			printf '\033[33mWARNING: lx-loader buildExtension failed. Falling back to release zip...\033[0m\n'; \
			curl -f -L -o lx-loader/fallback.zip "$(LX_LOADER_FALLBACK_URL)" || exit 1; \
			$(call install_extension_zip,lx-loader/fallback.zip,$(LX_LOADER_DIR),lx-loader); \
		fi; \
		printf '\033[32mlx-loader extension installed successfully.\033[0m\n'; \
	fi

install-lx-loader: 05-install-lx-loader

# ── Stage 6: Install GhidraDosToolbox Extension ───────────────────────────────

DOS_TOOLBOX_DIR = $(INSTALL_DIR)/Ghidra/Extensions/GhidraDosToolbox

06-install-dos-toolbox: 03-install-ghidra ## Build GhidraDosToolbox extension using ghidra/gradlew
	@if [ -d "$(DOS_TOOLBOX_DIR)" ]; then \
		echo "GhidraDosToolbox extension already installed at $(DOS_TOOLBOX_DIR), skipping."; \
	else \
		echo "Building GhidraDosToolbox extension using ghidra Gradle wrapper..."; \
		(cd dos-toolbox && ../ghidra/gradlew -p . -PGHIDRA_INSTALL_DIR="$(INSTALL_DIR)" buildExtension) || exit 1; \
		$(call install_extension_zip,dos-toolbox/dist/*.zip,$(DOS_TOOLBOX_DIR),dos-toolbox); \
		printf '\033[32mGhidraDosToolbox extension installed successfully.\033[0m\n'; \
	fi

install-dos-toolbox: 06-install-dos-toolbox

# ── Stage 7: Python Virtualenv ────────────────────────────────────────────────

07-venv: 01-checkout ## Create Python venv and install bridge-mcp-ghidra
	@if [ -d "$(VENV_DIR)" ] && [ -x "$(BRIDGE_BIN)" ]; then \
		echo "Virtual environment already configured at $(VENV_DIR), skipping."; \
	else \
		echo "Creating virtual environment at $(VENV_DIR)..."; \
		python3 -m venv "$(VENV_DIR)" || exit 1; \
		echo "Installing bridge-mcp-ghidra in editable mode..."; \
		"$(PIP)" install -e ./ghidra-mcp || exit 1; \
		printf '\033[32mVirtual environment configured successfully.\033[0m\n'; \
	fi

venv: 07-venv

# ── Stage 8: opencode MCP Registration ────────────────────────────────────────

OPENCODE_CONFIG = $(HOME)/.config/opencode/opencode.json

08-register-mcp: 07-venv ## Register bridge-mcp-ghidra in ~/.config/opencode/opencode.json
	@echo "Registering bridge-mcp-ghidra with opencode..."
	@mkdir -p "$$(dirname "$(OPENCODE_CONFIG)")"
	@python3 -c '\
import json, os; \
cfg_path = os.path.expanduser("$(OPENCODE_CONFIG)"); \
bridge_bin = os.path.abspath("$(BRIDGE_BIN)"); \
data = None; \
if os.path.exists(cfg_path): \
    with open(cfg_path, "r", encoding="utf-8") as f: \
        try: data = json.load(f) \
        except Exception: pass; \
if data is None: \
    data = {"$$schema": "https://opencode.ai/config.json"}; \
entry = {"type": "local", "command": [bridge_bin], "enabled": True}; \
if data.get("mcp", {}).get("ghidra") == entry: \
    print("Ghidra MCP server already registered in " + cfg_path); \
else: \
    data.setdefault("mcp", {})["ghidra"] = entry; \
    with open(cfg_path + ".tmp", "w", encoding="utf-8") as f: \
        json.dump(data, f, indent=2); \
    os.replace(cfg_path + ".tmp", cfg_path); \
    print("Registered ghidra MCP server in " + cfg_path)'
	@printf '\033[32mMCP registration complete.\033[0m\n'

register-mcp: 08-register-mcp

# ── Pipeline & Runtime ────────────────────────────────────────────────────────

install: 00-env 01-checkout 02-build-ghidra 03-install-ghidra 04-install-mcp 05-install-lx-loader 06-install-dos-toolbox 07-venv 08-register-mcp ## Run entire build and installation pipeline
	@printf '\n\033[01;32m==============================================\033[00m\n'
	@printf '\033[01;32m Ghidra Bundle installation completed!       \033[00m\n'
	@printf '\033[01;32m Run '\''make run'\'' to launch Ghidra.            \033[00m\n'
	@printf '\033[01;32m==============================================\033[00m\n\n'

run: ## Launch isolated Ghidra instance (checks port 8089 collision)
	@if lsof -i :8089 >/dev/null 2>&1; then \
		printf '\033[31mERROR: Port 8089 is already bound by another process:\033[0m\n'; \
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
	@if [ ! -x "$(BRIDGE_BIN)" ]; then \
		echo "ERROR: $(BRIDGE_BIN) not found. Run 'make venv' first."; \
		exit 1; \
	fi
	@"$(BRIDGE_BIN)"

verify: ## Check GhidraMCP plugin connection at http://127.0.0.1:8089
	@echo "Testing GhidraMCP HTTP endpoint..."
	@curl -s -f http://127.0.0.1:8089/check_connection || { \
		printf '\n\033[31mCould not connect to GhidraMCP server on port 8089.\033[0m\n'; \
		echo "Ensure Ghidra is running with the GhidraMCP plugin enabled."; \
		exit 1; \
	}
	@printf '\n\033[32mGhidraMCP connection verified.\033[0m\n'

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean: ## Remove build outputs (dist/, .venv/, repo target/dist artifacts)
	@echo "Cleaning bundle build artifacts..."
	@rm -rf $(DIST_DIR) $(VENV_DIR) \
		ghidra/build \
		ghidra-mcp/target ghidra-mcp/build \
		lx-loader/dist lx-loader/build lx-loader/.gradle lx-loader/fallback.zip \
		dos-toolbox/dist dos-toolbox/build dos-toolbox/.gradle
	@printf '\033[32mClean complete.\033[0m\n'

distclean: clean ## Remove build outputs and de-initialize submodules
	@echo "De-initializing submodules..."
	git submodule deinit -f --all
	@printf '\033[32mDistclean complete.\033[0m\n'
