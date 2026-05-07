import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private var windowControllers: [NSWindowController] = []

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  @IBAction func newWindow(_ sender: Any?) {
    let windowController = makeWindowController()
    windowControllers.append(windowController)
    windowController.showWindow(sender)
    windowController.window?.makeKeyAndOrderFront(sender)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else {
      return
    }

    windowControllers.removeAll { $0.window === window }
  }

  private func makeWindowController() -> NSWindowController {
    let flutterViewController = FlutterViewController()
    let window = NSWindow(contentViewController: flutterViewController)

    window.setContentSize(NSSize(width: 800, height: 600))
    window.title = "Termeh"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.delegate = self

    if #available(macOS 11.0, *) {
      window.toolbarStyle = .unifiedCompact
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    return NSWindowController(window: window)
  }
}
