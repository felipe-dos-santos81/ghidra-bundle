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
