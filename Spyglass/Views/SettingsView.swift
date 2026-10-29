import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(Recorder.self) private var recorder
    @Environment(Library.self) private var library

    var body: some View {
        @Bindable var preferences = recorder.preferences

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Section("Video quality") {
                    VStack(spacing: 0) {
                        ForEach(OutputQuality.allCases) { quality in
                            QualityRow(quality: quality, isSelected: preferences.quality == quality) {
                                withAnimation(.snappy) { preferences.quality = quality }
                            }
                            if quality != OutputQuality.allCases.last { Divider().padding(.leading, 40) }
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }

                Section("Recording") {
                    VStack(spacing: 0) {
                        SettingRow(title: "Camera bubble size") {
                            Picker("Camera bubble size", selection: $preferences.bubbleSize) {
                                ForEach(BubbleSize.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 110)
                        }
                        Divider().padding(.leading, 12)
                        SettingRow(title: "3-2-1 countdown") {
                            Toggle("3-2-1 countdown", isOn: $preferences.countsDown)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }

                Section("Save recordings to") {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Preferences.defaultFolder.deletingLastPathComponent().path))
                            .resizable()
                            .frame(width: 26, height: 26)
                        Text(displayPath(preferences.folder))
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        if preferences.folder != Preferences.defaultFolder {
                            Button("Reset") {
                                preferences.folder = Preferences.defaultFolder
                                library.refresh()
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        }
                        Button("Change…", action: chooseFolder)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }

                Section("Shortcuts") {
                    VStack(spacing: 0) {
                        SettingRow(title: "Start or stop recording") {
                            ShortcutRecorder(shortcut: $preferences.toggleShortcut, fallback: .toggleDefault)
                        }
                        Divider().padding(.leading, 12)
                        SettingRow(title: "Discard while recording") {
                            ShortcutRecorder(shortcut: $preferences.discardShortcut, fallback: .discardDefault)
                        }
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Save Recordings To"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = recorder.preferences.folder
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            recorder.preferences.folder = url
            library.refresh()
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct QualityRow: View {
    let quality: OutputQuality
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quality.title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(quality.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
