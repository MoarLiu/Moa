import Foundation

enum MoaRuntimeMode {
    #if MOA_TESTING
    nonisolated(unsafe) static var suppressesUserInteraction = true
    #else
    nonisolated(unsafe) static var suppressesUserInteraction = false
    #endif
}
