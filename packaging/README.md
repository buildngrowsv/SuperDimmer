# ⚠️ MOVED: Release Scripts Are Now in the Website Repo

The release packaging scripts have been moved to the **SuperDimmer-Website** repository for a streamlined release workflow.

## New Location

```bash
cd ../SuperDimmer-Website/packaging/
./release.sh 1.1.0
```

## Why the Move?

The release workflow now:
1. Builds the app (from this Mac-App repo)
2. Creates DMG
3. Signs and notarizes
4. **Auto-updates appcast.xml** (in Website repo)
5. **Copies DMG to releases/** (in Website repo)

Since steps 4-5 modify the Website repo anyway, it makes sense to run everything from there.

## Quick Reference

```bash
# Navigate to website repo
cd /Users/ak/UserRoot/Github/SuperDimmer/SuperDimmer-Website/packaging

# Full release
./release.sh 1.2.0

# Dev build (no signing)
./release.sh 1.2.0 --skip-sign

# Then push website repo to deploy
cd ..
git add . && git commit -m "Release v1.2.0" && git push
```

## Files Here (Legacy)

These scripts are kept for reference but the **Website repo version is the canonical source**:

- `build-release.sh` - Build + DMG (use release.sh instead)
- `create-dmg.sh` - DMG creation helper
- `create-background.sh` - DMG background generator
