import SwiftUI

@main
struct LocalLosslessPlayerApp: App {
    private let persistence = PersistenceController.shared
    @StateObject private var player = PlayerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(player)
        }
    }
}
