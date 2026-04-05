import Foundation
import GRDB

struct RepositoryRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "repositories"

    var repoId: String
    var name: String
    var path: String
    var createdAt: String
    var sortOrder: Int
}
