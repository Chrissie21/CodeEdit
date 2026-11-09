//
//  TerminalScrollerLayoutTests.swift
//  CodeEditTests
//

import AppKit
import XCTest
@testable import CodeEdit

@MainActor
final class TerminalScrollerLayoutTests: XCTestCase {
    private final class TrackingTerminalView: CETerminalView {
        var scrollerAttachments = 0

        override func didAddSubview(_ subview: NSView) {
            super.didAddSubview(subview)
            if subview is NSScroller {
                scrollerAttachments += 1
            }
        }
    }

    func testRepeatedResizeDoesNotReattachFrontmostScroller() async throws {
        _ = NSApplication.shared
        let terminal = TrackingTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        terminal.setFrameSize(NSSize(width: 650, height: 320))
        let attachments = terminal.scrollerAttachments
        let scroller = try XCTUnwrap(terminal.subviews.compactMap { $0 as? NSScroller }.first)

        for _ in 0..<5 {
            terminal.setFrameSize(NSSize(width: 650, height: 320))
        }

        XCTAssertEqual(terminal.scrollerAttachments, attachments)
        XCTAssertTrue(scroller.superview === terminal)
        XCTAssertTrue(terminal.subviews.last === scroller)
    }

    func testActualResizeUpdatesScrollerGeometryWithoutReattaching() async throws {
        _ = NSApplication.shared
        let terminal = TrackingTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        terminal.setFrameSize(NSSize(width: 650, height: 320))
        let attachments = terminal.scrollerAttachments
        let scroller = try XCTUnwrap(terminal.subviews.compactMap { $0 as? NSScroller }.first)

        terminal.setFrameSize(NSSize(width: 800, height: 400))

        XCTAssertEqual(terminal.scrollerAttachments, attachments)
        XCTAssertEqual(scroller.frame.maxX, terminal.bounds.maxX)
        XCTAssertEqual(scroller.frame.height, terminal.bounds.height)
        XCTAssertEqual(terminal.subviews.filter { $0 is NSScroller }.count, 1)
    }

    func testScrollerCanStillBeMovedAboveAnotherSubview() async throws {
        _ = NSApplication.shared
        let terminal = TrackingTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let scroller = try XCTUnwrap(terminal.subviews.compactMap { $0 as? NSScroller }.first)
        terminal.addSubview(NSView(frame: terminal.bounds))
        let attachments = terminal.scrollerAttachments

        terminal.addSubview(scroller)
        XCTAssertTrue(terminal.subviews.last === scroller)
        XCTAssertEqual(terminal.scrollerAttachments, attachments + 1)

        terminal.addSubview(scroller)
        XCTAssertEqual(terminal.scrollerAttachments, attachments + 1)
    }
}
