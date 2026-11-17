import CoreData
import Foundation
import os
import SwiftData
#if os(macOS)
import Security
#endif

/// Where the app and its widgets keep their data.
///
/// Both targets open the same SwiftData store inside the App Group container, so a task
/// checked off on the macOS desktop or the iPhone Home Screen is the same record the app shows.
/// Without the App Group entitlement (SwiftUI Previews, a fresh checkout before signing is set
/// up) the app falls back to its own default container and the widget shows a "connect" state,
/// so nothing crashes.
enum SharedModelContainer {
    /// Must match the App Groups capability on both the app and the widget extension.
    static let appGroupName = "group.com.krishpatel.momentum"

    /// iOS uses `group.…` as-is (authorized by the provisioning profile). macOS uses the
    /// Team ID–prefixed form (`<TEAMID>.group.…`), which the Mac sandbox accepts without a
    /// profile entry; it's read from the entitlements so the team isn't hard-coded.
    static let appGroupID: String = {
        #if os(macOS)
        return entitledAppGroups.first { $0.hasSuffix(appGroupName) } ?? appGroupName
        #else
        return appGroupName
        #endif
    }()

    /// Must match the iCloud capability; `.automatic` CloudKit picks it from the entitlements.
    static let cloudKitContainerID = "iCloud.com.krishpatel.momentum"

    static let schema = Schema([
        TaskItem.self, Award.self, RewardCheckpoint.self, RewardRedemption.self, ActivePass.self, MomentumEvent.self,
    ])

    /// Darwin notification the widget posts after writing, so a running app picks up the change.
    static let externalChangeNotification = "\(appGroupID).store-did-change"

    private static let logger = Logger(subsystem: "com.krishpatel.momentum", category: "Persistence")

    // MARK: Locations

    /// The App Group directory, or `nil` when this process isn't entitled to it.
    static let groupContainerURL: URL? = {
        #if os(macOS)
        // On macOS this API returns a path even without the entitlement, so check first.
        guard hasAppGroupEntitlement else { return nil }
        #endif
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }()

    static var isUsingAppGroup: Bool { groupContainerURL != nil }

    /// The shared SQLite store both targets open.
    static var sharedStoreURL: URL? {
        groupContainerURL?
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            .appending(path: "Momentum.store", directoryHint: .notDirectory)
    }

    /// Settings the widget also needs (the reminder schedule). Falls back to `.standard`.
    static var sharedDefaults: UserDefaults {
        guard isUsingAppGroup, let defaults = UserDefaults(suiteName: appGroupID) else { return .standard }
        return defaults
    }

    // MARK: Containers

    /// The app's container. Tries, in order: the App Group store with iCloud sync, the App Group
    /// store locally, the default store with iCloud, the default store locally, and in-memory.
    /// `.automatic` iCloud is an ordinary local store when the iCloud capability is off.
    static func makeAppContainer() -> ModelContainer {
        var candidates: [(label: String, configuration: ModelConfiguration)] = []

        if let url = sharedStoreURL {
            prepareSharedStore(at: url)
            candidates.append(("App Group + iCloud", ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .automatic)))
            candidates.append(("App Group, local", ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)))
        } else {
            logger.notice("App Group \(appGroupID, privacy: .public) unavailable; widgets won't see app data.")
        }
        candidates.append(("Default + iCloud", ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)))
        candidates.append(("Default, local", ModelConfiguration(schema: schema, cloudKitDatabase: .none)))
        candidates.append(("In-memory", ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)))

        for candidate in candidates {
            do {
                let container = try ModelContainer(for: schema, configurations: candidate.configuration)
                logger.info("Opened store: \(candidate.label, privacy: .public)")
                return container
            } catch {
                logger.error("\(candidate.label, privacy: .public) store failed: \(error.localizedDescription)")
            }
        }
        fatalError("Unable to create any ModelContainer")
    }

    private static let widgetContainerCache = OSAllocatedUnfairLock<ModelContainer?>(initialState: nil)

    /// The widget's view of the shared store, or `nil` until the app has created it.
    ///
    /// The widget never creates the store (the app owns creation and the one-time migration
    /// from the pre-App Group location) and never syncs to iCloud itself: the app exports
    /// widget edits from persistent history the next time it runs.
    static func widgetContainer() -> ModelContainer? {
        widgetContainerCache.withLock { cached in
            if let cached { return cached }
            guard let url = sharedStoreURL,
                  FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
            do {
                let container = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
                )
                cached = container
                return container
            } catch {
                logger.error("Widget could not open shared store: \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: Migration

    /// Creates the store's directory and, on first launch with App Groups, copies the existing
    /// store from the app's private container so no tasks, badges or passes are lost.
    private static func prepareSharedStore(at destination: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            logger.error("Could not create App Group store directory: \(error.localizedDescription)")
            return
        }

        guard !fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else { return }
        let legacy = URL.applicationSupportDirectory.appending(path: "default.store")
        guard fileManager.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }

        // SQLite keeps recent writes in the -wal file, so all three files move together.
        let suffixes = ["", "-wal", "-shm"]
        do {
            for suffix in suffixes {
                let source = URL(fileURLWithPath: legacy.path(percentEncoded: false) + suffix)
                guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                try fileManager.copyItem(at: source, to: URL(fileURLWithPath: destination.path(percentEncoded: false) + suffix))
            }
            logger.info("Copied existing store into the App Group container.")
        } catch {
            logger.error("Store migration failed, will retry next launch: \(error.localizedDescription)")
            for suffix in suffixes {
                try? fileManager.removeItem(at: URL(fileURLWithPath: destination.path(percentEncoded: false) + suffix))
            }
        }
    }

    /// Copies settings saved before App Groups were enabled into the shared defaults.
    static func migrateDefaultsToAppGroup(keys: [String]) {
        guard isUsingAppGroup, let shared = UserDefaults(suiteName: appGroupID) else { return }
        for key in keys where shared.object(forKey: key) == nil {
            if let value = UserDefaults.standard.object(forKey: key) {
                shared.set(value, forKey: key)
            }
        }
    }

    // MARK: Cross-process change signal

    static func postExternalChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(externalChangeNotification as CFString),
            nil, nil, true
        )
    }

    /// Re-broadcasts the widget's Darwin notification as `.momentumStoreDidChangeExternally`
    /// on the main queue. Call once per process.
    static func observeExternalChanges() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .momentumStoreDidChangeExternally, object: nil)
                }
            },
            externalChangeNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: CloudKit schema

    #if DEBUG && !WIDGET_EXTENSION
    /// Pushes every model's record type to the CloudKit **Development** environment.
    ///
    /// Run a Debug build once with the launch argument `-InitializeCloudKitSchema YES` (Xcode:
    /// Product › Scheme › Edit Scheme › Arguments) after changing the models, then deploy the
    /// schema to Production in the CloudKit Console before shipping a TestFlight build.
    /// Uses a throwaway local store, so no real data is read or written.
    static func initializeCloudKitSchemaIfRequested() {
        guard UserDefaults.standard.bool(forKey: "InitializeCloudKitSchema") else { return }
        let types: [any PersistentModel.Type] = [
            TaskItem.self, Award.self, RewardCheckpoint.self, RewardRedemption.self, ActivePass.self, MomentumEvent.self,
        ]
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: types) else {
            logger.error("CloudKit schema: could not build a Core Data model from the SwiftData schema.")
            return
        }

        let storeURL = URL.temporaryDirectory.appending(path: "cloudkit-schema-\(UUID().uuidString).sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "MomentumSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }

        if let loadError {
            logger.error("CloudKit schema: store failed to load: \(loadError.localizedDescription)")
        } else {
            do {
                try container.initializeCloudKitSchema()
                logger.notice("CloudKit schema initialized in the Development environment.")
            } catch {
                logger.error("CloudKit schema initialization failed: \(error)")
            }
        }

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path(percentEncoded: false) + suffix))
        }
    }
    #endif

    // MARK: Entitlements

    #if os(macOS)
    private static var entitledAppGroups: [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
        else { return [] }
        return value as? [String] ?? []
    }

    private static var hasAppGroupEntitlement: Bool {
        entitledAppGroups.contains(appGroupID)
    }
    #endif
}

extension Notification.Name {
    /// Another process (the widget extension) changed the shared store.
    static let momentumStoreDidChangeExternally = Notification.Name("MomentumStoreDidChangeExternally")
}
