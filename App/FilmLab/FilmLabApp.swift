import SwiftUI

@main
struct FilmLabApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .tint(FL.ochre)
            // 整套视觉是相纸暖白，强制浅色；跟随系统切到深色会把这套配色打散
            .preferredColorScheme(.light)
        }
    }
}
