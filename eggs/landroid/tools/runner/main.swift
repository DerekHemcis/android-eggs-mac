// Standalone fullscreen runner for the Landroid saver view.
import AppKit
import ScreenSaver

final class Delegate: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var views: [ScreenSaverView] = []
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let saverBundle = Self.locateSaver(),
              saverBundle.load(),
              let cls = NSClassFromString("LandroidView") as? ScreenSaverView.Type else {
            let a = NSAlert(); a.messageText = "找不到 Landroid.saver"
            a.informativeText = "请把 Landroid.saver 放在 ~/Library/Screen Savers/"
            a.runModal(); NSApp.terminate(nil); return
        }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                             backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver + 1
            w.backgroundColor = .black
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isOpaque = true
            let v = cls.init(frame: NSRect(origin: .zero, size: screen.frame.size), isPreview: false)!
            v.autoresizingMask = [.width, .height]
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            w.makeKeyAndOrderFront(nil)
            w.orderFrontRegardless()
            views.append(v); windows.append(w)
            v.startAnimation()
        }
        NSCursor.hide()
        NSApp.activate(ignoringOtherApps: true)
        // 60 fps driver
        let t = Timer(timeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.views.forEach { $0.animateOneFrame() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { _ in
            NSApp.terminate(nil); return nil
        }
    }

    static func locateSaver() -> Bundle? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let installed = home.appendingPathComponent("Library/Screen Savers/Landroid.saver")
        if FileManager.default.fileExists(atPath: installed.path),
           let b = Bundle(url: installed) { return b }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Landroid.saver"),
           let b = Bundle(url: res) { return b }
        return nil
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
