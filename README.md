# AeroDock

**A little less switching.** A lightweight floating island for your Mac, tucked just below the camera.

AeroDock is an early native macOS app built with SwiftUI and AppKit. Hover at the top center of your screen, near the camera, to reveal compact music controls. Click the song/title to expand Music, Calendar, Focus, and Apps. Click again (or press Escape) to collapse. Use the menu bar icon to bring it back or quit.

## Download

Download the ZIP from [Releases](https://github.com/Tzanidakis/aerodock/releases), unzip it, and move AeroDock.app into Applications. Requires **macOS 14 or newer**. The first preview is for **Apple silicon** Macs.

The downloaded app includes AeroDock's matte mint-and-cyan application icon in every standard macOS icon size.

This is an **unsigned developer preview** (ad-hoc signed, not Apple notarized). macOS may prevent it from opening normally. Only install it if you trust this project; a Developer ID signed and notarized release is planned. Source builds are available below.

## Fixed in 0.4.1

- Stopping a voice recording immediately resets the timer and input level to zero, ready for the next recording.
- Recent recordings refresh when the Record tab opens, when AeroDock regains focus, and every second while the tab is visible. Files deleted or moved in Finder disappear from the list. Play/export also check that a file still exists.

## New in 0.4

- **Quicker interaction:** hover dwell reduced from 180 ms to 80 ms, pointer checks every 50 ms, visible music updates every 500 ms (previously 3 seconds). Play/pause changes visually immediately and is reconciled with the player. Actual playback latency still depends on the music app.
- **Voice recorder:** open Record, press Start recording, and grant microphone access when macOS asks. Stop & save creates a local `.m4a` audio file. Use the recent list to play/export, or Files to open all recordings in Finder. The compact island and menu bar show a recording indicator and stop control. Recording continues if you explicitly hide the island; quit stops it.
- **Presentation script:** paste text in Script, set reading pace and font size, then Play presentation. The island becomes a reader near the camera with short text cards, progress, pause/play, previous/next, and live speed adjustment. It stays visible during presentation. Space pauses/resumes when the reader has keyboard focus; Escape or Edit returns to the editor. Scripts are saved locally between launches. This is a visual teleprompter, not text-to-speech or transcription.
- You can record your microphone while presenting. The reader includes a stop-recording control.

Recordings are kept under `~/Library/Application Support/AeroDock/Recordings` and are never uploaded by AeroDock. The recorder captures the selected macOS microphone input, not screen video or direct system audio. Share/export only the recordings you choose. The teleprompter can appear in screen sharing if you share your entire display; share your presentation window when you want to keep the script private.

## Album art & lighting (0.3)

- **Album covers** in the compact player and expanded Music card, from Spotify and Apple Music (when their desktop apps expose artwork).
- **Cover-inspired colors:** the player accents and edge lighting pick a color from the current album cover.
- **Animated playback glow:** a soft moving light around the island and small animated equalizer bars while playing. Pausing stops the animation and turns off the edge glow; the cover stays visible.
- **Reduce Motion:** keeps a static glow and static bars instead. Animations stop while the island is hidden.
- Missing/offline artwork uses a music-note fallback. Images are downsampled and downloads are limited to 10 MB. Changing player or disconnecting clears the previous artwork.

The glow is decorative and follows playback state, not the song's audio waveform. AeroDock does not record the microphone or system audio. Spotify covers are fetched directly from the HTTPS artwork URL provided by Spotify; Apple Music covers are read locally from its app. No listening history is sent to an AeroDock server.

## Also included (0.2)

- **Auto-hide:** the island disappears when you move away. Hover around the camera/top-center edge for a moment to reveal it. The hotspot extends just below the camera, so it remains reachable. On screens without a notch, use the top center below the menu bar.
- **Compact controls:** previous, play/pause, and next without opening the large panel. First choose Spotify or Apple Music and connect it from the Music tab. The selected app is remembered; AeroDock does not automatically switch players.
- **Tuck behind the camera:** click the crossed-out eye to tuck the island away immediately. Activity lights remain visible while music plays, recording runs, or a focus timer is active. Hover near the camera to bring the island back.
- **Hide completely:** choose “Hide AeroDock until I show it” in the menu bar. Hover no longer reveals it until you choose Show AeroDock. The menu bar icon remains available.
- **Pin:** keep the island visible; Unpin returns to auto-hide. Visibility preference survives relaunch. Launching in auto-hide briefly shows the island before it tucks away.
- **Quit completely:** expand AeroDock and press the red power button in the footer. AeroDock stops running, including its menu-bar item and background activity. Open AeroDock again from Applications whenever you want to restart it.
- **Apple Music and Spotify:** current song, artist, playback controls, reconnect/disconnect, and an Open App button. The expanded player shows elapsed and total time with a draggable seek bar for moving to another part of the song. The Stop control pauses playback.
- **Focus timer:** 5-, 25-, and 50-minute sessions, pause/resume/reset. Keeps time when the island is hidden and across sleep while the app is running. Completion is shown silently; quitting resets it.
- **Quick apps:** open Notes, Reminders, Calendar, Mail, Shortcuts, and Calculator. These are launch shortcuts, not embedded app views. Unavailable apps are disabled.
- **Calendar:** the next three events in the next seven days from calendars synced to the Mac.

While recording, focusing, or playing music, the island tucks away five seconds after you move away. Only a narrow pulsing outline around the camera housing remains: red for recording, mint for focus, or the album color for music (in that priority order). Hover over the camera to reveal controls again. Hidden mode suppresses the glow; pinned mode and the presentation reader stay visible. Displays without a notch use a small top-center indicator. Reduce Motion disables pulsing. Revealed controls sit beneath it. It uses pointer position without requiring Accessibility or Input Monitoring permissions.

Open your music app and choose **Connect Spotify** or **Connect Apple Music**. macOS may ask for Automation permission separately for each player. Choose **Connect Calendar** separately to enable upcoming events. Permissions are optional. Calendar access is read-only in AeroDock's implementation, although macOS requires full-access permission to read events. No AeroDock accounts, server, analytics, or uploads are used. Spotify artwork downloads contact the image host supplied by Spotify.

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

Music control requires the selected desktop app and Automation permission; browser players are not supported. Launch at login, auto-updates, and user-selectable display placement are future work. The island prefers a display with a notch, otherwise the primary display. Full-screen behavior depends on macOS and the active app. Broader live playback, permission, and multiple-display testing is still needed before a stable release.

## Development

The app lives in `Sources/AeroDock/AeroDock.swift`; bundle metadata lives in `Resources/Info.plist`. No external dependencies. Run `./scripts/test.sh` for thirteen deterministic hover/visibility, timer, artwork, presentation, and recording-file tests (works with Command Line Tools alone). CI runs these checks, builds the app and attaches a preview ZIP as a workflow artifact.

Feature ideas and bug reports are welcome through [Issues](https://github.com/Tzanidakis/aerodock/issues). Include your macOS version, Mac model, and steps to reproduce; please omit personal calendar details.

## Roadmap

- Developer ID signing and Apple notarization for straightforward installation
- Volume controls
- Launch at login and appearance settings
- More optional widgets
- Intel release builds and broader accessibility/display testing

## License

MIT — see [LICENSE](LICENSE).

Use the trash button beside a recent recording to remove the saved recording and its entry immediately. Deleted recordings go to macOS Trash for recovery; separately exported copies are unaffected.

The Calendar tab includes a full month grid, month/year heading, weekday labels, highlighted today, previous/next month controls, and a complete selected date. Upcoming events remain below the grid. The month view works without calendar access.

The expanded island uses a wide horizontal layout, with all six tabs in one row and calendar/events side by side. Longer panels scroll within the island.

The compact island remains 360 × 52 points. Opening the full AeroDock uses the same horizontal proportions in a smaller 650 × 397-point panel.

## New in 0.7

- AirPods and connected Bluetooth headphones appear with an earbud icon and circular battery gauge. A six-second connection card shows left, right, and case readings when macOS provides them. Devices are checked every five seconds; unavailable readings show a dash rather than an estimated percentage.
- Hover near the camera to reveal the compact dock; click its title to expand the floating panel. Panel size changes animate, respecting Reduce Motion.
- Press the circular person icon to open a 100-point circular camera mirror. Press it again to close. Closing or hiding the panel stops capture. Camera access is requested on first use; no video is recorded or uploaded.

### 0.7.1

The camera mirror now applies horizontal mirroring after the camera session starts. A white ring lights up when the central camera image stays dim; the lightbulb button overrides it. The light stays on until dismissed to avoid flicker. All brightness analysis stays on the Mac and no frames are saved. Hover reveals only the compact dock; click the title to expand it.
