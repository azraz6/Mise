import Foundation
import SwiftData

enum MiseSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Recipe.self,
            RecipeCollection.self,
            ShoppingList.self,
            ShoppingItem.self,
            MealPlanEntry.self,
            ImportJob.self
        ]
    }
}

enum MiseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MiseSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

enum ModelContainerFactory {
    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mise", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Mise.store")
    }

    static func make(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MiseSchemaV1.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration("Mise", schema: schema, url: storeURL ?? Self.storeURL)
        }
        return try ModelContainer(for: schema, migrationPlan: MiseMigrationPlan.self, configurations: [configuration])
    }
}
