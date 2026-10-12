import NotePadCore
import SwiftUI

struct FindBarView: View {
    @Bindable var find: FindModel
    @FocusState private var focused: Field?
    private enum Field { case query, replacement }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Find", text: $find.query)
                    .textFieldStyle(.plain)
                    .frame(width: 170)
                    .focused($focused, equals: .query)
                    .onSubmit { find.next() }
                    .onExitCommand { find.hide() }
                Text(find.counterText)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(find.hasNoResults ? Color.red : .secondary)
                    .frame(minWidth: 56, alignment: .trailing)
                toggle("Aa", help: "Match case", isOn: $find.options.matchCase)
                toggle("ab", help: "Whole word", isOn: $find.options.wholeWord)
                iconButton("chevron.up", help: "Previous match") { find.previous() }
                iconButton("chevron.down", help: "Next match") { find.next() }
                iconButton("arrow.triangle.2.circlepath", help: "Show replace", isOn: find.showsReplace) {
                    find.showsReplace.toggle()
                }
                iconButton("xmark", help: "Close find") { find.hide() }
            }
            if find.showsReplace {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Replace", text: $find.replacement)
                        .textFieldStyle(.plain)
                        .frame(width: 170)
                        .focused($focused, equals: .replacement)
                        .onSubmit { find.replaceCurrent() }
                        .onExitCommand { find.hide() }
                    Spacer(minLength: 0)
                    Button("Replace") { find.replaceCurrent() }
                        .disabled(find.matches.isEmpty)
                        .pointingHandCursor()
                    Button("Replace All") { find.replaceAll() }
                        .disabled(find.matches.isEmpty)
                        .pointingHandCursor()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 470)
        .glassRounded(14)
        .onChange(of: find.query) { find.refresh(select: true) }
        .onChange(of: find.options) { find.refresh(select: true) }
        .onChange(of: find.focusToken) { claimFocus() }
        .onAppear { claimFocus() }
    }

    /// The bar is inserted with a transition, so the field can only take focus on the next run-loop turn.
    private func claimFocus() {
        DispatchQueue.main.async { focused = .query }
    }

    private func toggle(_ label: String, help: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 24)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                .background(RoundedRectangle(cornerRadius: 8).fill(isOn.wrappedValue ? Color.accentColor.opacity(0.16) : .clear))
                .pointingHandCursor()
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }

    private func iconButton(_ symbol: String, help: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                .pointingHandCursor()
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
