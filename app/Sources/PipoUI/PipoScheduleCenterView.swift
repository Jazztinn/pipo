import AppKit
import PipoAppCore
import SwiftUI
import UniformTypeIdentifiers

#if canImport(PDFKit)
  import PDFKit
#endif

@MainActor
public struct PipoScheduleCenterView: View {
  public let controller: PipoScheduleController
  @State private var importerPresented = false
  @State private var selectedDate = Date()
  @State private var weekMode = false
  @State private var setupName = ""
  @State private var setupStart = Date()
  @State private var setupEnd = Date()
  @State private var setupZone = "Asia/Manila"
  @State private var confirmingDelete = false

  public init(controller: PipoScheduleController) { self.controller = controller }

  public var body: some View {
    HStack(spacing: 0) {
      sourcePane
      Divider()
      editorPane
    }
    .frame(minWidth: 920, minHeight: 640)
    .confirmationDialog("Delete this account's saved schedule?", isPresented: $confirmingDelete) {
      Button("Delete schedule", role: .destructive) { Task { await controller.delete() } }
    }
    .fileImporter(isPresented: $importerPresented, allowedContentTypes: [.pdf, .png, .jpeg, .heic])
    { result in
      if case .success(let url) = result { Task { await controller.importDocument(at: url) } }
    }
  }

  private var signedIn: Bool { controller.accountID != nil }

  private var sourcePane: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Source").font(.headline)
        Spacer()
        Button("Import…") { importerPresented = true }.disabled(!signedIn)
      }
      if let preview = controller.preview {
        SourcePreview(preview: preview).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "No source preview", systemImage: "doc.viewfinder",
          description: Text("Import a PDF or image to review its schedule.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

    }
    .padding(20)
    .frame(width: 380)
    .dropDestination(for: URL.self) { urls, _ in
      guard signedIn, let url = urls.first else { return false }
      Task { await controller.importDocument(at: url) }
      return true
    }
  }

  private var editorPane: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Schedule").font(.title2.weight(.semibold))
        Spacer()
        if controller.isImporting { ProgressView() }
        if controller.isEditing || controller.isImporting || controller.preview != nil {
          Button("Cancel review") { controller.cancelReview() }.disabled(!signedIn)
        }
      }
      if let error = controller.error {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
      }
      if controller.draft == nil {
        termSetup
      } else if let draft = controller.draft {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            termEditor(draft)
            ForEach(Array(draft.rows.enumerated()), id: \.element.id) { index, row in
              SubjectEditor(controller: controller, rowIndex: index, row: row, enabled: signedIn)
            }
            Button("Add subject", systemImage: "plus") { controller.newSubject() }.disabled(
              !signedIn)
            if !controller.validationIssues.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Needs attention").font(.headline)
                ForEach(controller.validationIssues) { issue in
                  Label(
                    issue.message,
                    systemImage: issue.severity == .error
                      ? "exclamationmark.circle" : "exclamationmark.triangle"
                  ).foregroundStyle(issue.severity == .error ? .red : .orange)
                }
              }
            }
            timeline(draft)
          }.padding(.vertical, 4)
        }
        HStack {
          Button("Delete", role: .destructive) { confirmingDelete = true }.disabled(!signedIn)
          Spacer()
          if draft.rows.contains(where: { !$0.uncertainty.isEmpty })
            && !controller.hasAcknowledgedUncertainty
          {
            Button("Acknowledge uncertain fields") { controller.acknowledgeUncertainty() }.disabled(
              !signedIn)
          }
          Button("Save") { Task { await controller.save() } }.buttonStyle(.borderedProminent)
            .disabled(!signedIn || !controller.canSave)
        }
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var termSetup: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Set term details").font(.headline)
      TextField("Term label", text: $setupName)
      DatePicker("Start", selection: $setupStart, displayedComponents: .date)
      DatePicker("End", selection: $setupEnd, displayedComponents: .date)
      TextField("Time zone identifier", text: $setupZone)
      Button(controller.pendingRows.isEmpty ? "Create schedule" : "Review imported rows") {
        guard let zone = TimeZone(identifier: setupZone) else { return }
        controller.createDraft(
          term: .init(
            name: setupName, startDate: .init(setupStart, timeZone: zone),
            endDate: .init(setupEnd, timeZone: zone), timeZoneIdentifier: setupZone))
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        !signedIn || setupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || setupStart > setupEnd || TimeZone(identifier: setupZone) == nil)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func termEditor(_ draft: ScheduleDraft) -> some View {
    GroupBox("Term") {
      VStack(alignment: .leading) {
        TextField(
          "Term label",
          text: Binding(get: { draft.term.name }, set: { controller.setTerm(name: $0) })
        ).disabled(!signedIn)
        TextField(
          "Time zone identifier",
          text: Binding(
            get: { draft.term.timeZoneIdentifier },
            set: { controller.setTerm(name: draft.term.name, timeZoneIdentifier: $0) })
        ).disabled(!signedIn)
        if let zone = draft.term.timeZone, let start = draft.term.startDate.date(in: zone),
          let end = draft.term.endDate.date(in: zone)
        {
          DatePicker(
            "Start",
            selection: Binding(
              get: { start },
              set: { controller.setTerm(name: draft.term.name, start: .init($0, timeZone: zone)) }),
            displayedComponents: .date
          ).disabled(!signedIn)
          DatePicker(
            "End",
            selection: Binding(
              get: { end },
              set: { controller.setTerm(name: draft.term.name, end: .init($0, timeZone: zone)) }),
            displayedComponents: .date
          ).disabled(!signedIn)
        } else {
          Text("Enter a valid IANA time zone before editing dates.").foregroundStyle(.orange)
        }
      }.padding(4)
    }
  }

  private func timeline(_ draft: ScheduleDraft) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Classes").font(.headline)
        Spacer()
        Toggle("Week", isOn: $weekMode).toggleStyle(.switch)
        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
      }
      TimelineView(.periodic(from: .now, by: 60)) { context in
        occurrenceList(draft, now: context.date)
      }
    }
  }

  private func occurrenceList(_ draft: ScheduleDraft, now: Date) -> some View {
    let zone = draft.term.timeZone ?? TimeZone(identifier: "Asia/Manila")!
    let calendar = Calendar.pipoCalendar(timeZone: zone)
    let interval = calendar.dateInterval(of: weekMode ? .weekOfYear : .day, for: selectedDate)!
    let occurrences = ScheduleOccurrenceGenerator.occurrences(
      term: draft.term, rows: draft.rows, in: interval)
    let subjects = Dictionary(
      draft.rows.map { ($0.subject.id, $0.subject) }, uniquingKeysWith: { first, _ in first })
    let days = Array(
      Set(occurrences.compactMap { $0.start.map { ScheduleLocalDate($0, timeZone: zone) } })
    ).sorted()
    return VStack(alignment: .leading, spacing: 10) {
      ForEach(days, id: \.self) { day in
        Text(dateLabel(day.date(in: zone), zone: zone, date: true)).font(
          .subheadline.weight(.semibold))
        ForEach(
          occurrences.filter { $0.start.map { ScheduleLocalDate($0, timeZone: zone) } == day }
        ) { item in
          let subject = subjects[item.subjectID]
          let current = item.start.map { $0 <= now && now < (item.end ?? $0) } ?? false
          VStack(alignment: .leading, spacing: 3) {
            Text("\(subject?.code ?? "") · \(subject?.name ?? "Class")").fontWeight(
              current ? .semibold : .regular)
            Text(
              "\(dateLabel(item.start, zone: zone))–\(dateLabel(item.end, zone: zone))\(location(item.meetingID, draft: draft))"
            ).foregroundStyle(.secondary)
            if current {
              Label("Now", systemImage: "clock.fill").foregroundStyle(Color.accentColor)
            } else if let start = item.start, start > now {
              Text("Starts in \(max(1, Int(ceil(start.timeIntervalSince(now) / 60)))) minutes")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if occurrences.isEmpty { Text("No classes this period.").foregroundStyle(.secondary) }
      ForEach(draft.rows.filter { $0.meetings.contains(where: \.isTBA) }) { row in
        Text("\(row.subject.code) · \(row.subject.name) · Time TBA").foregroundStyle(.secondary)
      }
    }
  }

  private func dateLabel(_ value: Date?, zone: TimeZone, date: Bool = false) -> String {
    guard let value else { return "TBA" }
    let formatter = DateFormatter()
    formatter.timeZone = zone
    formatter.dateStyle = date ? .full : .none
    formatter.timeStyle = date ? .none : .short
    return formatter.string(from: value)
  }

  private func location(_ meetingID: UUID, draft: ScheduleDraft) -> String {
    let value = draft.rows.flatMap(\.meetings).first { $0.id == meetingID }?.location ?? ""
    return value.isEmpty ? "" : " · " + value
  }
}

@MainActor
private struct SubjectEditor: View {
  let controller: PipoScheduleController
  let rowIndex: Int
  let row: ScheduleReviewRow
  let enabled: Bool
  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          TextField(
            "Code",
            text: Binding(
              get: { row.subject.code },
              set: { controller.updateSubjectCode(index: rowIndex, code: $0) }))
          TextField(
            "Subject",
            text: Binding(
              get: { row.subject.name },
              set: { controller.updateSubjectName(index: rowIndex, name: $0) }))
        }
        TextField(
          "Section",
          text: Binding(
            get: { row.subject.section },
            set: { controller.updateSubjectSection(index: rowIndex, section: $0) }))
        TextField(
          "Instructor (optional)",
          text: Binding(
            get: { row.subject.instructor },
            set: { controller.updateSubjectInstructor(index: rowIndex, instructor: $0) }))
        ForEach(Array(row.meetings.enumerated()), id: \.element.id) { index, meeting in
          MeetingEditor(
            controller: controller, rowIndex: rowIndex, meetingIndex: index, meeting: meeting,
            enabled: enabled)
        }
        HStack {
          Button("Add meeting") { controller.addMeeting(subjectID: row.id) }
          Button("Remove subject", role: .destructive) { controller.removeSubject(id: row.id) }
        }.disabled(!enabled)
      }.disabled(!enabled).padding(4)
    }
  }
}

@MainActor
private struct MeetingEditor: View {
  let controller: PipoScheduleController
  let rowIndex: Int
  let meetingIndex: Int
  let meeting: ClassMeeting
  let enabled: Bool
  @State private var start = ""
  @State private var end = ""
  @State private var initialized = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Toggle(
          "Time TBA",
          isOn: Binding(
            get: { meeting.isTBA },
            set: {
              controller.updateMeeting(index: rowIndex, meetingIndex: meetingIndex, isTBA: $0)
            }))
        Spacer()
        Button("Remove meeting", role: .destructive) {
          controller.removeMeeting(subjectID: meeting.subjectID, meetingID: meeting.id)
        }
      }
      if !meeting.isTBA {
        HStack {
          ForEach(ScheduleWeekday.allCases, id: \.self) { day in
            Toggle(label(day), isOn: dayBinding(day)).toggleStyle(.button)
          }
        }
        HStack {
          TextField("Start (24h HH:MM)", text: $start)
          TextField("End (24h HH:MM)", text: $end)
        }
        .onChange(of: start) { _, _ in commit() }
        .onChange(of: end) { _, _ in commit() }
        if parse(start) == nil || parse(end) == nil {
          Label("Enter valid 24-hour times, such as 09:30.", systemImage: "exclamationmark.circle")
            .font(.caption).foregroundStyle(.red)
        }
        Toggle(
          "Ends next day",
          isOn: Binding(
            get: { meeting.overnightDayOffset == 1 },
            set: {
              controller.updateMeeting(
                index: rowIndex, meetingIndex: meetingIndex, overnightDayOffset: $0 ? 1 : 0)
            }))
      }
      TextField(
        "Location (optional)",
        text: Binding(
          get: { meeting.location },
          set: {
            controller.updateMeeting(index: rowIndex, meetingIndex: meetingIndex, location: $0)
          }))
    }
    .onAppear {
      start = format(meeting.startTime)
      end = format(meeting.endTime)
      initialized = true
    }
    .disabled(!enabled)
  }

  private func dayBinding(_ day: ScheduleWeekday) -> Binding<Bool> {
    Binding(
      get: { meeting.weekdays.contains(day) },
      set: { value in
        var days = meeting.weekdays
        if value { days.insert(day) } else { days.remove(day) }
        controller.updateMeeting(index: rowIndex, meetingIndex: meetingIndex, weekdays: days)
      })
  }

  private func commit() {
    guard initialized else { return }
    controller.updateMeeting(
      index: rowIndex, meetingIndex: meetingIndex,
      startTime: parse(start) ?? .init(hour: -1, minute: -1),
      endTime: parse(end) ?? .init(hour: -1, minute: -1))
  }

  private func parse(_ value: String) -> ScheduleClockTime? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
      (0..<24).contains(hour), (0..<60).contains(minute)
    else { return nil }
    return .init(hour: hour, minute: minute)
  }

  private func format(_ value: ScheduleClockTime?) -> String {
    guard let value, value.isValid else { return "" }
    return String(format: "%02d:%02d", value.hour, value.minute)
  }

  private func label(_ day: ScheduleWeekday) -> String {
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][day.rawValue - 1]
  }
}

extension Calendar {
  fileprivate static func pipoCalendar(timeZone: TimeZone) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = timeZone
    return c
  }
}
private struct SourcePreview: View {
  let preview: PipoEAFSourcePreview
  var body: some View {
    #if canImport(PDFKit)
      if preview.data.starts(with: Data("%PDF-".utf8)) {
        PDFSourceView(data: preview.data)
      } else if let image = NSImage(data: preview.images.first ?? preview.data) {
        Image(nsImage: image).resizable().scaledToFit()
      } else {
        Text("Preview available during review").foregroundStyle(.secondary)
      }
    #else
      Text("Preview available during review").foregroundStyle(.secondary)
    #endif
  }
}
#if canImport(PDFKit)
  private struct PDFSourceView: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
      let view = PDFView()
      view.autoScales = true
      view.document = PDFDocument(data: data)
      return view
    }
    func updateNSView(_ view: PDFView, context: Context) { view.document = PDFDocument(data: data) }
  }
#endif
