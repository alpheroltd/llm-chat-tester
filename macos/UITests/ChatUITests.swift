import XCTest

/// Smoke tests against the real app and the local Ollama.
final class ChatUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // UserDefaults argument domain: skip onboarding and pin settings for reproducible replies.
        app.launchArguments += ["-tab", "Chat", "-hasCompletedOnboarding", "YES", "-temperature", "0", "-seed", "42", "-systemPrompt", "",
                                "-sessionsPath", NSTemporaryDirectory() + "uitest-sessions-\(UUID().uuidString)", "-mode", "Free chat",
                                "-completedMissions", "()", "-beatenLevels", "()",
                                "-testCasesPath", NSTemporaryDirectory() + "uitest-\(UUID().uuidString).json"]
        app.launch()
        XCTAssertTrue(app.buttons["send"].waitForExistence(timeout: 10), "chat composer should appear")
    }

    private func send(_ text: String) {
        let input = app.textFields["prompt-input"]
        input.click()
        input.typeText(text)
        input.typeKey(.return, modifierFlags: [])
    }

    /// The last reply finished streaming once its Run ×5 link appears (link-style buttons are exposed as links).
    private func waitForReply(count: Int, timeout: TimeInterval = 60) {
        let predicate = NSPredicate(format: "count >= %d", count)
        let done = expectation(for: predicate, evaluatedWith: app.descendants(matching: .any).matching(identifier: "rerun-reply"))
        wait(for: [done], timeout: timeout)
    }

    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testOllamaConnectedAndModelSelected() {
        let status = app.descendants(matching: .any)["status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let connected = NSPredicate(format: "label CONTAINS 'Ollama connected' OR value CONTAINS 'Ollama connected'")
        let anyConnected = app.staticTexts.containing(connected).firstMatch
        XCTAssertTrue(anyConnected.waitForExistence(timeout: 10), "status should say Ollama connected")
        // At the minimum window size, the model picker and tabs must be on screen (not in a toolbar overflow menu).
        XCTAssertTrue(app.descendants(matching: .any)["model-select"].isHittable, "model picker should be visible")
        let tabs = app.descendants(matching: .any)["tabs"]
        XCTAssertTrue(tabs.exists && tabs.isHittable, "Chat / Test cases / LLM-as-a-judge tabs should be visible")
        tabs.radioButtons["LLM-as-a-judge"].click()
        XCTAssertTrue(app.buttons["judge-run"].waitForExistence(timeout: 5), "switching tabs should work")
        tabs.radioButtons["Chat"].click()
        attachScreenshot("layout")
    }

    func testReplyStreamsWithStats() {
        send("What is the capital of France? Answer in one word.")
        waitForReply(count: 1)
        let reply = app.staticTexts.matching(identifier: "message-assistant").element(boundBy: 0)
        XCTAssertTrue(text(of: reply).localizedCaseInsensitiveContains("paris"), "got: \(text(of: reply))")
        let meta = app.staticTexts.matching(identifier: "message-meta").element(boundBy: 0)
        XCTAssertTrue(text(of: meta).contains("tok/s"), "got: \(text(of: meta))")
        XCTAssertTrue(text(of: meta).contains("seed 42"), "got: \(text(of: meta))")
        attachScreenshot("reply")
    }

    func testHTMLIsShownVerbatim() {
        let odd = "<script>alert('xss')</script> Hello! <b>bold?</b>"
        send(odd)
        let user = app.staticTexts.matching(identifier: "message-user").element(boundBy: 0)
        XCTAssertTrue(user.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: user), odd)
        waitForReply(count: 1)
    }

    func testRunFiveTimesWithFixedSeedGivesOneAnswer() {
        send("Write a one-sentence tagline for a coffee shop.")
        waitForReply(count: 1)
        app.descendants(matching: .any).matching(identifier: "rerun-reply").element(boundBy: 0).click()
        // The summary is the disclosure's label, which accessibility folds into the disclosure control,
        // so find it by content. Only compare `label` across all elements: some `value`s are numbers
        // (slider, radio buttons) and a string CONTAINS on them throws inside the app and crashes it.
        let byLabel = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'unique answer'"))
        let byValue = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'unique answer'"))
        let deadline = Date().addingTimeInterval(120)
        while byLabel.count == 0 && byValue.count == 0 && Date() < deadline { sleep(1) }
        let element = byLabel.count > 0 ? byLabel.element(boundBy: 0) : byValue.element(boundBy: 0)
        XCTAssertTrue(element.exists, "Run ×5 never finished")
        let summary = text(of: element)
        XCTAssertTrue(summary.hasPrefix("1 unique answer out of 5"), "got: \(summary)")
        attachScreenshot("run-x5")
    }
}
