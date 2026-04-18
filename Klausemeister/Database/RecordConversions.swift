// Klausemeister/Database/RecordConversions.swift
import Foundation

// Mapping between GRDB persistence records and the domain types that
// cross the dependency boundary (reducer state, actions, etc.). Keeping
// these in one file makes it easy to find "the write-side" of any read
// that appears in a reducer effect.

// MARK: - LinearWorkflowState ↔ LinearWorkflowStateRecord

extension LinearWorkflowState {
    nonisolated init(from record: LinearWorkflowStateRecord) {
        self.init(
            id: record.id,
            name: record.name,
            type: record.type,
            position: record.position,
            teamId: record.teamId
        )
    }
}

extension LinearWorkflowStateRecord {
    nonisolated init(from state: LinearWorkflowState, fetchedAt: Date) {
        self.init(
            id: state.id,
            teamId: state.teamId,
            name: state.name,
            type: state.type,
            position: state.position,
            fetchedAt: ISO8601DateFormatter.shared.string(from: fetchedAt)
        )
    }
}
