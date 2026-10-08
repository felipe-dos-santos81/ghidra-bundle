# Ghidra Bundle: portable Ghidra built from source, with GhidraMCP, lx-loader
# and GhidraDosToolbox. `make install` runs the numbered stages in order:
#   00-deps → 00-env → 01-checkout → 02-build-ghidra → 03-install-ghidra →
#   04-install-mcp → 05-install-lx-loader → 06-install-dos-toolbox →
#   verify-extensions → 07-venv → 08-register-mcp → test
# Every stage is idempotent and skips work that is already done.

.NOTPARALLEL:
.DEFAULT_GOAL := help
SHELL := /bin/bash

# ── Configuration ─────────────────────────────────────────────────────────────

# Must match application.version in the ghidra submodule (checked by stage 02).
GHIDRA_VERSION := 12.1.4
MCP_PORT := 8089

BUNDLE_DIR := $(CURDIR)
DIST_DIR := $(BUNDLE_DIR)/dist
PACKAGES_DIR := $(DIST_DIR)/packages
INSTALL_DIR := $(DIST_DIR)/ghidra_$(GHIDRA_VERSION)_PUBLIC
PORTABLE_DIR := $(INSTALL_DIR)/portable
EXT_DIR := $(INSTALL_DIR)/Ghidra/Extensions
VENV_DIR := $(BUNDLE_DIR)/.venv
BRIDGE_BIN := $(VENV_DIR)/bin/bridge-mcp-ghidra
OPENCODE_CONFIG := $(HOME)/.config/opencode/opencode.json

UNAME_S := $(shell uname -s)
# GNU timeout, needed by `make test`: coreutils on Linux, Homebrew's gtimeout on macOS.
TIMEOUT_CMD := $(if $(filter Darwin,$(UNAME_S)),gtimeout,timeout)

# JDK 21: JAVA21_HOME if given, else $JAVA_HOME, /usr/lib/jvm/*21*, or javac on PATH.
ifndef JAVA21_HOME
ifeq ($(UNAME_S),Darwin)
JAVA21_HOME := $(shell /usr/libexec/java_home -F -v 21 2>/dev/null)
else
JAVA21_HOME := $(shell for j in "$$JAVA_HOME" /usr/lib/jvm/*21* \
	"$$(dirname "$$(dirname "$$(readlink -f "$$(command -v javac)" 2>/dev/null)")")"; do \
	[ -n "$$j" ] && [ -x "$$j/bin/java" ] && "$$j/bin/java" -version 2>&1 | grep -q 'version "21' && { readlink -f "$$j"; break; }; \
	done)
endif
endif
export JAVA_HOME := $(JAVA21_HOME)
export PATH := $(JAVA21_HOME)/bin:$(HOME)/.local/bin:$(HOME)/.cargo/bin:$(PATH)

# Message helpers: $(OK) "text", $(WARN) "text", $(ERR) "text"
OK = printf '\033[32m%s\033[0m\n'
WARN = printf '\033[33m%s\033[0m\n'
ERR = printf '\033[31mERROR: %s\033[0m\n'

# Ghidra's own zip name ends in its platform (linux_arm_64, mac_x86_64, ...). Extension
# zips also start with ghidra_<version>_, so match on "_64.zip" to tell them apart.
GHIDRA_ZIP = ghidra_$(1)_*_64.zip

.PHONY: help 00-deps deps 00-env env 01-checkout checkout 02-build-ghidra build-ghidra \
	03-install-ghidra install-ghidra 04-install-mcp install-mcp \
	05-install-lx-loader install-lx-loader 06-install-dos-toolbox install-dos-toolbox \
	verify-extensions test 07-venv venv 08-register-mcp register-mcp \
	install run run-bridge verify clean distclean

help: ## Show this help
	@printf '\033[01;32mGhidra Bundle (Ghidra $(GHIDRA_VERSION))\033[0m\n\nUsage: make <target>\n\n'
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

# ── Stage 0: Host prerequisites ───────────────────────────────────────────────

00-deps: ## Install missing OS packages (apt or brew) and uv
	@if [ "$(UNAME_S)" = "Darwin" ]; then \
		[ -d "$(JAVA21_HOME)" ] || brew install --cask temurin@21; \
		for p in maven:mvn python@3.12:python3 uv:uv git:git coreutils:gtimeout; do \
			command -v $${p#*:} >/dev/null 2>&1 || brew install $${p%%:*}; \
		done; \
		command -v clang >/dev/null 2>&1 || xcode-select --install; \
	else \
		PKGS=""; \
		[ -d "$(JAVA21_HOME)" ] || PKGS+=" openjdk-21-jdk"; \
		for p in maven:mvn clang:clang git:git curl:curl; do \
			command -v $${p#*:} >/dev/null 2>&1 || PKGS+=" $${p%%:*}"; \
		done; \
		python3 -c 'import venv' >/dev/null 2>&1 || PKGS+=" python3 python3-venv"; \
		if [ -n "$$PKGS" ]; then sudo apt update && sudo apt install -y $$PKGS || exit 1; \
		else echo "All OS packages present."; fi; \
		command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh || exit 1; \
	fi
	@$(OK) "System dependencies ready."

# $(call check_tool,command,label,version command)
check_tool = command -v $(1) >/dev/null 2>&1 || { $(ERR) "$(2) not found on PATH (run 'make deps')"; exit 1; }; \
	printf '\033[32m✔ %-7s\033[0m %s\n' "$(2)" "$$($(3) 2>&1 | head -n 1)"

00-env: ## Check host prerequisites (JDK 21, Maven, Clang, Python 3, uv, Git, curl, GNU timeout)
	@[ -d "$(JAVA21_HOME)" ] || { $(ERR) "JDK 21 not found (run 'make deps')"; exit 1; }
	@printf '\033[32m✔ %-7s\033[0m %s\n' "JDK 21" "$(JAVA21_HOME)"
	@$(call check_tool,mvn,Maven,mvn -version)
	@$(call check_tool,clang,Clang,clang --version)
	@$(call check_tool,python3,Python,python3 --version)
	@$(call check_tool,uv,uv,uv --version)
	@$(call check_tool,git,Git,git --version)
	@$(call check_tool,curl,curl,curl --version)
	@$(call check_tool,$(TIMEOUT_CMD),timeout,$(TIMEOUT_CMD) --version)
	@$(OK) "Environment check passed."

deps: 00-deps
env: 00-env

# ── Stages 1–3: Ghidra ────────────────────────────────────────────────────────

01-checkout: ## Fetch the pinned submodules (shallow)
	git submodule sync --recursive --quiet
	git submodule update --init --recursive --depth 1

02-build-ghidra: 01-checkout ## Build the Ghidra distribution zip from source into dist/packages/
	@grep -qx 'application.version=$(GHIDRA_VERSION)' ghidra/Ghidra/application.properties || \
		{ $(ERR) "ghidra submodule is not Ghidra $(GHIDRA_VERSION): update GHIDRA_VERSION or the submodule"; exit 1; }
	@if compgen -G "$(PACKAGES_DIR)/$(call GHIDRA_ZIP,$(GHIDRA_VERSION))" >/dev/null; then \
		echo "Ghidra $(GHIDRA_VERSION) zip already in $(PACKAGES_DIR), skipping."; \
	else \
		compgen -G "ghidra/build/dist/$(call GHIDRA_ZIP,$(GHIDRA_VERSION))" >/dev/null || ./build-ghidra.sh || exit 1; \
		ZIP=$$(ls -1t ghidra/build/dist/$(call GHIDRA_ZIP,$(GHIDRA_VERSION)) 2>/dev/null | head -n 1); \
		[ -n "$$ZIP" ] || { $(ERR) "no Ghidra $(GHIDRA_VERSION) zip in ghidra/build/dist/"; exit 1; }; \
		mkdir -p "$(PACKAGES_DIR)" && rm -f "$(PACKAGES_DIR)"/$(call GHIDRA_ZIP,*) && \
			mv "$$ZIP" "$(PACKAGES_DIR)/" && rm -f ghidra/build/dist/$(call GHIDRA_ZIP,$(GHIDRA_VERSION)) || exit 1; \
		$(OK) "Moved $${ZIP##*/} to $(PACKAGES_DIR)."; \
	fi

03-install-ghidra: 02-build-ghidra ## Extract Ghidra into dist/ and enable portable mode
	@if grep -qs '^# --- Portable Mode Overrides ---' "$(INSTALL_DIR)/support/launch.properties"; then \
		echo "$(INSTALL_DIR) already installed, skipping."; \
	else \
		ZIP=$$(ls -1t "$(PACKAGES_DIR)"/$(call GHIDRA_ZIP,$(GHIDRA_VERSION)) 2>/dev/null | head -n 1); \
		[ -n "$$ZIP" ] || { $(ERR) "no Ghidra zip in $(PACKAGES_DIR)/"; exit 1; }; \
		mkdir -p "$(DIST_DIR)"; \
		TMP=$$(mktemp -d "$(DIST_DIR)/.extract-XXXXXX"); \
		unzip -q -o "$$ZIP" -d "$$TMP" || exit 1; \
		rm -rf "$(INSTALL_DIR)"; \
		mv "$$TMP"/ghidra_$(GHIDRA_VERSION)_* "$(INSTALL_DIR)" && rmdir "$$TMP" || exit 1; \
		mkdir -p "$(PORTABLE_DIR)"/{settings,cache,temp} "$(EXT_DIR)"; \
		printf '%s\n' '' '# --- Portable Mode Overrides ---' \
			'JAVA_HOME_OVERRIDE=$(JAVA21_HOME)' \
			'VMARGS=-Dapplication.settingsdir=$${INSTALL_DIR}/portable/settings' \
			'VMARGS=-Dapplication.cachedir=$${INSTALL_DIR}/portable/cache' \
			'VMARGS=-Dapplication.tempdir=$${INSTALL_DIR}/portable/temp' \
			>> "$(INSTALL_DIR)/support/launch.properties"; \
		$(OK) "Installed $(INSTALL_DIR) in portable mode."; \
	fi

checkout: 01-checkout
build-ghidra: 02-build-ghidra
install-ghidra: 03-install-ghidra

# ── Stages 4–6: Extensions ────────────────────────────────────────────────────

# $(call install_extension,directory,source dir,zip glob[,legacy directory to remove][,gradle subdir])
# Builds an extension with ghidra/gradlew (in <source dir>/<gradle subdir>), moves the
# zip into $(PACKAGES_DIR) and unzips it into $(EXT_DIR). The zip glob names the build
# output and contains $(GHIDRA_VERSION); older versions of that zip in $(PACKAGES_DIR)
# and stale builds left in the build folder are deleted. The source commit is recorded
# in <ext>/.bundle-source; the stage rebuilds when it changes or when the zip is
# missing from $(PACKAGES_DIR).
# Never rename the unzipped directory: Ghidra only loads classes from
# <ext>/lib/<jar> when the jar name starts with the directory name, so a
# renamed extension silently loses its loaders, analyzers and plugins.
define install_extension
@SRC=$$(git -C $(2) rev-parse HEAD 2>/dev/null); \
if [ -d "$(EXT_DIR)/$(1)" ] && compgen -G "$(PACKAGES_DIR)/$(notdir $(3))" >/dev/null && \
	{ [ -z "$$SRC" ] || [ "$$(cat "$(EXT_DIR)/$(1)/.bundle-source" 2>/dev/null)" = "$$SRC" ]; }; then \
	echo "$(1) already installed$${SRC:+ from $${SRC:0:7}}, skipping."; \
else \
	echo "Building $(1)$${SRC:+ from $${SRC:0:7}}..."; \
	(cd "$(2)/$(or $(5),.)" && "$(BUNDLE_DIR)/ghidra/gradlew" -p . \
		-PGHIDRA_INSTALL_DIR="$(INSTALL_DIR)" buildExtension) || exit 1; \
	ZIP=$$(ls -1t $(3) 2>/dev/null | head -n 1); \
	[ -n "$$ZIP" ] || { $(ERR) "no zip matching $(3)"; exit 1; }; \
	mkdir -p "$(PACKAGES_DIR)" && rm -f "$(PACKAGES_DIR)"/$(subst $(GHIDRA_VERSION),*,$(notdir $(3))) && \
		mv "$$ZIP" "$(PACKAGES_DIR)/" && rm -f $(3) || exit 1; \
	ZIP="$(PACKAGES_DIR)/$${ZIP##*/}"; \
	rm -rf "$(EXT_DIR)/$(1)" $(if $(4),"$(EXT_DIR)/$(4)"); \
	unzip -q -o "$$ZIP" -d "$(EXT_DIR)" || exit 1; \
	[ -d "$(EXT_DIR)/$(1)" ] || { $(ERR) "$$ZIP did not create $(EXT_DIR)/$(1)"; exit 1; }; \
	[ -z "$$SRC" ] || echo "$$SRC" > "$(EXT_DIR)/$(1)/.bundle-source"; \
	$(OK) "$(1) installed ($${ZIP##*/} in $(PACKAGES_DIR))."; \
fi
endef

04-install-mcp: 03-install-ghidra ## Build and install the GhidraMCP extension
	$(call install_extension,GhidraMCP,ghidra-mcp,ghidra-mcp/build/distributions/GhidraMCP-*.zip)

05-install-lx-loader: 03-install-ghidra ## Build and install the lx-loader extension
	$(call install_extension,lx-loader,lx-loader,lx-loader/dist/ghidra_$(GHIDRA_VERSION)_*_lx-loader.zip,ghidra-lx-loader)

06-install-dos-toolbox: 03-install-ghidra ## Build and install the GhidraDosToolbox extension
	$(call install_extension,dos-toolbox,dos-toolbox,dos-toolbox/dist/ghidra_$(GHIDRA_VERSION)_*_dos-toolbox.zip,GhidraDosToolbox)

verify-extensions: ## Check headlessly that Ghidra loads every extension's classes
	@[ -x "$(INSTALL_DIR)/support/analyzeHeadless" ] || { $(ERR) "Ghidra not installed; run 'make install'"; exit 1; }
	@echo "Checking extension class discovery (headless)..."
	@WORK=$$(mktemp -d "$(PORTABLE_DIR)/temp/verify-extensions-XXXXXX"); \
	trap 'rm -rf "$$WORK"' EXIT; \
	printf '\x90\xc3' > "$$WORK/probe.bin"; \
	"$(INSTALL_DIR)/support/analyzeHeadless" "$$WORK" probe -import "$$WORK/probe.bin" \
		-loader BinaryLoader -processor x86:LE:32:default -noanalysis -deleteProject \
		-scriptPath "$(BUNDLE_DIR)/ghidra_scripts" -preScript VerifyExtensions.java \
		> "$$WORK/headless.log" 2>&1 || { tail -20 "$$WORK/headless.log"; exit 1; }; \
	grep -o 'VERIFY [A-Z]* [^(]*' "$$WORK/headless.log" | sed 's/^VERIFY /  /'; \
	if grep -q 'VERIFY MISSING' "$$WORK/headless.log"; then \
		$(ERR) "some extension classes were not loaded (is an extension directory renamed?)"; exit 1; \
	elif ! grep -q 'VERIFY OK' "$$WORK/headless.log"; then \
		$(ERR) "VerifyExtensions.java produced no results"; tail -20 "$$WORK/headless.log"; exit 1; \
	fi
	@$(OK) "All extension classes loaded."

install-mcp: 04-install-mcp
install-lx-loader: 05-install-lx-loader
install-dos-toolbox: 06-install-dos-toolbox

# ── Stages 7–8: MCP bridge ────────────────────────────────────────────────────

07-venv: 01-checkout ## Create .venv and install bridge-mcp-ghidra (editable)
	@if [ -x "$(BRIDGE_BIN)" ]; then \
		echo "$(VENV_DIR) already set up, skipping."; \
	else \
		python3 -m venv "$(VENV_DIR)" && "$(VENV_DIR)/bin/pip" install -e ./ghidra-mcp || exit 1; \
		$(OK) "bridge-mcp-ghidra installed in $(VENV_DIR)."; \
	fi

# Adds/updates the "ghidra" entry in the opencode config (atomic write).
define REGISTER_OPENCODE
import json, os
path = "$(OPENCODE_CONFIG)"
entry = {"type": "local", "command": ["$(BRIDGE_BIN)"], "enabled": True}
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except (OSError, ValueError):
    data = {"$$schema": "https://opencode.ai/config.json"}
if data.get("mcp", {}).get("ghidra") == entry:
    print("opencode: ghidra MCP server already registered")
else:
    data.setdefault("mcp", {})["ghidra"] = entry
    with open(path + ".tmp", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(path + ".tmp", path)
    print("opencode: registered ghidra MCP server in " + path)
endef
export REGISTER_OPENCODE

08-register-mcp: 07-venv ## Register the "ghidra" MCP server with opencode and Claude Code
	@mkdir -p "$(dir $(OPENCODE_CONFIG))"
	@python3 -c "$$REGISTER_OPENCODE"
	@if ! command -v claude >/dev/null 2>&1; then \
		$(WARN) "claude CLI not found, skipping Claude Code registration."; \
	elif claude mcp get ghidra 2>/dev/null | grep -qF "$(BRIDGE_BIN)"; then \
		echo "Claude Code: ghidra MCP server already registered"; \
	else \
		claude mcp remove ghidra --scope user >/dev/null 2>&1; \
		claude mcp add --scope user ghidra -- "$(BRIDGE_BIN)" || exit 1; \
	fi

venv: 07-venv
register-mcp: 08-register-mcp

# ── Pipeline & runtime ────────────────────────────────────────────────────────

PIPELINE := 00-deps 00-env 01-checkout 02-build-ghidra 03-install-ghidra 04-install-mcp \
	05-install-lx-loader 06-install-dos-toolbox verify-extensions 07-venv 08-register-mcp test

install: $(PIPELINE) ## Run the full pipeline (all stages above, in order)
	@$(OK) "Ghidra Bundle installed. Run 'make run' to launch Ghidra."

test: ## Run the sanity test suite (fixtures, decompiler, extensions, GhidraMCP)
	@[ -d "$(JAVA21_HOME)" ] || { $(ERR) "JDK 21 not found (run 'make deps')"; exit 1; }
	@PACKAGES_DIR="$(DIST_DIR)/packages" tests/run-sanity.sh "$(INSTALL_DIR)" "$(JAVA21_HOME)"

run: ## Launch Ghidra (fails if port 8089 is already in use)
	@[ -x "$(INSTALL_DIR)/ghidraRun" ] || { $(ERR) "Ghidra not installed; run 'make install'"; exit 1; }
	@if { command -v lsof >/dev/null && lsof -i :$(MCP_PORT); } || \
		{ command -v ss >/dev/null && ss -ltnp 2>/dev/null | grep ':$(MCP_PORT) '; }; then \
		$(ERR) "port $(MCP_PORT) is already in use (see above)"; exit 1; \
	fi
	"$(INSTALL_DIR)/ghidraRun"

run-bridge: ## Run bridge-mcp-ghidra over stdio
	@[ -x "$(BRIDGE_BIN)" ] || { $(ERR) "$(BRIDGE_BIN) not found; run 'make venv'"; exit 1; }
	@"$(BRIDGE_BIN)"

verify: ## Check that the GhidraMCP plugin answers on port 8089
	@curl -sf http://127.0.0.1:$(MCP_PORT)/check_connection && echo || \
		{ $(ERR) "no GhidraMCP on port $(MCP_PORT): run Ghidra and open a program in the CodeBrowser"; exit 1; }
	@$(OK) "GhidraMCP is answering on port $(MCP_PORT)."

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean: ## Remove dist/, .venv/ and all build outputs
	rm -rf "$(DIST_DIR)" "$(VENV_DIR)" ghidra/build ghidra-mcp/target ghidra-mcp/build \
		lx-loader/dist lx-loader/build lx-loader/.gradle \
		dos-toolbox/dist dos-toolbox/build dos-toolbox/.gradle

distclean: clean ## clean, then de-initialize all submodules
	git submodule deinit -f --all
