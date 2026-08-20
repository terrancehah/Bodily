import Foundation
import Combine
import SwiftUI
import WidgetKit
import Security
import Sparkle

/// Tracks the current state of the Garmin Connect login flow.
enum LoginState: Equatable {
    case idle
    case authenticating
    case mfaRequired
    case success
    case error(String)
}

/// App theme mode: follow system setting, or force light/dark.
enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// ViewModel for the host app's main content view.
/// Manages loading metrics, checking connection status, and triggering actions.
class AppViewModel: ObservableObject {
    
    @Published var currentMetrics: GarminMetrics?
    @Published var isConnected: Bool = false
    @Published var lastUpdateTime: String?
    @Published var isRefreshing: Bool = false
    @Published var loginState: LoginState = .idle
    @Published var savedEmail: String = ""
    @Published var savedPassword: String = ""
    @Published var hasExistingAuth: Bool = false
    // Account info populated after successful login
    @Published var accountDisplayName: String = ""
    @Published var accountFullName: String = ""
    @Published var accountEmail: String = ""
    @Published var accountProfileImageURL: String = ""
    @Published var accountDeviceName: String = ""
    /// Whether the launchd fetcher agent (com.bodily.fetcher) is currently loaded
    @Published var fetcherRunning: Bool = false
    /// True while the account-info script is refreshing profile data in the background
    @Published var isRefreshingAccountInfo: Bool = false
    /// True during first-launch environment setup (venv creation, pip install, launchd agent)
    @Published var isSettingUpEnvironment: Bool = false
    /// Ordered list of metrics shown in the main grid — user-customizable via the drawer
    @Published var visibleMetrics: [MetricID] = MetricID.defaultVisible
    /// Current theme mode: system, light, or dark
    @Published var themeMode: ThemeMode = .system

    /// UserDefaults keys for persisting saved login credentials and account info.
    /// Password is stored in the macOS Keychain (see keychainService), not UserDefaults.
    private let savedEmailKey = "bodily.savedEmail"
    private let savedDisplayNameKey = "bodily.savedDisplayName"
    private let savedFullNameKey = "bodily.savedFullName"
    private let savedAccountEmailKey = "bodily.savedAccountEmail"
    private let savedProfileImageURLKey = "bodily.savedProfileImageURL"
    private let savedDeviceNameKey = "bodily.savedDeviceName"

    /// launchd label of the background fetcher agent (must match the installed plist)
    private let fetcherAgentLabel = "com.bodily.fetcher"

    /// UserDefaults key for the customized metric grid (ordered raw value array)
    private let visibleMetricsKey = "bodily.visibleMetrics"
    /// UserDefaults key for the theme mode preference
    private let themeModeKey = "bodily.themeMode"

    /// Grid capacity — 9 tiles so the large widget (3×3) can show the full selection
    static let maxVisibleMetrics = 9

    /// UserDefaults suite shared with the widget extension so both render the same selection
    private let sharedDefaults = UserDefaults(suiteName: "group.com.bodily.shared")
    
    /// Long-lived process and pipes for the two-phase login (credentials → MFA)
    private var loginProcess: Process?
    private var loginStdin: FileHandle?
    private var loginStdout: FileHandle?
    private var loginStderr: FileHandle?
    /// Stores credentials and rememberMe preference between phase 1 and phase 2
    private var loginRememberMe: Bool = true
    private var loginEmail: String = ""
    private var loginPassword: String = ""
    
    // MARK: - Path Resolution

    /// Resolves the path to a bundled fetcher script.
    /// Scripts are copied into Resources/fetcher/ by the Xcode build phase
    /// and are always available at runtime. No fallback needed.
    private func scriptPath(_ filename: String) -> String {
        let resourcePath = Bundle.main.resourcePath ?? ""
        return "\(resourcePath)/fetcher/\(filename)"
    }

    /// Path to the Python fetcher script
    private var fetcherScriptPath: String { scriptPath("garmin_fetcher.py") }

    /// Path to the non-interactive login script
    private var loginScriptPath: String { scriptPath("login.py") }

    /// Path to the account info script
    private var accountInfoScriptPath: String { scriptPath("account-info.py") }

    /// Discovers a working Python 3 interpreter on the user's system.
    /// Tries Homebrew paths first (they allow pip installs), then system Python.
    /// Returns nil if no Python 3 is found — the first-launch setup will guide the user.
    private func discoverSystemPython() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",       // Homebrew Apple Silicon
            "/usr/local/bin/python3",           // Homebrew Intel
            "/usr/bin/python3",                 // System (pip restricted on macOS 14+)
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Path to the app-managed venv Python executable.
    /// Created on first launch so the app controls its own dependency environment.
    private var venvPythonPath: String {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Bodily")
        return appSupport.appendingPathComponent("venv/bin/python3").path
    }

    /// Returns the Python to use: venv Python if set up, otherwise system Python.
    /// The refresh/login flows call this so they always use the best available Python.
    private var resolvedPythonPath: String {
        if FileManager.default.fileExists(atPath: venvPythonPath) {
            return venvPythonPath
        }
        return discoverSystemPython() ?? "/usr/bin/python3"
    }

    /// Path to the fetcher log file (in the App Group container so the widget can read it)
    private let logPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Group Containers/group.com.bodily.shared/fetcher.log"
    }()

    /// Path to the token store / config directory (~/.garminconnect)
    private let configDirectoryPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.garminconnect"
    }()

    /// Directory for app-managed data (venv, launchd plist backups)
    private var appSupportDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Bodily").path
    }
    
    init() {
        loadSavedEmail()
        checkExistingAuth()
        loadVisibleMetrics()
        loadTheme()
        applyTheme()
    }

    // MARK: - Metric Grid Customization

    /// Restores the saved metric selection, falling back to the default six.
    private func loadVisibleMetrics() {
        // Migrate any selection saved in standard defaults before the App Group switch
        if let legacy = UserDefaults.standard.stringArray(forKey: visibleMetricsKey) {
            sharedDefaults?.set(legacy, forKey: visibleMetricsKey)
            UserDefaults.standard.removeObject(forKey: visibleMetricsKey)
        }
        guard let rawValues = sharedDefaults?.stringArray(forKey: visibleMetricsKey) else { return }
        let restored = rawValues.compactMap { MetricID(rawValue: $0) }
        if !restored.isEmpty {
            visibleMetrics = Array(restored.prefix(Self.maxVisibleMetrics))
        }
    }

    /// Persists the current selection to the shared suite as ordered raw values.
    /// Widget reloads are NOT fired here — drags persist on every hover move,
    /// so the widget is only reloaded when a drag finishes (see reloadWidgetTimelines).
    private func persistVisibleMetrics() {
        sharedDefaults?.set(visibleMetrics.map(\.rawValue), forKey: visibleMetricsKey)
    }

    /// Tells WidgetKit the metric layout changed so the widget mirrors the app.
    /// Called when a drag finishes or customize mode closes — not on every hover move.
    func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "BodilyWidget")
    }

    // MARK: - Theme

    /// Restores the saved theme preference, defaulting to system.
    private func loadTheme() {
        guard let rawValue = UserDefaults.standard.string(forKey: themeModeKey),
              let mode = ThemeMode(rawValue: rawValue) else { return }
        themeMode = mode
    }

    /// Persists the current theme preference and applies it to the app window.
    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: themeModeKey)
        applyTheme()
    }

    /// Overrides NSApp.appearance to match the selected theme mode.
    private func applyTheme() {
        switch themeMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Moves a metric to sit just before another one in the grid.
    /// When the grid is full and the dragged card comes from the pool, the
    /// target card is swapped out to the pool — the grid never exceeds 6.
    func moveOrInsert(_ dropped: MetricID, before target: MetricID) {
        guard dropped != target else { return }
        let wasVisible = visibleMetrics.contains(dropped)
        visibleMetrics.removeAll { $0 == dropped }
        if wasVisible || visibleMetrics.count < Self.maxVisibleMetrics {
            let targetIndex = visibleMetrics.firstIndex(of: target) ?? visibleMetrics.count
            visibleMetrics.insert(dropped, at: targetIndex)
        } else if let targetIndex = visibleMetrics.firstIndex(of: target) {
            // Grid full + pool card: swap takes the target's slot
            visibleMetrics[targetIndex] = dropped
        }
        persistVisibleMetrics()
    }

    /// Moves a metric to sit just after another one in the grid.
    /// Used when the cursor drops on the right half of a target card.
    /// When the grid is full and the dragged card comes from the pool, the
    /// target card is swapped out to the pool — the grid never exceeds 6.
    func moveOrInsert(_ dropped: MetricID, after target: MetricID) {
        guard dropped != target else { return }
        let wasVisible = visibleMetrics.contains(dropped)
        visibleMetrics.removeAll { $0 == dropped }
        if wasVisible || visibleMetrics.count < Self.maxVisibleMetrics {
            let targetIndex = visibleMetrics.firstIndex(of: target) ?? max(visibleMetrics.count - 1, 0)
            let insertIndex = min(targetIndex + 1, visibleMetrics.count)
            visibleMetrics.insert(dropped, at: insertIndex)
        } else if let targetIndex = visibleMetrics.firstIndex(of: target) {
            // Grid full + pool card: swap takes the target's slot
            visibleMetrics[targetIndex] = dropped
        }
        persistVisibleMetrics()
    }

    /// Moves a metric to the end of the grid. A pool card is only added when
    /// the grid has room — at capacity, dropping on empty space is a no-op.
    func moveOrAppend(_ metric: MetricID) {
        let wasVisible = visibleMetrics.contains(metric)
        visibleMetrics.removeAll { $0 == metric }
        guard wasVisible || visibleMetrics.count < Self.maxVisibleMetrics else { return }
        visibleMetrics.append(metric)
        persistVisibleMetrics()
    }

    /// Removes a metric from the grid, returning it to the extra-metrics pool.
    func hideMetric(_ metric: MetricID) {
        visibleMetrics.removeAll { $0 == metric }
        persistVisibleMetrics()
    }
    
    /// Load current status from the shared metrics file.
    func loadStatus() {
        currentMetrics = MetricsReader.readLatestMetrics()
        
        // Determine connection status based on whether we have recent data
        if let metrics = currentMetrics, metrics.error == nil {
            isConnected = true
            
            // Format last update time
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: metrics.timestamp) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateStyle = .short
                displayFormatter.timeStyle = .short
                lastUpdateTime = displayFormatter.string(from: date)
            }
        } else {
            isConnected = false
            lastUpdateTime = nil
        }
    }
    
    /// Runs the fetcher, reloads metrics, and tells WidgetKit to refresh.
    /// This is the single action triggered by the refresh button and after login.
    func refresh() {
        guard !isRefreshing else { return }

        // If the Python venv hasn't been set up yet (first launch), defer the fetch
        // until ensureEnvironmentSetup() completes — it will call refresh() again.
        if !FileManager.default.fileExists(atPath: venvPythonPath) {
            ensureEnvironmentSetup()
            return
        }

        isRefreshing = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: resolvedPythonPath)
        task.arguments = [fetcherScriptPath]
        task.environment = ProcessInfo.processInfo.environment
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.loadStatus()
                    WidgetCenter.shared.reloadTimelines(ofKind: "BodilyWidget")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isRefreshing = false
                    }
                }
            } catch {
                print("[AppViewModel] Failed to run fetcher: \(error)")
                DispatchQueue.main.async {
                    self.isRefreshing = false
                }
            }
        }
    }
    
    /// Opens the fetcher log file in Console.app or the default text editor.
    func openLog() {
        let url = URL(fileURLWithPath: logPath)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Account Info

    /// Runs the account-info script to refresh profile and device data using saved
    /// tokens. Called when the Account view opens — self-heals accounts that were
    /// set up before profile data was saved (display name falling back to email).
    func refreshAccountInfo() {
        guard hasExistingAuth, !isRefreshingAccountInfo else { return }
        isRefreshingAccountInfo = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: resolvedPythonPath)
        task.arguments = [accountInfoScriptPath]

        let stdoutPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = Pipe()

        // Full parent environment so Python and its dependencies resolve correctly
        task.environment = ProcessInfo.processInfo.environment

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                guard let outputString = String(data: outputData, encoding: .utf8),
                      let firstLine = outputString.components(separatedBy: "\n").first,
                      let responseData = firstLine.data(using: .utf8),
                      let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      response["status"] as? String == "success" else {
                    print("[AppViewModel] Account info refresh failed or returned no data")
                    DispatchQueue.main.async { self.isRefreshingAccountInfo = false }
                    return
                }

                DispatchQueue.main.async {
                    // Update and persist each field, keeping existing values as fallback
                    let displayName = response["display_name"] as? String ?? ""
                    let fullName = response["full_name"] as? String ?? ""
                    let profileImageURL = response["profile_image_url"] as? String ?? ""
                    let deviceName = response["device_name"] as? String ?? ""

                    if !displayName.isEmpty {
                        self.accountDisplayName = displayName
                        UserDefaults.standard.set(displayName, forKey: self.savedDisplayNameKey)
                    }
                    if !fullName.isEmpty {
                        self.accountFullName = fullName
                        UserDefaults.standard.set(fullName, forKey: self.savedFullNameKey)
                    }
                    if !profileImageURL.isEmpty {
                        self.accountProfileImageURL = profileImageURL
                        UserDefaults.standard.set(profileImageURL, forKey: self.savedProfileImageURLKey)
                    }
                    if !deviceName.isEmpty {
                        self.accountDeviceName = deviceName
                        UserDefaults.standard.set(deviceName, forKey: self.savedDeviceNameKey)
                    }
                    self.isRefreshingAccountInfo = false
                }
            } catch {
                print("[AppViewModel] Failed to run account-info script: \(error)")
                DispatchQueue.main.async { self.isRefreshingAccountInfo = false }
            }
        }
    }

    /// Checks whether the launchd fetcher agent is currently loaded.
    /// Runs `launchctl list` and looks for the agent's label in the output.
    func checkFetcherStatus() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["list"]

        let stdoutPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = Pipe()

        DispatchQueue.global(qos: .utility).async {
            do {
                try task.run()
                task.waitUntilExit()
                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let isRunning = output.contains(self.fetcherAgentLabel)
                DispatchQueue.main.async {
                    self.fetcherRunning = isRunning
                }
            } catch {
                print("[AppViewModel] Failed to check fetcher status: \(error)")
            }
        }
    }

    /// Reveals the ~/.garminconnect config directory in Finder for troubleshooting.
    func revealConfigDirectory() {
        NSWorkspace.shared.open(URL(fileURLWithPath: configDirectoryPath))
    }

    // MARK: - Keychain Credential Storage

    /// Service name used to identify Bodily entries in the macOS Keychain.
    private let keychainService = "com.bodily.garmin"

    /// Saves the Garmin Connect password to the macOS Keychain.
    /// Deletes any existing entry for the same email first to avoid duplicates.
    private func savePasswordToKeychain(_ password: String, forEmail email: String) {
        deletePasswordFromKeychain(forEmail: email)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: email,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[AppViewModel] Keychain save failed: \(status)")
        }
    }

    /// Loads the Garmin Connect password from the macOS Keychain for a given email.
    /// Returns nil if no matching entry exists or retrieval fails.
    private func loadPasswordFromKeychain(forEmail email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Deletes the Garmin Connect password from the macOS Keychain for a given email.
    /// Safe to call even if no entry exists (SecItemDelete is a no-op in that case).
    private func deletePasswordFromKeychain(forEmail email: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: email,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Sparkle Updates

    /// Enables Sparkle update checks after the user has logged in.
    /// Called once on first successful login — subsequent launches will have
    /// the feed URL already set in UserDefaults from the prior session.
    private func enableSparkleUpdates() {
        let feedURL = "https://raw.githubusercontent.com/terrancehah/Bodily/main/appcast.xml"
        UserDefaults.standard.set(feedURL, forKey: "SUFeedURL")
        // Trigger an initial check in the background — silent, no dialog on success
        SUUpdater.shared()?.checkForUpdatesInBackground()
    }

    // MARK: - Environment Setup

    /// Ensures the Python venv with garminconnect exists and the launchd agent is
    /// installed. Called before every fetch — fast-paths when already set up.
    /// On first launch, this creates the venv, pip-installs the dependency, and
    /// writes the launchd plist so the fetcher runs every 15 minutes in the background.
    func ensureEnvironmentSetup() {
        // Fast path: venv already exists
        if FileManager.default.fileExists(atPath: venvPythonPath) {
            return
        }

        guard let systemPython = discoverSystemPython() else {
            print("[AppViewModel] No Python 3 found on system — cannot set up environment")
            return
        }

        isSettingUpEnvironment = true

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default

            // Create app support directory if needed
            try? fm.createDirectory(atPath: self.appSupportDirectory,
                                    withIntermediateDirectories: true)

            // Create venv
            let venvTask = Process()
            venvTask.executableURL = URL(fileURLWithPath: systemPython)
            venvTask.arguments = ["-m", "venv", "\(self.appSupportDirectory)/venv"]
            venvTask.environment = ProcessInfo.processInfo.environment
            do {
                try venvTask.run()
                venvTask.waitUntilExit()
                print("[AppViewModel] venv created at \(self.appSupportDirectory)/venv")
            } catch {
                print("[AppViewModel] Failed to create venv: \(error)")
                DispatchQueue.main.async { self.isSettingUpEnvironment = false }
                return
            }

            // Pip install garminconnect into the venv
            let pipTask = Process()
            pipTask.executableURL = URL(fileURLWithPath: self.venvPythonPath)
            pipTask.arguments = ["-m", "pip", "install", "--quiet", "garminconnect"]
            pipTask.environment = ProcessInfo.processInfo.environment
            do {
                try pipTask.run()
                pipTask.waitUntilExit()
                print("[AppViewModel] garminconnect installed into venv")
            } catch {
                print("[AppViewModel] Failed to pip install garminconnect: \(error)")
                DispatchQueue.main.async { self.isSettingUpEnvironment = false }
                return
            }

            // Install the launchd agent
            self.installLaunchAgent()

            DispatchQueue.main.async {
                self.isSettingUpEnvironment = false
                self.checkFetcherStatus()
                // Now that the venv is ready, run the deferred fetch
                self.refresh()
            }
        }
    }

    /// Writes and loads the launchd plist that runs the fetcher every 15 minutes.
    /// Uses the venv Python and the bundled fetcher script so paths survive app updates.
    private func installLaunchAgent() {
        let plistDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        try? FileManager.default.createDirectory(at: plistDir,
                                                  withIntermediateDirectories: true)
        let plistPath = plistDir.appendingPathComponent("\(fetcherAgentLabel).plist").path

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(fetcherAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(venvPythonPath)</string>
                <string>\(fetcherScriptPath)</string>
            </array>
            <key>StartInterval</key>
            <integer>900</integer>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>/tmp/bodily-fetcher.stdout.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/bodily-fetcher.stderr.log</string>
            <!-- Restart immediately if the fetcher exits with an error (API change, network failure, etc.) -->
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
        </dict>
        </plist>
        """

        do {
            try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
            print("[AppViewModel] launchd plist written to \(plistPath)")
        } catch {
            print("[AppViewModel] Failed to write launchd plist: \(error)")
            return
        }

        // Load the agent
        let loadTask = Process()
        loadTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        loadTask.arguments = ["load", plistPath]
        do {
            try loadTask.run()
            loadTask.waitUntilExit()
            print("[AppViewModel] launchd agent loaded")
        } catch {
            print("[AppViewModel] Failed to load launchd agent: \(error)")
        }
    }
    
    // MARK: - Login
    
    /// Loads saved login credentials and account info.
    /// Email comes from UserDefaults; password is retrieved from the macOS Keychain.
    func loadSavedEmail() {
        savedEmail = UserDefaults.standard.string(forKey: savedEmailKey) ?? ""
        // Load password from Keychain using the saved email as the account identifier
        if !savedEmail.isEmpty {
            savedPassword = loadPasswordFromKeychain(forEmail: savedEmail) ?? ""
        }
        accountDisplayName = UserDefaults.standard.string(forKey: savedDisplayNameKey) ?? ""
        accountFullName = UserDefaults.standard.string(forKey: savedFullNameKey) ?? ""
        accountEmail = UserDefaults.standard.string(forKey: savedAccountEmailKey) ?? ""
        accountProfileImageURL = UserDefaults.standard.string(forKey: savedProfileImageURLKey) ?? ""
        accountDeviceName = UserDefaults.standard.string(forKey: savedDeviceNameKey) ?? ""
    }
    
    /// Checks whether a config.json already exists in ~/.garminconnect/,
    /// indicating a prior successful login. Also loads account info from
    /// config.json if UserDefaults don't have it (e.g., login happened
    /// before the account info feature was added).
    func checkExistingAuth() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let configPath = "\(home)/.garminconnect/config.json"
        hasExistingAuth = FileManager.default.fileExists(atPath: configPath)
        
        // If account info isn't in UserDefaults yet, try loading from config.json
        if hasExistingAuth && accountDisplayName.isEmpty {
            if let data = FileManager.default.contents(atPath: configPath),
               let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                accountEmail = config["email"] as? String ?? ""
                // Prefer the stored display name; only fall back to email when truly absent
                let configDisplayName = config["display_name"] as? String ?? ""
                accountDisplayName = configDisplayName.isEmpty ? accountEmail : configDisplayName
                accountFullName = config["full_name"] as? String ?? ""
                accountProfileImageURL = config["profile_image_url"] as? String ?? ""
                accountDeviceName = config["device_name"] as? String ?? ""
                // Persist to UserDefaults so future loads are faster
                UserDefaults.standard.set(accountDisplayName, forKey: savedDisplayNameKey)
                UserDefaults.standard.set(accountFullName, forKey: savedFullNameKey)
                UserDefaults.standard.set(accountEmail, forKey: savedAccountEmailKey)
                UserDefaults.standard.set(accountProfileImageURL, forKey: savedProfileImageURLKey)
                UserDefaults.standard.set(accountDeviceName, forKey: savedDeviceNameKey)
            }
        }
    }
    
    /// Attempts to log in to Garmin Connect by running the Python login script.
    /// Phase 1: sends credentials JSON via stdin, reads one JSON status line from stdout.
    /// If MFA is required, sets loginState to .mfaRequired and keeps the process alive
    /// so that submitMfaCode() can send the code and read the final response.
    func login(email: String, password: String, mfaCode: String?, rememberMe: Bool) {
        loginState = .authenticating
        loginRememberMe = rememberMe
        loginEmail = email
        loginPassword = password
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: resolvedPythonPath)
        task.arguments = [loginScriptPath]
        
        // Pipe stdin (for credentials + MFA code), stdout (for status), stderr (for debugging)
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        
        // Use the full parent process environment so Python and its
        // dependencies (curl_cffi, shared libraries, etc.) can find
        // everything they need (e.g. /opt/homebrew/bin on Apple Silicon).
        task.environment = ProcessInfo.processInfo.environment
        
        // Store process and pipe handles for potential MFA phase 2
        loginProcess = task
        loginStdin = stdinPipe.fileHandleForWriting
        loginStdout = stdoutPipe.fileHandleForReading
        loginStderr = stderrPipe.fileHandleForReading
        
        // Build the credentials JSON payload for stdin (phase 1)
        let credentials: [String: Any] = [
            "email": email,
            "password": password,
        ]
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                
                // Write credentials JSON + newline to the script's stdin.
                // The newline is required so Python's readline() can complete.
                // Do NOT close stdin — the script may wait for MFA code input next.
                let jsonData = try JSONSerialization.data(withJSONObject: credentials)
                self.loginStdin?.write(jsonData)
                self.loginStdin?.write(Data([0x0A])) // 0x0A = newline
                
                // Read one JSON line from stdout (the script flushes after each status)
                let outputString = self.readLineFromStdout()
                
                if outputString.isEmpty {
                    // stdout was empty — script likely crashed before producing output.
                    // Wait for exit and read stderr for the actual error message.
                    self.loginProcess?.waitUntilExit()
                    let stderrString = self.readAllStderr()
                    self.handleLoginResponse(outputString, email: email, password: password, rememberMe: rememberMe, stderr: stderrString)
                } else {
                    // Check if the response is an error — if so, also capture stderr
                    // for additional debugging context. For success/mfa_required,
                    // we don't wait (the process may still be alive for MFA).
                    let isErrorResponse = outputString.contains("\"status\":\"error\"") || outputString.contains("\"status\": \"error\"")
                    var stderrString = ""
                    if isErrorResponse {
                        self.loginProcess?.waitUntilExit()
                        stderrString = self.readAllStderr()
                    }
                    self.handleLoginResponse(outputString, email: email, password: password, rememberMe: rememberMe, stderr: stderrString)
                }
            } catch {
                let stderrString = self.readAllStderr()
                DispatchQueue.main.async {
                    var errorDetail = "Failed to run login: \(error.localizedDescription)"
                    if !stderrString.isEmpty {
                        errorDetail += "\nStderr: \(stderrString)"
                    }
                    self.loginState = .error(errorDetail)
                }
            }
        }
    }
    
    /// Phase 2: Submits the MFA code to the still-running login process.
    /// Writes {"mfa_code": "..."} to stdin and reads the final JSON status from stdout.
    func submitMfaCode(_ code: String) {
        loginState = .authenticating
        
        let mfaPayload: [String: Any] = ["mfa_code": code]
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Write MFA code JSON + newline to stdin (the script's callback is waiting for this)
            if let data = try? JSONSerialization.data(withJSONObject: mfaPayload) {
                self.loginStdin?.write(data)
                self.loginStdin?.write(Data([0x0A])) // 0x0A = newline
            }
            
            // Read the final JSON status line from stdout
            let outputString = self.readLineFromStdout()
            
            // Wait for the process to exit and read any stderr
            self.loginProcess?.waitUntilExit()
            let stderrString = self.readAllStderr()
            
            // Parse the final response
            self.handleLoginResponse(outputString, email: self.loginEmail, password: self.loginPassword, rememberMe: self.loginRememberMe, stderr: stderrString)
            
            // Clean up process references
            self.cleanupLoginProcess()
        }
    }
    
    /// Reads a single line (JSON status) from the login process stdout.
    /// Blocks until a newline is available or the pipe is closed.
    /// Only returns content up to the first newline (exclusive), so any
    /// extra data in the pipe doesn't break JSON parsing.
    private func readLineFromStdout() -> String {
        guard let stdout = loginStdout else { return "" }
        var buffer = Data()
        while true {
            let chunk = stdout.availableData
            if chunk.isEmpty {
                // Pipe closed — return whatever we have
                break
            }
            buffer.append(chunk)
            // Check if we have a complete line (newline-delimited JSON)
            if buffer.contains(0x0A) { // 0x0A = newline
                break
            }
        }
        // Only return up to the first newline (exclusive) to ensure
        // JSON parsing gets exactly one JSON object, not extra data.
        if let newlineIndex = buffer.firstIndex(of: 0x0A) {
            return String(data: buffer[buffer.startIndex..<newlineIndex], encoding: .utf8) ?? ""
        }
        return String(data: buffer, encoding: .utf8) ?? ""
    }
    
    /// Reads all available stderr data from the login process (for debugging).
    private func readAllStderr() -> String {
        guard let stderr = loginStderr else { return "" }
        let data = stderr.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    /// Parses a JSON status response from the login script and updates loginState.
    private func handleLoginResponse(_ outputString: String, email: String, password: String, rememberMe: Bool, stderr: String = "") {
        if let responseData = outputString.data(using: .utf8),
           let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            let status = response["status"] as? String ?? "error"
            let message = response["message"] as? String ?? "Unknown error"
            
            DispatchQueue.main.async {
                switch status {
                case "success":
                    // Persist or clear login credentials based on "Remember login" toggle.
                    // Email is stored in UserDefaults; password is stored in the macOS Keychain.
                    if rememberMe && !email.isEmpty {
                        UserDefaults.standard.set(email, forKey: self.savedEmailKey)
                        self.savePasswordToKeychain(password, forEmail: email)
                    } else if !email.isEmpty {
                        UserDefaults.standard.removeObject(forKey: self.savedEmailKey)
                        self.deletePasswordFromKeychain(forEmail: email)
                    }
                    // Save account info from login response
                    let displayName = response["display_name"] as? String ?? email
                    let fullName = response["full_name"] as? String ?? ""
                    let acctEmail = response["email"] as? String ?? email
                    let profileImageURL = response["profile_image_url"] as? String ?? ""
                    let deviceName = response["device_name"] as? String ?? ""
                    self.accountDisplayName = displayName
                    self.accountFullName = fullName
                    self.accountEmail = acctEmail
                    self.accountProfileImageURL = profileImageURL
                    self.accountDeviceName = deviceName
                    UserDefaults.standard.set(displayName, forKey: self.savedDisplayNameKey)
                    UserDefaults.standard.set(fullName, forKey: self.savedFullNameKey)
                    UserDefaults.standard.set(acctEmail, forKey: self.savedAccountEmailKey)
                    UserDefaults.standard.set(profileImageURL, forKey: self.savedProfileImageURLKey)
                    UserDefaults.standard.set(deviceName, forKey: self.savedDeviceNameKey)
                    self.loginState = .success
                    self.hasExistingAuth = true
                    self.loadStatus()
                    self.cleanupLoginProcess()
                    // Enable Sparkle update checks now that the user is set up
                    self.enableSparkleUpdates()
                    // Fetch metrics now that login is complete
                    self.refresh()
                case "mfa_required":
                    // Keep the process alive — submitMfaCode() will send the code
                    self.loginState = .mfaRequired
                default:
                    // Include stderr if available for additional debugging context
                    var fullMessage = message
                    if !stderr.isEmpty {
                        fullMessage += "\n\nStderr:\n\(stderr)"
                    }
                    self.loginState = .error(fullMessage)
                    self.cleanupLoginProcess()
                }
            }
        } else {
            // JSON parsing failed — include raw stdout and stderr for debugging.
            // If stderr wasn't provided, try to read it from the process.
            var stderrDetail = stderr
            if stderrDetail.isEmpty {
                // Wait briefly for the process to exit so stderr is available
                self.loginProcess?.waitUntilExit()
                stderrDetail = self.readAllStderr()
            }
            DispatchQueue.main.async {
                var errorDetail = "Unexpected response from login script."
                if !outputString.isEmpty {
                    errorDetail += "\nStdout: \(outputString)"
                }
                if !stderrDetail.isEmpty {
                    errorDetail += "\nStderr: \(stderrDetail)"
                }
                self.loginState = .error(errorDetail)
                self.cleanupLoginProcess()
            }
        }
    }
    
    /// Cleans up the login process and pipe handles after completion or cancellation.
    private func cleanupLoginProcess() {
        try? loginStdin?.close()
        try? loginStdout?.close()
        try? loginStderr?.close()
        loginProcess = nil
        loginStdin = nil
        loginStdout = nil
        loginStderr = nil
    }
    
    /// Resets the login state back to idle (used when dismissing the login sheet).
    func resetLoginState() {
        // Terminate any running login process (e.g., user cancelled during MFA)
        if let process = loginProcess, process.isRunning {
            process.terminate()
        }
        cleanupLoginProcess()
        loginState = .idle
    }
    
    /// Logs out: deletes config, tokens, and cached credentials.
    /// Resets all auth state so the user must log in again.
    func logout() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Delete config and tokens from ~/.garminconnect/
        let tokenStorePath = "\(home)/.garminconnect"
        try? FileManager.default.removeItem(atPath: "\(tokenStorePath)/config.json")
        try? FileManager.default.removeItem(atPath: "\(tokenStorePath)/garmin_tokens.json")
        // Clear cached credentials and account info.
        // Password is removed from Keychain; email and profile info from UserDefaults.
        UserDefaults.standard.removeObject(forKey: savedEmailKey)
        if !savedEmail.isEmpty {
            deletePasswordFromKeychain(forEmail: savedEmail)
        }
        UserDefaults.standard.removeObject(forKey: savedDisplayNameKey)
        UserDefaults.standard.removeObject(forKey: savedFullNameKey)
        UserDefaults.standard.removeObject(forKey: savedAccountEmailKey)
        UserDefaults.standard.removeObject(forKey: savedProfileImageURLKey)
        UserDefaults.standard.removeObject(forKey: savedDeviceNameKey)
        // Reset state
        savedEmail = ""
        savedPassword = ""
        accountDisplayName = ""
        accountFullName = ""
        accountEmail = ""
        accountProfileImageURL = ""
        accountDeviceName = ""
        hasExistingAuth = false
        isConnected = false
        currentMetrics = nil
        lastUpdateTime = nil
        loginState = .idle
        // Refresh widget to show no data
        WidgetCenter.shared.reloadTimelines(ofKind: "BodilyWidget")
    }
}
