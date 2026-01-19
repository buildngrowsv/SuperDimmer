# Add UpdateChecker.swift to Xcode Project

**Required:** 30 seconds

---

## Steps

1. **Open Xcode**
   ```bash
   open SuperDimmer.xcodeproj
   ```

2. **In Project Navigator** (left sidebar):
   - Find the `Services` folder
   - Right-click on it
   - Select "Add Files to SuperDimmer..."

3. **In the file picker:**
   - Navigate to: `SuperDimmer/Services/UpdateChecker.swift`
   - **UNCHECK** "Copy items if needed"
   - **CHECK** "SuperDimmer" target
   - Click "Add"

4. **Build**
   ```
   ⌘B (or Product → Build)
   ```

5. **Run**
   ```
   ⌘R (or Product → Run)
   ```

---

## Expected Result

**Console output:**
```
🔍 UpdateChecker: Running automatic update check...
   Fetching version.json from https://superdimmer.com/version.json
   HTTP 200
   📱 Current version: 1.0.1 (build 7)
   🌐 Remote version:  1.0.0 (build 1)
   ✅ App is up to date
```

**No alert** (since app is current)

---

## Test It

1. **Click menu bar icon**
2. **Click "Check for Updates"** at bottom
3. **Should show:** "You're Up to Date" alert

4. **Open Preferences** (⌘,)
5. **Go to General tab**
6. **See "Software Updates" section** with:
   - Beta toggle
   - Check for Updates button
   - View Update Log button

---

## Done! ✅

Updates are now fully integrated and working.
