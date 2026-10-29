import AppKit
import SwiftUI

struct RecordingRow: View {
    let recording: Recording

    @Environment(Library.self) private var library
    @State private var isHovering = false
    @State private var copied = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(image: library.thumbnails[recording.url], duration: recording.duration)
                .frame(width: 64, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .semibold))
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { isRenaming = false }
                        .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
                } else {
                    Text(recording.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Group {
                    if copied {
                        Text("Copied — paste it anywhere").foregroundStyle(.tint)
                    } else {
                        Text(recording.date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11))
                .lineLimit(1)
                .transition(.blurReplace)
            }

            Spacer(minLength: 6)

            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .foregroundStyle(isHovering || copied ? .primary : .secondary)
            .help("Copy the video to the clipboard")
        }
        .padding(8)
        .padding(.trailing, 4)
        .contentShape(.rect(cornerRadius: 16))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .onTapGesture { if !isRenaming { open() } }
        .onHover { hovering in withAnimation(.snappy(duration: 0.18)) { isHovering = hovering } }
        .onDrag { NSItemProvider(contentsOf: recording.url) ?? NSItemProvider() }
        .contextMenu { menu }
        .help("Click to watch and trim · drag into any app")
    }

    @ViewBuilder
    private var menu: some View {
        Button("Watch & Trim", systemImage: "play.rectangle", action: open)
        Button("Copy Video", systemImage: "doc.on.doc", action: copy)
        Button("Show in Finder", systemImage: "folder") { FileActions.reveal(recording.url) }
        Button("Rename", systemImage: "pencil") {
            draftName = recording.name
            isRenaming = true
            nameFocused = true
        }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) {
            withAnimation(.smooth) { library.trash(recording.url) }
        }
    }

    private func open() {
        NSApp.keyWindow?.close()
        ReviewWindow.show(recording.url, library: library)
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        library.rename(recording.url, to: draftName)
    }

    private func copy() {
        FileActions.copy(recording.url)
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.smooth) { copied = false }
        }
    }
}

private struct Thumbnail: View {
    let image: NSImage?
    let duration: TimeInterval?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                Image(systemName: "film")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 64, height: 40)
        .clipShape(.rect(cornerRadius: 8))
        .overlay(alignment: .bottomTrailing) {
            if let duration {
                Text(Recording.durationText(duration))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(3)
            }
        }
    }
}
