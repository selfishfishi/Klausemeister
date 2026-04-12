import Foundation
import GRDB

struct HiddenProjectRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "hidden_projects"

    var projectName: String
}
