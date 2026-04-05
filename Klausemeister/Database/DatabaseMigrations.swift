// Klausemeister/Database/DatabaseMigrations.swift
import Foundation
import GRDB

enum DatabaseMigrations {
    nonisolated static func registerAll(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1-imported-issues") { db in
            try db.create(table: "imported_issues") { t in
                t.column("linearId", .text).primaryKey()
                t.column("identifier", .text).notNull()
                t.column("title", .text).notNull()
                t.column("status", .text).notNull()
                t.column("statusId", .text).notNull()
                t.column("statusType", .text).notNull()
                t.column("projectName", .text)
                t.column("assigneeName", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("labels", .text).notNull().defaults(to: "[]")
                t.column("description", .text)
                t.column("url", .text).notNull()
                t.column("createdAt", .text).notNull()
                t.column("updatedAt", .text).notNull()
                t.column("importedAt", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }
    }
}
