import Foundation

enum MoaRuntimeMode {
    static var isWorkspacePreview: Bool { CommandLine.arguments.contains("--workspace-preview") }
    #if MOA_TESTING
    nonisolated(unsafe) static var suppressesUserInteraction = true
    #else
    nonisolated(unsafe) static var suppressesUserInteraction = false
    #endif
}
