import Foundation
import ServiceManagement

@MainActor
public final class LaunchAtLoginHelper: ObservableObject {
    public static let shared = LaunchAtLoginHelper()

    @Published public var isEnabled: Bool = false

    private let launchAgentURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/org.lordfirehawk.firehawk-focus.plist")
    }()

    public init() {
        checkStatus()
    }

    public func checkStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled {
                self.isEnabled = true
                return
            }
        }
        self.isEnabled = FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    public func setEnabled(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                    self.isEnabled = true
                    try? FileManager.default.removeItem(at: launchAgentURL)
                    return
                } else {
                    try SMAppService.mainApp.unregister()
                    self.isEnabled = false
                    try? FileManager.default.removeItem(at: launchAgentURL)
                    return
                }
            } catch {
                print("[LaunchAtLogin] SMAppService notice: \(error), using LaunchAgent")
            }
        }

        // Fallback to standard user LaunchAgent
        if enable {
            let appPath = Bundle.main.bundlePath
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>org.lordfirehawk.firehawk-focus</string>
                <key>ProgramArguments</key>
                <array>
                    <string>/usr/bin/open</string>
                    <string>-a</string>
                    <string>\(appPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>ProcessType</key>
                <string>Interactive</string>
            </dict>
            </plist>
            """
            try? FileManager.default.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plistContent.write(to: launchAgentURL, atomically: true, encoding: .utf8)
            self.isEnabled = true
        } else {
            try? FileManager.default.removeItem(at: launchAgentURL)
            self.isEnabled = false
        }
    }
}
