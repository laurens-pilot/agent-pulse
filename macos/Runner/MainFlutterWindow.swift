import Cocoa
import FlutterMacOS

private let codexRootAccessChannelName = "com.laurens.codexDashboard/codexRootAccess"

private final class CodexRootAccessController {
  private static let bookmarkDefaultsKey = "codexRootSecurityScopedBookmark"

  private let channel: FlutterMethodChannel
  private weak var window: NSWindow?
  private var activeURL: URL?
  private var openPanel: NSOpenPanel?

  init(channel: FlutterMethodChannel, window: NSWindow) {
    self.channel = channel
    self.window = window
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "resolveOrRequestCodexRoot" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.resolveOrRequestCodexRoot(result: result)
    }
  }

  deinit {
    activeURL?.stopAccessingSecurityScopedResource()
    channel.setMethodCallHandler(nil)
  }

  private func resolveOrRequestCodexRoot(result: @escaping FlutterResult) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.resolveOrRequestCodexRoot(result: result)
      }
      return
    }

    if let url = restoreBookmarkedURL() {
      result(url.path)
      return
    }
    presentFolderPicker(result: result)
  }

  private func restoreBookmarkedURL() -> URL? {
    guard
      let bookmark = UserDefaults.standard.data(
        forKey: Self.bookmarkDefaultsKey
      )
    else {
      return nil
    }

    do {
      var isStale = false
      let url = try URL(
        resolvingBookmarkData: bookmark,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      guard startAccessing(url), isCodexRoot(url) else {
        clearBookmark()
        return nil
      }
      if isStale {
        try storeBookmark(for: url)
      }
      return url
    } catch {
      clearBookmark()
      return nil
    }
  }

  private func presentFolderPicker(result: @escaping FlutterResult) {
    guard openPanel == nil else {
      result(
        FlutterError(
          code: "request_in_progress",
          message: "The Codex folder picker is already open.",
          details: nil
        )
      )
      return
    }

    let panel = NSOpenPanel()
    panel.title = "Allow access to your Codex data"
    panel.message =
      "Choose the .codex folder in your home directory. Codex Pulse receives read-only access."
    panel.prompt = "Grant Read-Only Access"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.showsHiddenFiles = true
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex", isDirectory: true)
    openPanel = panel

    let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard let self else {
        result(
          FlutterError(
            code: "access_unavailable",
            message: "Codex folder access is unavailable.",
            details: nil
          )
        )
        return
      }
      self.openPanel = nil
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      guard self.isCodexRoot(url) else {
        url.stopAccessingSecurityScopedResource()
        result(
          FlutterError(
            code: "invalid_codex_root",
            message: "Choose the .codex folder that contains history.jsonl.",
            details: nil
          )
        )
        return
      }

      do {
        try self.storeBookmark(for: url)
        self.adoptPanelAccess(to: url)
        result(url.path)
      } catch {
        url.stopAccessingSecurityScopedResource()
        self.clearBookmark()
        result(
          FlutterError(
            code: "bookmark_failed",
            message: "Read-only access to the selected folder could not be saved.",
            details: nil
          )
        )
      }
    }

    if let window {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      completion(panel.runModal())
    }
  }

  private func isCodexRoot(_ url: URL) -> Bool {
    FileManager.default.isReadableFile(
      atPath: url.appendingPathComponent("history.jsonl").path
    )
  }

  private func storeBookmark(for url: URL) throws {
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    UserDefaults.standard.set(bookmark, forKey: Self.bookmarkDefaultsKey)
  }

  private func startAccessing(_ url: URL) -> Bool {
    if activeURL?.standardizedFileURL == url.standardizedFileURL {
      return true
    }
    guard url.startAccessingSecurityScopedResource() else {
      return false
    }
    activeURL?.stopAccessingSecurityScopedResource()
    activeURL = url
    return true
  }

  private func adoptPanelAccess(to url: URL) {
    if activeURL?.standardizedFileURL == url.standardizedFileURL {
      return
    }
    activeURL?.stopAccessingSecurityScopedResource()
    // NSOpenPanel starts security-scoped access for the selected URL.
    activeURL = url
  }

  private func clearBookmark() {
    activeURL?.stopAccessingSecurityScopedResource()
    activeURL = nil
    UserDefaults.standard.removeObject(forKey: Self.bookmarkDefaultsKey)
  }
}

class MainFlutterWindow: NSWindow {
  private var codexRootAccessController: CodexRootAccessController?

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
    let codexRootAccessChannel = FlutterMethodChannel(
      name: codexRootAccessChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    codexRootAccessController = CodexRootAccessController(
      channel: codexRootAccessChannel,
      window: self
    )

    super.awakeFromNib()
  }
}
