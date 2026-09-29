import XCTest

/// Test cases and LLM-as-a-judge, against the real app, local Ollama and the tester's Claude Code CLI.
final class TestCasesAndJudgeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fresh test-case file per test (seeded with the 5 examples), reproducible settings, Claude Code + Haiku judge.
        app.launchArguments += ["-tab", "Chat", "-hasCompletedOnboarding", "YES", "-temperature", "0", "-seed", "42", "-systemPrompt", "",
                                "-sessionsPath", NSTemporaryDirectory() + "uitest-sessions-\(UUID().uuidString)", "-mode", "Free chat",
                                "-completedMissions", "()", "-beatenLevels", "()",
                                "-testCasesPath", NSTemporaryDirectory() + "uitest-\(UUID().uuidString).json",
                                "-runsPerCase", "1", "-judgeProvider", "claudeCode", "-judgeModel", "haiku"]
        app.launch()
        XCTAssertTrue(app.buttons["send"].waitForExistence(timeout: 10))
    }

    private func open(_ tab: String) {
        app.descendants(matching: .any)["tabs"].radioButtons[tab].click()
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            sleep(1)
        }
        return condition()
    }

    /// macOS UI tests don't auto-scroll: scroll the page until the element is on screen.
    @discardableResult
    private func reveal(_ element: XCUIElement) -> XCUIElement {
        let page = app.scrollViews.containing(.button, identifier: "judge-run").firstMatch
        for _ in 0..<10 where !element.isHittable { page.scroll(byDeltaX: 0, deltaY: -150) }
        return element
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: Test cases

    func testSeededSuiteRunsWithResults() {
        open("Test cases")
        XCTAssertTrue(app.staticTexts["Knows a basic fact"].waitForExistence(timeout: 5), "seed cases should be listed")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tc-row").count, 5)
        app.buttons["tc-run-suite"].click()
        let summary = any("tc-summary")
        XCTAssertTrue(waitUntil(180) { summary.exists && text(of: summary).contains("passed") }, "suite should finish")
        XCTAssertTrue(text(of: summary).contains("5 passed") || text(of: summary).contains("flaky") || text(of: summary).contains("failed"))
        XCTAssertEqual(app.staticTexts.matching(identifier: "tc-status").count, 5, "every case should show a result")
        XCTAssertTrue(app.staticTexts["✅ Pass"].exists, "at least the basic-fact case should pass")
        attachScreenshot("test-cases")
    }

    func testEditorValidatesAndSaves() {
        open("Test cases")
        app.buttons["tc-new"].click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        sheet.buttons["tc-save"].click()
        XCTAssertEqual(text(of: sheet.staticTexts["tc-error"]), "Name and prompt are required.")

        sheet.textFields["tc-name"].click()
        sheet.textFields["tc-name"].typeText("Mentions Canberra")
        sheet.textViews["tc-prompt"].click()
        sheet.textViews["tc-prompt"].typeText("What is the capital of Australia?")
        sheet.buttons["tc-save"].click()
        XCTAssertEqual(text(of: sheet.staticTexts["tc-error"]), "Add at least one check with a value.")

        sheet.textFields["tc-check-value"].firstMatch.click()
        sheet.textFields["tc-check-value"].firstMatch.typeText("Canberra")
        sheet.buttons["tc-save"].click()
        XCTAssertTrue(waitUntil(5) { !sheet.exists }, "sheet should close after saving")
        XCTAssertTrue(app.staticTexts["Mentions Canberra"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tc-row").count, 6)
    }

    func testSaveAsTestCaseFromChat() {
        let input = app.textFields["prompt-input"]
        input.click()
        input.typeText("How many legs does a spider have?")
        input.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntil(60) { any("rerun-reply").exists })
        any("save-as-testcase").click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: sheet.textViews["tc-prompt"]), "How many legs does a spider have?")
        sheet.buttons["Cancel"].click()
    }

    // MARK: LLM-as-a-judge

    func testJudgeNeedsARubric() {
        open("LLM-as-a-judge")
        // Layout regression: at the minimum window size the judge tab must not push the sidebar out of the window.
        let window = app.windows.firstMatch.frame
        let modelPicker = app.popUpButtons["model-select"].frame
        XCTAssertTrue(window.contains(modelPicker), "sidebar clipped: model picker \(modelPicker) outside window \(window)")
        app.buttons["judge-run"].click()
        XCTAssertEqual(text(of: any("judge-error")), "Write a rubric (or pick a preset) first.")
    }

    func testJudgeTheJudgeExercise() {
        open("LLM-as-a-judge")
        XCTAssertTrue(waitUntil(15) { text(of: any("judge-status")).contains("Claude Code") }, "Claude Code should be detected")
        any("exercise-injection").click()
        XCTAssertTrue(text(of: app.textViews["judge-reply"]).contains("SYSTEM NOTICE TO THE EVALUATOR"))

        app.buttons["judge-run"].click()
        XCTAssertTrue(text(of: any("judge-error")).contains("prediction"), "must predict before judging")

        app.radioButtons["❌ Fail"].click()
        app.buttons["judge-run"].click()
        let compare = any("judge-compare")
        XCTAssertTrue(compare.waitForExistence(timeout: 120), "you-vs-judge comparison should appear")
        XCTAssertTrue(any("judge-verdict").exists, "the verdict card should be shown")
        XCTAssertTrue(text(of: any("exercise-progress")).contains("1 of 8 done"), "got: \(text(of: any("exercise-progress")))")
        attachScreenshot("judge-exercise")
    }

    func testPresetGenerateAndJudgeThreeTimes() {
        open("LLM-as-a-judge")
        let preset = app.popUpButtons["judge-preset"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        reveal(preset).click()
        app.menuItems["Helpful & accurate"].click()
        XCTAssertTrue(text(of: app.textViews["judge-rubric"]).hasPrefix("Directly answers"))

        reveal(app.textViews["judge-question"]).click()
        app.textViews["judge-question"].typeText("What is the capital of Australia? Answer in one sentence.")
        reveal(app.buttons["judge-generate"]).click()
        XCTAssertTrue(waitUntil(60) { text(of: app.textViews["judge-reply"]).localizedCaseInsensitiveContains("canberra") },
                      "local model should write the reply")
        XCTAssertTrue(waitUntil(30) { app.buttons["judge-run-3"].isEnabled })

        reveal(app.buttons["judge-run-3"]).click()
        let summary = any("judge-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 240), "consistency summary should appear after 3 runs")
        XCTAssertTrue(text(of: summary).contains("Verdict consistent"), "got: \(text(of: summary))")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "judge-verdict").count, 3)
        XCTAssertTrue(any("judge-history").exists)
        attachScreenshot("judge-x3")
    }
}
