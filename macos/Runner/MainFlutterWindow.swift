import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Termeh"
    self.titleVisibility = .hidden
    self.isMovableByWindowBackground = true
    if #available(macOS 11.0, *) {
      self.toolbarStyle = .unifiedCompact
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
