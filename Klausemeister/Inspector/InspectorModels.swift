import Foundation

enum InspectorSelection: Equatable {
    case ticket(id: String)
}

enum InspectorDetailLoadState: Equatable {
    case empty
    case loading
    case error(InspectorFetchError)
    case loaded(InspectorTicketDetail)
}

enum InspectorFetchError: Error, Equatable {
    case notFound(id: String)
    case unauthorized
    case rateLimited
    case transport(message: String)
    case other(message: String)

    var userMessage: String {
        switch self {
        case let .notFound(id): "Issue \(id) was not found in Linear."
        case .unauthorized: "Your Linear session has expired. Please sign in again."
        case .rateLimited: "Linear is rate-limiting requests. Try again in a moment."
        case let .transport(message): "Network error: \(message)"
        case let .other(message): message
        }
    }

    static func from(_ error: Error) -> InspectorFetchError {
        if let api = error as? LinearAPIError {
            switch api {
            case let .issueNotFound(id): return .notFound(id: id)
            case .rateLimited: return .rateLimited
            case let .graphQLErrors(messages): return .other(message: messages.joined(separator: "; "))
            }
        }
        if let oauth = error as? OAuthError, oauth == .unauthorized {
            return .unauthorized
        }
        if error is URLError {
            return .transport(message: error.localizedDescription)
        }
        return .other(message: error.localizedDescription)
    }
}
