# Clipboard History for macOS

A native macOS menu-bar clipboard history app with a global, layout-independent
shortcut. Its primary and default shortcut is **Control + Command + V (`⌃⌘ V`)**.

## What is implemented

- `⌃⌘ V` is registered through Carbon `RegisterEventHotKey`, so it works while
  another application is active.
- Pressing the shortcut opens a focused floating history panel; pressing it
  again closes it. `Escape` also closes it.
- The panel selects the newest saved item on open. Arrow keys select an item;
  Return copies the selected item back to the system pasteboard and closes the
  panel. Mouse, trackpad, search, filtering, context menus, and row clicks are
  supported too.
- The app monitors `NSPasteboard.general.changeCount` every 0.5 seconds,
  snapshots all pasteboard items/types it can read, and stores their bytes
  separately from metadata under `Application Support/ClipboardHistory`.
- Restoring an item writes its original pasteboard representations back and is
  marked with the monitor to avoid a capture feedback loop.
- Exact duplicate captures use a SHA-256 digest, update the existing item, and
  move it to the top rather than creating another copy.
- The native Settings window includes **Shortcuts → Open Clipboard History**.
  Click the shortcut control and press a modified key combination to rebind it.
  The setting is persisted in `UserDefaults` only after macOS accepts it.

## Conflict handling

The shortcut is requested as an exclusive Carbon hot key. When macOS rejects
the candidate registration, the Settings screen reports the error and retains
the previous working shortcut. macOS does not expose a public API that can list
every shortcut claimed by every other app, so the app deliberately does not
claim to detect conflicts it cannot observe.

## Requirements and running

- macOS 14 or later
- A full Xcode installation (Command Line Tools alone omit the SwiftUI macro
  plug-ins used by SwiftUI projects)

Open `Package.swift` in Xcode and run the `ClipboardHistory` scheme, or run:

```bash
swift build
swift run ClipboardHistory
```

No Accessibility permission or network connection is requested for the global
shortcut or clipboard monitoring. Clipboard data remains local to the Mac.

## Tests

```bash
swift test
```

The test suite covers the `⌃⌘ V` default, invalid unmodified shortcuts, duplicate
coalescing, and metadata/payload persistence. Manual acceptance checks should
include another app being active, opening/closing with `⌃⌘ V`, `Escape`, arrow
selection, Return restore, rebind success, and a rejected shortcut registration.

## macOS limitations

`NSPasteboard` does not publish a push notification, so the app uses a small
change-count timer. An item larger than 100 MB is skipped to prevent a single
clipboard write from causing an unbounded memory spike. Source-application
attribution is intentionally not claimed because macOS does not reliably expose
it for every pasteboard write.
