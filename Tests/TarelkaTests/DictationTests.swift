import Testing
@testable import Tarelka

struct DictationTests {
    @Test func pauseDoesNotReplaceEarlierProducts() {
        var speech = DictationTranscript()
        speech.update("Картошка", start: 0.3, end: 1.0, completed: true)
        speech.update("Яйцо", start: 4.0, end: 4.6, completed: false)
        #expect(speech.text == "Картошка, Яйцо")
        speech.update("Яйцо и сыр", start: 4.0, end: 6.0, completed: true)
        #expect(speech.text == "Картошка, Яйцо и сыр")
    }
    @Test func partialCorrectionsReplaceInsteadOfDuplicating() {
        var speech = DictationTranscript()
        speech.update("Кар", start: 0, end: 0, completed: false)
        speech.update("Картошка", start: 0.4, end: 1, completed: false)
        speech.update("Картошка два яйца", start: 0.4, end: 2, completed: true)
        speech.update("Картошка, два яйца", start: 0.4, end: 2, completed: true)
        #expect(speech.text == "Картошка, два яйца")
    }
    @Test func punctuationRevisionAtZeroTimestampDoesNotDuplicate() {
        var speech = DictationTranscript()
        speech.update("Картошка два яйца", start: 0, end: 2, completed: true)
        speech.update("Картошка, два яйца.", start: 0, end: 2, completed: true)
        #expect(speech.text == "Картошка, два яйца.")
    }
    @Test @MainActor func resetClearsOldSessionWithoutStartingMicrophone() {
        let speech = SpeechInput()
        speech.reset()
        #expect(!speech.recording && !speech.requesting)
        #expect(speech.transcript.isEmpty && speech.elapsed == 0 && speech.activity.level == 0)
    }
    @Test func repeatedProductAfterPauseIsNotLost() {
        var speech = DictationTranscript()
        speech.update("Яйцо", start: 1, end: 2, completed: true)
        speech.update("Яйцо", start: 4, end: 5, completed: true)
        #expect(speech.text == "Яйцо, Яйцо")
    }
    @Test func restartedRecognizerPreservesList() {
        var speech = DictationTranscript()
        speech.update("Картошка", start: 0, end: 1, completed: true)
        speech.finishUtterance()
        speech.update("Яйцо", start: 0, end: 0, completed: false)
        speech.update("", start: nil, end: nil, completed: false)
        #expect(speech.text == "Картошка, Яйцо")
    }
    @Test func timestampResetAfterCompletedPhrasePreservesIt() {
        var speech = DictationTranscript()
        speech.update("Картошка", start: 0.5, end: 2, completed: true)
        speech.update("Яйцо", start: 0, end: 0, completed: false)
        #expect(speech.text == "Картошка, Яйцо")
    }
}
