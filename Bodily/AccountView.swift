import SwiftUI

/// Account view shown when the user is connected to Garmin.
/// Profile header with avatar, device info, and sync-health instrumentation,
/// following the same sports-instrument aesthetic as the main window.
struct AccountView: View {
    @ObservedObject var viewModel: AppViewModel
    let onDismiss: () -> Void

    /// Initials for the avatar fallback — derived from the full name when present,
    /// otherwise the first two letters of the display name.
    private var monogram: String {
        let source = viewModel.accountFullName.isEmpty
            ? viewModel.accountDisplayName
            : viewModel.accountFullName
        let parts = source.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let last = parts.last?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                Text("ACCOUNT")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(1.2)
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.bottom, 16)

            // Profile header: avatar + identity lines
            profileHeader
                .padding(.bottom, 16)

            // Instrument rows: device + sync health
            VStack(alignment: .leading, spacing: 10) {
                if !viewModel.accountDeviceName.isEmpty {
                    infoRow(icon: "applewatch", label: "DEVICE", value: viewModel.accountDeviceName)
                }

                infoRow(
                    icon: viewModel.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill",
                    iconColor: viewModel.isConnected ? .green : .red,
                    label: "GARMIN",
                    value: viewModel.isConnected ? "Connected" : "Not connected"
                )

                if let lastUpdate = viewModel.lastUpdateTime {
                    infoRow(icon: "arrow.triangle.2.circlepath", label: "LAST SYNC", value: lastUpdate)
                }
            }
            .padding(.bottom, 16)

            // Hint shown while profile data refreshes in the background
            if viewModel.isRefreshingAccountInfo {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing profile...")
                        .font(.system(size: 10))
                        .foregroundStyle(BodilyPalette.tertiaryText)
                }
                .padding(.bottom, 8)
            }

            Spacer()

            // Footer: quiet config action on the left, destructive logout on the right
            HStack {
                Button(action: { viewModel.revealConfigDirectory() }) {
                    Label("Reveal Config", systemImage: "folder")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(BodilyPalette.tertiaryText)
                .help("Open ~/.garminconnect in Finder")

                Spacer()

                Button(role: .destructive, action: {
                    viewModel.logout()
                    onDismiss()
                }) {
                    Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 360, height: 330)
        .background(BodilyPalette.surface)
        .onAppear {
            // Refresh live status and self-heal missing profile data
            viewModel.loadStatus()
            viewModel.refreshAccountInfo()
        }
    }

    // MARK: - Profile Header

    /// Avatar with identity lines: full name prominent, display name and email secondary.
    /// Keeping the three fields visually distinct avoids the old "same row repeated" look.
    private var profileHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                // Full name leads when available; display name otherwise
                Text(viewModel.accountFullName.isEmpty
                     ? viewModel.accountDisplayName
                     : viewModel.accountFullName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                // Show display name as a handle only when it differs from the email
                if !viewModel.accountFullName.isEmpty
                    && !viewModel.accountDisplayName.isEmpty
                    && viewModel.accountDisplayName != viewModel.accountEmail {
                    Text("@\(viewModel.accountDisplayName)")
                        .font(.system(size: 11))
                        .foregroundStyle(BodilyPalette.secondaryText)
                }

                Text(viewModel.accountEmail)
                    .font(.system(size: 11))
                    .foregroundStyle(BodilyPalette.tertiaryText)
                    .textSelection(.enabled)
            }

            Spacer()
        }
    }

    /// Profile image from Garmin, falling back to a volt monogram circle while
    /// loading or when the account has no avatar set.
    private var avatarView: some View {
        AsyncImage(url: URL(string: viewModel.accountProfileImageURL)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                // Volt monogram — also used for loading and failure states
                ZStack {
                    Circle()
                        .fill(BodilyPalette.volt)
                    Text(monogram)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(BodilyPalette.ink)
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(BodilyPalette.hairline, lineWidth: 1))
    }

    // MARK: - Info Row

    /// A single instrument row: icon, tracked small-caps label, and value.
    private func infoRow(icon: String, iconColor: Color = BodilyPalette.secondaryText,
                         label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.7)
                .foregroundStyle(BodilyPalette.tertiaryText)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    AccountView(viewModel: AppViewModel(), onDismiss: {})
}
