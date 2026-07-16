import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    let visibleFrame = NSScreen.main?.visibleFrame ?? self.frame
    let initialSize = NSSize(
      width: min(1440, visibleFrame.width - 80),
      height: min(900, visibleFrame.height - 80)
    )
    self.setContentSize(initialSize)
    self.minSize = NSSize(width: 900, height: 650)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
