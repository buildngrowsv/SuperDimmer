# 🔄 Quick Revert Instructions
## Remove Space Overlay Test Before Committing

**⚠️ IMPORTANT: Run these commands before committing anything**

---

## One-Command Revert

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App && \
git checkout -- SuperDimmer/MenuBar/MenuBarView.swift && \
git checkout -- SuperDimmer.xcodeproj/project.pbxproj && \
rm -rf SuperDimmer/SpaceIdentification/ && \
rm -f TEST_INTEGRATION_COMPLETE.md && \
rm -f QUICK_TEST_INTEGRATION.md && \
rm -f REVERT_INSTRUCTIONS.md && \
echo "✅ Test code reverted successfully!"
```

---

## Step-by-Step Revert

### 1. Revert Modified Files

```bash
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Mac-App

# Revert menu bar changes
git checkout -- SuperDimmer/MenuBar/MenuBarView.swift

# Revert Xcode project changes
git checkout -- SuperDimmer.xcodeproj/project.pbxproj
```

### 2. Remove Test Files

```bash
# Remove test code folder
rm -rf SuperDimmer/SpaceIdentification/

# Remove integration docs
rm -f TEST_INTEGRATION_COMPLETE.md
rm -f QUICK_TEST_INTEGRATION.md
rm -f REVERT_INSTRUCTIONS.md
```

### 3. Verify Clean State

```bash
# Check git status
git status

# Should show only your original changes
# Should NOT show:
# - SuperDimmer/MenuBar/MenuBarView.swift
# - SuperDimmer.xcodeproj/project.pbxproj
# - SuperDimmer/SpaceIdentification/
```

---

## What Gets Kept

**Research documents (these are valuable, keep them):**
- `docs/research/PER_SPACE_VISUAL_IDENTIFICATION.md`
- `docs/research/SPACE_OVERLAY_TEST_GUIDE.md`
- `docs/research/PER_DESKTOP_WALLPAPER_FEASIBILITY.md`

These contain your research findings and can be committed.

---

## What Gets Removed

**Test code (temporary, remove before commit):**
- ❌ `SuperDimmer/SpaceIdentification/SpaceOverlayTest.swift`
- ❌ Changes to `SuperDimmer/MenuBar/MenuBarView.swift`
- ❌ Changes to `SuperDimmer.xcodeproj/project.pbxproj`
- ❌ `TEST_INTEGRATION_COMPLETE.md`
- ❌ `QUICK_TEST_INTEGRATION.md`
- ❌ `REVERT_INSTRUCTIONS.md`

---

## After Reverting

### Check Your Work

```bash
# See what's left
git status

# See what you're about to commit
git diff --cached

# Make sure test code is gone
ls -la SuperDimmer/SpaceIdentification/  # Should not exist
```

### Safe to Commit

Once reverted, you can safely commit your other changes:

```bash
# Add your actual changes
git add <your-files>

# Commit
git commit -m "Your commit message"

# Push
git push
```

---

## If You Want to Keep Test Code

### Option: Stash Instead of Delete

```bash
# Stash test changes (can restore later)
git stash save "Space overlay test - do not commit"

# Your working directory is now clean
# Commit your other changes

# Later, to restore test:
git stash list  # Find your stash
git stash pop   # Restore test code
```

---

## Quick Checklist

Before committing, verify:

- [ ] `SuperDimmer/SpaceIdentification/` folder does not exist
- [ ] `MenuBarView.swift` has no test buttons
- [ ] `project.pbxproj` has no SpaceOverlayTest references
- [ ] `git status` shows only your intended changes
- [ ] Research docs are still present (good to commit)
- [ ] App still builds successfully

---

*Revert instructions created: January 21, 2026*  
*Run these commands before committing!*
