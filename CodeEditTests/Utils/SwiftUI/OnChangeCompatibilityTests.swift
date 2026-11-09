//
//  OnChangeCompatibilityTests.swift
//  CodeEditTests
//

import AppKit
import SwiftUI
import XCTest
@testable import CodeEdit

@MainActor
final class OnChangeCompatibilityTests: XCTestCase {
    private final class Model: ObservableObject {
        @Published var value = 0
        @Published var unrelatedValue = 0
    }

    private final class Changes {
        var values: [[Int]] = []
    }

    private struct Probe: View {
        @ObservedObject var model: Model
        let onAppear: () -> Void
        let onChange: (Int, Int) -> Void

        var body: some View {
            Text("\(model.unrelatedValue)")
                .onChangeCompatible(of: model.value, perform: onChange)
                .onAppear(perform: onAppear)
        }
    }

    private func withProbe(_ action: @MainActor (Model, Changes) async -> Void) async {
        _ = NSApplication.shared
        let model = Model()
        let changes = Changes()
        let appeared = expectation(description: "Probe appeared")
        let view = Probe(
            model: model,
            onAppear: { appeared.fulfill() },
            onChange: { oldValue, newValue in
                changes.values.append([oldValue, newValue])
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        defer { window.close() }
        await fulfillment(of: [appeared], timeout: 2)
        await action(model, changes)
    }

    private func renderChanges() async {
        // Allow SwiftUI to render while yielding the main actor to its callbacks.
        try? await Task.sleep(for: .milliseconds(100))
    }

    func testDoesNotNotifyOnAppearanceOrEqualValue() async {
        await withProbe { model, changes in
            XCTAssertEqual(changes.values.count, 0)
            model.value = 0
            await renderChanges()
            XCTAssertEqual(changes.values.count, 0)
        }
    }

    func testReportsPreviousAndNewValuesAcrossChanges() async {
        await withProbe { model, changes in
            model.value = 1
            await renderChanges()
            model.value = 2
            await renderChanges()
            XCTAssertEqual(changes.values, [[0, 1], [1, 2]])
        }
    }

    func testUnrelatedRedrawDoesNotNotifyOrLosePreviousValue() async {
        await withProbe { model, changes in
            model.unrelatedValue = 1
            await renderChanges()
            XCTAssertEqual(changes.values.count, 0)
            model.value = 2
            await renderChanges()
            XCTAssertEqual(changes.values, [[0, 2]])
        }
    }

    func testReturningToPreviousValueNotifiesAgain() async {
        await withProbe { model, changes in
            model.value = 1
            await renderChanges()
            model.value = 0
            await renderChanges()
            XCTAssertEqual(changes.values, [[0, 1], [1, 0]])
        }
    }
}
