import Foundation
import GRDB

struct LinearTeamRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "linear_teams"

    var id: String
    var key: String
    var name: String
    var colorIndex: Int
    var isEnabled: Bool
    var isHiddenFromBoard: Bool
}
