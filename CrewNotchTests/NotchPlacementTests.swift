//
//  NotchPlacementTests.swift
//  CrewNotchTests
//
//  Where the notch and its panel sit along the top edge of a display.
//

import CoreGraphics
import Testing
@testable import CrewNotch

@Suite("Notch placement")
struct NotchPlacementTests {
    let screen = CGRect(x: 1512, y: 0, width: 2560, height: 1440)  // a monitor right of the MacBook
    let notch = CGSize(width: 224, height: 38)

    func geometry(_ position: CGFloat) -> NotchGeometry {
        NotchGeometry(notchSize: notch, screenRect: screen, windowHeight: 750, position: position)
    }

    @Test("The middle is the screen's center, as before positions existed")
    func middle() {
        let rect = geometry(0.5).notchScreenRect
        #expect(rect.midX == screen.midX)
        #expect(rect.maxY == screen.maxY)
    }

    @Test("The ends keep the edge margin")
    func ends() {
        #expect(geometry(0).notchScreenRect.minX == screen.minX + NotchGeometry.edgeMargin)
        #expect(geometry(1).notchScreenRect.maxX == screen.maxX - NotchGeometry.edgeMargin)
        // Out-of-range positions stay on screen
        #expect(geometry(-1).notchScreenRect == geometry(0).notchScreenRect)
        #expect(geometry(2).notchScreenRect == geometry(1).notchScreenRect)
    }

    @Test("The panel hangs centered under the notch")
    func panelCentered() {
        let panel = geometry(0.3).panelScreenRect(for: CGSize(width: 480, height: 300))
        #expect(panel.midX == geometry(0.3).notchScreenRect.midX)
        #expect(panel.maxY == screen.maxY)
    }

    @Test("A panel wider than the room beside the notch moves in from the edge")
    func panelClamped() {
        let size = CGSize(width: 900, height: 300)
        #expect(geometry(0).panelScreenRect(for: size).minX == screen.minX)
        #expect(geometry(1).panelScreenRect(for: size).maxX == screen.maxX)
    }

    @Test("Dragging to a center and back gives the same position", arguments: [0, 0.25, 0.5, 0.8, 1] as [CGFloat])
    func roundTrip(position: CGFloat) {
        let x = NotchGeometry.centerX(for: position, notchWidth: 30, screenWidth: 200, margin: 8)
        let back = NotchGeometry.position(forCenterX: x, notchWidth: 30, screenWidth: 200, margin: 8)
        #expect(abs(back - position) < 0.0001)
    }

    @Test("A screen too narrow for the margins keeps the notch in the middle")
    func narrowScreen() {
        #expect(NotchGeometry.centerX(for: 0, notchWidth: 224, screenWidth: 300) == 150)
        #expect(NotchGeometry.position(forCenterX: 10, notchWidth: 224, screenWidth: 300) == 0.5)
    }
}
