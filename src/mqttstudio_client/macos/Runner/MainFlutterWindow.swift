import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // AppKit saves the frame under this name in the user defaults whenever the window moves or resizes
  private static let frameName = "MainWindow"

  // Started by the mqttstudio command (macos/packaging/mqttstudio): Dart runs the headless CLI and ends the process
  // with the exit code of the command (doc/cli-design.md).
  private static let isHeadlessCli = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "--cli"

  override func awakeFromNib() {
    let project = FlutterDartProject()
    if MainFlutterWindow.isHeadlessCli {
      // like the Windows console launcher, the version goes first; the GUI gets no arguments
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
      project.dartEntrypointArguments = ["--cli", "--app-version=\(version)"] + CommandLine.arguments.dropFirst(2)
    }
    let flutterViewController = FlutterViewController(project: project)
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    if MainFlutterWindow.isHeadlessCli {
      // no window, Dock icon or menu bar; the nib leaves the window hidden and state restoration must not show it
      NSApp.setActivationPolicy(.prohibited)
      self.isRestorable = false
      return
    }
    // the size and position of the last session, else Full HD (the layout is made for a wide window) or the whole
    // screen when it is smaller, centered
    if !self.setFrameUsingName(MainFlutterWindow.frameName) {
      self.setFrame(MainFlutterWindow.initialFrame(on: self.screen ?? NSScreen.main), display: true)
    }
    self.setFrameAutosaveName(MainFlutterWindow.frameName)
    self.makeKeyAndOrderFront(nil)
  }

  private static func initialFrame(on screen: NSScreen?) -> NSRect {
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let width = min(1920, visible.width)
    let height = min(1080, visible.height)
    return NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
  }
}
