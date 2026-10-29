import CoreGraphics
import Foundation

/// What ends up in the video.
nonisolated enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case screenAndCamera
    case screen
    case camera

    var id: Self { self }

    var title: String {
        switch self {
        case .screenAndCamera: "Screen + Cam"
        case .screen: "Screen"
        case .camera: "Cam"
        }
    }

    var symbol: String {
        switch self {
        case .screenAndCamera: "rectangle.inset.filled.and.person.filled"
        case .screen: "display"
        case .camera: "video.fill"
        }
    }

    var usesCamera: Bool { self != .screen }
    var usesScreen: Bool { self != .camera }
}

/// How much of the screen to record.
nonisolated enum CaptureScope: String, CaseIterable, Identifiable, Codable {
    case display
    case window
    case area

    var id: Self { self }

    var title: String {
        switch self {
        case .display: "Full Screen"
        case .window: "Window"
        case .area: "Area"
        }
    }

    var symbol: String {
        switch self {
        case .display: "rectangle.fill.on.rectangle.fill"
        case .window: "macwindow"
        case .area: "rectangle.dashed"
        }
    }
}

/// The resolved thing to record, once the user has picked it.
nonisolated enum CaptureTarget {
    case display(CGDirectDisplayID)
    /// A window, with its frame in Cocoa screen coordinates at the moment it was picked.
    case window(CGWindowID, frame: CGRect, display: CGDirectDisplayID)
    /// A region in Cocoa screen coordinates, always within one display.
    case area(CGRect, display: CGDirectDisplayID)
    case camera

    var displayID: CGDirectDisplayID? {
        switch self {
        case .display(let id), .window(_, _, let id), .area(_, let id): id
        case .camera: nil
        }
    }
}

nonisolated enum OutputQuality: String, CaseIterable, Identifiable, Codable {
    case h264HD
    case hevcNative

    var id: Self { self }

    var title: String {
        switch self {
        case .h264HD: "H.264 · up to 1080p"
        case .hevcNative: "HEVC · native resolution"
        }
    }

    var detail: String {
        switch self {
        case .h264HD: "Plays anywhere: Slack, Gmail, Windows, the web"
        case .hevcNative: "Retina-sharp and smaller, but some non-Apple players can't open it"
        }
    }

    var framesPerSecond: Int32 {
        switch self {
        case .h264HD: 30
        case .hevcNative: 60
        }
    }

    /// The pixel size to encode a capture of `points` at `scale`, kept even for the encoder.
    func pixelSize(forPoints points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        let native = CGSize(width: points.width * scale, height: points.height * scale)
        var factor: CGFloat = 1
        if self == .h264HD {
            let limit = native.width >= native.height ? CGSize(width: 1920, height: 1080) : CGSize(width: 1080, height: 1920)
            factor = min(1, limit.width / native.width, limit.height / native.height)
        }
        func even(_ value: CGFloat) -> Int { max(2, Int(value * factor) & ~1) }
        return (even(native.width), even(native.height))
    }
}

nonisolated enum BubbleSize: String, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large

    var id: Self { self }

    var diameter: CGFloat {
        switch self {
        case .small: 150
        case .medium: 210
        case .large: 300
        }
    }

    var title: String {
        switch self {
        case .small: "S"
        case .medium: "M"
        case .large: "L"
        }
    }
}
