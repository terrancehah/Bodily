import SwiftUI

/// Login interface for connecting to Garmin Connect.
/// Provides email/password fields with show/hide toggle, remember-email, and MFA support.
/// Communicates with the Python login script via AppViewModel.
struct LoginView: View {
    @ObservedObject var viewModel: AppViewModel
    
    /// Dismiss action for the sheet — called when user cancels or completes login.
    var onDismiss: () -> Void
    
    // Form state
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var mfaCode: String = ""
    @State private var showPassword: Bool = false
    @State private var rememberMe: Bool = true
    
    // Focus state for the email field — allows auto-focus on appear
    @FocusState private var focusedField: LoginField?
    
    enum LoginField: Hashable {
        case email
        case password
        case mfaCode
    }
    
    // True when the login process is running and all inputs should be locked
    private var isInputDisabled: Bool {
        viewModel.loginState == .authenticating || viewModel.loginState == .success
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title — tracked wordmark style ties into the instrument aesthetic
            Text("CONNECT TO GARMIN")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(1.2)
            
            // Email field
            VStack(alignment: .leading, spacing: 4) {
                Text("Email")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BodilyPalette.secondaryText)
                TextField("", text: $email, prompt: Text("Email").foregroundColor(.secondary.opacity(0.6)))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .email)
                    .disabled(isInputDisabled)
            }
            
            // Password field with show/hide toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("Password")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(BodilyPalette.secondaryText)
                HStack {
                    if showPassword {
                        // Plain text field when password is visible
                        TextField("", text: $password, prompt: Text("Password").foregroundColor(.secondary.opacity(0.6)))
                            .textFieldStyle(.roundedBorder)
                            .disableAutocorrection(true)
                            .focused($focusedField, equals: .password)
                            .disabled(isInputDisabled)
                    } else {
                        // Masked field when password is hidden
                        SecureField("", text: $password, prompt: Text("Password").foregroundColor(.secondary.opacity(0.6)))
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .password)
                            .disabled(isInputDisabled)
                    }
                    // Show/hide password toggle button
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isInputDisabled)
                    .help(showPassword ? "Hide password" : "Show password")
                }
            }
            
            // Remember login toggle — persists email and password via UserDefaults
            Toggle("Remember login", isOn: $rememberMe)
                .font(.system(size: 11))
                .controlSize(.small)
                .disabled(isInputDisabled)
            
            // MFA code field — shown only when Garmin requires MFA verification
            if viewModel.loginState == .mfaRequired {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MFA Code")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BodilyPalette.secondaryText)
                    TextField("", text: $mfaCode, prompt: Text("6-digit code").foregroundColor(.secondary.opacity(0.6)))
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .mfaCode)
                        .disabled(viewModel.loginState == .authenticating)
                }
            }
            
            // Status indicators
            if viewModel.loginState == .authenticating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Authenticating...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            
            if case .error(let message) = viewModel.loginState {
                VStack(alignment: .leading, spacing: 6) {
                    Text(message)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    // Copy button — copies the full error text to clipboard
                    Button("Copy error log") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 10))
                }
            }
            
            if viewModel.loginState == .success {
                Text("Successfully connected!")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
            
            // Action buttons
            HStack {
                Spacer()
                
                // Cancel button — stays enabled to allow cancellation during auth
                Button("Cancel") {
                    viewModel.resetLoginState()
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.loginState == .success)
                
                // Primary action changes based on login state
                if viewModel.loginState == .mfaRequired {
                    // Verify MFA button — submits the MFA code to the running process
                    Button("Verify") {
                        viewModel.submitMfaCode(mfaCode)
                    }
                    .buttonStyle(VoltButtonStyle())
                    .disabled(mfaCode.isEmpty || viewModel.loginState == .authenticating)
                } else if viewModel.loginState != .success {
                    // Login button — initial attempt with email + password
                    // Hidden after success (sheet auto-dismisses)
                    Button("Login") {
                        viewModel.login(
                            email: email,
                            password: password,
                            mfaCode: nil,
                            rememberMe: rememberMe
                        )
                    }
                    .buttonStyle(VoltButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || viewModel.loginState == .authenticating)
                }
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            // Pre-fill credentials if previously saved with "Remember login"
            email = viewModel.savedEmail
            password = viewModel.savedPassword
            rememberMe = !viewModel.savedEmail.isEmpty
            // Auto-focus email field (or password if email is pre-filled)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = email.isEmpty ? .email : .password
            }
        }
        .onChange(of: viewModel.loginState) { newState in
            // Auto-dismiss the sheet shortly after success is shown
            if newState == .success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    viewModel.resetLoginState()
                    onDismiss()
                }
            }
        }
    }
}
