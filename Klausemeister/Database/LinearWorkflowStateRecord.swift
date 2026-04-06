// Klausemeister/Database/LinearWorkflowStateRecord.swift
import Foundation
import GRDB

struct LinearWorkflowStateRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "linear_workflow_states"

    var id: String
    var teamId: String
    var name: String
    var type: String
    var position: Double
    var fetchedAt: String
}
