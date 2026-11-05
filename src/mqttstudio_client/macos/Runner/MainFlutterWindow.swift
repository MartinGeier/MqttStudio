import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // AppKit saves the frame under this name in the user defaults whenever the window moves or resizes
  private static let frameName = "MainWindow"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // the size and position of the last session, else Full HD (the layout is made for a wide window) or the whole
    // screen when it is smaller, centered
    if !self.setFrameUsingName(MainFlutterWindow.frameName) {
      self.setFrame(MainFlutterWindow.initialFrame(on: self.screen ?? NSScreen.main), display: true)
    }
    self.setFrameAutosaveName(MainFlutterWindow.frameName)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private static func initialFrame(on screen: NSScreen?) -> NSRect {
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let width = min(1920, visible.width)
    let height = min(1080, visible.height)
    return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
  }
}
