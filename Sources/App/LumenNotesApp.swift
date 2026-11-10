import SwiftUI
import UIKit

final class LumenAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if shortcutItem.type == "com.lumen.notes.quickcapture" {
            SharedCapture.enqueue(source: "home-shortcut")
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}

@main
@MainActor
struct LumenNotesApp: App {
    @UIApplicationDelegateAdaptor(LumenAppDelegate.self) private var appDelegate
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(container.fontTheme)
                .environment(container.lockService)
                .modelContainer(container.persistence.container)
        }
        .commands {
            LumenCommands()
        }
    }
}
