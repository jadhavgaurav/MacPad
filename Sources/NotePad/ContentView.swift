import AppKit
import NotePadCore
import SwiftUI

struct ContentView: View {
    private let state = AppState.shared
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
        .background(WindowConfigurator())
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.15), value: state.find.isVisible)
        .animation(.easeOut(duration: 0.15), value: state.notice)
        .animation(.easeOut(duration: 0.15), value: state.activeID.flatMap { state.diskStatus[$0] })
        .sheet(isPresented: Binding(get: { state.recoveryVisible }, set: { state.recoveryVisible = $0 })) {
            RecoveryView(state: state)
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.open(urls.filter(\.isFileURL))
            return !urls.isEmpty
        }
    }

    @ViewBuilder private var editorArea: some View {
        if let doc = state.activeDocument {
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
                    if state.find.isVisible {
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
                    MarkdownPreviewView(markdown: doc.text, scrollFraction: state.previewFraction)
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
                        TabBarView(state: state).padding(.leading, state.isFullScreen ? 0 : 74)
                        ToolbarView(state: state, formatAllText: formatAllText, wrapByDefault: wrapByDefault)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                if let doc = state.activeDocument, doc.isReadOnly {
                    ReadOnlyBanner(state: state, doc: doc)
                }
                if let doc = state.activeDocument, let status = state.diskStatus[doc.id] {
                    DiskNoticeView(state: state, doc: doc, status: status)
                }
                if let notice = state.notice { NoticeView(text: notice) }
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

/// Makes the title bar area draggable and the window comfortable to resize.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
