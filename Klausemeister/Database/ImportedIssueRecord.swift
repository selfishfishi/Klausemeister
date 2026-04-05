// Klausemeister/Database/ImportedIssueRecord.swift
import Foundation
import GRDB

struct ImportedIssueRecord: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "imported_issues"

    var linearId: String
    var identifier: String
    var title: String
    var status: String
    var statusId: String
    var statusType: String
    var projectName: String?
    var assigneeName: String?
    var priority: Int
    var labels: String
    var description: String?
    var url: String
    var createdAt: String
    var updatedAt: String
    var importedAt: String
    var sortOrder: Int
}
