import AppKit
import PipoAppCore
import SwiftUI

@MainActor
struct PipoSettingsCenterView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general, notifications, courses, updates, advanced

        var id: Self { self }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .general: "gear"
            case .notifications: "bell"
            case .courses: "books.vertical"
            case .updates: "arrow.triangle.2.circlepath"
            case .advanced: "wrench.and.screwdriver"
            }
        }
    }

    @Bindable private var model: PipoModel
    private let configuration: PipoUIConfiguration
    private let onSignOut: () -> Void
    @State private var selection: Page? = .general
    @State private var storageMessage: String?
    @State private var isRetryingSecureStorage = false
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
    }

    @ViewBuilder
    private func pageView(_ page: Page) -> some View {
        switch page {
        case .general: general
        case .notifications: notifications
        case .courses: courses
        case .updates: updates
        case .advanced: advanced
        }
    }

    private var general: some View {
        settingsForm("General") {
            Section("Account") {
                LabeledContent("Student", value: model.snapshot?.studentName ?? "Signed in")
                LabeledContent("Status", value: statusDescription)
                LabeledContent("LMS", value: PipoFoundation.lmsOrigin.host ?? "lms.lpucavite.edu.ph")
                Button("Open LMS", systemImage: "safari") { configuration.openURL(PipoFoundation.lmsOrigin) }
            }
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
                Button("Refresh now", systemImage: "arrow.clockwise") {
                    Task { try? await configuration.refresh() }
                }
            }
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
                Button("Allow Calendar access", systemImage: "calendar.badge.plus") {
                    Task { _ = try? await model.requestCalendarAccess() }
                }
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

    private func retrySecureStorage() {
        guard !isRetryingSecureStorage else { return }
        isRetryingSecureStorage = true
        Task {
            await configuration.retrySecureStorageAccess()
            isRetryingSecureStorage = false
        }
    }
}
