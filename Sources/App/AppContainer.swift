import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppContainer {
    let persistence: PersistenceController
    let fontTheme: FontTheme
    let lockService: LockService

    init() {
        let persistence = PersistenceController()
        self.persistence = persistence
        self.fontTheme = FontTheme()
        self.lockService = LockService()
        persistence.seedIfNeeded(context: persistence.container.mainContext)
        lockService.enforceLockedNotesOnLaunch(context: persistence.container.mainContext)
    }

    var modelContainer: ModelContainer {
        persistence.container
    }
}
