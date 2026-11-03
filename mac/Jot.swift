// 记一下 · macOS 壳
//
// 用 WKWebView 把 index.html 包成一个双击即用的原生窗口应用：
// 无地址栏、无浏览器 UI、独立的 Dock 图标、Cmd+V 粘贴可用、闹铃铃声可自动播放。
//
// 为什么不用 file:// 直接打开：WebKit 不会把 file:// 的 localStorage 落盘，
// 每次启动都是空的（实测 write 后重新打开为 MISSING），提醒数据会丢。
// 这里改用自定义协议 jot://app/ 提供页面，origin 固定、storage 可持久化。
//
// 构建：./mac/build.sh（产出 dist/Jot.app）

import Cocoa
import WebKit

/// 把包内的 index.html 通过 jot://app/index.html 提供给 WebView
final class AppSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(resourceRoot: URL) { root = resourceRoot }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }

        let file = root.appendingPathComponent(String(path.drop(while: { $0 == "/" })))
        guard let data = try? Data(contentsOf: file) else {
            let body = Data("404".utf8)
            let resp = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/plain; charset=utf-8"])!
            task.didReceive(resp); task.didReceive(body); task.didFinish()
            return
        }
        let mime = file.pathExtension.lowercased() == "html" ? "text/html" : "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "\(mime); charset=utf-8",
                                                  "Content-Length": "\(data.count)"])!
        task.didReceive(resp); task.didReceive(data); task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// 页面点「加入日历」时，把 .ics 内容通过 JS bridge 送过来，落到临时文件再交给 Calendar.app。
/// 这样不用依赖 WKWebView 的下载行为（blob 下载在壳里不弹保存面板，很容易默默失败）。
final class BridgeHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "jot",
              let body = message.body as? [String: Any],
              let content = body["content"] as? String else { return }
        let name = ((body["filename"] as? String) ?? "jot.ics").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try content.data(using: .utf8)?.write(to: url)
        } catch {
            return
        }
        // JOT_NO_OPEN=1 只写文件、不拉起日历（自检用）
        if ProcessInfo.processInfo.environment["JOT_NO_OPEN"] != "1" {
            NSWorkspace.shared.open(url)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {

    private var window: NSWindow!
    private var webView: WKWebView!
    private var schemeHandler: AppSchemeHandler!
    private let bridge = BridgeHandler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let cfg = WKWebViewConfiguration()
        // 闹铃响的时候往往没有「刚点过页面」的用户手势，这里放开自动播放限制
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.isElementFullscreenEnabled = true
        if let root = Bundle.main.resourceURL {
            schemeHandler = AppSchemeHandler(resourceRoot: root)
            cfg.setURLSchemeHandler(schemeHandler, forURLScheme: "jot")
        }

        // WKWebView 里 webkitSpeechRecognition 这个对象存在、但根本跑不起来，
        // 页面会因此显示一个按了没反应的麦克风按钮。这里在页面脚本之前抹掉它，
        // Mac 上改用系统听写（按两下 Fn 键）代替语音输入。
        let shim = """
        try { Object.defineProperty(window, 'SpeechRecognition', { value: undefined, configurable: true }); } catch (e) {}
        try { Object.defineProperty(window, 'webkitSpeechRecognition', { value: undefined, configurable: true }); } catch (e) {}
        window.__JOT_DESKTOP__ = true;
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        cfg.userContentController.add(bridge, name: "jot")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 840), configuration: cfg)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Jot"
        window.backgroundColor = NSColor(srgbRed: 0.965, green: 0.957, blue: 0.941, alpha: 1)
        window.minSize = NSSize(width: 380, height: 560)
        window.contentView = webView
        if !window.setFrameUsingName("JotMainWindow") {
            window.center()
        }
        window.setFrameAutosaveName("JotMainWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        loadPage()
        runAutomationIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    private func loadPage() {
        guard Bundle.main.url(forResource: "index", withExtension: "html") != nil else {
            let a = NSAlert()
            a.messageText = "index.html is missing"
            a.informativeText = "The app bundle has no index.html — re-run mac/build.sh to rebuild it."
            a.runModal()
            NSApp.terminate(nil)
            return
        }
        webView.load(URLRequest(url: URL(string: "jot://app/index.html")!))
    }

    // 页面里指向外部的链接交给系统浏览器，别在应用窗口里把应用顶掉
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.scheme != "jot" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - 菜单（没有 Edit 菜单，WKWebView 里的 Cmd+C / Cmd+V 会失效）

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Jot",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Jot", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Jot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = winMenu

        NSApp.mainMenu = main
    }

    // MARK: - 自动化小工具（只在带环境变量启动时生效，正常双击不会触发）
    //   JOT_SELFTEST=write|read  验证 localStorage 在应用容器里能否持久化
    //   JOT_SNAPSHOT=/path.png   把当前页面截图存盘（做文档/截图用，不依赖系统录屏权限）
    //   JOT_EVAL='<js>'          在页面里跑一段 JS 并打印结果（调试 bridge / 选择器用）

    private func runAutomationIfNeeded() {
        let env = ProcessInfo.processInfo.environment

        if let js = env["JOT_EVAL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.webView.evaluateJavaScript(js) { result, error in
                    print("EVAL:", result ?? "nil", error?.localizedDescription ?? "")
                    // 留一点时间让 postMessage 之类的异步消息落地
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { NSApp.terminate(nil) }
                }
            }
            return
        }

        if let out = env["JOT_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.webView.takeSnapshot(with: nil) { image, _ in
                    if let image = image,
                       let tiff = image.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: out))
                        print("SNAPSHOT:", out)
                    }
                    NSApp.terminate(nil)
                }
            }
            return
        }

        guard let mode = env["JOT_SELFTEST"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            let js = mode == "write"
                ? "localStorage.setItem('__selftest','ok'); 'wrote'"
                : "(localStorage.getItem('__selftest') || 'MISSING')"
            self?.webView.evaluateJavaScript(js) { result, error in
                print("SELFTEST[\(mode)]:", result ?? "nil", error?.localizedDescription ?? "")
                NSApp.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
