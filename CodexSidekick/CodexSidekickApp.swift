import SwiftUI

@main
struct CodexSidekickApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(appModel: appModel)
                .task {
                    await appModel.bootstrap()
                }
                .onOpenURL { url in
                    Task {
                        await appModel.importPairingLink(url.absoluteString)
                    }
                }
        }
    }
}
