# Unit-test evidence for criteria 1 to 4 (verify, 2026-11-14)

Full run of scheme Dicticus-Debug-Recorder on f841f7c (`xcodebuild … -derivedDataPath build … test`, 2042 tests 0 failures); the classes below are part of it. The review fix 46348f5 added two cases to RulesCleanupServiceTests, rerun on scheme Dicticus: 11 tests 0 failures.

```
Test Case '-[DicticusTests.AudioRetentionProbeTests testEmptyBufferWritesNothing]' passed.
Test Case '-[DicticusTests.AudioRetentionProbeTests testPurgeRemovesWavsOlderThanSevenDaysOnly]' passed.
Test Case '-[DicticusTests.AudioRetentionProbeTests testRetainWritesAPlayableWav]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordCodableRoundTrip_AppCategory]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordCodableRoundTrip_DefaultEmpty]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordCodableRoundTrip_ExplicitPromptVersion_v19c]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordCodableRoundTrip_FinalStagePopulated]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordCodableRoundTrip_PromptVersionDefault_v19d]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordCodableRoundTrip_WithEntries]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordDecode_PreFs1_TolerantToMissingFinalStage]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordDecode_PrePhase27_TolerantToMissingDictionaryFields]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordDecode_TolerantToMissingAppCategory]' passed.
Test Case '-[DicticusTests.DebugCleanupRecordCodableTests testDebugCleanupRecordDecode_TolerantToMissingPromptVersion]' passed.
Test Case '-[DicticusTests.DebugRecorderFinalStageTests testFinalStageCapturesPostCapitalizationMutation]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testAcceptedEditsSurviveGermanSentenceFinalNumberFormChange]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testDigitValueChangeNeverReachesOutput]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testGateEntryCarriesClassifiedEdits]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testGermanWordOrderRepairSurvivesTheWholePipeline]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testHistoricalGateEntriesStillDecode]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testInjectionReplyDiscardsWholeOutput]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testNumberFormPolicy_digitToWord_en]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testNumberFormPolicy_wordToDigit_en]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testPausePeriodBecomesCommaBeforeTheGate]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testPostGateUserEntryRewritesLLMFormedKey_RED]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testReasoningLeakDiscardsWholeOutput]' passed.
Test Case '-[DicticusTests.EditGuardPipelineTests testStep3aOrdering]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testArtifactStrip_interiorYeah_preserved]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testArtifactStrip_terminalMmHmm_stripped]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testArtifactStrip_terminalYeah_stripped]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testCleanResolvesClassicSelfCorrection]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testFullyScratchedUtterancePassesThroughRulesCleanup]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testGermanScratchPhrasePassesThroughRulesCleanup]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testPausePeriod_abbreviationsNumbersAndEllipsesStay]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testPausePeriod_capitalisedContinuation_stays]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testPausePeriod_isIdempotent]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testPausePeriod_lowercaseContinuation_becomesComma]' passed.
Test Case '-[DicticusTests.RulesCleanupServiceTests testScratchPhrasePassesThroughRulesCleanup]' passed.
Test Case '-[DicticusTests.TestIsolationCanaryTests testBootstrapRan]' passed.
Test Case '-[DicticusTests.TestIsolationCanaryTests testDebugRecordingsRedirectedToTestDirectory]' passed.
Test Case '-[DicticusTests.TestIsolationCanaryTests testHostIdentityIsNotProduction]' passed.
Test Case '-[DicticusTests.TestIsolationCanaryTests testMacProbesRedirectedToTestDirectory]' passed.
Test Case '-[DicticusTests.TestIsolationCanaryTests testRealDomainUnreachable]' passed.
Test Case '-[DicticusTests.TestIsolationCanaryTests testSuiteIsEphemeral]' passed.
```

Suite summaries of that run:

```
Dicticus-Debug-Recorder: 	 Executed 2042 tests, with 8 tests skipped and 0 failures (0 unexpected) in 140.196 (140.618) seconds
Dicticus:                	 Executed 1960 tests, with 7 tests skipped and 0 failures (0 unexpected) in 170.099 (170.556) seconds
iOS simulator:           	 Executed 1780 tests, with 9 tests skipped and 0 failures (0 unexpected) in 90.256 (90.654) seconds
```

Criterion 3, the public build: `nm` on the Dicticus scheme's `Dicticus.debug.dylib` counts 0 symbols for AudioRetentionProbe, DebugRecorder and AudioCaptureProbe; the Recorder test host's counts 62, 105 and 64 (task 2 commit 6a86544).
