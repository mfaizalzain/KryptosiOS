import SwiftUI
import SwiftData

@main
struct KryptosApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            VaultEntryRecord.self,
        ])
        return KryptosApp.makeModelContainer(schema: schema)
    }()

    @StateObject private var auth = GoogleAuthService()
    @StateObject private var billing = BillingService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(billing)
        }
        .modelContainer(modelContainer)
    }

    private static func makeModelContainer(schema: Schema) -> ModelContainer {
        let storeURL = vaultStoreURL()
        let configuration = ModelConfiguration(
            "KryptosVault",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            quarantineStore(at: storeURL)

            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create Kryptos vault container: \(error)")
            }
        }
    }

    private static func vaultStoreURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = applicationSupport.appending(path: "Kryptos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "KryptosVault.store")
    }

    private static func quarantineStore(at storeURL: URL) {
        let fileManager = FileManager.default
        let timestamp = Int(Date().timeIntervalSince1970)
        let candidates = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            let quarantineURL = url.deletingLastPathComponent()
                .appending(path: "\(url.lastPathComponent).failed-\(timestamp)")
            try? fileManager.moveItem(at: url, to: quarantineURL)
        }
    }
}
