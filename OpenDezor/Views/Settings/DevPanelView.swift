import SwiftUI
import UniformTypeIdentifiers

/// Developer panel: switch logging on, watch the log live, export or copy it, and run the
/// checks that help find out why something failed. Open to everyone on purpose; it only
/// ever shows facts about the app and the device (see `DebugLogSanitizer`).
public struct DevPanelView: View {
    @ObservedObject private var log: DebugLog = .shared
    @ObservedObject private var network: NetworkDiagnostics = .shared
    @State private var minLevel: DebugLogLevel = .info
    @State private var search = ""
    @State private var follow = true
    @State private var device = DeviceSnapshot.current()
    @State private var player = PlayerStats.current()
    @State private var stateLines = AppStateSnapshot.lines()
    @State private var addonChecks: [AddonCheckResult] = []
    @State private var checkingAddons = false
    @State private var reportText = ""
    @State private var copied = false

    public init() {}

    private var visible: [DebugLogEntry] {
        log.entries.filter {
            $0.level >= minLevel
                && (search.isEmpty || $0.line.localizedCaseInsensitiveContains(search))
        }
    }

    public var body: some View {
        List {
            loggingSection
            logSection
            exportSection
            diagnosticsSection
        }
        .scrollContentBackground(.hidden)
        .glassBackground()
        .navigationTitle("DEV")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { network.start() }
        // Live numbers refresh while the panel is on screen; the log itself is live already.
        .task {
            while !Task.isCancelled {
                device = DeviceSnapshot.current()
                player = PlayerStats.current()
                stateLines = AppStateSnapshot.lines()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        // The export text is rebuilt shortly after the log settles, not on every line.
        .task(id: "\(log.entries.count)-\(addonChecks.count)") {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            reportText = DebugReport.text(entries: log.entries, device: device, addonChecks: addonChecks)
        }
    }

    // MARK: Logging

    private var loggingSection: some View {
        Section {
            Toggle(isOn: Binding(get: { log.isEnabled }, set: { log.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Logging aktivieren"))
                        .foregroundColor(AppTheme.textPrimary)
                    Text(L("Nur im Speicher. Bleibt im Hintergrund erhalten, ist nach dem vollständigen Beenden der App weg."))
                        .appFont(size: 12)
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .tint(AppTheme.primaryAccent)
        } footer: {
            Text(L("Protokolliert wird, was die App tut, nie wer sie benutzt: keine Konto-Daten, Titel, IP-Adressen oder Netzwerknamen."))
                .appFont(size: 11)
                .foregroundColor(AppTheme.textTertiary)
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: Live log

    private var logSection: some View {
        Section {
            Picker(L("Stufe"), selection: $minLevel) {
                Text(L("Alle")).tag(DebugLogLevel.info)
                Text(L("Warnungen")).tag(DebugLogLevel.warning)
                Text(L("Fehler")).tag(DebugLogLevel.error)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(AppTheme.textTertiary)
                TextField(L("Im Log suchen"), text: $search)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                if !search.isEmpty { ClearFieldButton { search = "" } }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if visible.isEmpty {
                            Text(log.isEnabled ? L("Noch keine Einträge.") : L("Logging ist aus."))
                                .appFont(size: 12)
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.vertical, 8)
                        }
                        ForEach(visible) { entry in
                            Text(entry.line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(color(for: entry.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                }
                .frame(height: 280)
                .onChange(of: log.entries.count) { _, _ in
                    guard follow, let last = visible.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }

            Toggle(L("Automatisch mitscrollen"), isOn: $follow)
                .tint(AppTheme.primaryAccent)

            HStack {
                Button { log.marker(L("MARKER: Problem tritt jetzt auf")) } label: {
                    Label(L("Marker setzen"), systemImage: "flag")
                }
                Spacer()
                Button(role: .destructive) { log.clear() } label: {
                    Label(L("Leeren"), systemImage: "trash")
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text("\(L("Live-Log")) (\(visible.count))")
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(AppTheme.textSecondary)
        }
        .listRowBackground(AppTheme.surface)
    }

    private func color(for level: DebugLogLevel) -> Color {
        switch level {
        case .info: return AppTheme.textSecondary
        case .warning: return AppTheme.warning
        case .error: return AppTheme.destructive
        }
    }

    // MARK: Export

    private var exportSection: some View {
        Section {
            ShareLink(
                // Debounced copy (see the `.task(id:)` above): rebuilding the whole report on
                // every 2 s refresh of the live numbers would be wasted work.
                item: DebugReportFile(text: reportText.isEmpty ? "OpenDezor Debug-Bericht\n(noch leer)" : reportText),
                preview: SharePreview("OpenDezor Debug-Bericht")
            ) {
                Label(L("Als Datei exportieren"), systemImage: "square.and.arrow.up")
            }

            Button {
                let text = DebugReport.text(entries: log.entries, device: device, addonChecks: addonChecks)
                #if os(iOS)
                UIPasteboard.general.string = text
                #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif
                copied = true
                Task { try? await Task.sleep(nanoseconds: 1_800_000_000); copied = false }
            } label: {
                Label(copied ? L("Kopiert") : L("Bericht kopieren"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .sensoryFeedback(.success, trigger: copied) { _, new in new }
        } header: {
            Text(L("Bericht"))
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(AppTheme.textSecondary)
        } footer: {
            Text(L("Der Bericht enthält Gerät, Netzwerk, App-Zustand, Player und das Log als lesbaren Text."))
                .appFont(size: 11)
                .foregroundColor(AppTheme.textTertiary)
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        Group {
            infoSection(L("Gerät"), device.lines)
            infoSection(L("App-Zustand"), stateLines)
            infoSection(L("Player live"), player.lines)

            Section {
                ForEach(network.lines, id: \.self) { Text($0).appFont(size: 12).foregroundColor(AppTheme.textSecondary) }
                Button {
                    Task { await network.runSpeedTest() }
                } label: {
                    HStack {
                        Label(L("Geschwindigkeit testen"), systemImage: "speedometer")
                        Spacer()
                        if network.isTesting { ProgressView() }
                    }
                }
                .disabled(network.isTesting)
            } header: {
                Text(L("Netzwerk"))
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)

            Section {
                ForEach(addonChecks) { r in
                    Text(r.line).appFont(size: 12).foregroundColor(AppTheme.textSecondary)
                }
                Button {
                    Task {
                        checkingAddons = true
                        addonChecks = await AddonCheck.run()
                        checkingAddons = false
                    }
                } label: {
                    HStack {
                        Label(L("Addons prüfen"), systemImage: "stethoscope")
                        Spacer()
                        if checkingAddons { ProgressView() }
                    }
                }
                .disabled(checkingAddons)
            } header: {
                Text(L("Addon-Check"))
                    .appFont(size: 12, weight: .semibold)
                    .foregroundColor(AppTheme.textSecondary)
            }
            .listRowBackground(AppTheme.surface)
        }
    }

    private func infoSection(_ title: String, _ lines: [String]) -> some View {
        Section {
            ForEach(lines, id: \.self) {
                Text($0)
                    .appFont(size: 12)
                    .foregroundColor(AppTheme.textSecondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text(title)
                .appFont(size: 12, weight: .semibold)
                .foregroundColor(AppTheme.textSecondary)
        }
        .listRowBackground(AppTheme.surface)
    }
}

/// The export as a real `.txt` file, written when the user actually shares it.
struct DebugReportFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { report in
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("OpenDezor-Debug-\(stamp).txt")
            try report.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
