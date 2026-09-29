import XCTest

final class LearnUITests: XCTestCase {
    private var app: XCUIApplication!
    private let resetProgress = ["-learnLessonsRead", "()", "-learnQuizScores", "{}"]

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-tab", "Learn", "-learnLesson", "how-llms-work", "-hasCompletedOnboarding", "YES",
                                "-sessionsPath", NSTemporaryDirectory() + "uitest-sessions-\(UUID().uuidString)", "-mode", "Free chat",
                                "-completedMissions", "()", "-beatenLevels", "()", "-selectedBotID", "shopbot-2",
                                "-testCasesPath", NSTemporaryDirectory() + "uitest-\(UUID().uuidString).json"] + resetProgress
        app.launch()
        XCTAssertTrue(any("learn-outline").waitForExistence(timeout: 10), "Learn tab should open")
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    /// Scrolls the lesson reader until the element is on screen (macOS UI tests don't auto-scroll).
    @discardableResult
    private func reveal(_ element: XCUIElement) -> XCUIElement {
        let reader = app.scrollViews.containing(.any, identifier: "learn-body").firstMatch
        for _ in 0..<25 where !(element.exists && element.isHittable) { reader.scroll(byDeltaX: 0, deltaY: -150) }
        return element
    }

    private func openLesson(_ id: String) {
        any("learn-lesson-\(id)").click()
        XCTAssertTrue(any("learn-body").waitForExistence(timeout: 5))
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLearnIsFirstTabAndRendersALesson() {
        let tabs = any("tabs")
        XCTAssertEqual(tabs.radioButtons.firstMatch.label, "Learn", "Learn should be the first tab")
        XCTAssertFalse(app.popUpButtons["model-select"].isHittable, "the chat sidebar is collapsed while reading")
        XCTAssertTrue(app.staticTexts["What an LLM actually does"].exists, "## headings should render")
        XCTAssertTrue(any("learn-draft-banner").exists, "sample lessons are marked draft")
        // Only horizontal clipping matters: a scrolling list's frame includes rows below the fold.
        let window = app.window, outline = any("learn-outline").frame, body = any("learn-body").frame
        XCTAssertTrue(outline.minX >= window.minX - 1 && body.maxX <= window.maxX + 1,
                      "Learn layout is wider than the window: outline \(outline), body \(body), window \(window)")
        attachScreenshot("learn-lesson")
    }

    func testQuizScoresAndProgressSurviveARelaunch() {
        let answers = [1, 1, 2, 0] // correct option per question in how-llms-work.json
        let options = app.buttons.matching(identifier: "quiz-option")
        reveal(options.element(boundBy: 0))
        for (question, answer) in answers.enumerated() {
            reveal(options.element(boundBy: question * 4 + answer)).click()
        }
        reveal(app.buttons["quiz-check"]).click()
        XCTAssertEqual(text(of: reveal(any("quiz-score"))), "4 of 4 correct")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "quiz-explanation").count, 4)
        reveal(app.buttons["learn-mark-read"]).click()
        XCTAssertTrue(text(of: any("learn-progress")).contains("1 of 9 lessons read · quiz average 100%"),
                      "got: \(text(of: any("learn-progress")))")
        attachScreenshot("learn-quiz")

        // Relaunch without resetting progress: it must still be there.
        app.terminate()
        app.launchArguments = Array(app.launchArguments.dropLast(resetProgress.count))
        app.launch()
        XCTAssertTrue(any("learn-progress").waitForExistence(timeout: 10))
        XCTAssertTrue(text(of: any("learn-progress")).contains("quiz average 100%"), "got: \(text(of: any("learn-progress")))")
    }

    func testPracticeOpensMissionBotAndJudgeExercise() {
        // Mission
        reveal(app.buttons["Mission: Same question, different answers?"]).click()
        XCTAssertTrue(app.popUpButtons["mission-select"].waitForExistence(timeout: 5), "should open Chat in Missions mode")
        XCTAssertTrue(text(of: app.popUpButtons["mission-select"]).contains("Same question"))

        // Target bot
        any("tabs").radioButtons["Learn"].click()
        openLesson("prompt-injection")
        reveal(app.buttons["Target bot: ShopBot level 1"]).click()
        XCTAssertTrue(any("level-1").waitForExistence(timeout: 5))
        XCTAssertTrue(any("level-1").isSelected, "level 1 should be selected")

        // Judge exercise
        any("tabs").radioButtons["Learn"].click()
        openLesson("hallucination")
        reveal(app.buttons["Judge exercise: Confidently wrong"]).click()
        XCTAssertTrue(app.textViews["judge-reply"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(of: app.textViews["judge-reply"]).contains("1971"), "the exercise should be loaded")
    }

    func testGlossarySearchAndCheatSheetExport() {
        any("learn-glossary").click()
        let entries = app.descendants(matching: .any).matching(identifier: "glossary-entry")
        XCTAssertTrue(entries.firstMatch.waitForExistence(timeout: 5))
        let all = entries.count
        XCTAssertGreaterThanOrEqual(all, 20)
        let search = app.textFields["glossary-search"]
        search.click()
        search.typeText("seed")
        XCTAssertTrue(entries.count < all && entries.count >= 1, "search should filter (\(entries.count) of \(all))")
        attachScreenshot("learn-glossary")

        any("learn-cheatsheet-chatbot-test-checklist").click()
        app.buttons["cheatsheet-export"].click()
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "Export should open a save panel")
        panel.buttons["Cancel"].click()
    }
}

private extension XCUIApplication {
    var window: CGRect { windows.firstMatch.frame }
}
