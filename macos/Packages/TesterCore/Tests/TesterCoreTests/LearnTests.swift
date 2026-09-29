import Foundation
import Testing
@testable import TesterCore

@Suite struct MarkdownParserTests {
    @Test func parsesBlocks() {
        let md = """
        # Title

        Intro line one
        continues here with **bold**.

        ## Section
        - first
        - second
          wraps
        1. one
        2) two

        > **Tip:** a tip
        > more tip

        ```swift
        let x = 1

        print(x)
        ```

        ![A diagram](images/d.png)

        ---
        """
        let blocks = MarkdownParser.parse(md)
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("Intro line one continues here with **bold**."),
            .heading(level: 2, text: "Section"),
            .bullets(["first", "second wraps"]),
            .numbered(["one", "two"]),
            .quote("**Tip:** a tip\nmore tip"),
            .code(language: "swift", text: "let x = 1\n\nprint(x)"),
            .image(alt: "A diagram", path: "images/d.png"),
            .divider,
        ])
        #expect(MarkdownParser.imagePaths(in: md) == ["images/d.png"])
    }

    @Test func unclosedCodeFenceAndHashesWithoutSpace() {
        #expect(MarkdownParser.parse("```\ncode") == [.code(language: "", text: "code")])
        #expect(MarkdownParser.parse("#hashtag") == [.paragraph("#hashtag")])
    }
}

@Suite struct LearnContentTests {
    @Test func bundledCourseHasNoProblems() {
        let problems = ContentLint.problems(in: Content.learnDirectory)
        #expect(problems.isEmpty, "Learn content problems:\n\(problems.joined(separator: "\n"))")
    }

    @Test func bundledCourseLoadsInOrder() {
        let learn = Content.learn
        #expect(learn.course.modules.count == 9)
        #expect(learn.orderedLessons.count == 9)
        #expect(learn.orderedLessons.first?.id == "how-llms-work")
        #expect(learn.lesson(after: "how-llms-work")?.id == "testing-is-different")
        #expect(learn.lesson(after: "reporting-bugs") == nil)
        #expect(!learn.body(ofLesson: "how-llms-work").isEmpty)
        #expect(learn.glossary.count >= 20)
        #expect(!learn.body(ofCheatSheet: "chatbot-test-checklist").isEmpty)
        #expect(learn.orderedLessons.filter { !$0.quiz.isEmpty }.count == 2)
    }

    @Test func everyMissionBotAndExerciseIsPractisedSomewhere() {
        let links = Content.learn.orderedLessons.flatMap(\.practice)
        let missions = Set(links.filter { $0.kind == .mission }.compactMap(\.id))
        let exercises = Set(links.filter { $0.kind == .judgeExercise }.compactMap(\.id))
        #expect(missions == Set(Content.missions.map(\.id)), "missions without a lesson: \(Set(Content.missions.map(\.id)).subtracting(missions))")
        #expect(exercises == Set(Content.judgeExercises.map(\.id)), "exercises without a lesson: \(Set(Content.judgeExercises.map(\.id)).subtracting(exercises))")
        #expect(links.contains { $0.kind == .bot })
    }

    @Test func lintCatchesAuthorMistakes() throws {
        let fixture = try #require(Bundle.module.url(forResource: "Fixtures/broken-course", withExtension: nil))
        let problems = ContentLint.problems(in: fixture)
        let expected = [
            "module id \"m1\" is used more than once",
            "lesson \"good\" is listed more than once",
            "lessons/missing.json: missing",
            "key term \"unknown-term\" isn't in glossary.json",
            "no mission with id \"no-such-mission\"",
            "no bot with id \"shopbot-9\"",
            "\"answer\" is 3 but must be 0–1",
            "two options are identical",
            "\"minutes\" must be at least 1",
            "image \"images/missing.png\" not found",
            "seeAlso \"nope\"",
            "cheatsheets/absent.md: missing",
        ]
        for fragment in expected {
            #expect(problems.contains { $0.contains(fragment) }, "expected a problem mentioning: \(fragment)\nGot:\n\(problems.joined(separator: "\n"))")
        }
    }
}
