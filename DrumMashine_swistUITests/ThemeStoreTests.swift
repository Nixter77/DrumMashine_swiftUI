import Combine
import Foundation
import SwiftUI
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct ThemeStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "ThemeStoreTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func defaultsToDark() {
        #expect(ThemeStore(defaults: freshDefaults()).style == .dark)
    }

    @Test func persistsChoice() {
        let d = freshDefaults()
        let a = ThemeStore(defaults: d)
        a.toggle()
        #expect(a.style == .studioLight)
        #expect(ThemeStore(defaults: d).style == .studioLight)
        a.toggle()
        #expect(ThemeStore(defaults: d).style == .dark)
    }

    @Test func unknownValueFallsBackToDark() {
        let d = freshDefaults()
        d.set("neon", forKey: ThemeStore.defaultsKey)
        #expect(ThemeStore(defaults: d).style == .dark)
    }

    @Test func bothPalettesHaveEightPadColors() {
        #expect(AppTheme.darkPadColors.count == 8)
        #expect(AppTheme.lightPadColors.count == 8)
    }

    @Test func toggleNotifiesObservers() {
        let store = ThemeStore(defaults: freshDefaults())
        var seen: [AppThemeStyle] = []
        let sub = store.$style.dropFirst().sink { seen.append($0) }
        var willChange = 0
        let sub2 = store.objectWillChange.sink { willChange += 1 }
        store.toggle()
        store.toggle()
        #expect(seen == [.studioLight, .dark])
        #expect(willChange == 2)
        sub.cancel(); sub2.cancel()
    }

    @Test func tokensFollowTheSharedStyle() {
        let store = ThemeStore.shared
        let original = store.style
        defer { store.style = original }
        store.style = .dark
        #expect(AppTheme.background == AppTheme.Dark.background)
        #expect(AppTheme.accent == AppTheme.Dark.accent)
        store.style = .studioLight
        #expect(AppTheme.background == AppTheme.Light.background)
        #expect(AppTheme.textPrimary == AppTheme.Light.textPrimary)
    }

    @Test func cachedDarkTokensKeepTheOriginalValues() {
        #expect(AppTheme.Dark.background == Color(hex: "0E0E14"))
        #expect(AppTheme.Dark.surface == Color(hex: "1A1A22"))
        #expect(AppTheme.Dark.accent == Color(hex: "FF6B35"))
        #expect(AppTheme.Dark.inactiveStep == Color(hex: "22222C"))
        #expect(AppTheme.Dark.textPrimary == Color.white)
        #expect(AppTheme.Dark.shadowColor == Color.black.opacity(0.4))
    }
}
