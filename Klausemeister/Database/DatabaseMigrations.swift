// Klausemeister/Database/DatabaseMigrations.swift
import Foundation
import GRDB

enum DatabaseMigrations {
    // swiftlint:disable:next function_body_length
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

        migrator.registerMigration("v5-trim-imported-issues") { db in
            try db.alter(table: "imported_issues") { t in
                t.drop(column: "priority")
                t.drop(column: "assigneeName")
                t.drop(column: "teamName")
                t.drop(column: "createdAt")
            }
        }

        migrator.registerMigration("v6-linear-workflow-states-cache") { db in
            try db.create(table: "linear_workflow_states") { t in
                t.column("id", .text).primaryKey()
                t.column("teamId", .text).notNull()
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("position", .double).notNull().defaults(to: 0)
                t.column("fetchedAt", .text).notNull()
            }
        }

        migrator.registerMigration("v7-linear-teams") { db in
            try db.create(table: "linear_teams") { t in
                t.column("id", .text).primaryKey()
                t.column("key", .text).notNull()
                t.column("name", .text).notNull()
                t.column("colorIndex", .integer).notNull().defaults(to: 0)
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("isHiddenFromBoard", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v8-team-ingestion-strategy") { db in
            try db.alter(table: "linear_teams") { t in
                t.add(column: "ingestionStrategy", .text)
                    .notNull()
                    .defaults(to: "labelFiltered")
            }
        }

        migrator.registerMigration("v9-ignored-worktree-paths") { db in
            try db.create(table: "ignored_worktree_paths") { t in
                t.column("path", .text).primaryKey()
                t.column("repoId", .text).notNull()
            }
        }

        migrator.registerMigration("v10-command-palette-history") { db in
            try db.create(table: "command_palette_history") { table in
                table.column("commandRawValue", .text).primaryKey()
                table.column("usedAt", .text).notNull()
                table.column("useCount", .integer).notNull().defaults(to: 1)
            }
        }

        migrator.registerMigration("v11-team-state-mappings") { db in
            try db.create(table: "team_state_mappings") { t in
                t.column("teamId", .text).notNull()
                t.column("linearStateId", .text).notNull()
                t.column("linearStateName", .text).notNull()
                t.column("meisterState", .text).notNull()
                t.primaryKey(["teamId", "linearStateId"])
            }
        }

        migrator.registerMigration("v12-hidden-projects") { db in
            try db.create(table: "hidden_projects") { t in
                t.column("projectName", .text).primaryKey()
            }
        }

        migrator.registerMigration("v13-team-filter-label") { db in
            try db.alter(table: "linear_teams") { t in
                t.add(column: "ingestAllIssues", .boolean).notNull().defaults(to: false)
                t.add(column: "filterLabel", .text).notNull().defaults(to: "klause")
            }
            // Backfill from the old ingestionStrategy column before dropping it
            try db.execute(sql: """
                UPDATE linear_teams SET ingestAllIssues = 1 WHERE ingestionStrategy = 'allIssues'
            """)
            try db.alter(table: "linear_teams") { t in
                t.drop(column: "ingestionStrategy")
            }
        }

        migrator.registerMigration("v14-schedules") { db in
            try db.create(table: "schedules") { t in
                t.column("scheduleId", .text).primaryKey()
                t.column("repoId", .text).notNull()
                    .references("repositories", column: "repoId", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("linearProjectId", .text)
                t.column("createdAt", .text).notNull()
                t.column("runAt", .text)
            }

            try db.create(table: "schedule_items") { t in
                t.column("scheduleItemId", .text).primaryKey()
                t.column("scheduleId", .text).notNull()
                    .references("schedules", column: "scheduleId", onDelete: .cascade)
                t.column("worktreeId", .text).notNull()
                    .references("worktrees", column: "worktreeId", onDelete: .cascade)
                t.column("issueLinearId", .text).notNull()
                    .references("imported_issues", column: "linearId", onDelete: .cascade)
                t.column("issueIdentifier", .text).notNull()
                t.column("issueTitle", .text).notNull()
                t.column("position", .integer).notNull().defaults(to: 0)
                t.column("weight", .integer).notNull().defaults(to: 0)
                t.column("blockedByIssueLinearIds", .text).notNull().defaults(to: "[]")
                t.column("status", .text).notNull().defaults(to: "planned")
            }

            // Ordered render of a schedule's items, per worktree.
            try db.create(
                index: "idx_schedule_items_schedule_worktree_position",
                on: "schedule_items",
                columns: ["scheduleId", "worktreeId", "position"]
            )
            // Live-progress lookup: which schedule_items reference this issue.
            try db.create(
                index: "idx_schedule_items_issue_linear_id",
                on: "schedule_items",
                columns: ["issueLinearId"]
            )
        }
    }
}
