//
//  View+onChangeCompatible.swift
//  CodeEdit
//

import SwiftUI

extension View {
    /// Observes changes without firing on appearance, including on macOS Ventura.
    ///
    /// On Ventura, capture the value from the previous rendering to provide the same
    /// old/new value arguments as the macOS 14 overload. An unrelated rendering does
    /// not trigger the action because SwiftUI still compares the observed values.
    /// - Parameters:
    ///   - value: The equatable value to observe.
    ///   - action: Called with the previous and new values when the value changes.
    @ViewBuilder
    func onChangeCompatible<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value, Value) -> Void
    ) -> some View {
        if #available(macOS 14, *) {
            self.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self.onChange(of: value) { [value] newValue in
                action(value, newValue)
            }
        }
    }
}
