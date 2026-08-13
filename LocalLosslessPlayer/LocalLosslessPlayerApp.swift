import SwiftUI

@main
struct LocalLosslessPlayerApp: App {
    private let persistence = PersistenceController.shared
    @StateObject private var player = PlayerViewModel()
    @StateObject private var settings = AppSettings()
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
                .environmentObject(player)
                .environmentObject(settings)
                .environmentObject(favorites)
        }
    }
}
