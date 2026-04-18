import ComposableArchitecture
import Dependencies
import Foundation
import Testing
@testable import Klausemeister

// MARK: - themeChanged

@Test @MainActor
func `themeChanged sequences capture → destroy → rebuild → restore`() async {
    let events = LockIsolated<[String]>([])

    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.surfaceManager.captureSurfaces = {
            events.withValue { $0.append("capture") }
            return []
        }
        $0.surfaceManager.destroyAllSurfaces = {
            events.withValue { $0.append("destroy") }
        }
        $0.surfaceManager.restoreSurfaces = { _ in
            events.withValue { $0.append("restore") }
        }
        $0.ghosttyApp.rebuild = { theme in
            events.withValue { $0.append("rebuild(\(theme.rawValue))") }
        }
    }

    await store.send(.themeChanged(.gruvboxDarkHard))
    await store.finish()

    #expect(events.value == [
        "capture",
        "destroy",
        "rebuild(gruvboxDarkHard)",
        "restore"
    ])
}

// MARK: - initialThemeSeeded

@Test @MainActor
func `initialThemeSeeded only rebuilds ghostty and skips surface dance`() async {
    let events = LockIsolated<[String]>([])

    let store = TestStore(initialState: AppFeature.State()) {
        AppFeature()
    } withDependencies: {
        $0.ghosttyApp.rebuild = { theme in
            events.withValue { $0.append("rebuild(\(theme.rawValue))") }
        }
        // surfaceManager closures stay unimplemented — the reducer must
        // NOT invoke any of them for the initial prime.
    }

    await store.send(.initialThemeSeeded(.catppuccinMocha))
    await store.finish()

    #expect(events.value == ["rebuild(catppuccinMocha)"])
}

// MARK: - AppTheme.migrateStoredValue

@Test
func `migrateStoredValue leaves a current rawValue untouched`() {
    let stored = LockIsolated<[String: String?]>([
        AppTheme.storageKey: "gruvboxDarkHard"
    ])
    let writes = LockIsolated<Int>(0)
    let client = makeUserDefaultsClient(stored: stored, writes: writes)

    let resolved = AppTheme.migrateStoredValue(using: client)

    #expect(resolved == .gruvboxDarkHard)
    #expect(writes.value == 0)
}

@Test
func `migrateStoredValue rewrites a legacy darkMedium to everforestDarkMedium`() {
    let stored = LockIsolated<[String: String?]>([
        AppTheme.storageKey: "darkMedium"
    ])
    let writes = LockIsolated<Int>(0)
    let client = makeUserDefaultsClient(stored: stored, writes: writes)

    let resolved = AppTheme.migrateStoredValue(using: client)

    #expect(resolved == .everforestDarkMedium)
    #expect(stored.value[AppTheme.storageKey] == "everforestDarkMedium")
    #expect(writes.value == 1)
}

@Test
func `migrateStoredValue rewrites legacy darkHard preserving contrast`() {
    let stored = LockIsolated<[String: String?]>([
        AppTheme.storageKey: "darkHard"
    ])
    let writes = LockIsolated<Int>(0)
    let client = makeUserDefaultsClient(stored: stored, writes: writes)

    let resolved = AppTheme.migrateStoredValue(using: client)

    #expect(resolved == .everforestDarkHard)
    #expect(stored.value[AppTheme.storageKey] == "everforestDarkHard")
    #expect(writes.value == 1)
}

@Test
func `migrateStoredValue defaults to everforestDarkMedium when unset`() {
    let stored = LockIsolated<[String: String?]>([:])
    let writes = LockIsolated<Int>(0)
    let client = makeUserDefaultsClient(stored: stored, writes: writes)

    let resolved = AppTheme.migrateStoredValue(using: client)

    #expect(resolved == .everforestDarkMedium)
    // Nil stored → resolve defaults to everforestDarkMedium, rawValue
    // doesn't match (stored is nil), so it writes the default out.
    #expect(stored.value[AppTheme.storageKey] == "everforestDarkMedium")
    #expect(writes.value == 1)
}

// MARK: - Helpers

private func makeUserDefaultsClient(
    stored: LockIsolated<[String: String?]>,
    writes: LockIsolated<Int>
) -> UserDefaultsClient {
    UserDefaultsClient(
        bool: { _ in false },
        setBool: { _, _ in },
        string: { key in stored.value[key] ?? nil },
        setString: { value, key in
            stored.withValue { $0[key] = value }
            writes.withValue { $0 += 1 }
        }
    )
}
