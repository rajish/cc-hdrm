import Testing
@testable import cc_hdrm

@Suite("BenchmarkSectionView Tests")
@MainActor
struct BenchmarkSectionViewTests {

    @Test("Default benchmark models are sonnet then fable, in that order")
    func defaultModelsAreSonnetThenFable() {
        #expect(BenchmarkSectionView.defaultModels == ["claude-sonnet-4-6", "claude-fable-5"])
    }

    @Test("Empty stored models fall back to the defaults")
    func emptyStoredModelsUseDefaults() {
        #expect(BenchmarkSectionView.resolveModels(stored: []) == ["claude-sonnet-4-6", "claude-fable-5"])
    }

    @Test("Stored models take precedence over the defaults")
    func storedModelsWin() {
        #expect(BenchmarkSectionView.resolveModels(stored: ["claude-opus-4-6"]) == ["claude-opus-4-6"])
    }

    @Test("Benchmark cost copy states that Fable requests consume the Fable weekly cap")
    func fableCapNoteMentionsCap() {
        #expect(BenchmarkSectionView.fableCapNote.contains("Fable"))
        #expect(BenchmarkSectionView.fableCapNote.localizedCaseInsensitiveContains("weekly cap"))
    }

    @Test("The explanation says why Measure is gone")
    func noFiveHourNoteExplains() {
        #expect(BenchmarkSectionView.noFiveHourNote.contains("5-hour number"))
    }

    @Test("Earlier cards return only when the number is gone and the run finished nothing")
    func resultsAfterRun() {
        let earlier = [BenchmarkVariantResult(model: "earlier", variant: .outputHeavy, measurement: nil, inconclusive: true, retryCount: 3)]
        let newer = [BenchmarkVariantResult(model: "newer", variant: .outputHeavy, measurement: nil, inconclusive: true, retryCount: 3)]

        #expect(BenchmarkSectionView.resultsAfterRun(returned: [], previous: earlier, hasFiveHourNumber: false) == earlier)
        #expect(BenchmarkSectionView.resultsAfterRun(returned: newer, previous: earlier, hasFiveHourNumber: false) == newer)
        #expect(BenchmarkSectionView.resultsAfterRun(returned: [], previous: earlier, hasFiveHourNumber: true).isEmpty)
        #expect(BenchmarkSectionView.resultsAfterRun(returned: newer, previous: earlier, hasFiveHourNumber: true) == newer)
    }

    @Test("Empty trend text points at Measure only for accounts with a number")
    func emptyStateWording() {
        #expect(TPPSectionView.emptyStateText(hasNoFiveHourNumber: false).contains("Measure button"))
        #expect(TPPSectionView.emptyStateText(hasNoFiveHourNumber: true).contains("Measure") == false)
    }
}
