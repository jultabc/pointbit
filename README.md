# Pointbit

A macOS menu bar app that shows a mark where the mouse is clicked, so every click is visible.
A click sound is optional. It also takes pictures and recordings of a window or the whole screen
with two taps of ⌘ and one letter.

Version 1.0.0. Universal (Apple silicon + Intel), macOS 13 or later.

## Install
There is no download: build the app from the source. You need Xcode (Swift 6.3) and macOS 13 or later.
```
git clone https://github.com/jultabc/pointbit.git
cd pointbit
./build.sh                                                # tests + build/Pointbit.app
ditto build/Pointbit.app /Applications/Pointbit.app       # install
open /Applications/Pointbit.app
```
On the first start, the Preferences window opens. To take pictures and recordings, turn on the shortcuts there and
allow the two permissions it asks for ([docs/GUIDE.md](docs/GUIDE.md)).

## What it does
- Click marks: white at the center, translucent red toward the edge for a left click, green for a right click.
  Shown for 0.15 s by default, then removed at once (no growing, no fade). Size, duration and colors are adjustable.
- Click sounds: TACS (default; the app's own typewriter sound, fixed), Mouse click, Mouse click (soft),
  Mouse press only, Typewriter (short), Tink (macOS). The mouse and typewriter sounds are synthesized in code;
  Pitch, Brightness and Ring sliders change them (shown only for those sounds). After a sound setting changes,
  the sound plays once, 0.3 s after the last change (also when Audio is Off; clicks stay silent then).
- Capture and record (off by default; guide with pictures: [docs/GUIDE.md](docs/GUIDE.md)):
  tap ⌘ twice (within 0.35 s), then within 1 s press
  - T: start / stop recording the window under the pointer
  - A: start / stop recording the whole screen under the pointer
  - C: picture of the window under the pointer (no shadow)
  - S: picture of the whole screen under the pointer

  Files are named `TACS-<yyyyMMdd>-<HHmmssSSS>.png` / `.mov` and go to the save folder (the Desktop unless another
  folder is chosen). With "Copy the file path when it ends" on, the clipboard then holds the file's path as text,
  for pasting into a terminal or an AI agent's chat (with it off, a picture copies the image). A white flash and the shutter sound confirm a picture; the menu bar icon is a red dot while
  recording, and its menu shows "Stop Recording". Recordings are video only, 30 fps, with the pointer and the click marks.
  The action key is not passed to the front app; ⌘T, ⌘A, ⌘C and ⌘S are not affected.
  Needs Accessibility (to see the ⌘ ⌘ keys) and Screen & System Audio Recording (no audio is recorded).
  Keys are read by a listen-only tap, which cannot hold back input. A second tap that holds back the T, A, C or S
  exists only from the second ⌘ press until that key is released, at most 3 s.
- Menu bar icon: About · Show Visual Feedback · Play Click Sound · Settings… · Quit, plus Stop Recording while recording.
- Preferences in three sections: General (Launch on computer startup), Click Marks and Capture and Record.
  The window opens by itself only on the first start; after that, from the menu bar icon → Settings….
  It stays in front of other apps while open, so clicks can be tried with it open.
  After a click on a slider, the arrow keys move it (1% of the range; with Shift, 10%).
- Only one copy runs. A second copy (for example the one in `build/`) quits at start.
- App and menu bar icons are drawn in code.
- Settings are stored in the `si.codegg.pointbit` defaults domain (`defaults read si.codegg.pointbit`).

## Size
| Part | Swift lines (incl. blank and comment lines) |
|---|---|
| App and icon tool (`Sources/`, 19 files) | 1533 |
| Tests and `Package.swift` (7 test files + 1) | 492 |
| Total | 2025 |

Recount: `git ls-files '*.swift' | xargs wc -l`

## Build from source
Toolchain: Xcode with Swift 6.3, macOS 13+ target. Check with `swift --version`.
```
./build.sh                                                # tests + build
swift test                                                # tests only
ditto build/Pointbit.app /Applications/Pointbit.app       # install (quit the running one first)
open /Applications/Pointbit.app                           # start
open /Applications/Pointbit.app --args --settings         # start with the settings window open
```

## Stop
To quit, choose "Quit Pointbit" from the menu bar icon.
To stop it from a terminal, find the app's PID with `pgrep -if "Pointbit.app/Contents/MacOS/Pointbit"`.
Then run `kill <PID>` with that number.

## Common problems
- The Preferences window does not appear at start: it opens by itself only on the first start. Open it from the menu bar icon → Settings….
- No mark appears: check that Visual Effect is On in Preferences. Marks do not appear on the login screen, because the app is not running there.
- No menu bar icon, or no red dot while recording: on a Mac with a notch, macOS hides icons that do not fit. Hold ⌘ and drag the icon to the right.

## License
PolyForm Shield 1.0.0. See `LICENSE`.
You may use, change and build Pointbit for any purpose permitted by the license, including at work.
You may not use it to provide a product that competes with Pointbit (for example, selling or giving away builds of it).
The license text decides.
Earlier copies released under MIT keep that license.
