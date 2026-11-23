import Testing
import UIKit
@testable import DuoRemote

@MainActor
struct ViewportTests {
    func make(content: CGSize = CGSize(width: 2880, height: 1800),
              bounds: CGSize = CGSize(width: 402, height: 874),
              insets: UIEdgeInsets = .zero) -> Viewport {
        var v = Viewport()
        v.setBounds(bounds, insets: insets, displayScale: 3)
        v.setContentSize(content)
        return v
    }

    @Test func fitsAndCentres() {
        let v = make()
        #expect(abs(v.scale - 402.0 / 2880) < 1e-9)
        #expect(v.isFit)
        #expect(abs(v.contentFrame.midY - 437) < 1e-6)
        #expect(abs(v.contentFrame.minX) < 1e-6)
    }

    @Test func fitUsesVisibleRect() {
        let v = make(insets: UIEdgeInsets(top: 0, left: 0, bottom: 100, right: 0))
        #expect(abs(v.contentFrame.midY - 387) < 1e-6)
    }

    @Test func fitToRectCentresUsingVisibleInsets() {
        var v = make(content: CGSize(width: 4000, height: 2000),
                     bounds: CGSize(width: 600, height: 500),
                     insets: UIEdgeInsets(top: 20, left: 30, bottom: 80, right: 10))
        let rect = CGRect(x: 2000, y: 1000, width: 2000, height: 1000)
        v.fit(to: rect)
        #expect(abs(v.scale - 0.28) < 1e-9)
        let centre = v.toView(CGPoint(x: rect.midX, y: rect.midY))
        #expect(abs(centre.x - v.visibleRect.midX) < 1e-6)
        #expect(abs(centre.y - v.visibleRect.midY) < 1e-6)
        #expect(v.isFit)
        v.setBounds(CGSize(width: 800, height: 600), insets: .zero, displayScale: 3)
        #expect(abs(v.scale - 0.4) < 1e-9)
        #expect(v.toView(CGPoint(x: rect.midX, y: rect.midY)) == CGPoint(x: 400, y: 300))
        v.zoomToFit()
        #expect(v.scale == v.fitScale)
    }

    @Test func fitToSmallRectAllowsFitBeyondPixelZoomLimitAndGestures() {
        var v = make(content: CGSize(width: 100, height: 100), bounds: CGSize(width: 400, height: 400))
        let rect = CGRect(x: 75, y: 75, width: 25, height: 25)
        v.fit(to: rect)
        #expect(v.scale == 16)
        v.pan(by: CGVector(dx: 10, dy: 10))
        #expect(!v.isFit)
        let before = v.scale
        v.zoom(by: 0.5, anchor: CGPoint(x: 200, y: 200))
        #expect(v.scale < before && v.scale >= v.fitScale)
        v.zoom(by: 2, anchor: CGPoint(x: 200, y: 200))
        #expect(v.scale == before)
    }

    @Test func fitToRectWaitsForCanvasBounds() {
        var v = Viewport()
        v.setContentSize(CGSize(width: 2000, height: 1000))
        v.fit(to: CGRect(x: 1000, y: 0, width: 1000, height: 1000))
        v.setBounds(CGSize(width: 400, height: 600), insets: .zero, displayScale: 3)
        #expect(abs(v.scale - 0.4) < 1e-9)
        #expect(v.toView(CGPoint(x: 1500, y: 500)) == CGPoint(x: 200, y: 300))
    }

    @Test func fitToRectClipsAndIgnoresEmptyRects() {
        var v = make()
        v.fit(to: CGRect(x: -100, y: -100, width: 200, height: 200))
        #expect(abs(v.scale - 4.02) < 1e-9)
        let before = v
        v.fit(to: .zero)
        #expect(v == before)
    }

    @Test func mappingRoundTrips() {
        var v = make()
        v.zoom(by: 3, anchor: CGPoint(x: 100, y: 300))
        let p = CGPoint(x: 1234, y: 567)
        let back = v.toContent(v.toView(p))
        #expect(abs(back.x - p.x) < 1e-6 && abs(back.y - p.y) < 1e-6)
    }

    @Test func zoomKeepsAnchorOverSameContent() {
        var v = make()
        let anchor = CGPoint(x: 200, y: 437)
        let before = v.toContent(anchor)
        v.zoom(by: 2, anchor: anchor)
        let after = v.toContent(anchor)
        #expect(abs(before.x - after.x) < 1e-6 && abs(before.y - after.y) < 1e-6)
        #expect(!v.isFit)
    }

    @Test func zoomIsClampedToRange() {
        var v = make()
        v.zoom(by: 0.1, anchor: .zero)
        #expect(abs(v.scale - v.fitScale) < 1e-9)
        v.zoom(by: 1000, anchor: .zero)
        #expect(abs(v.scale - 4.0 / 3) < 1e-9)
    }

    @Test func panIsClampedToContent() {
        var v = make()
        v.zoom(by: 4, anchor: .zero)
        v.pan(by: CGVector(dx: 10_000, dy: 10_000))
        #expect(v.contentFrame.minX == 0 && v.contentFrame.minY == 0)
        v.pan(by: CGVector(dx: -100_000, dy: -100_000))
        #expect(abs(v.contentFrame.maxX - 402) < 1e-6 && abs(v.contentFrame.maxY - 874) < 1e-6)
    }

    @Test func followKeepsPointerVisible() {
        var v = make()
        v.zoom(by: 6, anchor: .zero)
        let p = CGPoint(x: 2800, y: 1700)
        v.follow(p)
        let vp = v.toView(p)
        #expect(vp.x <= 402 - 24 + 1e-6 && vp.y <= 874 - 24 + 1e-6)
    }

    @Test func resizeKeepsCentreAndFit() {
        var v = make()
        v.setBounds(CGSize(width: 874, height: 402), insets: .zero, displayScale: 3)
        #expect(v.isFit && abs(v.scale - 402.0 / 1800) < 1e-9)

        v.zoom(by: 3, anchor: CGPoint(x: 437, y: 201))
        let centre = v.toContent(CGPoint(x: 437, y: 201))
        v.setBounds(CGSize(width: 600, height: 400), insets: .zero, displayScale: 3)
        let after = v.toContent(CGPoint(x: 300, y: 200))
        #expect(abs(centre.x - after.x) < 1 && abs(centre.y - after.y) < 1)
    }
}
