# Troubleshooting Guide

## Issue: Commitizen Bump Failed

### Symptoms
```
Invalid version tag: 'v26.0.0' does not match any configured tag format
[develop 9c93e2b] chore(release): bump version {current_version} → {new_version}
```

### Root Causes
1. ❌ `tag_format = ""` in `.cz.toml` prevents commitizen from finding existing versions
2. ❌ No git tags exist in repository
3. ❌ Commit message placeholders not interpolated

### Solution

#### Step 1: Undo the Bad Commit
```bash
make undo-last-commit
```

Or manually:
```bash
git reset --soft HEAD~1
```

#### Step 2: Create Initial Git Tag
```bash
# Create the initial version tag
git tag -a v26.0.0 -m "chore: initial version"
git push origin v26.0.0
```

#### Step 3: Verify Configuration
The `.cz.toml` should have:
```toml
tag_format = "v$version"    # ✅ Changed from ""
version = "26.0.0"           # ✅ Current version
```

#### Step 4: Test Bump (Dry Run)
```bash
make cz-bump-dry
```

Expected output:
```
bump: version 26.0.0 → 26.1.0
tag to create: v26.1.0
increment detected: MINOR
```

#### Step 5: Run Release Again
```bash
make release-start INCREMENT=minor
```

---

## Issue: Version Not Updating in .cz.toml

### Cause
Commitizen updates `.cz.toml` automatically during bump.

### Verify
```bash
cz version
# Should show current version
```

---

## Issue: Git Tag Already Exists

### Symptoms
```
fatal: tag 'v26.1.0' already exists
```

### Solution
```bash
# Delete local tag
git tag -d v26.1.0

# Delete remote tag
git push origin :refs/tags/v26.1.0

# Or force update
git tag -fa v26.1.0 -m "chore: bump version"
git push origin v26.1.0 --force
```

---

## Issue: Release Branch Already Exists

### Symptoms
```
fatal: A branch named 'release/26.1.0' already exists
```

### Solution
```bash
# Delete local branch
git branch -D release/26.1.0

# Delete remote branch
git push origin --delete release/26.1.0
```

---

## Clean Slate Reset

If everything is messed up, start fresh:

```bash
# 1. Return to develop
git checkout develop

# 2. Delete bad commits (if not pushed)
git reset --hard HEAD~1  # Adjust number based on bad commits

# 3. Delete bad tags
git tag -d v26.1.0
git push origin :refs/tags/v26.1.0

# 4. Delete bad branches
git branch -D release/26.1.0
git push origin --delete release/26.1.0

# 5. Create proper initial tag
git tag -a v26.0.0 -m "chore: initial version"
git push origin v26.0.0

# 6. Try again
make release-start INCREMENT=minor
```

---

## Best Practices

### Before Creating Release

1. ✅ Ensure you're on `develop` branch
2. ✅ Working tree is clean (no uncommitted changes)
3. ✅ Initial git tag exists (e.g., `v26.0.0`)
4. ✅ `.cz.toml` has correct `tag_format = "v$version"`

### Verification Commands

```bash
# Check current branch
git branch --show-current

# Check working tree status
git status

# List all tags
git tag -l

# Check commitizen version
cz version

# Test bump (dry run)
cz bump --dry-run
```

---

## Common Makefile Commands

```bash
# Setup tools
make cz-setup

# Create commit
make commit

# Check commit messages
make cz-check

# Test version bump
make cz-bump-dry

# Create release (manual)
make release-start INCREMENT=minor

# Create release (auto-detect)
make release-auto

# Undo last commit
make undo-last-commit
```

---

## Support

For more information:
- Commitizen docs: https://commitizen-tools.github.io/commitizen/
- Conventional Commits: https://www.conventionalcommits.org/
