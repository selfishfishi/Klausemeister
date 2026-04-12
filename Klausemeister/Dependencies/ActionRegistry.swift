import Dependencies

struct ActionRegistry: Sendable {
    var resolvedBindings: @Sendable () -> [AppCommand: KeyBinding]
}

extension ActionRegistry: DependencyKey {
    nonisolated static let liveValue = ActionRegistry(
        resolvedBindings: {
            Dictionary(
                uniqueKeysWithValues: AppCommand.allCases.compactMap { command in
                    guard let binding = command.defaultBinding else { return nil }
                    return (command, binding)
                }
            )
        }
    )
    nonisolated static let testValue = ActionRegistry(
        resolvedBindings: { [:] }
    )
}

extension DependencyValues {
    var actionRegistry: ActionRegistry {
        get { self[ActionRegistry.self] }
        set { self[ActionRegistry.self] = newValue }
    }
}
