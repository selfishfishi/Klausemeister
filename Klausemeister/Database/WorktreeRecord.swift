// Klausemeister/Database/WorktreeRecord.swift
import Foundation
import GRDB

struct WorktreeRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "worktrees"

    var worktreeId: String
    var name: String
    var sortOrder: Int
    var gitWorktreePath: String
    var createdAt: String
    var repoId: String?
    var meisterAgent: String
}
