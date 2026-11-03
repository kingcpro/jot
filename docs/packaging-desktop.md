# Desktop packaging: Windows, Linux, and the "no build at all" route

Short answer to "does this run on Windows?" — **the app runs, the macOS shell doesn't.**
`index.html` is plain HTML/CSS/JS, so any browser on Windows opens it. What you don't get for free
is a double-clickable `.exe` with its own window.

There are three ways to get there, in increasing order of effort.

## 1. Install it as an app (recommended, no build)

If the page is served over http(s) — GitHub Pages, Netlify, any static host, or a local server —
Chrome and Edge can install it as a real application:

1. Open the page.
2. Address-bar install icon → **Install**, or menu → *Apps → Install this site as an app*.
3. It lands in the Start menu (Windows) / application launcher (Linux), opens in its own window,
   keeps its own icon, and works offline thanks to `sw.js`.

macOS gets the same thing via Safari 17+ → *File → Add to Dock*.

This is why the repo ships `manifest.webmanifest`, `sw.js` and `icons/` even though the app itself
is one file: the manifest is what makes "install" possible. `file://` won't do — installability
requires a real origin, and the service worker needs one too.

Serving locally for a test:

```bash
python3 -m http.server 8000     # then open http://localhost:8000
```

## 2. A real `.exe` with Tauri (~30 MB)

[Tauri](https://tauri.app) wraps the same HTML in a native window and produces `.msi`/`.exe` on
Windows, `.dmg` on macOS and `.AppImage`/`.deb` on Linux from one codebase. It uses the system
webview (WebView2 on Windows, WebKitGTK on Linux, WKWebView on macOS) instead of bundling Chromium,
so the binary stays small.

Rough shape:

```bash
cargo install create-tauri-app
# point frontendDist at this folder, add index.html as the entry
```

Two things to decide when you do it:

- **Storage.** Tauri serves the app from a custom protocol, which gives a stable origin and working
  `localStorage` — the same problem the macOS shell solves with `jot://`.
- **The calendar export.** A Blob download may not surface a save dialog inside the webview. Either
  enable Tauri's `dialog`/`fs` plugins, or call the OS handler directly
  (`startTransition`/`opener` plugin) to open the `.ics`.

## 3. Electron (~150 MB)

The most predictable option: Chromium is bundled, so rendering and `localStorage` behave exactly
like a browser. It costs ~150 MB per install and a Node toolchain in CI. For a 40 KB single-file
app it's the last resort, not the first.

## What no packaging option fixes

- **An alarm needs a live process.** Close the window and nothing rings — that's true of the
  browser version, the macOS shell, and a Tauri build. The cross-platform answer is
  **Add to Calendar**: the `.ics` export puts the reminder into the OS calendar, which keeps
  notifying with the app closed.
- **Notifications differ per platform.** Chrome/Edge support the Web Notifications API and
  Service Worker triggers; WKWebView has neither. The full-screen alarm is the common denominator.
