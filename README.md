# AeroDock

**A little less switching.** A lightweight floating island for your Mac, tucked just below the camera.

AeroDock is an early native macOS app built with SwiftUI and AppKit. Hover at the top center of your screen, near the camera, to reveal compact music controls. Click the song/title to expand Music, Calendar, Focus, and Apps. Click again (or press Escape) to collapse. Use the menu bar icon to bring it back or quit.

## Download

Download the ZIP from [Releases](https://github.com/Tzanidakis/aerodock/releases), unzip it, and move AeroDock.app into Applications. Requires **macOS 14 or newer**. The first preview is for **Apple silicon** Macs.

This is an **unsigned developer preview** (ad-hoc signed, not Apple notarized). macOS may prevent it from opening normally. Only install it if you trust this project; a Developer ID signed and notarized release is planned. Source builds are available below.

## New in 0.2

- **Auto-hide:** the island disappears when you move away. Hover around the camera/top-center edge for a moment to reveal it. The hotspot extends just below the camera, so it remains reachable. On screens without a notch, use the top center below the menu bar.
- **Compact controls:** previous, play/pause, and next without opening the large panel. First choose Spotify or Apple Music and connect it from the Music tab. The selected app is remembered; AeroDock does not automatically switch players.
- **Hide completely:** click the crossed-out eye, or choose “Hide AeroDock until I show it” in the menu bar. Hover no longer reveals it until you choose Show AeroDock. The menu bar icon remains available.
- **Pin:** keep the island visible; Unpin returns to auto-hide. Visibility preference survives relaunch. Launching in auto-hide briefly shows the island before it tucks away.
- **Apple Music and Spotify:** current song, artist, playback controls, reconnect/disconnect, and an Open App button. The expanded Stop control pauses playback.
- **Focus timer:** 5-, 25-, and 50-minute sessions, pause/resume/reset. Keeps time when the island is hidden and across sleep while the app is running. Completion is shown silently; quitting resets it.
- **Quick apps:** open Notes, Reminders, Calendar, Mail, Shortcuts, and Calculator. These are launch shortcuts, not embedded app views. Unavailable apps are disabled.
- **Calendar:** the next three events in the next seven days from calendars synced to the Mac.

The island disappears completely when tucked away; it does not draw into the physical camera cutout. Revealed controls sit beneath it. It uses pointer position without requiring Accessibility or Input Monitoring permissions.

Open your music app and choose **Connect Spotify** or **Connect Apple Music**. macOS may ask for Automation permission separately for each player. Choose **Connect Calendar** separately to enable upcoming events. Permissions are optional. Calendar access is read-only in AeroDock's implementation, although macOS requires full-access permission to read events. No accounts, server, analytics, or uploads are used by AeroDock.

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

Music control requires the selected desktop app and Automation permission; browser players are not supported. Album artwork, launch at login, auto-updates, and user-selectable display placement are future work. The island prefers a display with a notch, otherwise the primary display. Full-screen behavior depends on macOS and the active app. Broader live playback, permission, and multiple-display testing is still needed before a stable release.

## Development

The app lives in `Sources/AeroDock/AeroDock.swift`; bundle metadata lives in `Resources/Info.plist`. No external dependencies. Run `./scripts/test.sh` for six deterministic hover/visibility and timer tests (works with Command Line Tools alone). CI runs these checks, builds the app and attaches a preview ZIP as a workflow artifact.

Feature ideas and bug reports are welcome through [Issues](https://github.com/Tzanidakis/aerodock/issues). Include your macOS version, Mac model, and steps to reproduce; please omit personal calendar details.

## Roadmap

- Developer ID signing and Apple notarization for straightforward installation
- Album artwork and volume controls
- Launch at login and appearance settings
- More optional widgets
- Intel release builds and broader accessibility/display testing

## License

MIT — see [LICENSE](LICENSE).
