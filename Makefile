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
JAVA21_HOME := $(shell /usr/libexec/java_home -F -v 21 2>/dev/null)

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
		echo "\033[31mERROR: JDK 21 not found via /usr/libexec/java_home -F -v 21\033[0m"; \
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

# ── Stage 2: Build Ghidra ─────────────────────────────────────────────────────

02-build-ghidra: 01-checkout ## Build Ghidra 12.1.2 from source via build-ghidra.sh
	@if compgen -G "ghidra/build/dist/ghidra_12.1.2_*.zip" > /dev/null; then \
		echo "Ghidra distribution zip already exists in ghidra/build/dist/, skipping."; \
	else \
		JAVA_HOME="$(JAVA21_HOME)" ./build-ghidra.sh; \
	fi

build-ghidra: 02-build-ghidra

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
