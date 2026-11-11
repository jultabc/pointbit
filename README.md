# Pointbit

**Point, understood.**

A macOS menu bar app that shows a mark where the mouse is clicked, so every click is visible, also on a large screen.
It records a window, an area or the whole screen, so a problem can be shown to an agent instead of typed.
It cuts out a subject or a line of text, and takes pictures, also while it records.
Recording, cutting out and pictures are two taps of ⌘ and one letter. A click sound is optional.

Version 1.2.0. Universal (Apple silicon + Intel), macOS 13 or later.

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
  tap ⌘ twice (within 0.35 s), then within 1 s press a letter. Four groups: record T · A · D (This window,
  All screen, Draw a box), picture C · S · R (Capture window, Screen, Remove background), pen shape L · O · B
  (Line, Oval, Box), erase Z · X and colors 1 · 2 · 3, zoom M (Magnify).
  - T: start / stop recording the window under the pointer. A line around it and the dimmed rest of the screen show what is
    recorded (neither is in the video);
    when the window moves, the recorded rect and the highlighter lines move with it (same size)
  - A: start / stop recording the whole screen under the pointer
  - D: a box the size of the window under the pointer. Drag a corner, an edge or the inside to change it;
    Return (or ⌘ ⌘ D) starts recording the box, Esc cancels, ⌘ ⌘ D stops
  - C: picture of the window under the pointer (no shadow)
  - S: picture of the whole screen under the pointer
  - R: cut out a subject of the window under the pointer. The window is taken once and Vision (on this Mac) finds
    its subjects and lines of text; a box shows the line or the subject under the pointer as it moves (every
    subject on the background). Return or ⌘ ⌘ R saves it as a transparent PNG, cropped; a line of text also gets
    its words in a .txt (both files and paths on the clipboard, when Copy to clipboard is on); Esc cancels. A beep when nothing is found.
    macOS 14 or later; on macOS 13 R is not a shortcut and goes on to the front app.
  - Z: while recording, erase the last highlight (again for the one before)
  - X: while recording, erase all highlights
  - 1 · 2 · 3: while recording, highlight color 1 · 2 · 3
  - L · O · B: while recording, the highlighter draws a free line (the default), an oval or a box; it stays until
    changed, and is the free line again in the next recording
  - M: while recording, the video zooms to twice the size around the pointer and follows it; M again goes back.
    On the screen, a solid line goes around the part the video shows and the rest is dimmed
    (the screen itself does not change)
- Highlighter while recording: on a trackpad, hold ⌥ (Option) and move two fingers; the pen starts at the pointer
  and the pointer follows it; lifting the fingers or releasing ⌥ ends the line. One finger with ⌥ does not draw.
  While ⌥ is held, a small lavender dot at the pointer shows where the line starts (not in the video).
  With a mouse, hold ⌥ and drag with the left button. Add ⇧ (⌥ + ⇧) for a straight line from where the line
  started; within 20° of level it is exactly horizontal (the start's y) or vertical (the start's x), other angles
  stay as drawn. A closed loop (back near its start, once around, close to round) becomes a clean ellipse, or a
  circle when nearly round; ⌘ ⌘ Z on it brings back the hand-drawn line first. The line is in the video.
  ⌘ ⌘ 1 · 2 · 3 pick color 1 · 2 · 3 (yellow, red, blue by default; set in Preferences).
  After ⌘ ⌘ O or ⌘ ⌘ B the same ⌥ drag draws an oval or a box from where it started (one corner) to the pen (the
  opposite corner), redrawn as it moves; with ⇧ a circle or a square.
  ⌥ + click on a line erases that line; where lines cross, the one whose start is nearest the click.
  While ⌥ is held, two-finger scrolling does not reach the app; an ⌥ + press, its drag and its release do not either.
  Lines stay until erased and are all removed when the recording stops. The event tap behind this exists
  only while recording and is removed, not turned on again, if macOS turns it off.
- Record my voice (off by default): recordings include the microphone (not system or app sound), and afterwards
  `TACS-<…>.txt` next to the `.mov` holds what was said, one line per sentence or pause, each with its time
  (`[01:05] …`). An agent cannot hear a video, but it can read this file. Speech recognition runs on this Mac,
  in the Mac's language or one chosen in Preferences:
  - macOS 26 or later: SpeechAnalyzer, made for long sound. macOS downloads its language model once.
  - Earlier macOS: SFSpeechRecognizer with `requiresOnDeviceRecognition`. It needs System Settings → Keyboard →
    Dictation on and works in parts of 50 s; a word cut at a part's edge can be lost, and a part that fails shows as
    `[00:50] (not recognized: 00:50–01:40)`.

  Needs Microphone, and Speech Recognition for the earlier engine. Without the Microphone permission, or without a microphone, the video is still recorded, without sound. With "Copy to clipboard when it ends" on,
  the clipboard gets both files and both paths (video, a space, text) once the text is written, unless something else was copied
  in between.

  Files are named `TACS-<yyyyMMdd>-<HHmmssSSS>.png` / `.mov` and go to the save folder (the Desktop unless another
  folder is chosen). With "Copy to clipboard when it ends" on, the clipboard then holds the file and its path:
  Notes or a chat app pastes the file, a terminal usually pastes the path (each app picks; with it off, nothing
  is copied). A white flash and the shutter sound confirm a picture; while recording, the menu bar
  icon is replaced by the seconds recorded (0, 1, 2 …), and its menu shows "Stop Recording". Recordings are half size by default (point size: half each way
  on a Retina screen, smaller files; Preferences → Capture → Recording size → Full for all pixels), 30 fps, with the pointer and the click marks;
  sound only with Record my voice.
  The app sets no fixed time limit (free disk space still applies). Size per minute, half size (measured 2026-11-04/05 on an M1, H.264): about 12 MB for a
  quiet 1800 × 1130 window, 45–50 MB for a moving window or the whole screen; so about 0.7–3 GB an hour. Full size
  may be larger (not measured). The `.txt` of a long recording can take a few minutes after it stops.
  The action key is not passed to the front app; ⌘T, ⌘A, ⌘C, ⌘S, ⌘R, ⌘Z, ⌘X and ⌘1 · ⌘2 · ⌘3 are not affected.
  Needs Accessibility (to see the ⌘ ⌘ keys) and Screen & System Audio Recording (system audio is never recorded).
  Keys are read by a listen-only tap, which cannot hold back input. A second tap that holds back the action key
  exists only from the second ⌘ press until that key is released, at most 3 s.
- Menu bar icon: About · Show Visual Feedback · Play Click Sound · Settings… · Quit, plus Stop Recording while recording.
- Preferences in three tabs: Click Marks, Capture (shortcuts, file path, voice, save folder, permissions) and
  Highlighter (how to draw and erase, the three colors). Under the tabs: Launch on computer startup and Restore Defaults.
  The window opens by itself only on the first start; after that, from the menu bar icon → Settings….
  It stays in front of other apps while open, so clicks can be tried with it open.
  After a click on a slider, the arrow keys move it (1% of the range; with Shift, 10%).
- Only one copy runs. A second copy (for example the one in `build/`) quits at start.
- App and menu bar icons are drawn in code.
- Settings are stored in the `si.codegg.pointbit` defaults domain (`defaults read si.codegg.pointbit`).

## Size
| Part | Swift lines (incl. blank and comment lines) |
|---|---|
| App and icon tool (`Sources/`, 33 files) | 4165 |
| Tests and `Package.swift` (18 test files + 1) | 1684 |
| Total | 5849 |

Recount: `git ls-files '*.swift' | xargs wc -l`

## Build from source
Toolchain: Xcode with Swift 6.3, macOS 13+ target. Check with `swift --version`.
```
./build.sh                                                # tests + build
swift test                                                # tests only
ditto build/Pointbit.app /Applications/Pointbit.app       # install (quit the running one first)
open /Applications/Pointbit.app                           # start
open /Applications/Pointbit.app --args --settings         # start with the settings window open
open -n /Applications/Pointbit.app --args --transcribe /path/TACS-….mov   # write the .txt again for a recording
```

## Stop
To quit, choose "Quit Pointbit" from the menu bar icon.
To stop it from a terminal, find the app's PID with `pgrep -if "Pointbit.app/Contents/MacOS/Pointbit"`.
Then run `kill <PID>` with that number.

## Common problems
- The Preferences window does not appear at start: it opens by itself only on the first start. Open it from the menu bar icon → Settings….
- No mark appears: check that Visual Effect is On in Preferences. Marks do not appear on the login screen, because the app is not running there.
- No menu bar icon, or no seconds while recording: on a Mac with a notch, macOS hides icons that do not fit. Hold ⌘ and drag the icon to the right.

## License
PolyForm Shield 1.0.0. See `LICENSE`.
You may use, change and build Pointbit for any purpose permitted by the license, including at work.
You may not use it to provide a product that competes with Pointbit (for example, selling or giving away builds of it).
The license text decides.
Earlier copies released under MIT keep that license.
