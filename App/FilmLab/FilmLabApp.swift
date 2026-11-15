import SwiftUI

@main
struct FilmLabApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
            .tint(FL.ochre)
            // 深色剪辑台界面：预览是大面积画面，暗底才不抢画面、也更像专业剪辑 App
            .preferredColorScheme(.dark)
        }
    }
}
