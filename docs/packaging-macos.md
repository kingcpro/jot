# Packaging Jot as a macOS app

`dist/Jot.app` is a ~1 MB native shell around `index.html`: no address bar, its own Dock icon,
`Cmd+C/V` works, and the alarm chime is allowed to autoplay. Build it with:

```bash
./mac/build.sh
open dist/Jot.app
```

## Why a WKWebView shell

| Option | Native feel | Cost | Works from disk | Problem |
| --- | --- | --- | --- | --- |
| Safari → *Add to Dock* (macOS 14+) | ★★★★ | zero code | no | needs http(s); `file://` can't be added |
| AppleScript wrapper (`osacompile`) | ★★ | 3 commands | yes | still opens a browser tab |
| **WKWebView shell (this repo)** | ★★★★ | one ~200-line Swift file | yes | the process must stay open to ring |
| Electron / Tauri | ★★★★★ | tens of MB + toolchain | yes | heavy for a 40 KB page |

## Gotchas worth knowing before you touch the shell

**1. `localStorage` does not persist for `file://` pages in WebKit.**
Loading `index.html` with `loadFileURL` works until you restart: values written in one session come
back as `null`. For a reminder app that means silent data loss. The fix is a custom scheme —
`jot://app/index.html`, served by a `WKURLSchemeHandler` from the bundle — which gives a stable
origin (`jot://app`) and a persistent store. Verified with `JOT_SELFTEST` (see below): `wrote` → `ok`.

**2. Without an Edit menu, `Cmd+V` does nothing.**
Paste goes through the responder chain, which needs those menu items to exist. The shell builds
App / Edit / Window menus by hand.

**3. Autoplay is blocked exactly when you need it.**
An alarm fires without a fresh user gesture, so `mediaTypesRequiringUserActionForPlayback = []` is
mandatory — otherwise the screen goes dark and stays silent.

**4. `webkitSpeechRecognition` exists in WKWebView but cannot work.**
The page would show a microphone button that does nothing. The shell injects a shim that removes
both constructors before page scripts run, so the button stays hidden; on macOS use the system
dictation key (press `Fn` twice) instead.

**5. There are no Web Notifications in WKWebView.**
The full-screen alarm + chime is the whole mechanism here. Don't expect `Notification` to fire.

**6. Downloads are unreliable, so the calendar export uses a bridge.**
`<a download>` with a Blob can silently do nothing inside a shell. The page posts the `.ics` text to
a `WKScriptMessageHandler` named `jot`; the shell writes it to the temp directory and opens it, which
hands the event to Calendar.app.

## Layout

```
mac/
├── Jot.swift        window, menus, jot:// handler, calendar bridge, dev hooks
├── Info.plist       bundle id app.jot.reminder, display name Jot
└── build.sh         swiftc → .app, generates the .icns from tools/icon.swift
```

`build.sh` tries the default SDK first and falls back through every installed `MacOSX*.sdk`, because
Command Line Tools occasionally ship a `swiftc` older than the default SDK ("this SDK is not
supported by the compiler").

## Dev hooks

Nothing below runs on a normal double-click; each one is an environment variable:

```bash
JOT_SELFTEST=write ./dist/Jot.app/Contents/MacOS/Jot    # write a probe value
JOT_SELFTEST=read  ./dist/Jot.app/Contents/MacOS/Jot    # read it back → "ok"
JOT_SNAPSHOT=/tmp/shot.png ./dist/Jot.app/Contents/MacOS/Jot   # page screenshot (no screen-recording permission needed)
JOT_EVAL='document.title' ./dist/Jot.app/Contents/MacOS/Jot    # run JS, print the result
JOT_NO_OPEN=1 ...                                       # with the bridge: write the .ics but don't launch Calendar
```

## Distribution

Ad-hoc signed locally, so it runs on the machine that built it. Handing it to someone else means a
Developer ID signature plus notarization, otherwise Gatekeeper blocks it. Since the app is just
`index.html` in a bundle, most people are better served by the PWA install (see
[packaging-desktop.md](packaging-desktop.md)).

## Still true after packaging

The shell does not fix the platform limit: **close the process and the alarm stops.** The calendar
export exists for exactly that case. If you want to go further, the options are a background
agent (`launchd` + menu bar item), EventKit (write into Reminders.app and let the system notify),
or a native notification layer — all bigger than this shell.
