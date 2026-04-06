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

        migrator.registerMigration("v2-worktrees") { db in
            try db.create(table: "worktrees") { t in
                t.column("worktreeId", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("gitWorktreePath", .text).notNull()
                t.column("createdAt", .text).notNull()
            }

            try db.create(table: "worktree_queue_items") { t in
                t.column("id", .text).primaryKey()
                t.column("worktreeId", .text).notNull()
                    .references("worktrees", column: "worktreeId", onDelete: .cascade)
                t.column("issueLinearId", .text).notNull()
                    .references("imported_issues", column: "linearId", onDelete: .cascade)
                t.column("queuePosition", .text).notNull().defaults(to: "inbox")
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("assignedAt", .text).notNull()
                t.column("completedAt", .text)
            }
        }

        migrator.registerMigration("v3-repositories") { db in
            try db.create(table: "repositories") { t in
                t.column("repoId", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
                t.column("createdAt", .text).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }

            try db.alter(table: "worktrees") { t in
                t.add(column: "repoId", .text)
            }
        }

        migrator.registerMigration("v4-imported-issue-team-orphaned") { db in
            try db.alter(table: "imported_issues") { t in
                t.add(column: "teamId", .text).notNull().defaults(to: "")
                t.add(column: "teamName", .text).notNull().defaults(to: "")
                t.add(column: "isOrphaned", .boolean).notNull().defaults(to: false)
            }
        }
    }
}
