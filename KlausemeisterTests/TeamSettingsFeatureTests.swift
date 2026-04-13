import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

private let teamKLA = LinearTeam(
    id: "team-kla", key: "KLA", name: "Klausemeister",
    colorIndex: 0, isEnabled: true, isHiddenFromBoard: false
)
private let teamMOB = LinearTeam(
    id: "team-mob", key: "MOB", name: "Mobile",
    colorIndex: 1, isEnabled: true, isHiddenFromBoard: false
)
private let teamINF = LinearTeam(
    id: "team-inf", key: "INF", name: "Infrastructure",
    colorIndex: 2, isEnabled: false, isHiddenFromBoard: false
)

private let persistedKLA = LinearTeamRecord(from: teamKLA)
private let persistedMOB = LinearTeamRecord(from: teamMOB)

// MARK: - Loading Tests

@Test func `onAppear loads and merges teams from API and DB`() async {
    let store = TestStore(initialState: TeamSettingsFeature.State()) {
        TeamSettingsFeature()
    } withDependencies: {
        $0.linearAPIClient.fetchTeams = { [teamKLA, teamMOB, teamINF] }
        $0.linearAPIClient.fetchLabels = { ["klause", "bug", "feature"] }
        $0.databaseClient.fetchTeams = { [persistedKLA, persistedMOB] }
    }

    await store.send(.onAppear) {
        $0.loadingStatus = .loading
    }

    await store.receive(\.teamsLoaded.success) {
        $0.loadingStatus = .loaded
        // KLA and MOB are enabled (from DB), INF is new and disabled
        $0.allTeams = [teamKLA, teamMOB, teamINF]
        $0.enabledTeamIds = ["team-kla", "team-mob"]
        $0.originalIngestAllFlags = [
            "team-kla": false,
            "team-mob": false,
            "team-inf": false
        ]
        $0.originalFilterLabels = [
            "team-kla": "klause",
            "team-mob": "klause",
            "team-inf": "klause"
        ]
        // "klause" comes from both the API labels and team filterLabel defaults
        $0.availableLabels = ["bug", "feature", "klause"]
    }
}

// MARK: - Toggle Tests

@Test func `enable toggle adds and removes from enabledTeamIds`() async {
    var state = TeamSettingsFeature.State()
    state.allTeams = [teamKLA, teamMOB, teamINF]
    state.enabledTeamIds = ["team-kla", "team-mob"]

    let store = TestStore(initialState: state) {
        TeamSettingsFeature()
    }

    // Enable INF
    await store.send(.enableTeamToggled(teamId: "team-inf")) {
        $0.enabledTeamIds = ["team-kla", "team-mob", "team-inf"]
    }

    // Disable MOB
    await store.send(.enableTeamToggled(teamId: "team-mob")) {
        $0.enabledTeamIds = ["team-kla", "team-inf"]
    }
}

// MARK: - Removal Tests

@Test func `remove team shows confirmation alert`() async {
    var state = TeamSettingsFeature.State()
    state.allTeams = [teamKLA, teamMOB]
    state.enabledTeamIds = ["team-kla", "team-mob"]

    let store = TestStore(initialState: state) {
        TeamSettingsFeature()
    }

    await store.send(.removeTeamTapped(teamId: "team-mob")) {
        $0.alert = AlertState {
            TextState("Remove MOB?")
        } actions: {
            ButtonState(role: .destructive, action: .confirmRemoval(teamId: "team-mob")) {
                TextState("Remove")
            }
            ButtonState(role: .cancel) {
                TextState("Cancel")
            }
        } message: {
            TextState("This will delete all imported issues from Mobile. This cannot be undone.")
        }
    }

    await store.send(.alert(.presented(.confirmRemoval(teamId: "team-mob")))) {
        $0.alert = nil
        $0.teamsToRemove = ["team-mob"]
        $0.enabledTeamIds = ["team-kla"]
    }
}

// MARK: - Save Tests

@Test func `save deletes removed team issues and emits delegate`() async {
    var state = TeamSettingsFeature.State()
    state.allTeams = [teamKLA, teamMOB]
    state.enabledTeamIds = ["team-kla"]
    state.teamsToRemove = ["team-mob"]
    state.loadingStatus = .loaded

    var deletedTeamIds: [String] = []
    var savedRecords: [LinearTeamRecord] = []

    let store = TestStore(initialState: state) {
        TeamSettingsFeature()
    } withDependencies: {
        $0.databaseClient.deleteIssuesByTeam = { teamId in
            deletedTeamIds.append(teamId)
        }
        $0.databaseClient.deleteTeam = { _ in }
        $0.databaseClient.saveTeams = { records in
            savedRecords = records
        }
    }

    await store.send(.saveTapped)

    await store.receive(\.saveCompleted.success)

    // Only KLA should be saved (MOB was removed)
    await store.receive(\.delegate.teamsUpdated)

    #expect(deletedTeamIds == ["team-mob"])
    #expect(savedRecords.count == 1)
    #expect(savedRecords.first?.id == "team-kla")
}

// MARK: - Cancel Tests

@Test func `cancel emits dismissed delegate without DB calls`() async {
    let store = TestStore(initialState: TeamSettingsFeature.State()) {
        TeamSettingsFeature()
    }

    await store.send(.cancelTapped)
    await store.receive(\.delegate.dismissed)
}

// MARK: - Ingestion Strategy Tests

@Test func `ingest all toggle updates team`() async {
    var state = TeamSettingsFeature.State()
    state.allTeams = [teamKLA, teamMOB]
    state.enabledTeamIds = ["team-kla", "team-mob"]

    let store = TestStore(initialState: state) {
        TeamSettingsFeature()
    }

    await store.send(.ingestAllToggled(teamId: "team-kla")) {
        $0.allTeams[0].ingestAllIssues = true
    }
}

@Test func `ingest all toggle with unknown team ID is no-op`() async {
    var state = TeamSettingsFeature.State()
    state.allTeams = [teamKLA]
    state.enabledTeamIds = ["team-kla"]

    let store = TestStore(initialState: state) {
        TeamSettingsFeature()
    }

    await store.send(.ingestAllToggled(teamId: "nonexistent"))
}

@Test func `filter label change updates team`() async {
    var state = TeamSettingsFeature.State()
    state.allTeams = [teamKLA]
    state.enabledTeamIds = ["team-kla"]

    let store = TestStore(initialState: state) {
        TeamSettingsFeature()
    }

    await store.send(.filterLabelChanged(teamId: "team-kla", label: "feature")) {
        $0.allTeams[0].filterLabel = "feature"
    }
}

@Test func `save persists changed ingest all flag`() async {
    var klaAllIssues = teamKLA
    klaAllIssues.ingestAllIssues = true

    var state = TeamSettingsFeature.State()
    state.allTeams = [klaAllIssues]
    state.enabledTeamIds = ["team-kla"]
    state.originalIngestAllFlags = ["team-kla": false]
    state.originalFilterLabels = ["team-kla": "klause"]
    state.loadingStatus = .loaded

    var savedRecords: [LinearTeamRecord] = []

    let store = TestStore(initialState: state) {
        TeamSettingsFeature()
    } withDependencies: {
        $0.databaseClient.saveTeams = { records in
            savedRecords = records
        }
    }

    await store.send(.saveTapped)
    await store.receive(\.saveCompleted.success)
    await store.receive(\.delegate.teamsUpdated)

    #expect(savedRecords.count == 1)
    #expect(savedRecords.first?.ingestAllIssues == true)
}
