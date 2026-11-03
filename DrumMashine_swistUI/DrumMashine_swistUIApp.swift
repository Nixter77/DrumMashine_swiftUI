//
//  DrumMashine_swistUIApp.swift
//  DrumMashine_swistUI
//
//  Created by Nikolay Nikolayenko on 18/02/2026.
//

import AppKit
import SwiftUI

@main
struct DrumMashine_swistUIApp: App {
    @NSApplicationDelegateAdaptor(DrumMachineAppDelegate.self) private var appDelegate
    @Bindable private var theme = ThemeStore.shared

    var body: some Scene {
        WindowGroup {
            ThemedRootView()
        }
        .defaultSize(width: AppLayout.defaultWindow.width, height: AppLayout.defaultWindow.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .importExport) {
                Button("Экспорт…") { ProjectTransfer.shared.beginExport() }
                Button("Импорт…") { ProjectTransfer.shared.importPresented = true }
            }
            CommandMenu("Тема") {
                Picker("Тема", selection: $theme.style) {
                    ForEach(AppThemeStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Button("Переключить тему") { theme.toggle() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            #if DEBUG
            CommandMenu("Debug") {
                Button("Simulate save error") {
                    PatternManager.shared.simulateSaveError()
                }
            }
            #endif
        }
    }
}

/// Observes the theme inside the window. The App's own state does not re-run the content of a
/// window that is already open, so the switch has to be observed here to apply live.
struct ThemedRootView: View {
    private let theme = ThemeStore.shared

    var body: some View {
        MainLayoutView(sequencer: AppSequencer.shared)
            .background(AppTheme.background)
            .environment(\.appThemeStyle, theme.style)
            .preferredColorScheme(theme.style.isLight ? .light : .dark)
            // Only closing the window flushes the five stores, never a theme switch.
            .onDisappear {
                SessionStore.flush()
                PatternManager.shared.flushSave()
                UserPresetStore.flush()
                KitStore.flush()
                EffectSceneStore.flush()
            }
    }
}

/// Quit has to finish the write before the process exits. A queued task would miss it.
final class DrumMachineAppDelegate: NSObject, NSApplicationDelegate {
    nonisolated func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            PatternManager.shared.flushSave()
            SessionStore.flush()
            UserPresetStore.flush()
            KitStore.flush()
            EffectSceneStore.flush()
        }
        return .terminateNow
    }
}
