import Foundation
import GRDB

struct StateMappingRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "team_state_mappings"

    var teamId: String
    var linearStateId: String
    var linearStateName: String
    var meisterState: String
}
