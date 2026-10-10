import Combine
import SwiftUI

/// The app's two looks. `.dark` is the original design and stays the default.
enum AppThemeStyle: String, CaseIterable, Identifiable {
    case dark
    case studioLight

    var id: String { rawValue }
    var title: String { self == .dark ? "Dark" : "Studio Light" }
    var isLight: Bool { self == .studioLight }
}

/// Holds the chosen style. AppTheme tokens read `ThemeStore.style` so call sites stay unchanged.
/// `ThemedRootView` and `MainLayoutView` observe `shared` and key the panels on `style`, so a switch
/// applies live without a restart.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    static let defaultsKey = "appThemeStyle"

    @Published var style: AppThemeStyle {
        didSet { defaults.set(style.rawValue, forKey: Self.defaultsKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.style = AppThemeStyle(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .dark
    }

    /// Fast read for theme tokens.
    static var style: AppThemeStyle { shared.style }
    static var isLight: Bool { shared.style.isLight }

    func toggle() { style = style == .dark ? .studioLight : .dark }
}

private struct AppThemeStyleKey: EnvironmentKey {
    static let defaultValue: AppThemeStyle = .dark
}

extension EnvironmentValues {
    /// The live style, for views that want to depend on the theme explicitly.
    var appThemeStyle: AppThemeStyle {
        get { self[AppThemeStyleKey.self] }
        set { self[AppThemeStyleKey.self] = newValue }
    }
}
