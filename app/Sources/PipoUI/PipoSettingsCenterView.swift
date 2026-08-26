import AppKit
import PipoAppCore
import SwiftUI

@MainActor
struct PipoSettingsCenterView: View {
    private struct LegalDocument: Identifiable {
        let id: String
        let title: String
        let text: String
    }
    private enum Page: String, CaseIterable, Identifiable {
        case general, notifications, courses, updates, advanced, about

        var id: Self { self }
        var title: String {
            switch self {
            case .about: "About Pipo"
            default: rawValue.capitalized
            }
        }
        var icon: String {
            switch self {
            case .general: "gear"
            case .notifications: "bell"
            case .courses: "books.vertical"
            case .updates: "arrow.triangle.2.circlepath"
            case .advanced: "wrench.and.screwdriver"
            case .about: "info.circle"
            }
        }
    }

    @Bindable private var model: PipoModel
    private let configuration: PipoUIConfiguration
    private let onSignOut: () -> Void
    @State private var selection: Page? = .general
    @State private var storageMessage: String?
    @State private var isRetryingSecureStorage = false
    @State private var isRefreshing = false
    @State private var syncMessage: String?
    @State private var isRequestingCalendar = false
    @State private var calendarMessage: String?
    @State private var authMethod: PipoAuthMethod = .schoolAccount
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var validationMessage: String?
    @State private var legalDocument: LegalDocument?
    @AppStorage(PipoLegal.acknowledgementKey) private var acceptedLegalVersion = ""
    @AppStorage(PipoLegal.preReleaseAcknowledgementKey) private var acceptedPreReleaseVersion = ""
    @AppStorage("pipo.updates.channel") private var updateChannel = "stable"

    init(model: PipoModel, configuration: PipoUIConfiguration, onSignOut: @escaping () -> Void) {
        self._model = Bindable(model)
        self.configuration = configuration
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $selection) { page in
                Label(page.title, systemImage: page.icon).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            pageView(selection ?? .general)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color(red: 1, green: 82 / 255, blue: 119 / 255))
        .sheet(item: $legalDocument) { document in
            VStack(spacing: 0) {
                HStack {
                    Text(document.title).font(.headline)
                    Spacer()
                    Button("Done") { legalDocument = nil }.keyboardShortcut(.cancelAction)
                }
                .padding()
                Divider()
                ScrollView {
                    Text(document.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .frame(minWidth: 620, idealWidth: 700, minHeight: 440, idealHeight: 520)
        }
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .general: general
        case .notifications: notifications
        case .courses: courses
        case .updates: updates
        case .advanced: advanced
        case .about: about
        }
    }

    private var general: some View {
        settingsForm("General") {
            connectionSection
            Section("Sync") {
                LabeledContent("Last successful sync") {
                    if let date = model.refreshDate { Text(date, style: .relative) } else { Text("Never") }
                }
                HStack {
                    Text("Refresh every \(Int(model.settings.refreshInterval / 60)) minutes")
                    Slider(value: Binding(
                        get: { model.settings.refreshInterval / 60 },
                        set: { model.settings.refreshInterval = $0 * 60 }
                    ), in: 5...60, step: 5)
                }
                Button {
                    refreshNow()
                } label: {
                    if isRefreshing {
                        HStack { ProgressView().controlSize(.small); Text("Refreshing…") }
                    } else {
                        Label("Refresh now", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(!isConnected || isBusy || isRefreshing)
                if let syncMessage { Text(syncMessage).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section("Connection") {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: PipoBrandAssets.hollowLogo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionTitle).font(.headline)
                    Text(connectionDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if isBusy { ProgressView().controlSize(.small).accessibilityLabel(statusDescription) }
                else { Label(statusDescription, systemImage: statusIcon).labelStyle(.iconOnly).foregroundStyle(statusColor) }
            }
            .frame(minHeight: 56)

            if needsCredentials && acceptedPreReleaseVersion != PipoLegal.preReleaseVersion {
                PipoPreReleaseNoticeView()
            } else if needsCredentials {
                Picker("Sign-in method", selection: $authMethod) {
                    ForEach(PipoAuthMethod.allCases) { method in Text(method.title).tag(method) }
                }
                .pickerStyle(.segmented)
                .onChange(of: authMethod) { _, _ in validationMessage = nil }

                if acceptedLegalVersion != PipoLegal.currentVersion {
                    PipoLegalAcknowledgementView(openURL: configuration.openURL)
                }

                if authMethod == .schoolAccount {
                    TextField("LMS username", text: $username).textContentType(.username)
                    SecureField("LMS password", text: $password).textContentType(.password)
                    Button(isFailed ? "Retry sign in" : "Sign in", systemImage: "arrow.right.circle.fill") {
                        submitPassword()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy || acceptedLegalVersion != PipoLegal.currentVersion)
                } else {
                    SecureField("Paste access token", text: $token)
                    Button("Use token", systemImage: "key.fill") { submitToken() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isBusy || acceptedLegalVersion != PipoLegal.currentVersion)
                }
                if let message = validationMessage ?? model.authenticationError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                LabeledContent("Student", value: model.snapshot?.studentName ?? "LPU Cavite student")
            }
            LabeledContent("LMS", value: PipoFoundation.lmsOrigin.host ?? "lms.lpucavite.edu.ph")
            Button("Open LMS", systemImage: "safari") { configuration.openURL(PipoFoundation.lmsOrigin) }
        }
    }

    private var notifications: some View {
        settingsForm("Notifications") {
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $model.settings.notificationsEnabled)
                Toggle("Assignments", isOn: $model.settings.assignmentNotifications)
                Toggle("Announcements", isOn: $model.settings.announcementNotifications)
                Toggle("Messages", isOn: $model.settings.messageNotifications)
                Toggle("Grade feedback", isOn: $model.settings.gradeNotifications)
            }
            Section("Reminders") {
                Toggle("24 hours before deadline", isOn: $model.settings.reminderDayBefore)
                Toggle("1 hour before deadline", isOn: $model.settings.reminderHourBefore)
                Picker("Quiet hours start", selection: $model.settings.quietHoursStart) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Picker("Quiet hours end", selection: $model.settings.quietHoursEnd) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
            }
            Section("Calendar") {
                LabeledContent("Authorization", value: model.calendarAuthorizationDescription)
                Button {
                    requestCalendarAccess()
                } label: {
                    if isRequestingCalendar {
                        HStack { ProgressView().controlSize(.small); Text("Requesting access…") }
                    } else {
                        Label("Allow Calendar access", systemImage: "calendar.badge.plus")
                    }
                }
                .disabled(isRequestingCalendar)
                if let calendarMessage { Text(calendarMessage).foregroundStyle(.secondary) }
            }
        }
    }

    private var courses: some View {
        settingsForm("Courses") {
            Section("Pinned") {
                courseRows(ids: model.localState.pinnedCourseIDs, actionTitle: "Unpin", icon: "pin.slash") { id in
                    Task { await model.setPinnedCourse(id, pinned: false) }
                }
            }
            Section("Hidden") {
                courseRows(ids: model.localState.hiddenCourseIDs, actionTitle: "Show", icon: "eye") { id in
                    Task { await model.setHiddenCourse(id, hidden: false) }
                }
            }
        }
    }

    private var updates: some View {
        settingsForm("Updates") {
            Section("Update preferences") {
                Picker("Channel", selection: $updateChannel) {
                    Text("Stable").tag("stable")
                    Text("Beta").tag("beta")
                }
                .onChange(of: updateChannel) { _, _ in
                    NotificationCenter.default.post(name: Notification.Name("com.jazztinn.pipo.update-channel-changed"), object: nil)
                }
                if let installUpdate = configuration.installUpdate {
                    Button("Check for updates", systemImage: "arrow.down.circle", action: installUpdate)
                }
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
            }
        }
    }

    private var advanced: some View {
        settingsForm("Advanced") {
            Section("Storage") {
                if configuration.secureStorageStatus() != .available {
                    Text("Pipo cannot access secure storage right now.").foregroundStyle(.secondary)
                    Button(isRetryingSecureStorage ? "Retrying…" : "Retry secure storage", systemImage: "key") {
                        retrySecureStorage()
                    }.disabled(isRetryingSecureStorage)
                }
                Button("Clear saved dashboard", systemImage: "trash") {
                    Task {
                        do { try await configuration.clearCache(); storageMessage = "Saved dashboard cleared." }
                        catch { storageMessage = "Could not clear saved dashboard." }
                    }
                }
                if let storageMessage { Text(storageMessage).foregroundStyle(.secondary) }
            }
            Section("Diagnostics") {
                if let export = configuration.exportDiagnostics {
                    Button("Export redacted diagnostics", systemImage: "doc.badge.gearshape", action: export)
                }
                Text("Diagnostics exclude tokens, message bodies, grades, excerpts, and student identity.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if isConnected {
                Section("LMS capabilities") {
                    capabilityRow("Schedule", supported: model.snapshot?.supported.schedule ?? false)
                    capabilityRow("Submission status", supported: model.snapshot?.supported.submissionStatus ?? false)
                    capabilityRow("Announcements", supported: model.snapshot?.supported.announcements ?? false)
                    capabilityRow("Resources", supported: model.snapshot?.supported.resources ?? false)
                }
                Section {
                    Button("Sign out", role: .destructive, action: onSignOut)
                }
            }
        }
    }

    private var about: some View {
        settingsForm("About Pipo") {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: PipoBrandAssets.hollowLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pipo").font(.title2.bold())
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")")
                            .foregroundStyle(.secondary)
                        Text("Independent, unofficial LMS utility for LPU Cavite students.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Pre-Release & Permissions") {
                Text("Pipo is pre-release software and is currently unnotarized by Apple. macOS may show security warnings. Features and LMS compatibility may change; verify important information in the official LMS.")
                    .foregroundStyle(.secondary)
                Label("Keychain — required to store the LMS token and cache encryption key securely.", systemImage: "key")
                Label("Notifications — optional; requested after a successful sync when enabled. Declining disables deadline and LMS alerts.", systemImage: "bell")
                Label("Calendar — optional; declining means Add to Calendar is unavailable. Requested only when you use that feature.", systemImage: "calendar")
                Text("Pipo uses network access to connect to the LPU Cavite LMS and, when enabled, check GitHub-hosted update feeds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Manage or revoke Notifications and Calendar access in System Settings > Notifications or Privacy & Security. Keychain items can be removed by signing out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Open Privacy & Security Settings", systemImage: "gear") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Terms of Use", systemImage: "doc.text") { configuration.openURL(PipoLegal.termsURL) }
                Button("Privacy Policy", systemImage: "hand.raised") { configuration.openURL(PipoLegal.privacyURL) }
                LabeledContent("Notice acknowledged", value: PipoLegal.isPreReleaseAcknowledged() ? "Yes" : "No")
                LabeledContent("Legal acknowledged", value: PipoLegal.isAcknowledged() ? "Yes" : "No")
            }
            Section("Licenses") {
                Button("Pipo License", systemImage: "doc.plaintext") {
                    showBundledDocument(name: "LICENSE", extension: "txt", title: "Pipo License")
                }
                Button("Third-Party Notices", systemImage: "doc.text") {
                    showBundledDocument(name: "THIRD_PARTY_NOTICES", extension: "md", title: "Third-Party Notices")
                }
            }
        }
    }

    private func settingsForm<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .formStyle(.grouped)
            .navigationTitle(title)
    }

    @ViewBuilder
    private func courseRows(
        ids: Set<Int>,
        actionTitle: String,
        icon: String,
        action: @escaping (Int) -> Void
    ) -> some View {
        if ids.isEmpty {
            Text("None").foregroundStyle(.secondary)
        } else {
            ForEach(ids.sorted(), id: \.self) { id in
                HStack {
                    Text(courseName(for: id))
                    Spacer()
                    Button(actionTitle, systemImage: icon) { action(id) }
                }
            }
        }
    }

    private func courseName(for id: Int) -> String {
        model.snapshot?.courses.first(where: { $0.id == id })?.name ?? "Course \(id)"
    }

    private func capabilityRow(_ title: String, supported: Bool) -> some View {
        LabeledContent(title) {
            if supported {
                Label("Available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("Unavailable", systemImage: "minus.circle").foregroundStyle(.secondary)
            }
        }
    }

    private var statusDescription: String {
        switch model.phase {
        case .signedOut: "Signed out"
        case .authenticating: "Signing in"
        case .loading: "Syncing"
        case .ready: "Ready"
        case .offline: "Offline"
        case .failed: "Needs attention"
        }
    }

    private var isBusy: Bool {
        switch model.phase {
        case .authenticating, .loading: true
        default: false
        }
    }

    private var isConnected: Bool {
        switch model.phase {
        case .ready, .offline: true
        default: false
        }
    }

    private var isFailed: Bool {
        if case .failed = model.phase { return true }
        return false
    }

    private var needsCredentials: Bool {
        switch model.phase {
        case .signedOut, .failed: true
        default: false
        }
    }

    private var connectionTitle: String {
        switch model.phase {
        case .signedOut: "Connect Pipo"
        case .authenticating: "Signing in"
        case .loading: "Syncing your LMS"
        case .ready: model.snapshot?.studentName ?? "Connected to LPU Cavite LMS"
        case .offline: "Using saved LMS data"
        case .failed: "Connection needs attention"
        }
    }

    private var connectionDetail: String {
        switch model.phase {
        case .signedOut: "Sign in with your school account or an LMS access token."
        case .authenticating: "Checking your credentials securely."
        case .loading: "Loading courses, deadlines, messages, and grades."
        case .ready: "Your LMS data is available and up to date."
        case .offline: "Pipo will reconnect and refresh when the LMS is reachable."
        case .failed: "Review the message below, then retry with your credentials."
        }
    }

    private var statusIcon: String {
        switch model.phase {
        case .ready: "checkmark.circle.fill"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        default: "person.crop.circle.badge.questionmark"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .ready: .green
        case .failed: .orange
        default: .secondary
        }
    }

    private func submitPassword() {
        guard acceptedPreReleaseVersion == PipoLegal.preReleaseVersion else {
            validationMessage = "Continue through the Pre-Release & Permissions notice first."
            return
        }
        guard acceptedLegalVersion == PipoLegal.currentVersion else {
            validationMessage = "Acknowledge the Terms of Use and Privacy Policy to continue."
            return
        }
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty else { validationMessage = "Enter your LMS username."; return }
        guard !password.isEmpty else { validationMessage = "Enter your LMS password."; return }
        validationMessage = nil
        let submittedPassword = password
        password = ""
        Task { await model.signIn(username: cleanUsername, password: submittedPassword) }
    }

    private func submitToken() {
        guard acceptedPreReleaseVersion == PipoLegal.preReleaseVersion else {
            validationMessage = "Continue through the Pre-Release & Permissions notice first."
            return
        }
        guard acceptedLegalVersion == PipoLegal.currentVersion else {
            validationMessage = "Acknowledge the Terms of Use and Privacy Policy to continue."
            return
        }
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { validationMessage = "Paste an access token to continue."; return }
        validationMessage = nil
        token = ""
        Task { await model.signIn(withToken: cleanToken) }
    }

    private func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        syncMessage = nil
        Task {
            do {
                _ = try await configuration.refresh()
                switch model.phase {
                case .ready: syncMessage = "Dashboard refreshed."
                case .offline: syncMessage = "Could not refresh. Showing saved LMS data."
                case .failed(let message): syncMessage = message
                default: syncMessage = nil
                }
            } catch {
                syncMessage = "Pipo could not refresh the LMS. Try again."
            }
            isRefreshing = false
        }
    }

    private func requestCalendarAccess() {
        guard !isRequestingCalendar else { return }
        isRequestingCalendar = true
        calendarMessage = nil
        Task {
            do {
                let granted = try await model.requestCalendarAccess()
                calendarMessage = granted ? "Calendar access granted." : "Calendar access was not granted."
            } catch {
                calendarMessage = "Calendar access could not be updated."
            }
            isRequestingCalendar = false
        }
    }

    private func showBundledDocument(name: String, extension fileExtension: String, title: String) {
        legalDocument = LegalDocument(
            id: name,
            title: title,
            text: PipoLegal.bundledDocument(named: name, extension: fileExtension) ?? "This packaged document could not be loaded."
        )
    }

    private func retrySecureStorage() {
        guard !isRetryingSecureStorage else { return }
        isRetryingSecureStorage = true
        Task {
            await configuration.retrySecureStorageAccess()
            isRetryingSecureStorage = false
        }
    }
}
