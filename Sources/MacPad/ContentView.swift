import AppKit
import MacPadCore
import SwiftUI

struct ContentView: View {
    /// The window this view shows. Each window shows its own active tab.
    let windowID: UUID
    private let state = AppState.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.fontName) private var fontName = EditorSettings.systemMono
    @AppStorage(SettingsKey.fontSize) private var fontSize = 13.0
    @AppStorage(SettingsKey.wrapByDefault) private var wrapByDefault = true
    @AppStorage(SettingsKey.formatAllText) private var formatAllText = false

    private var settings: EditorSettings {
        EditorSettings(fontName: fontName, fontSize: fontSize, wrapByDefault: wrapByDefault, formatAllText: formatAllText)
    }

    var body: some View {
        ZStack(alignment: .top) {
            editorArea
            overlays
        }
        .background(WindowConfigurator(windowID: windowID, state: state))
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.15), value: state.find.isVisible)
        .animation(.easeOut(duration: 0.15), value: state.notice)
        .animation(.easeOut(duration: 0.15), value: windowDocument.flatMap { state.diskStatus[$0.id] })
        .sheet(isPresented: Binding(get: { state.recoveryVisible && isFocused }, set: { state.recoveryVisible = $0 })) {
            RecoveryView(state: state)
        }
        .sheet(isPresented: Binding(get: { state.historyVisible && isFocused }, set: { state.historyVisible = $0 })) {
            VersionHistoryView(state: state)
        }
        // A torn-off window hands its tabs back when its content goes away, which happens when the window closes.
        .onDisappear { if windowID != AppState.mainWindowID { state.windowWasClosed(windowID) } }
        .task {
            state.openWindowAction = { openWindow(value: $0) }
            state.dismissWindowAction = { dismissWindow(value: $0) }
            state.openSettingsAction = { openSettings() }
            if windowID == AppState.mainWindowID { await state.start() }
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.open(urls.filter(\.isFileURL))
            return !urls.isEmpty
        }
    }

    /// The tab this window shows.
    private var windowDocument: TextDocument? {
        state.tabs.first { $0.id == state.activeByWindow[windowID] }
    }

    /// Only the focused window shows the find bar, notices and sheets, so they never appear twice.
    private var isFocused: Bool { state.focusedWindowID == windowID }

    @ViewBuilder private var editorArea: some View {
        if let doc = windowDocument {
            HStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    EditorHost(
                        controller: state.controller(for: doc),
                        settings: settings,
                        zoom: doc.zoom,
                        wrap: doc.usesWordWrap(default: wrapByDefault),
                        formatted: doc.usesFormattedView(formatAllText: formatAllText),
                        showLineNumbers: state.showLineNumbers
                    )
                    .id(doc.id)
                    // Keeps the editor's scroll bar clear of the preview divider.
                    .padding(.trailing, doc.previewVisible ? 10 : 0)
                    if state.find.isVisible && isFocused {
                        // Sits in the editor pane, below the tab and toolbar strip, so it never covers the preview or the wall.
                        FloatingHost(content: FindBarView(find: state.find))
                            .fixedSize()
                            .padding(.top, 64)
                            .padding(.trailing, doc.previewVisible ? 26 : 16)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                if doc.previewVisible {
                    Divider()
                    MarkdownPreviewView(
                        markdown: doc.text,
                        scrollLine: state.previewLine,
                        onScroll: { state.previewScrolled($0) },
                        onHeading: { _ = state.goTo(line: $0) },
                        find: state.find.previewHighlight
                    )
                        .frame(minWidth: 240)
                }
            }
            .frame(maxWidth: state.focusMode ? 720 : .infinity)
        } else {
            Color(nsColor: .textBackgroundColor)
        }
    }

    private var overlays: some View {
        overlayStack.animation(.easeOut(duration: 0.15), value: state.focusMode)
    }

    private var overlayStack: some View {
        ZStack {
            if !state.focusMode { VStack(spacing: 8) {
                GlassGroup(spacing: 10) {
                    HStack(spacing: 10) {
                        TabBarView(state: state, windowID: windowID).padding(.leading, state.isFullScreen ? 0 : 74)
                        ToolbarView(state: state, formatAllText: formatAllText, wrapByDefault: wrapByDefault)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                if let doc = windowDocument, doc.isReadOnly {
                    ReadOnlyBanner(state: state, doc: doc)
                }
                if let doc = windowDocument, let status = state.diskStatus[doc.id] {
                    DiskNoticeView(state: state, doc: doc, status: status)
                }
                if let notice = state.notice, isFocused { NoticeView(text: notice) }
                Spacer(minLength: 0)
            } }
            if !state.focusMode {
                VStack {
                    Spacer()
                    StatusBarView(state: state).padding(.bottom, 12)
                }
            }
        }
    }
}

/// Makes the title bar area draggable, and reports when this window becomes key.
private struct WindowConfigurator: NSViewRepresentable {
    let windowID: UUID
    let state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(windowID: windowID, state: state) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        let windowID = windowID
        let state = state
        // The view joins its window a little after it is created, so retry briefly until the window exists.
        func configure(attempt: Int) {
            guard let window = view.window else {
                if attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { configure(attempt: attempt + 1) }
                }
                return
            }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            coordinator.observe(window)
            if let point = state.pendingPlacements.removeValue(forKey: windowID) {
                // Opens under the drop point, but never partly off the screen.
                let target = NSRect(origin: NSPoint(x: point.x - 90, y: point.y - window.frame.height + 14), size: window.frame.size)
                let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? window.screen
                window.setFrame(screen.map { window.constrainFrameRect(target, to: $0) } ?? target, display: true)
            }
        }
        DispatchQueue.main.async { configure(attempt: 0) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator {
        private let windowID: UUID
        private let state: AppState
        private var tokens: [NSObjectProtocol] = []

        init(windowID: UUID, state: AppState) {
            self.windowID = windowID
            self.state = state
        }

        func observe(_ window: NSWindow) {
            guard tokens.isEmpty else { return }
            let center = NotificationCenter.default
            let windowID = windowID
            let state = state
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { state.focusedWindowID = windowID }
            })
        }
    }
}
