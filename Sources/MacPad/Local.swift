import SwiftUI

/// View-local state, equivalent to `@State`.
///
/// The macOS 27 SDK declares `@State` as a macro whose compiler plugin ships only with full Xcode,
/// so a Command Line Tools build fails on it. `@Local` builds everywhere. Once Xcode is the
/// standard toolchain it can be swapped for `@State` with no other change.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    @MainActor
    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }

    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    @MainActor var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    @MainActor var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
