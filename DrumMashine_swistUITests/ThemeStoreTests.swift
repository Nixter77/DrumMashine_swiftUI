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
        var changes = 0
        func track() {
            withObservationTracking { _ = store.style } onChange: { changes += 1 }
        }
        track()
        store.toggle()
        #expect(store.style == .studioLight)
        track()
        store.toggle()
        #expect(store.style == .dark)
        #expect(changes == 2)
        // Token reads through the static accessor are tracked too, so views redraw without `.id`.
        let shared = ThemeStore.shared
        let original = shared.style
        defer { shared.style = original }
        var tokenChanges = 0
        withObservationTracking { _ = AppTheme.accent } onChange: { tokenChanges += 1 }
        shared.toggle()
        #expect(tokenChanges == 1)
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
