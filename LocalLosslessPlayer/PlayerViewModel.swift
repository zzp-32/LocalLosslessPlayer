import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "LocalLosslessPlayer", managedObjectModel: model)
        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            container.persistentStoreDescriptions = [description]
        } else {
            let description = NSPersistentStoreDescription(
                url: StorageConfiguration.dataRootURL.appendingPathComponent("Library.sqlite")
            )
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [description]
        }
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data store failed: \(error)") }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "Song"
        entity.managedObjectClassName = NSStringFromClass(Song.self)

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = true) -> NSAttributeDescription {
            let item = NSAttributeDescription()
            item.name = name; item.attributeType = type; item.isOptional = optional
            return item
        }

        entity.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("title", .stringAttributeType, optional: false),
            attribute("artist", .stringAttributeType),
            attribute("album", .stringAttributeType),
            attribute("fileName", .stringAttributeType, optional: false),
            attribute("filePath", .stringAttributeType, optional: false),
            attribute("checksum", .stringAttributeType, optional: false),
            attribute("duration", .doubleAttributeType, optional: false),
            attribute("createdAt", .dateAttributeType, optional: false),
            attribute("lastPlayedAt", .dateAttributeType),
            attribute("artworkPath", .stringAttributeType),
            attribute("lyricsPath", .stringAttributeType),
            attribute("sourceBookmark", .binaryDataAttributeType),
            attribute("sourceRootBookmark", .binaryDataAttributeType),
            attribute("sourceRelativePath", .stringAttributeType)
        ]
        model.entities = [entity]
        return model
    }
}

@objc(Song)
final class Song: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var artist: String?
    @NSManaged var album: String?
    @NSManaged var fileName: String
    @NSManaged var filePath: String
    @NSManaged var checksum: String
    @NSManaged var duration: Double
    @NSManaged var createdAt: Date
    @NSManaged var lastPlayedAt: Date?
    @NSManaged var artworkPath: String?
    @NSManaged var lyricsPath: String?
    @NSManaged var sourceBookmark: Data?
    @NSManaged var sourceRootBookmark: Data?
    @NSManaged var sourceRelativePath: String?
}

extension Song {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Song> { NSFetchRequest<Song>(entityName: "Song") }
}
