import XCTest

final class TTSUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }


    /// Test that the library loads with the pre-installed book
    func testLibraryLoadsBook() throws {
        // The library should show the book after auto-scanning
        let bookGrid = app.scrollViews.firstMatch
        XCTAssertTrue(bookGrid.waitForExistence(timeout: 15), "Book grid should be visible")

        // There should be at least one book card
        let bookCards = bookGrid.otherElements.allElementsBoundByIndex
        XCTAssertTrue(bookCards.count >= 1, "At least one book should be in the library")
    }

    /// Test opening a book and accessing TTS controls
    func testOpenBookAndShowTTSControls() throws {
        // Wait for the library to load and scan for books
        let bookGrid = app.scrollViews.firstMatch
        XCTAssertTrue(bookGrid.waitForExistence(timeout: 15), "Book grid should be visible")

        // Tap on the first book to open it
        let firstCard = bookGrid.images.firstMatch
        if firstCard.exists {
            firstCard.tap()
        } else {
            // Try tapping the first element in the grid
            let firstElement = bookGrid.otherElements.firstMatch
            XCTAssertTrue(firstElement.exists, "Should have a book to tap")
            firstElement.tap()
        }

        // Wait for the reader to load
        sleep(3)

        // The TTS control panel should appear at the bottom of the reader
        // Look for the play button
        let playButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'play' OR label CONTAINS 'Play' OR identifier CONTAINS 'play'")
        ).firstMatch

        // Alternatively, check for any button with the play.circle.fill icon
        let allButtons = app.buttons.allElementsBoundByIndex
        var foundPlayButton = false
        for button in allButtons {
            // In SwiftUI, buttons with SFSymbols may have specific labels
            if button.label.lowercased().contains("play") ||
                button.label.lowercased().contains("pause") {
                foundPlayButton = true
                break
            }
        }

        // The TTS panel should be visible with playback controls
        // Check for backward/forward buttons as well
        let backwardButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'backward'")
        ).firstMatch

        let forwardButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'forward'")
        ).firstMatch

        // At minimum, the reader should have loaded and show some content
        // The TTS panel buttons should exist
        XCTAssertTrue(
            foundPlayButton || playButton.exists || backwardButton.exists || forwardButton.exists,
            "TTS control buttons should be visible in the reader"
        )
    }

    /// Test TTS playback by pressing the play button
    func testTTSPlayback() throws {
        // Wait for library
        let bookGrid = app.scrollViews.firstMatch
        XCTAssertTrue(bookGrid.waitForExistence(timeout: 15), "Book grid should be visible")

        // Open the first book
        let firstElement = bookGrid.images.firstMatch.exists
            ? bookGrid.images.firstMatch
            : bookGrid.otherElements.firstMatch

        guard firstElement.exists else {
            XCTFail("No book available to open")
            return
        }
        firstElement.tap()

        // Wait for the book to load (Kokoro model is ~325MB)
        sleep(15)

        // Find and tap the play button to start TTS
        // The play button is the large play.circle.fill button
        let playButtonQuery = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'play' OR label CONTAINS[cd] 'pause'")
        )

        if playButtonQuery.firstMatch.exists {
            playButtonQuery.firstMatch.tap()

            // Wait for TTS model to load (Kokoro ~325MB model needs more time)
            sleep(10)

            // After tapping play, the state should change to playing
            // The button should now show as pause
            let pauseButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[cd] 'pause'")
            ).firstMatch

            // Verify the button changed state (play -> pause)
            // Increased timeout for TTS model initialization
            let pauseAppeared = pauseButton.waitForExistence(timeout: 20)
            XCTAssertTrue(pauseAppeared, "After pressing play, the pause button should appear indicating TTS is playing")

            // Now press pause
            pauseButton.tap()
            sleep(1)

            // The play button should appear again
            let playButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[cd] 'play'")
            ).firstMatch
            XCTAssertTrue(playButton.waitForExistence(timeout: 5), "After pausing, the play button should reappear")
        } else {
            // Try to find buttons by index - the play button is the center one
            let buttons = app.buttons.allElementsBoundByIndex
            if buttons.count >= 3 {
                // The play/pause button is typically the middle one in the TTS panel
                buttons[buttons.count / 2].tap()
                sleep(3)
            }
        }
    }
}
