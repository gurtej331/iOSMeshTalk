# MeshTalk-iOS — foreground-only companion to the Android app

Same protocol as the Android app: same BLE service/characteristic UUIDs,
same JSON message format, same shared-passphrase AES-GCM encryption. If
this is built correctly and the Android app is running with the mesh
toggle on, they should be able to exchange messages with each other, not
just separately work.

**Status: also untested**, same honest caveat as the Android code — I
wrote this without Xcode, a Mac, or an iPhone in front of me. Treat it the
same way: a structurally sound draft, not a proven build.

## The one thing that's different on purpose

This app has **no background BLE capability at all**, deliberately. As
covered earlier: two backgrounded iPhones can't reliably discover each
other over Bluetooth — that's an OS restriction, not a bug to fix. Adding
background mode entries here would look like a feature and not act like
one. **Keep this app open on screen on both ends while testing.**

## What you actually need (all three, no way around any of them)

1. **A Mac, or a cloud Mac.** Building an `.ipa` needs Xcode, which is
   macOS-only. If you don't own a Mac: Expo — already connected in this
   chat — offers cloud Mac builds via EAS, but that path is for React
   Native projects, not this plain-Swift one. For this exact code, you
   need actual Xcode, meaning an actual Mac (yours, a friend's, a rented
   cloud Mac service, or a library/campus one).
2. **An Apple Developer account — $99/year.** Unlike Android sideloading,
   Apple requires this even to install an unpublished app on your own
   iPhone for a week of testing. There's no free tier that gets you
   around this the way GitHub Actions did for Android.
3. Your iPhone, with Bluetooth on, connected to Xcode over USB (or
   wirelessly once paired once).

## Setup

1. Xcode → **File → New → Project → iOS → App**. Interface: SwiftUI.
   Language: Swift. Product name: `MeshTalk`.
2. Delete the auto-generated `ContentView.swift` and `MeshTalkApp.swift`
   (or `<ProductName>App.swift`), and drag in the four files from this
   folder instead: `MeshTalkApp.swift`, `ContentView.swift`,
   `MeshMessage.swift`, `SimpleCrypto.swift`, `BleMeshManager.swift`.
3. Select the project in the navigator → your target → **Signing &
   Capabilities**. Set your Team (your $99 Apple Developer account) —
   Xcode handles the signing certificate automatically from there.
4. Same screen area, **Info** tab: add two keys (required or the app
   crashes on launch when it touches Bluetooth):
   - `Privacy - Bluetooth Always Usage Description` → e.g. "Used to find
     and message nearby devices without internet."
   - `Privacy - Bluetooth Peripheral Usage Description` → same kind of
     text.
5. Plug in your iPhone, select it as the run destination, hit Run (▶).
   First run on a new device requires trusting the developer certificate
   on the phone: **Settings → General → VPN & Device Management** → trust
   it there if prompted.

## Testing cross-platform relay

1. Open this app on the iPhone, foreground, mesh toggle on.
2. Open the Android app, mesh toggle on.
3. Send a message from either side. If it doesn't arrive: check both
   Bluetooth radios are actually on, both apps are genuinely foregrounded
   (not just backgrounded with the screen showing something else), and
   both have accepted their permission prompts.
4. If messages still don't cross, the two most likely culprits are (a) a
   subtle mismatch in the JSON field names/types between the two
   `Message`/`MeshMessage` definitions, or (b) a GATT timing issue on one
   side — send me the exact symptom (nothing received at all vs. received
   but garbled vs. crash) and which side it's on, and I'll go straight to
   the matching code path instead of guessing.
