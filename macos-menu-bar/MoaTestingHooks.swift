import Foundation

#if MOA_TESTING || MOA_TEST_SUPPORT
func moaTestingCodexOfficialAccounts(environment: [String: String]) throws -> [(id: String, name: String)] {
    try ConfigProfileController(environment: environment)
        .officialAccounts()
        .map { (id: $0.id, name: $0.name) }
}

func moaTestingSelectedCodexOfficialAccountName(environment: [String: String]) throws -> String? {
    try ConfigProfileController(environment: environment).selectedOfficialAccount()?.name
}

func moaTestingCodexCurrentOfficialLoginSaveStatus(environment: [String: String]) throws -> (hasLogin: Bool, savedAccountName: String?) {
    try ConfigProfileController(environment: environment).currentOfficialLoginSaveStatus()
}

func moaTestingAddCodexOfficialAccount(environment: [String: String], name: String) throws -> String {
    try ConfigProfileController(environment: environment)
        .addOfficialAccountFromCurrentLogin(name: name)
        .id
}

func moaTestingApplyCodexOfficialAccount(environment: [String: String], id: String) throws -> String {
    try ConfigProfileController(environment: environment)
        .applyOfficialAccount(id: id)
        .name
}

func moaTestingRestoreCodexOfficial(environment: [String: String]) throws {
    try ConfigProfileController(environment: environment).restoreOfficial()
}

func moaTestingRenameSelectedCodexOfficialAccount(environment: [String: String], name: String) throws -> String {
    try ConfigProfileController(environment: environment)
        .renameSelectedOfficialAccount(name: name)
        .name
}

func moaTestingDeleteSelectedCodexOfficialAccount(environment: [String: String]) throws -> (deleted: String, activated: String?) {
    let result = try ConfigProfileController(environment: environment).deleteSelectedOfficialAccount()
    return (deleted: result.deleted.name, activated: result.activated?.name)
}
#endif
