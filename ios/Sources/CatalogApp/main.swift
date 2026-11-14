import Foundation

// Test dymny przed uruchomieniem GUI: `CatalogApp --selftest`
if CommandLine.arguments.contains("--selftest") {
    MainActor.assumeIsolated { SelfTest.run() }
}

KarpatiaCatalogApp.main()
