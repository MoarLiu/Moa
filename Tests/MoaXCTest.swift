#if !MOA_TESTING
import XCTest
@testable import Moa

final class MoaXCTest: XCTestCase {
    private var pricingHome: URL?
    override func setUp() {
        super.setUp()
        MoaRuntimeMode.suppressesUserInteraction = true
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("moa-test-pricing-\(UUID().uuidString)")
        pricingHome = home
        MoaUsagePricing.useRemoteCatalogStoreForTesting(.init(environment: ["HOME": home.path]))
    }

    override func tearDown() {
        MoaUsagePricing.resetRemoteCatalogStoreForTesting()
        if let pricingHome { try? FileManager.default.removeItem(at: pricingHome) }
        super.tearDown()
    }

    private func run(_ name: String) throws {
        guard let entry = MoaCoreTests.tests.first(where: { $0.0 == name }) else {
            XCTFail("Missing check: " + name)
            return
        }
        try entry.1()
    }

    func testNativeDiscoveryMatchesTheCheckRegistry() {
        let expected: Set<String> = [
            "deleting a stale official selection keeps the unsaved live login",
            "official account deletion follows the live file including saved and signed-out sessions",
            "Codex profile edits recheck selection inside the store lock",
            "Claude profile edits recheck selection inside the store lock",
            "Grok Build aliases and Fast context rates price local usage",
            "full pricing downloads preserve all records and accept new model IDs",
            "pricing commits immediately invalidate independent catalog caches",
            "manual price updates coalesce and reprice unchanged downloads",
            "failed price downloads keep prior catalogs and custom prices",
            "stopping price updates releases requests and suppresses stale callbacks",
            "new remote models reprice unchanged WorkBuddy logs without a release",
            "DeepSeek edits only the account grant in Harness YAML",
            "DeepSeek rejects ambiguous and unsupported credential formats",
            "DeepSeek saves after quit and manages saved account copies",
            "DeepSeek account enrollment and switching preserve other credentials",
            "DeepSeek launch failures restore only the previous account grant",
            "DeepSeek credential writes respect process locks and stopped clients",
            "DeepSeek rejects symbolic links and corrupt saved accounts",
            "DeepSeek account snapshots stay outside packages and iCloud",
            "retired provider storage keeps direct profiles and requires reselection",
            "direct profile round trips omit retired routing fields",
            "retired provider imports fail atomically with migration guidance",
            "Codex connection tests require the Responses endpoint",
            "WorkBuddy saves exact encrypted login after quit",
            "WorkBuddy switching preserves refreshed outgoing accounts",
            "WorkBuddy new-account login and launch rollback",
            "WorkBuddy rejects key mismatch, invalid auth and symlinks",
            "WorkBuddy credentials stay outside packages and iCloud",
            "WorkBuddy usage normalizes and deduplicates logs",
            "WorkBuddy usage prices requests and custom overrides",
            "WorkBuddy account writes exclude other instances",
            "WorkBuddy rollback retains tokens rotated during launch",
            "WorkBuddy distinct requests survive cross-file deduplication",
            "usage sources load independently after a source fails",
            "Sub2API pricing units, Fast rates and context tiers parse",
            "WorkBuddy aliases use API list prices without credit discounts",
            "GPT-6 Sol and Luna use current standard and Fast rates",
            "Claude current models apply correct context and cache prices",
            "fresh remote prices replace seeds while stale mirrors cannot",
            "ZCode context prices apply to requests before aggregation",
            "WorkBuddy editions have separate identities and state paths",
            "WorkBuddy China switching and recovery preserve the AI client",
            "WorkBuddy cross-edition snapshots are rejected and old AI data loads",
            "WorkBuddy China usage and prices remain separate from AI",
            "WorkBuddy China and AI daily alerts are independent",
            "WorkBuddy operation locks are scoped to their own client",
            "data root paths are Moa scoped",
            "profile caches distinguish data root paths",
            "legacy Moa-Lite local data migrates without overwrite",
            "legacy Moa-Lite iCloud data migrates to Moa",
            "legacy nested iCloud directories merge recursively",
            "recursive migration does not follow destination symlinks",
            "TOML multiline strings survive structural edits",
            "official restore keeps selected provider identity",
            "official restore strips selected direct provider credentials",
            "Codex session provider migration requires current provider",
            "Codex session provider migration updates JSONL and SQLite",
            "Codex session provider migration rolls back on failure",
            "official account displays email from auth token",
            "official account auth paths stay contained",
            "official no-account mode preserves third-party config without login",
            "official no-account mode captures current login without selecting it",
            "official no-account mode selects first direct config when none selected",
            "official no-account mode deduplicates current login by email",
            "official account list syncs selected account email",
            "updater compares versions and parses release feed",
            "updater prunes old backups",
            "GPT-5.6 family uses current local pricing",
            "ChatGPT application override respects renamed bundles",
            "Codex client helpers preserve settings and account state",
            "provider switching preserves live desktop and unrelated tables",
            "TOML scalar updates respect quoted keys and arrays",
            "Codex new records deduplicate mirrored legacy events",
            "GPT-6 prices include cache writes and request boundaries",
            "updater orders RC versions and keeps stable feed isolated",
            "Codex usage ignores inherited model-less token history",
            "remote pricing catalog parses, merges, and overrides fallback",
            "pricing updater schedules the daily local check",
            "ZCode GLM pricing is estimated from usage tokens",
            "ZCode usage scanner aggregates local SQLite usage",
            "Claude live files and selected state roll back together",
            "Codex profile state rolls back together",
            "Codex official account state rolls back together",
            "data packages round trip without temporary leaks",
            "ZCode scanner drains large subprocess output",
            "official account sync preserves identities after external login",
            "shared workspace accounts retain separate JWT user identities",
            "provider edits preserve commented array tables and their fields",
            "official restore removes complete quoted and multiline credentials",
            "data imports reject concurrent store writes and allow safe retry",
            "provider switching normalizes quoted and dotted identifiers",
            "multiline scalar updates replace complete assignments",
            "diagnostic TOML omits inline and multiline secrets",
            "provider updates preserve complete multiline values and arrays",
            "data imports reject external, chained and cyclic links",
            "legacy data manifests cannot hide symbolic links",
            "WorkBuddy request replays and timestamp formats aggregate correctly",
            "custom prices can be updated and removed after pricing a model",
            "price caches reload across roots and same-time imports",
            "menu storage reads stay responsive during an active export",
            "process output cannot block and timed-out children are reaped",
            "failed noisy exports release the shared data operation",
            "schema 2 requires complete valid file and link hashes",
            "streaming file hashes preserve digests and propagate read errors",
            "ZCode query cache avoids work and invalidates on database and WAL changes",
            "account menu reads preserve timestamps while refreshed credentials persist",
            "provider edits preserve adjacent comments and multiline values",
            "usage scheduling reduces idle work while preserving alerts and forced reloads",
        ]
        XCTAssertEqual(Set(MoaCoreTests.tests.map { $0.0 }), expected)
        XCTAssertEqual(MoaCoreTests.tests.count, expected.count)
    }

    func testDeletingStaleOfficialSelection() throws { try run("deleting a stale official selection keeps the unsaved live login") }
    func testOfficialDeletionLiveFile() throws { try run("official account deletion follows the live file including saved and signed-out sessions") }
    func testCodexProfileEditSelection() throws { try run("Codex profile edits recheck selection inside the store lock") }
    func testClaudeProfileEditSelection() throws { try run("Claude profile edits recheck selection inside the store lock") }
    func testGrokBuildPricing() throws { try run("Grok Build aliases and Fast context rates price local usage") }
    func testFullPricingCatalog() throws { try run("full pricing downloads preserve all records and accept new model IDs") }
    func testPricingCacheInvalidation() throws { try run("pricing commits immediately invalidate independent catalog caches") }
    func testManualPricingRefresh() throws { try run("manual price updates coalesce and reprice unchanged downloads") }
    func testFailedPricingDownload() throws { try run("failed price downloads keep prior catalogs and custom prices") }
    func testStoppedPricingRefresh() throws { try run("stopping price updates releases requests and suppresses stale callbacks") }
    func testRepriceUnchangedLogs() throws { try run("new remote models reprice unchanged WorkBuddy logs without a release") }

    func testDeepSeekDocumentEdits() throws { try run("DeepSeek edits only the account grant in Harness YAML") }
    func testDeepSeekDocumentGuards() throws { try run("DeepSeek rejects ambiguous and unsupported credential formats") }
    func testDeepSeekSaveAndManage() throws { try run("DeepSeek saves after quit and manages saved account copies") }
    func testDeepSeekSwitchAndEnroll() throws { try run("DeepSeek account enrollment and switching preserve other credentials") }
    func testDeepSeekLaunchRollback() throws { try run("DeepSeek launch failures restore only the previous account grant") }
    func testDeepSeekWriteExclusion() throws { try run("DeepSeek credential writes respect process locks and stopped clients") }
    func testDeepSeekStorageGuards() throws { try run("DeepSeek rejects symbolic links and corrupt saved accounts") }
    func testDeepSeekStorageIsolation() throws { try run("DeepSeek account snapshots stay outside packages and iCloud") }

    func testWorkBuddySavesExactEncryptedLoginAfterQuit() throws {
        try run("WorkBuddy saves exact encrypted login after quit")
    }

    func testWorkBuddySwitchingPreservesRefreshedOutgoingAccounts() throws {
        try run("WorkBuddy switching preserves refreshed outgoing accounts")
    }

    func testWorkBuddyNewAccountLoginAndLaunchRollback() throws {
        try run("WorkBuddy new-account login and launch rollback")
    }

    func testWorkBuddyRejectsKeyMismatchInvalidAuthAndSymlinks() throws {
        try run("WorkBuddy rejects key mismatch, invalid auth and symlinks")
    }

    func testWorkBuddyCredentialsStayOutsidePackagesAndICloud() throws {
        try run("WorkBuddy credentials stay outside packages and iCloud")
    }

    func testWorkBuddyUsageNormalizesAndDeduplicatesLogs() throws {
        try run("WorkBuddy usage normalizes and deduplicates logs")
    }

    func testWorkBuddyUsagePricesRequestsAndCustomOverrides() throws {
        try run("WorkBuddy usage prices requests and custom overrides")
    }

    func testWorkBuddyAccountWritesExcludeOtherInstances() throws {
        try run("WorkBuddy account writes exclude other instances")
    }

    func testWorkBuddyRollbackRetainsTokensRotatedDuringLaunch() throws {
        try run("WorkBuddy rollback retains tokens rotated during launch")
    }

    func testWorkBuddyDistinctRequestsSurviveCrossFileDeduplication() throws {
        try run("WorkBuddy distinct requests survive cross-file deduplication")
    }

    func testUsageSourcesLoadIndependentlyAfterASourceFails() throws {
        try run("usage sources load independently after a source fails")
    }

    func testSub2APIPricingUnitsFastRatesAndContextTiersParse() throws {
        try run("Sub2API pricing units, Fast rates and context tiers parse")
    }

    func testWorkBuddyAliasesUseAPIListPricesWithoutCreditDiscounts() throws {
        try run("WorkBuddy aliases use API list prices without credit discounts")
    }

    func testGPT6SolAndLunaUseCurrentStandardAndFastRates() throws {
        try run("GPT-6 Sol and Luna use current standard and Fast rates")
    }

    func testClaudeCurrentModelsApplyCorrectContextAndCachePrices() throws {
        try run("Claude current models apply correct context and cache prices")
    }

    func testOfficialPricingCorrectionsOverrideStaleAndRegionalMirrors() throws {
        try run("fresh remote prices replace seeds while stale mirrors cannot")
    }

    func testZCodeContextPricesApplyToRequestsBeforeAggregation() throws {
        try run("ZCode context prices apply to requests before aggregation")
    }

    func testWorkBuddyEditionsHaveSeparateIdentitiesAndStatePaths() throws {
        try run("WorkBuddy editions have separate identities and state paths")
    }

    func testWorkBuddyChinaSwitchingAndRecoveryPreserveTheAIClient() throws {
        try run("WorkBuddy China switching and recovery preserve the AI client")
    }

    func testWorkBuddyCrossEditionSnapshotsAreRejectedAndOldAIDataLoads() throws {
        try run("WorkBuddy cross-edition snapshots are rejected and old AI data loads")
    }

    func testWorkBuddyChinaUsageAndPricesRemainSeparateFromAI() throws {
        try run("WorkBuddy China usage and prices remain separate from AI")
    }

    func testWorkBuddyChinaAndAIDailyAlertsAreIndependent() throws {
        try run("WorkBuddy China and AI daily alerts are independent")
    }

    func testWorkBuddyOperationLocksAreScopedToTheirOwnClient() throws {
        try run("WorkBuddy operation locks are scoped to their own client")
    }

    func testDataRootPathsAreMoaScoped() throws {
        try run("data root paths are Moa scoped")
    }

    func testProfileCachesDistinguishDataRootPaths() throws {
        try run("profile caches distinguish data root paths")
    }

    func testLegacyMoaLiteLocalDataMigratesWithoutOverwrite() throws {
        try run("legacy Moa-Lite local data migrates without overwrite")
    }

    func testLegacyMoaLiteICloudDataMigratesToMoa() throws {
        try run("legacy Moa-Lite iCloud data migrates to Moa")
    }

    func testLegacyNestedICloudDirectoriesMergeRecursively() throws {
        try run("legacy nested iCloud directories merge recursively")
    }

    func testRecursiveMigrationDoesNotFollowDestinationSymlinks() throws {
        try run("recursive migration does not follow destination symlinks")
    }

    func testTOMLMultilineStringsSurviveStructuralEdits() throws {
        try run("TOML multiline strings survive structural edits")
    }

    func testOfficialRestoreKeepsSelectedProviderIdentity() throws {
        try run("official restore keeps selected provider identity")
    }

    func testOfficialRestoreStripsSelectedDirectProviderCredentials() throws {
        try run("official restore strips selected direct provider credentials")
    }

    func testCodexSessionProviderMigrationRequiresCurrentProvider() throws {
        try run("Codex session provider migration requires current provider")
    }

    func testCodexSessionProviderMigrationUpdatesJSONLAndSQLite() throws {
        try run("Codex session provider migration updates JSONL and SQLite")
    }

    func testCodexSessionProviderMigrationRollsBackOnFailure() throws {
        try run("Codex session provider migration rolls back on failure")
    }

    func testOfficialAccountDisplaysEmailFromAuthToken() throws {
        try run("official account displays email from auth token")
    }

    func testOfficialAccountAuthPathsStayContained() throws {
        try run("official account auth paths stay contained")
    }

    func testOfficialNoAccountModePreservesThirdPartyConfigWithoutLogin() throws {
        try run("official no-account mode preserves third-party config without login")
    }

    func testOfficialNoAccountModeCapturesCurrentLoginWithoutSelectingIt() throws {
        try run("official no-account mode captures current login without selecting it")
    }

    func testOfficialNoAccountModeSelectsFirstDirectConfigWhenNoneSelected() throws {
        try run("official no-account mode selects first direct config when none selected")
    }

    func testOfficialNoAccountModeDeduplicatesCurrentLoginByEmail() throws {
        try run("official no-account mode deduplicates current login by email")
    }

    func testOfficialAccountListSyncsSelectedAccountEmail() throws {
        try run("official account list syncs selected account email")
    }

    func testUpdaterComparesVersionsAndParsesReleaseFeed() throws {
        try run("updater compares versions and parses release feed")
    }

    func testUpdaterPrunesOldBackups() throws {
        try run("updater prunes old backups")
    }

    func testGPT56FamilyUsesCurrentLocalPricing() throws {
        try run("GPT-5.6 family uses current local pricing")
    }

    func testChatGPTApplicationOverrideRespectsRenamedBundles() throws {
        try run("ChatGPT application override respects renamed bundles")
    }

    func testCodexClientHelpersPreserveSettingsAndAccountState() throws {
        try run("Codex client helpers preserve settings and account state")
    }

    func testProviderSwitchingPreservesLiveDesktopAndUnrelatedTables() throws {
        try run("provider switching preserves live desktop and unrelated tables")
    }

    func testTOMLScalarUpdatesRespectQuotedKeysAndArrays() throws {
        try run("TOML scalar updates respect quoted keys and arrays")
    }

    func testCodexNewRecordsDeduplicateMirroredLegacyEvents() throws {
        try run("Codex new records deduplicate mirrored legacy events")
    }

    func testGPT6PricesIncludeCacheWritesAndRequestBoundaries() throws {
        try run("GPT-6 prices include cache writes and request boundaries")
    }

    func testUpdaterOrdersRCVersionsAndKeepsStableFeedIsolated() throws {
        try run("updater orders RC versions and keeps stable feed isolated")
    }

    func testCodexUsageIgnoresInheritedModelLessTokenHistory() throws {
        try run("Codex usage ignores inherited model-less token history")
    }

    func testRemotePricingCatalogParsesMergesAndOverridesFallback() throws {
        try run("remote pricing catalog parses, merges, and overrides fallback")
    }

    func testPricingUpdaterSchedulesTheDailyLocalCheck() throws {
        try run("pricing updater schedules the daily local check")
    }

    func testZCodeGLMPricingIsEstimatedFromUsageTokens() throws {
        try run("ZCode GLM pricing is estimated from usage tokens")
    }

    func testZCodeUsageScannerAggregatesLocalSQLiteUsage() throws {
        try run("ZCode usage scanner aggregates local SQLite usage")
    }

    func testClaudeLiveFilesAndSelectedStateRollBackTogether() throws {
        try run("Claude live files and selected state roll back together")
    }

    func testCodexProfileStateRollsBackTogether() throws {
        try run("Codex profile state rolls back together")
    }

    func testCodexOfficialAccountStateRollsBackTogether() throws {
        try run("Codex official account state rolls back together")
    }

    func testDataPackagesRoundTripWithoutTemporaryLeaks() throws {
        try run("data packages round trip without temporary leaks")
    }

    func testZCodeScannerDrainsLargeSubprocessOutput() throws {
        try run("ZCode scanner drains large subprocess output")
    }

    func testOfficialAccountSyncPreservesIdentitiesAfterExternalLogin() throws {
        try run("official account sync preserves identities after external login")
    }

    func testSharedWorkspaceAccountsRetainSeparateJWTUserIdentities() throws {
        try run("shared workspace accounts retain separate JWT user identities")
    }

    func testProviderEditsPreserveCommentedArrayTablesAndTheirFields() throws {
        try run("provider edits preserve commented array tables and their fields")
    }

    func testOfficialRestoreRemovesCompleteQuotedAndMultilineCredentials() throws {
        try run("official restore removes complete quoted and multiline credentials")
    }

    func testDataImportsRejectConcurrentStoreWritesAndAllowSafeRetry() throws {
        try run("data imports reject concurrent store writes and allow safe retry")
    }

    func testProviderSwitchingNormalizesQuotedAndDottedIdentifiers() throws {
        try run("provider switching normalizes quoted and dotted identifiers")
    }

    func testMultilineScalarUpdatesReplaceCompleteAssignments() throws {
        try run("multiline scalar updates replace complete assignments")
    }

    func testDiagnosticTOMLOmitsInlineAndMultilineSecrets() throws {
        try run("diagnostic TOML omits inline and multiline secrets")
    }

    func testProviderUpdatesPreserveCompleteMultilineValuesAndArrays() throws {
        try run("provider updates preserve complete multiline values and arrays")
    }

    func testDataImportsRejectExternalChainedAndCyclicLinks() throws {
        try run("data imports reject external, chained and cyclic links")
    }

    func testLegacyDataManifestsCannotHideSymbolicLinks() throws {
        try run("legacy data manifests cannot hide symbolic links")
    }

    func testWorkBuddyRequestReplaysAndTimestampFormatsAggregateCorrectly() throws {
        try run("WorkBuddy request replays and timestamp formats aggregate correctly")
    }

    func testCustomPricesCanBeUpdatedAndRemovedAfterPricingAModel() throws {
        try run("custom prices can be updated and removed after pricing a model")
    }

    func testPriceCachesReloadAcrossRootsAndSameTimeImports() throws {
        try run("price caches reload across roots and same-time imports")
    }

    func testMenuStorageReadsStayResponsiveDuringAnActiveExport() throws {
        try run("menu storage reads stay responsive during an active export")
    }

    func testProcessOutputCannotBlockAndTimedOutChildrenAreReaped() throws {
        try run("process output cannot block and timed-out children are reaped")
    }

    func testFailedNoisyExportsReleaseTheSharedDataOperation() throws {
        try run("failed noisy exports release the shared data operation")
    }

    func testSchema2RequiresCompleteValidFileAndLinkHashes() throws {
        try run("schema 2 requires complete valid file and link hashes")
    }

    func testStreamingFileHashesPreserveDigestsAndPropagateReadErrors() throws {
        try run("streaming file hashes preserve digests and propagate read errors")
    }

    func testZCodeQueryCacheAvoidsWorkAndInvalidatesOnDatabaseAndWALChanges() throws {
        try run("ZCode query cache avoids work and invalidates on database and WAL changes")
    }

    func testAccountMenuReadsPreserveTimestampsWhileRefreshedCredentialsPersist() throws {
        try run("account menu reads preserve timestamps while refreshed credentials persist")
    }

    func testProviderEditsPreserveAdjacentCommentsAndMultilineValues() throws {
        try run("provider edits preserve adjacent comments and multiline values")
    }

    func testUsageSchedulingReducesIdleWorkWhilePreservingAlertsAndForcedReloads() throws {
        try run("usage scheduling reduces idle work while preserving alerts and forced reloads")
    }
    func testRetiredProviderStorage() throws {
        try run("retired provider storage keeps direct profiles and requires reselection")
    }

    func testDirectProfileCompatibility() throws {
        try run("direct profile round trips omit retired routing fields")
    }

    func testRetiredProviderImport() throws {
        try run("retired provider imports fail atomically with migration guidance")
    }

    func testCodexResponsesConnection() throws {
        try run("Codex connection tests require the Responses endpoint")
    }

}
#endif
