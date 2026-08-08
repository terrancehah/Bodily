import Foundation
import Combine
import SwiftUI
import WidgetKit

/// Tracks the current state of the Garmin Connect login flow.
enum LoginState: Equatable {
    case idle
    case authenticating
    case mfaRequired
    case success
    case error(String)
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
    /// Whether the launchd fetcher agent (com.garminwidget.fetcher) is currently loaded
    @Published var fetcherRunning: Bool = false
    /// True while the account-info script is refreshing profile data in the background
    @Published var isRefreshingAccountInfo: Bool = false
    /// Ordered list of metrics shown in the main grid — user-customizable via the drawer
    @Published var visibleMetrics: [MetricID] = MetricID.defaultVisible

    /// UserDefaults keys for persisting saved login credentials and account info
    private let savedEmailKey = "bodily.savedEmail"
    private let savedPasswordKey = "bodily.savedPassword"
    private let savedDisplayNameKey = "bodily.savedDisplayName"
    private let savedFullNameKey = "bodily.savedFullName"
    private let savedAccountEmailKey = "bodily.savedAccountEmail"
    private let savedProfileImageURLKey = "bodily.savedProfileImageURL"
    private let savedDeviceNameKey = "bodily.savedDeviceName"

    /// launchd label of the background fetcher agent (must match the installed plist)
    private let fetcherAgentLabel = "com.garminwidget.fetcher"

    /// UserDefaults key for the customized metric grid (ordered raw value array)
    private let visibleMetricsKey = "bodily.visibleMetrics"

    /// Grid capacity — matches the medium widget's 6-tile layout so app and widget mirror each other
    static let maxVisibleMetrics = 6

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
    
    /// Path to the Python fetcher script
    private let fetcherScriptPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Developer/Xcode/UntitledProjects/GarminWidget/fetcher/garmin_fetcher.py"
    }()
    
    /// Path to the venv Python executable
    private let pythonPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Developer/Xcode/UntitledProjects/GarminWidget/.venv/bin/python3"
    }()
    
    /// Path to the fetcher log file
    private let logPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Group Containers/group.com.bodily.shared/fetcher.log"
    }()
    
    /// Path to the non-interactive login script (reads credentials from stdin)
    private let loginScriptPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Developer/Xcode/UntitledProjects/GarminWidget/fetcher/login.py"
    }()

    /// Path to the account info script (refreshes profile + device data via saved tokens)
    private let accountInfoScriptPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Developer/Xcode/UntitledProjects/GarminWidget/fetcher/account-info.py"
    }()

    /// Path to the token store / config directory (~/.garminconnect)
    private let configDirectoryPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.garminconnect"
    }()
    
    init() {
        loadSavedEmail()
        checkExistingAuth()
        loadVisibleMetrics()
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
    /// This is the single action triggered by the refresh button.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonPath)
        task.arguments = [fetcherScriptPath]
        
        // Use the full parent process environment so Python and its
        // dependencies (curl_cffi, shared libraries, etc.) can find
        // everything they need (e.g. /opt/homebrew/bin on Apple Silicon).
        task.environment = ProcessInfo.processInfo.environment
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
                
                // Reload status and widget on the main thread
                DispatchQueue.main.async {
                    self.loadStatus()
                    WidgetCenter.shared.reloadTimelines(ofKind: "BodilyWidget")
                    
                    // Stop animation after a short delay
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
        task.executableURL = URL(fileURLWithPath: pythonPath)
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
    
    // MARK: - Login
    
    /// Loads saved login credentials and account info from UserDefaults.
    func loadSavedEmail() {
        savedEmail = UserDefaults.standard.string(forKey: savedEmailKey) ?? ""
        savedPassword = UserDefaults.standard.string(forKey: savedPasswordKey) ?? ""
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
        task.executableURL = URL(fileURLWithPath: pythonPath)
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
                    // Persist or clear login credentials based on "Remember login" toggle
                    if rememberMe && !email.isEmpty {
                        UserDefaults.standard.set(email, forKey: self.savedEmailKey)
                        UserDefaults.standard.set(password, forKey: self.savedPasswordKey)
                    } else if !email.isEmpty {
                        UserDefaults.standard.removeObject(forKey: self.savedEmailKey)
                        UserDefaults.standard.removeObject(forKey: self.savedPasswordKey)
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
        // Clear cached credentials and account info from UserDefaults
        UserDefaults.standard.removeObject(forKey: savedEmailKey)
        UserDefaults.standard.removeObject(forKey: savedPasswordKey)
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
