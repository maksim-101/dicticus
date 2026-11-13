# Unit-test evidence for criteria 1 and 2 (verify, 2026-11-13, commit 4ecc40e)

Scheme Dicticus-Debug-Recorder, `xcodebuild … -derivedDataPath build … test`, full run (the three classes below are part of it). Suite summaries from the same run and the Dicticus scheme follow the test lines.

```
Test Case '-[DicticusTests.AppCategoryReaderTests testBundleWithoutKeyGivesNil]' passed.
Test Case '-[DicticusTests.AppCategoryReaderTests testCorruptPlistIsNotCached]' passed.
Test Case '-[DicticusTests.AppCategoryReaderTests testEachBundleIsReadOnce]' passed.
Test Case '-[DicticusTests.AppCategoryReaderTests testFlatBundleIsRead]' passed.
Test Case '-[DicticusTests.AppCategoryReaderTests testNilAppGivesNil]' passed.
Test Case '-[DicticusTests.AppCategoryReaderTests testReadsDeclaredCategory]' passed.
Test Case '-[DicticusTests.AppCategoryReaderTests testUnreadablePlistIsNotCached]' passed.
Test Case '-[DicticusTests.ContextResolverTests testDeveloperToolsCategoryResolvesToCodeForAnyBundleID]' passed.
Test Case '-[DicticusTests.ContextResolverTests testDisabledShortCircuitsEvenWithCodeBundleID]' passed.
Test Case '-[DicticusTests.ContextResolverTests testDisabledShortCircuitsEvenWithPin]' passed.
Test Case '-[DicticusTests.ContextResolverTests testFallbackAppliesWhenNoPinOrOverride]' passed.
Test Case '-[DicticusTests.ContextResolverTests testFullPrecedenceChain]' passed.
Test Case '-[DicticusTests.ContextResolverTests testIsEnabledDefaultsTrueOnAbsentKey]' passed.
Test Case '-[DicticusTests.ContextResolverTests testIsEnabledReadsExplicitFalse]' passed.
Test Case '-[DicticusTests.ContextResolverTests testIsEnabledReadsExplicitTrue]' passed.
Test Case '-[DicticusTests.ContextResolverTests testLoadGuardedAbsentKeyReturnsEmptyAndDoesNotSuppress]' passed.
Test Case '-[DicticusTests.ContextResolverTests testLoadGuardedGenuinelyEmptyDecodedMapDoesNotSuppressSeed]' passed.
Test Case '-[DicticusTests.ContextResolverTests testLoadGuardedPresentButUnreadableBlobSuppressesSeed]' passed.
Test Case '-[DicticusTests.ContextResolverTests testOtherCategoriesResolveToDefault]' passed.
Test Case '-[DicticusTests.ContextResolverTests testOverrideBeatsDeveloperToolsCategory]' passed.
Test Case '-[DicticusTests.ContextResolverTests testOverrideBeatsTerminalFallback]' passed.
Test Case '-[DicticusTests.ContextResolverTests testPinBeatsOverride]' passed.
Test Case '-[DicticusTests.ContextResolverTests testPresentButUnreadableBlobIsPreservedInBackupOnNextSave]' passed.
Test Case '-[DicticusTests.ContextResolverTests testSaveCopiesPriorBlobToBackupKeyBeforeOverwriting]' passed.
Test Case '-[DicticusTests.ContextResolverTests testSaveDoesNotWriteBackupWhenBlobUnchanged]' passed.
Test Case '-[DicticusTests.ContextResolverTests testSaveThenLoadRoundTripsOverrides]' passed.
Test Case '-[DicticusTests.ContextResolverTests testTerminalFallbackAppliesWhenCategorySaysOtherwise]' passed.
Test Case '-[DicticusTests.ContextResolverTests testUnknownAndNilBundleIDOrCategoryResolveToDefault]' passed.
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
```

Suite summaries:

```
Dicticus-Debug-Recorder: 	 Executed 2035 tests, with 8 tests skipped and 0 failures (0 unexpected) in 138.720 (139.132) seconds
Dicticus:                	 Executed 1956 tests, with 7 tests skipped and 0 failures (0 unexpected) in 138.400 (138.838) seconds
```
