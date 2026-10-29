import AppKit
import ServiceManagement
import SwiftUI

struct PanelView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(Library.self) private var library
    @Environment(Devices.self) private var devices
    @State private var showsSettings = false
    @State private var window: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(showsSettings: $showsSettings)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Group {
                if showsSettings {
                    SettingsView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    VStack(spacing: 12) {
                        if recorder.isIdle {
                            CaptureControls(onRecord: record)
                                .transition(.blurReplace)
                        } else {
                            LiveCard()
                                .transition(.blurReplace)
                        }
                        RecentSection()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

            FooterView()
        }
        .frame(width: 360)
        .background(WindowReader { window = $0 })
        .background(WindowVisibilityObserver { visible in
            guard visible else { return }
            library.refresh()
            devices.refresh()
        })
        .animation(.smooth(duration: 0.35), value: showsSettings)
        .animation(.smooth(duration: 0.35), value: recorder.isIdle)
    }

    private func record() {
        // Get the panel out of the way before anything is captured.
        window?.close()
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await recorder.start()
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @Binding var showsSettings: Bool
    @Environment(Recorder.self) private var recorder

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(showsSettings ? "Settings" : "Spyglass")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .contentTransition(.opacity)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                showsSettings.toggle()
            } label: {
                Image(systemName: showsSettings ? "checkmark" : "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help(showsSettings ? "Done" : "Settings")
        }
    }

    private var statusLine: String {
        switch recorder.phase {
        case .idle: showsSettings ? "Trim your sails" : "Eyes on the horizon"
        case .preparing: "Getting ready…"
        case .countingDown: "Starting…"
        case .recording: "Recording · \(Recording.durationText(recorder.elapsed))"
        case .finishing: "Saving…"
        }
    }
}

// MARK: - While recording

private struct LiveCard: View {
    @Environment(Recorder.self) private var recorder

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if recorder.phase == .finishing || recorder.phase == .preparing {
                    ProgressView().controlSize(.small)
                } else {
                    RecordingDot(isLive: recorder.isRecording)
                }
            }
            .frame(width: 30, height: 30)
            .background(.red.opacity(0.14), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(Recording.durationText(recorder.elapsed))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer(minLength: 6)

            if recorder.isRecording || recorder.phase == .countingDown {
                Button("Discard", systemImage: "trash") { Task { await recorder.discard() } }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Discard")
            }
            if recorder.isRecording {
                Button("Stop", systemImage: "stop.fill") { Task { await recorder.stop() } }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
            }
        }
        .padding(12)
        .glassEffect(.regular.tint(.red.opacity(0.08)), in: .rect(cornerRadius: 16))
    }

    private var title: String {
        switch recorder.phase {
        case .preparing: "Getting ready"
        case .countingDown: "Counting down"
        case .finishing: "Saving your video"
        case .idle, .recording: "Recording"
        }
    }
}

// MARK: - Recent recordings

private struct RecentSection: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Open Folder") {
                    try? library.ensureFolder()
                    FileActions.open(library.folder)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tint)
            }
            .padding(.horizontal, 4)

            if library.recordings.isEmpty {
                EmptyRecentView()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(library.recordings.prefix(10)) { recording in
                            RecordingRow(recording: recording)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.smooth(duration: 0.35), value: library.recordings.map(\.url))
    }
}

private struct EmptyRecentView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: SpyglassGlyph.menuBarImage)
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundStyle(.tint)
                .padding(.top, 4)
            Text("Nothing on the horizon yet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("Your recordings will show up here, ready to copy and share.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

// MARK: - Footer

private struct FooterView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.glass)
                .controlSize(.small)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Divider().padding(.horizontal, 16)
        }
    }
}
