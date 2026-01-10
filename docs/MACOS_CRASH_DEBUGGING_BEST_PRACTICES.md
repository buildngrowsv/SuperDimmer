# macOS Crash Debugging Best Practices

## EXC_BAD_ACCESS in `objc_release` / Autorelease Pool Crashes

**Symptoms:**
- Crash in `objc_release` at small memory address (e.g., `0x22dc8`)
- Backtrace shows `AutoreleasePoolPage::releaseUntil()`
- Crash during `[NSApplication run]` or similar run loop code

---

## Quick Fixes to Try

### 1. ❌ NEVER Call `NSWindow.close()` on Overlay Windows

```swift
// BAD - Triggers AppKit internals that crash
overlay.close()

// GOOD - Just hide it
overlay.orderOut(nil)
overlay.setDimLevel(0.0, animated: false)
hiddenOverlays.append(overlay)  // Keep alive!
```

**Why:** `close()` triggers AppKit cleanup that autoreleases objects. When the pool drains, those objects may already be freed → crash.

---

### 2. ✅ Wrap Core Animation Operations in `autoreleasepool`

```swift
// BAD
CATransaction.begin()
layer.backgroundColor = newColor
CATransaction.commit()

// GOOD
autoreleasepool {
    CATransaction.begin()
    layer.backgroundColor = newColor
    CATransaction.commit()
}
```

**Why:** Drains autoreleased CA objects immediately, not at run loop end.

---

### 3. ✅ Add `isClosing` Guards

```swift
private var isClosing = false

func setDimLevel(_ level: CGFloat) {
    guard !isClosing else { return }  // Prevent use-after-close
    // ... rest of method
}

override func close() {
    guard !isClosing else { return }
    isClosing = true
    super.close()
}
```

**Why:** Prevents operating on windows that are being destroyed.

---

### 4. ✅ Use Thread-Safe Locks for Shared Data

```swift
private let lock = NSRecursiveLock()

func modifyOverlays() {
    lock.lock()
    defer { lock.unlock() }
    // ... safe to access dictionaries
}
```

**Why:** Background threads + main thread accessing same data = race conditions.

---

## Debugging Tools

### Enable Zombie Objects (Best for objc_release crashes)

In Xcode scheme → Run → Diagnostics → OR add to scheme XML:

```xml
<EnvironmentVariables>
   <EnvironmentVariable key="NSZombieEnabled" value="YES" isEnabled="YES"/>
   <EnvironmentVariable key="MallocStackLogging" value="1" isEnabled="YES"/>
</EnvironmentVariables>
```

**What it does:** Instead of `EXC_BAD_ACCESS`, you'll see:
```
*** -[MyClass retain]: message sent to deallocated instance 0x7f8...
```

### LLDB Commands at Crash

```lldb
bt              # Full backtrace
bt all          # All threads (find race conditions)
register read x0   # Object being released
frame variable     # Local variables
```

---

## Common Crash Patterns

| Pattern | Likely Cause | Fix |
|---------|-------------|-----|
| Crash in `objc_release` | Over-release or use-after-free | Don't close windows, use Zombies |
| Crash in `AutoreleasePoolPage` | Autoreleased object freed early | Use `autoreleasepool {}` blocks |
| Crash after `[NSWindow close]` | AppKit internal cleanup race | Never close, just hide |
| Crash with many threads | Race condition | Add locks to shared data |
| Crash after animation | Core Animation lifecycle | Wrap in autoreleasepool, flush transactions |

---

## The Golden Rule

> **If you're crashing when destroying UI objects, DON'T destroy them.**
> 
> Just hide them and keep them alive. Memory is cheap. Crashes are expensive.

```swift
// Memory cost: ~10KB per window
// User experience cost of crash: Priceless
```

---

## Files to Check

When debugging overlay/window crashes in SuperDimmer:

1. `OverlayManager.swift` - `safeHideOverlay()`, dictionary access
2. `DimOverlayWindow.swift` - `close()` override, `isClosing` guards
3. `DimmingCoordinator.swift` - Threading, when overlays are created/removed

---

*Created: January 10, 2026 after fixing persistent EXC_BAD_ACCESS crash*
