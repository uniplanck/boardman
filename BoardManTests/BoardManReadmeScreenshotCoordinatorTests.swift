import Testing
@testable import Board_Man

@Suite
struct BoardManReadmeScreenshotCoordinatorTests {
    @Test
    func requestParsingIsDeterministic() throws {
        #expect(BoardManReadmeScreenshotCoordinator.request(environment: [:]) == nil)
        #expect(BoardManReadmeScreenshotCoordinator.request(environment: [
            "BOARDMAN_SCREENSHOT_OUTPUT": ""
        ]) == nil)

        let request = try #require(BoardManReadmeScreenshotCoordinator.request(environment: [
            "BOARDMAN_SCREENSHOT_OUTPUT": "/tmp/boardman/readme.png",
            "BOARDMAN_SCREENSHOT_SCENE": "TeMpLaTeS",
            "BOARDMAN_SCREENSHOT_WIDTH": "960",
            "BOARDMAN_SCREENSHOT_HEIGHT": "720"
        ]))
        #expect(request.outputPath == "/tmp/boardman/readme.png")
        #expect(request.scene == "templates")
        #expect(request.width == 960)
        #expect(request.height == 720)

        let defaultScene = try #require(BoardManReadmeScreenshotCoordinator.request(environment: [
            "BOARDMAN_SCREENSHOT_OUTPUT": "/tmp/default.png",
            "BOARDMAN_SCREENSHOT_WIDTH": "not-a-number"
        ]))
        #expect(defaultScene.scene == "history")
        #expect(defaultScene.width == nil)
        #expect(defaultScene.height == nil)
    }
}
