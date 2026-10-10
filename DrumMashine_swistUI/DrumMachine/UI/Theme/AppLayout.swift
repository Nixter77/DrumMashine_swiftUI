import SwiftUI

/// Shared window and panel sizes. `minWindow` starts at 1100×720 and is raised
/// after the transport and column layout land, if anything still clips.
struct AppLayout {
    static let minWindow = CGSize(width: 1100, height: 720)
    static let defaultWindow = CGSize(width: 1440, height: 900)

    static let leftColumnWidth: CGFloat = 360
    static let leftColumnMin: CGFloat = 300
    static let leftColumnMax: CGFloat = 440
    static let rightColumnMin: CGFloat = 640
    static let contentSpacing: CGFloat = 12
    static let libraryInspectorMin: CGFloat = 260
    static let libraryInspectorIdeal: CGFloat = 300
    static let libraryInspectorMax: CGFloat = 340
    /// A fresh session opens the library when the window is at least this wide.
    static let libraryOpensAtWidth: CGFloat = 1280
    static let effectsRowMinHeight: CGFloat = 170
    static let effectsRowHeight: CGFloat = 220
    static let sequencerTrackWidth: CGFloat = 64
    static let sequencerMuteWidth: CGFloat = 58
    static let sequencerVolumeWidth: CGFloat = 74
    static let sequencerPanWidth: CGFloat = 64
    static let sequencerRowMin: CGFloat = 26
    static let sequencerRowMax: CGFloat = 44
    static let sequencerTrackSpacing: CGFloat = 3
    static let transportBarHeight: CGFloat = 110
    static let sequencerControlBarHeight: CGFloat = 44
    /// One-row transport. Narrower windows use the two-row layout.
    static let transportWideMinWidth: CGFloat = 1320
    static let playButtonSize: CGFloat = 60
}
