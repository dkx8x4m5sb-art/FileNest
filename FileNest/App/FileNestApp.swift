import SwiftUI

@main
struct FileNestApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack {
            BrowserView(folder: FileManager.default.documentsURL)
        }
    }
}
