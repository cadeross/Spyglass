import SwiftUI

/// Mode, target, devices and the big Record button.
struct CaptureControls: View {
    let onRecord: () -> Void
    @Environment(Recorder.self) private var recorder

    var body: some View {
        @Bindable var preferences = recorder.preferences

        VStack(spacing: 10) {
            SegmentedGlass(selection: $preferences.mode, options: CaptureMode.allCases, title: \.title, symbol: \.symbol, height: 46)

            if preferences.mode.usesScreen {
                SegmentedGlass(selection: $preferences.scope, options: CaptureScope.allCases, title: \.title, symbol: \.symbol, height: 30, compact: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            DeviceCard()

            Button(action: onRecord) {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Start Recording")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(preferences.toggleShortcut.displayString)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.75)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .animation(.smooth(duration: 0.3), value: preferences.mode)
    }
}

/// A row of glass buttons that act like a segmented control.
private struct SegmentedGlass<Option: Hashable & Identifiable>: View where Option.ID: Sendable {
    @Binding var selection: Option
    let options: [Option]
    let title: KeyPath<Option, String>
    let symbol: KeyPath<Option, String>
    var height: CGFloat
    var compact = false
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(options) { option in
                    let selected = option == selection
                    Button {
                        withAnimation(.bouncy(duration: 0.35)) { selection = option }
                    } label: {
                        Group {
                            if compact {
                                Label(option[keyPath: title], systemImage: option[keyPath: symbol])
                                    .font(.system(size: 11.5, weight: .medium))
                            } else {
                                VStack(spacing: 3) {
                                    Image(systemName: option[keyPath: symbol])
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(option[keyPath: title])
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                        }
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.85)))
                        .frame(maxWidth: .infinity, minHeight: height)
                        .contentShape(.rect(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
                        in: .rect(cornerRadius: compact ? 11 : 14)
                    )
                    .glassEffectID(option.id, in: glass)
                }
            }
        }
    }
}

/// Camera, microphone and system audio, in one glass card.
private struct DeviceCard: View {
    @Environment(Recorder.self) private var recorder
    @Environment(Devices.self) private var devices

    var body: some View {
        let preferences = recorder.preferences

        VStack(spacing: 0) {
            if preferences.mode.usesCamera {
                Menu {
                    if devices.cameras.isEmpty {
                        Text("No cameras connected")
                    }
                    ForEach(devices.cameras) { camera in
                        Button {
                            preferences.cameraID = camera.id
                        } label: {
                            checkLabel(camera.name, checked: camera.name == devices.cameraName(for: preferences.cameraID))
                        }
                    }
                } label: {
                    DeviceRow(symbol: "video.fill", title: "Camera", value: devices.cameraName(for: preferences.cameraID), isOn: !devices.cameras.isEmpty)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)

                Divider().padding(.leading, 50)
            }

            Menu {
                Button {
                    preferences.recordsMicrophone = false
                } label: {
                    checkLabel("No microphone", checked: !preferences.recordsMicrophone)
                }
                Divider()
                ForEach(devices.microphones) { mic in
                    Button {
                        preferences.microphoneID = mic.id
                        preferences.recordsMicrophone = true
                    } label: {
                        checkLabel(mic.name, checked: preferences.recordsMicrophone && mic.name == devices.microphoneName(for: preferences.microphoneID))
                    }
                }
            } label: {
                DeviceRow(
                    symbol: preferences.recordsMicrophone ? "mic.fill" : "mic.slash.fill",
                    title: "Microphone",
                    value: preferences.recordsMicrophone ? devices.microphoneName(for: preferences.microphoneID) : "Off",
                    isOn: preferences.recordsMicrophone
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            if preferences.mode.usesScreen {
                Divider().padding(.leading, 50)

                HStack(spacing: 10) {
                    DeviceIcon(symbol: preferences.recordsSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill", isOn: preferences.recordsSystemAudio)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("System audio")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(preferences.recordsSystemAudio ? "Sound from your Mac is recorded" : "Off")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("System audio", isOn: Binding(get: { preferences.recordsSystemAudio }, set: { preferences.recordsSystemAudio = $0 }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private func checkLabel(_ title: String, checked: Bool) -> some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

private struct DeviceRow: View {
    let symbol: String
    let title: String
    let value: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            DeviceIcon(symbol: symbol, isOn: isOn)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(.rect)
    }
}

private struct DeviceIcon: View {
    let symbol: String
    let isOn: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary.opacity(0.85)))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 28, height: 28)
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: .circle)
    }
}
