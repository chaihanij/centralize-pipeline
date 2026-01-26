# ==========================================================
# Makefile — Enterprise Git Flow + Commitizen
# Year-based semantic versioning: YY.MINOR.PATCH
# - Commit only (NO TAG)
# - Auto bump from commit message
# - Create release/${VERSION}
# ==========================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# ----------------------------------------------------------
# Versioning
# ----------------------------------------------------------
VERSION := 26.0.0
CURRENT_BRANCH := $(shell git branch --show-current)

# ----------------------------------------------------------
# Help
# ----------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "Commit & Release Commands:"
	@echo ""
	@echo "  make cz-setup           Setup commitizen & pre-commit"
	@echo "  make commit             Create commit (interactive)"
	@echo "  make commit-msg msg=    Commit with message (validated)"
	@echo ""
	@echo "  make cz-check           Validate commit messages"
	@echo "  make cz-bump-dry        Dry-run bump"
	@echo ""
	@echo "Release:"
	@echo "  make release-start INCREMENT=minor|patch|major"
	@echo "  make release-auto       Auto detect bump from commits"
	@echo ""
	@echo "Rules:"
	@echo "  - Must run on develop"
	@echo "  - Clean working tree required"
	@echo "  - NO git tag created"
	@echo ""

# ----------------------------------------------------------
# Setup
# ----------------------------------------------------------
.PHONY: cz-setup
cz-setup:
	@echo "Installing Commitizen..."
	@command -v cz >/dev/null 2>&1 || { \
		echo "Commitizen not found. Installing via Homebrew..."; \
		command -v brew >/dev/null 2>&1 || { \
			echo "❌ Homebrew not found"; exit 1; }; \
		brew install commitizen; \
	}
	@echo "Installing pre-commit..."
	@command -v pre-commit >/dev/null 2>&1 || brew install pre-commit
	@pre-commit install --hook-type commit-msg --hook-type pre-push
	@echo "✅ Commitizen setup complete"

# ----------------------------------------------------------
# Commit
# ----------------------------------------------------------
.PHONY: commit
commit:
	@cz commit

.PHONY: commit-msg
commit-msg:
	@if [ -z "$(msg)" ]; then \
		echo "❌ Usage: make commit-msg msg='feat: your message'"; \
		exit 1; \
	fi
	@git add .
	@tmpfile=$$(mktemp); \
	echo "$(msg)" > $$tmpfile; \
	cz check --commit-msg-file $$tmpfile \
	&& git commit -m "$(msg)" \
	|| { rm -f $$tmpfile; exit 1; }; \
	rm -f $$tmpfile

# ----------------------------------------------------------
# Commitizen utilities
# ----------------------------------------------------------
.PHONY: cz-check
cz-check:
	@cz check --rev-range origin/develop..HEAD

.PHONY: cz-bump-dry
cz-bump-dry:
	@cz bump --dry-run

.PHONY: cz-example
cz-example:
	@cz example

.PHONY: cz-schema
cz-schema:
	@cz schema

.PHONY: cz-changelog
cz-changelog:
	@cz changelog

# ----------------------------------------------------------
# Guards
# ----------------------------------------------------------
.PHONY: guard-clean
guard-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "❌ Working tree is dirty"; exit 1; \
	fi

.PHONY: guard-develop
guard-develop:
	@if [ "$(CURRENT_BRANCH)" != "develop" ]; then \
		echo "❌ Must be on 'develop' (current: $(CURRENT_BRANCH))"; \
		exit 1; \
	fi

# ----------------------------------------------------------
# Utilities
# ----------------------------------------------------------
.PHONY: undo-last-commit
undo-last-commit:
	@echo "⚠️  Undoing last commit (keeping changes)"
	@git reset --soft HEAD~1
	@echo "✅ Last commit undone"

# ----------------------------------------------------------
# Manual Release Start
# ----------------------------------------------------------
.PHONY: release-start
release-start: guard-clean guard-develop
	@echo "▶ Pull develop"
	@git pull origin develop

	@echo "▶ Bump version ($(INCREMENT)) — commit only (no tag)"
	@cz bump --increment $(INCREMENT) --yes --changelog-to-stdout || true

	@VERSION=$$(grep -E '^version = ' .cz.toml | sed 's/version = "\(.*\)"/\1/'); \
	if [ -z "$$VERSION" ]; then \
		echo "❌ Failed to extract version from .cz.toml"; \
		exit 1; \
	fi; \
	echo "▶ Create release/$$VERSION"; \
	git checkout -b release/$$VERSION; \
	git push -u origin release/$$VERSION; \
	echo "🎉 Release created: release/$$VERSION"

# ----------------------------------------------------------
# Auto Release (detect from commit message)
# ----------------------------------------------------------
.PHONY: release-auto
release-auto: guard-clean guard-develop
	@echo "▶ Detect bump level from commit messages"
	@COMMITS="$$(git log --pretty=format:%s origin/develop..HEAD)"; \
	if echo "$$COMMITS" | grep -qE 'BREAKING CHANGE|!:'; then \
		INCREMENT=major; \
	elif echo "$$COMMITS" | grep -qE '^feat(\(.+\))?:'; then \
		INCREMENT=minor; \
	elif echo "$$COMMITS" | grep -qE '^fix(\(.+\))?:'; then \
		INCREMENT=patch; \
	else \
		echo "❌ No feat/fix/breaking commits found"; \
		exit 1; \
	fi; \
	echo "✅ Detected bump: $$INCREMENT"; \
	git pull origin develop; \
	cz bump --increment $$INCREMENT --yes; \
	VERSION=$$(grep -E '^version = ' .cz.toml | sed 's/version = "\(.*\)"/\1/'); \
	if [ -z "$$VERSION" ]; then \
		echo "❌ Failed to extract version from .cz.toml"; \
		exit 1; \
	fi; \
	git checkout -b release/$$VERSION; \
	git push -u origin release/$$VERSION; \
	echo ""; \
	echo "🎉 Release created"; \
	echo "   branch : release/$$VERSION"; \
	echo "   version: $$VERSION"; \
	echo "   bump   : $$INCREMENT"