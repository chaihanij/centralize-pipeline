# Year-based semantic versioning: YY.MINOR.PATCH
VERSION := 26.0.0

cz-setup:
	@echo "Installing Commitizen..."
	@command -v cz >/dev/null 2>&1 || { \
		echo "Commitizen not found. Installing via Homebrew..."; \
		command -v brew >/dev/null 2>&1 || { \
			echo "❌ Error: Homebrew not found. Please install Homebrew first:"; \
			echo "   /bin/bash -c \"\$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""; \
			exit 1; \
		}; \
		brew install commitizen; \
	}
	@echo "Installing pre-commit..."
	@command -v pre-commit >/dev/null 2>&1 || { \
		command -v brew >/dev/null 2>&1 && brew install pre-commit || { \
			echo "❌ Error: Cannot install pre-commit. Please install Homebrew first."; \
			exit 1; \
		}; \
	}
	@echo "Installing pre-commit hooks..."
	@pre-commit install --hook-type commit-msg --hook-type pre-push
	@echo "✅ Commitizen setup complete!"
	@echo ""
	@echo "Usage:"
	@echo "  make commit          - Create a new commit interactively"
	@echo "  make cz-bump         - Bump version and update changelog"
	@echo "  make cz-check        - Validate commit messages"
commit:
	@cz commit
commit-msg:
	@if [ -z "$(msg)" ]; then \
		echo "Error: Please provide a message using msg='your message'"; \
		echo "Example: make commit-msg msg='feat: add new feature'"; \
		exit 1; \
	fi
	@git add .
	@tmpfile=$$(mktemp); \
	echo "$(msg)" > $$tmpfile; \
	cz check --commit-msg-file $$tmpfile && git commit -m "$(msg)" && git push || { \
		rm -f $$tmpfile; \
		echo ""; \
		echo "❌ Commit message doesn't follow Conventional Commits format"; \
		echo "Use 'make commit' for interactive mode or check docs/COMMIT_CONVENTION.md"; \
		exit 1; \
	}; \
	rm -f $$tmpfile

cz-bump:
	@cz bump --changelog
cz-bump-dry:
	@cz bump --changelog --dry-run
cz-check:
	@cz check --rev-range origin/develop..HEAD
cz-example:
	@cz example
cz-schema:
	@cz schema
cz-changelog:
	@cz changelog