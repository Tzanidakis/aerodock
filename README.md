# AeroDock

**A little less switching.** A lightweight floating island for your Mac, tucked just below the camera.

AeroDock is an early native macOS app built with SwiftUI and AppKit. Click the island to expand it, switch between Music and Calendar, and click again (or press Escape) to collapse. Use the menu bar icon to bring it back or quit.

## Download

Download the ZIP from [Releases](https://github.com/Tzanidakis/aerodock/releases), unzip it, and move AeroDock.app into Applications. Requires **macOS 14 or newer**. The first preview is for **Apple silicon** Macs.

This is an **unsigned developer preview** (ad-hoc signed, not Apple notarized). macOS may prevent it from opening normally. Only install it if you trust this project; a Developer ID signed and notarized release is planned. Source builds are available below.

## What works in this preview

- Compact, expandable island below the camera/menu bar, with a dark interface and mint accents.
- Spotify desktop app: current song, artist, previous, next, play/pause, and a stop button that pauses playback (Spotify does not expose a separate stop command).
- Calendar: the next three events within seven days, including all-day events, from calendars synced to your Mac.
- Menu bar controls and positioning that updates when displays change; works on screens without a notch too.

Open Spotify and play a track, then choose **Connect Spotify**. macOS will ask for Automation permission. Choose **Connect Calendar** separately to enable upcoming events. Permissions are optional. Calendar access is read-only in AeroDock's implementation, although macOS requires its full-access permission to read events. No accounts, server, analytics, or uploads are used by AeroDock.

## Build locally

Install Apple's Xcode Command Line Tools, then run:

```sh
git clone https://github.com/Tzanidakis/aerodock.git
cd aerodock
./scripts/build-app.sh
open dist/AeroDock.app
```

The script builds for the current Mac architecture, creates an application bundle, ad-hoc signs it, and packages `dist/AeroDock-macOS.zip`. Run the bundled app for calendar and Automation permissions; `swift run` is not the supported launch method.

## Preview limitations

Spotify requires the desktop app and Automation permission. Browser playback and other music players are not supported yet. The island opens by clicking; hover expansion, launch at login, album artwork, auto-updates, and user-selectable display placement are future work. Full-screen behavior depends on macOS and the active application. End-to-end permission and playback testing is still required before a stable release.

## Development

The app lives in `Sources/AeroDock/AeroDock.swift`; bundle metadata lives in `Resources/Info.plist`. No external dependencies. CI builds the app and attaches a preview ZIP as a workflow artifact.

Feature ideas and bug reports are welcome through [Issues](https://github.com/Tzanidakis/aerodock/issues). Include your macOS version, Mac model, and steps to reproduce; please omit personal calendar details.

## Roadmap

- Developer ID signing and Apple notarization for straightforward installation
- Apple Music support, album artwork, and volume controls
- Hover expansion, launch at login, and appearance settings
- Focus timer and more optional widgets
- Intel release builds and broader accessibility/display testing

## License

MIT — see [LICENSE](LICENSE).
