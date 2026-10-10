import AppKit
import SwiftUI
import UniformTypeIdentifiers
// MARK: - Main Layout View (Adaptive + Premium Design)
struct MainLayoutView: View {
    @State private var sequencerEngine: SequencerEngine
    @State private var libraryOpen: Bool
    @State private var didSettleLibrary = false
    /// Snapshot tests draw the panels before the engine finishes loading.
    private let showsLayoutForSnapshot: Bool
    private let snapshotShowsPatterns: Bool
    private var audioManager: AudioEngineManager { AudioEngineManager.shared }
    /// AppTheme tokens are static reads, so a theme switch rebuilds the panels below via `.id`.
    /// The engine is @State of this view and is not part of that subtree, so playback continues.
    @ObservedObject private var theme = ThemeStore.shared

    /// The window passes `AppSequencer.shared`. Snapshots and previews get a private engine.
    init(
        sequencer: SequencerEngine? = nil,
        showsLayoutForSnapshot: Bool = false,
        snapshotShowsPatterns: Bool = false
    ) {
        let session = SessionStore.load()
        _sequencerEngine = State(initialValue: sequencer ?? SequencerEngine(session: session))
        // Closed until the window width is known. An open inspector would force the window past the minimum.
        // The patterns snapshot draws the library beside the columns: ImageRenderer drops `.inspector`.
        _libraryOpen = State(initialValue: session?.libraryInspectorOpen ?? false)
        self.showsLayoutForSnapshot = showsLayoutForSnapshot
        self.snapshotShowsPatterns = snapshotShowsPatterns
    }
    
    var body: some View {
        @Bindable var transfer = ProjectTransfer.shared
        ZStack(alignment: .top) {
            // Deep background with subtle gradient
            LinearGradient(
                colors: [AppTheme.backgroundDeep, AppTheme.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Ambient glow orbs for depth
            ambientBackground
            
            // Loading overlay. The error banner stays visible while sounds are still loading,
            // otherwise a failed engine.start() is hidden behind "Loading Sounds...".
            if !audioManager.isReady && !showsLayoutForSnapshot {
                loadingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshotShowsPatterns {
                // ImageRenderer does not draw `.inspector`. The live window still uses it.
                HStack(spacing: 0) {
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    SoundLibraryView(
                        sequencer: sequencerEngine,
                        startsOnPatterns: true,
                        snapshotLayout: true
                    )
                        .frame(width: AppLayout.libraryInspectorIdeal)
                        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("library.panel")
                }
            } else {
                // Keep the transport on screen when the columns are taller than the window.
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            if let error = audioManager.errorMessage {
                errorBanner(error)
            }
            if PersistenceAlerts.shared.isVisible, let error = PersistenceAlerts.shared.lastError {
                VStack {
                    Spacer()
                        .allowsHitTesting(false)
                    persistenceBanner(error)
                }
            }
        }
        .frame(
            minWidth: AppLayout.minWindow.width,
            minHeight: AppLayout.minWindow.height,
            alignment: .top
        )
        .onChange(of: libraryOpen) { _, open in
            if SessionStore.libraryInspectorOpen != open {
                SessionStore.libraryInspectorOpen = open
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                settleLibraryInspector()
                DispatchQueue.main.async {
                    #if DEBUG
                    placeDebugWindowIfRequested()
                    #endif
                }
            }
        }
        .modifier(LibraryInspectorModifier(
            enabled: !showsLayoutForSnapshot,
            isPresented: $libraryOpen,
            sequencer: sequencerEngine
        ))
        .id(theme.style)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    libraryOpen.toggle()
                } label: {
                    Image(systemName: "books.vertical")
                }
                .help(libraryOpen ? "Скрыть библиотеку" : "Показать библиотеку")
                .accessibilityLabel("Библиотека")
                .accessibilityIdentifier("library.toggle")
            }
        }
        .fileExporter(
            isPresented: $transfer.exportPresented,
            document: transfer.exportDocument,
            contentType: .drumproj,
            defaultFilename: transfer.exportDocument.project.name
        ) { result in
            if case .failure(let error) = result {
                PersistenceAlerts.shared.report(
                    .failed(operation: .write, file: "drumproj", reason: error.localizedDescription),
                    url: PatternManager.shared.directory
                )
            }
        }
        .fileImporter(isPresented: $transfer.importPresented, allowedContentTypes: [.drumproj]) { result in
            transfer.receiveImport(result)
        }
        .confirmationDialog("Импорт проекта", isPresented: $transfer.askReplace, titleVisibility: .visible) {
            Button("Заменить") { transfer.apply(.replace) }
            Button("Добавить пресеты и слоты") { transfer.apply(.add) }
            Button("Отмена", role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: ProjectTransfer.didImport)) { note in
            guard let session = note.object as? SessionState else { return }
            sequencerEngine.adopt(session)
        }
    }

    /// A saved session keeps its inspector. A first launch follows the window width.
    private func settleLibraryInspector() {
        guard !didSettleLibrary else { return }
        didSettleLibrary = true
        if snapshotShowsPatterns {
            return
        }
        if SessionStore.load() != nil {
            libraryOpen = SessionStore.libraryInspectorOpen
            return
        }
        #if DEBUG
        if let requested = Self.debugWindowSize() {
            libraryOpen = requested.width >= AppLayout.libraryOpensAtWidth
            return
        }
        #endif
        let width = NSApp.windows.first { $0.isVisible }?.frame.width
            ?? NSApp.windows.first?.frame.width
            ?? AppLayout.defaultWindow.width
        libraryOpen = width >= AppLayout.libraryOpensAtWidth
    }

    #if DEBUG
    /// UI tests pass `-DMDataDirectory` and `-DMWindowSize 1100x720`. Release builds never call this.
    private func placeDebugWindowIfRequested() {
        let requested = Self.debugWindowSize()
        guard requested != nil || PatternManager.debugDataDirectory() != nil else { return }
        let window = NSApp.windows.first { $0.isVisible } ?? NSApp.windows.first
        guard let window else { return }
        let size = requested ?? CGSize(width: 1440, height: 900)
        window.setFrame(NSRect(x: 40, y: 40, width: size.width, height: size.height), display: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// `-DMWindowSize 1100x720`.
    static func debugWindowSize() -> CGSize? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-DMWindowSize"),
              arguments.indices.contains(flag + 1) else { return nil }
        let parts = arguments[flag + 1].split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }
    #endif
    
    // MARK: - Ambient Background
    private var ambientBackground: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accent.opacity(0.05))
                .frame(width: 500, height: 500)
                .blur(radius: 100)
                .offset(x: -250, y: -120)
            Circle()
                .fill(AppTheme.accentSecondary.opacity(0.04))
                .frame(width: 400, height: 400)
                .blur(radius: 90)
                .offset(x: 250, y: 180)
        }
        .ignoresSafeArea()
        .drawingGroup(opaque: false)
        .allowsHitTesting(false)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.16))
                    .frame(width: 120, height: 120)
                Image(systemName: "waveform.circle")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.accentGradient)
                    .symbolEffect(.pulse)
            }
            Text("Loading Sounds...")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)
            ProgressView(value: audioManager.loadingProgress)
                .progressViewStyle(.linear)
                .tint(AppTheme.accent)
                .frame(width: 220)
            Text("\(Int(audioManager.loadingProgress * 100))%")
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundColor(AppTheme.textSecondary)
        }
    }
    
    // MARK: - Error Banner
    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppTheme.accentWarning)
                    .font(.body)
                Text(message)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .background(AppTheme.accentMute.opacity(0.2))
            .cornerRadius(10)
            .padding()
            Spacer()
        }
    }

    /// Sits at the bottom so the transport at the top stays visible.
    private func persistenceBanner(_ error: PersistenceError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundColor(AppTheme.accentWarning)
            Text(PersistenceAlerts.shared.text(for: error))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Показать в Finder") { showPersistenceFile() }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.accent)
            Button("Повторить") { retryPersistence() }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.accent)
            Button("Скрыть") { PersistenceAlerts.shared.dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(AppTheme.textSecondary)
        }
        .padding(12)
        .background(AppTheme.accentMute.opacity(0.85))
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private func showPersistenceFile() {
        guard let url = PersistenceAlerts.shared.fileURL else { return }
        let target = FileManager.default.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private func retryPersistence() {
        PatternManager.shared.flushSave()
        SessionStore.flush()
        UserPresetStore.flush()
        KitStore.flush()
        EffectSceneStore.flush()
    }
    
    // MARK: - Main Content
    private var mainContent: some View {
        VStack(spacing: AppLayout.contentSpacing) {
            TransportBarView(sequencer: sequencerEngine)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: AppLayout.contentSpacing) {
                VStack(spacing: 10) {
                    PadsGridView(sequencer: sequencerEngine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("pads.panel")
                    AudioVisualizerView()
                        .frame(height: 120)
                    MasterControlView()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(
                    minWidth: AppLayout.leftColumnMin,
                    idealWidth: AppLayout.leftColumnWidth,
                    maxWidth: AppLayout.leftColumnMax
                )
                .frame(maxHeight: .infinity, alignment: .top)

                VStack(spacing: 10) {
                    SequencerView(sequencer: sequencerEngine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("seq.panel")
                    EffectsRackView(bpm: sequencerEngine.bpm, showsLayoutForSnapshot: showsLayoutForSnapshot)
                        .frame(maxWidth: .infinity)
                        .frame(
                            minHeight: AppLayout.effectsRowMinHeight,
                            idealHeight: AppLayout.effectsRowHeight,
                            maxHeight: AppLayout.effectsRowHeight
                        )
                }
                .frame(minWidth: AppLayout.rightColumnMin, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(AppLayout.contentSpacing)
    }
}

/// ImageRenderer cannot flatten the inspector's split view, so snapshots omit it.
private struct LibraryInspectorModifier: ViewModifier {
    let enabled: Bool
    @Binding var isPresented: Bool
    let sequencer: SequencerEngine

    func body(content: Content) -> some View {
        if enabled {
            content.inspector(isPresented: $isPresented) {
                SoundLibraryView(sequencer: sequencer)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("library.panel")
                    .inspectorColumnWidth(
                        min: AppLayout.libraryInspectorMin,
                        ideal: AppLayout.libraryInspectorIdeal,
                        max: AppLayout.libraryInspectorMax
                    )
            }
        } else {
            content
        }
    }
}

#Preview(traits: .landscapeLeft) {
    MainLayoutView()
}
