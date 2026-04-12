import Foundation
import GRDB

struct CommandPaletteHistoryRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "command_palette_history"

    var commandRawValue: String
    var usedAt: String
    var useCount: Int
}
