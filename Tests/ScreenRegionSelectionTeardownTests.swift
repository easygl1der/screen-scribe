import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private final class RecordingOverlayWindow: RegionSelectionOverlayWindow {
    private(set) var orderOutCallCount = 0
    private(set) var prepareForReuseCallCount = 0
    private(set) var setFrameCallCount = 0
    private(set) var lastFrame: CGRect?

    func orderOut(_ sender: Any?) {
        orderOutCallCount += 1
    }

    func prepareForReuse() {
        prepareForReuseCallCount += 1
    }

    func setFrame(_ frame: CGRect, display: Bool) {
        setFrameCallCount += 1
        lastFrame = frame
    }
}

@main
struct ScreenRegionSelectionTeardownTests {
    static func main() {
        let teardown = RegionSelectionOverlayTeardown()

        let window = RecordingOverlayWindow()
        teardown.dismiss(window)

        expect(window.orderOutCallCount == 1, "dismiss should hide the overlay immediately")
        expect(window.prepareForReuseCallCount == 1, "dismiss should reset responder state for reuse")

        let presenter = RegionSelectionOverlayPresenter()
        let reusedWindow = RecordingOverlayWindow()
        let expectedFrame = CGRect(x: 10, y: 20, width: 300, height: 400)
        var factoryCallCount = 0

        let returnedWindow = presenter.prepareWindow(
            existingWindow: reusedWindow,
            frame: expectedFrame,
            makeWindow: { frame in
                factoryCallCount += 1
                let window = RecordingOverlayWindow()
                window.setFrame(frame, display: false)
                return window
            }
        )

        expect(returnedWindow === reusedWindow, "presenter should reuse the existing overlay window")
        expect(reusedWindow.setFrameCallCount == 1, "reused window should be resized for the new desktop frame")
        expect(reusedWindow.lastFrame == expectedFrame, "reused window should receive the requested frame")
        expect(factoryCallCount == 0, "presenter should not create a replacement window when one already exists")

        print("ScreenRegionSelectionTeardownTests passed")
    }
}
