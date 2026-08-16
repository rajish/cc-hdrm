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
}
