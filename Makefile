SHELL := /bin/bash
.DEFAULT_GOAL := help

# =============================================================================
# Kotlin Multiplatform (KMP) Module Management — Makefile
#
# This Makefile is a thin, documented wrapper around our helper scripts in /scripts.
# It provides a unified developer experience for creating, linking, and unlinking
# KMP modules without having to remember long bash command lines.
#
# Key ideas:
# - `new` creates a new KMP module folder structure, sets namespace, adds it to
#   settings.gradle.kts, and links it to an existing module (default: app).
# - `link` and `unlink` modify existing Gradle build files to manage dependencies
#   between modules.
# - All operations are transactional: failures trigger rollbacks to avoid
#   leaving the repo in a half-broken state.
#
# Usage examples:
#   make new GROUP=features NAME=Auth
#   make new GROUP=core NAME=Networking DEPS=":core:logging,:core:config"
#   make link FROM=:features:auth TO=:core:navigation
#   make unlink FROM=:features:auth TO=:core:navigation
#
# Notes:
# - Variables can be overridden at the CLI level (see defaults below).
# - Scripts are macOS/BSD/Linux compatible (portable awk/sed usage).
# =============================================================================

# ---- Default variable values ----
GROUP        ?= features     # e.g., features|core|data|integration
NAME         ?= sample       # e.g., Auth, Cashout, Navigation
DEPS         ?=              # CSV of Gradle paths, e.g., ":core:navigation,:core:config"
LINK_TO      ?=              # blank => auto-detect app module (e.g., :composeApp)
TARGETS      ?=              # blank => auto (android,ios) or android-only / ios-only
WITH_COMPOSE ?= true         # true|false
TYPE         ?= library      # library|app

# ---- Internal helpers ----
define _require_script
	@if [[ ! -x "$(1)" ]]; then \
		echo "Missing script: $(1) (make sure it exists and is executable)"; \
		exit 1; \
	fi
endef

define _require_from_to
	@if [[ -z "$(FROM)" || -z "$(TO)" ]]; then \
	  echo "Usage: make $(1) FROM=:moduleA TO=:moduleB"; exit 1; \
	fi
endef

.PHONY: help new new-android new-ios link unlink

## help: Show available targets and overridable variables
help:
	@echo ""
	@echo "KMP Module Management — Targets"
	@echo "  make new             # scaffold a KMP module and link it"
	@echo "  make new-android     # scaffold Android-only module"
	@echo "  make new-ios         # scaffold iOS-only module"
	@echo "  make link FROM=:A TO=:B    # add dependency A -> B"
	@echo "  make unlink FROM=:A TO=:B  # remove dependency A -X-> B"
	@echo ""
	@echo "Variables (override as needed):"
	@echo "  GROUP=$(GROUP)   NAME=$(NAME)   DEPS=$(DEPS)"
	@echo "  LINK_TO=$(LINK_TO)   TARGETS=$(TARGETS)"
	@echo "  WITH_COMPOSE=$(WITH_COMPOSE)   TYPE=$(TYPE)"
	@echo ""

## new: Scaffold <GROUP>/<NAME>, include in settings, and link to LINK_TO (or app)
new:
	$(call _require_script,scripts/new-module.sh)
	@bash scripts/new-module.sh \
	  --group "$(GROUP)" \
	  --name  "$(NAME)" \
	  --deps  "$(DEPS)" \
	  --link-to "$(LINK_TO)" \
	  --targets "$(TARGETS)" \
	  --with-compose "$(WITH_COMPOSE)" \
	  --type "$(TYPE)"

## new-android: Shortcut for Android-only module
new-android:
	@$(MAKE) new TARGETS=android-only

## new-ios: Shortcut for iOS-only module
new-ios:
	@$(MAKE) new TARGETS=ios-only

## link: Make :FROM depend on :TO (idempotent)
link:
	$(call _require_script,scripts/link-module.sh)
	$(call _require_from_to,link)
	@bash scripts/link-module.sh --from "$(FROM)" --to "$(TO)"

## unlink: Remove dependency :FROM -X-> :TO
unlink:
	$(call _require_script,scripts/unlink-module.sh)
	$(call _require_from_to,unlink)
	@bash scripts/unlink-module.sh --from "$(FROM)" --to "$(TO)"

## pods: generate podspec + sync + pod install untuk iosApp
pods:
	@./gradlew :umbrella:podspec :umbrella:syncFramework
	@cd iosApp && pod install