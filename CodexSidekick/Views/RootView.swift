import Observation
import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var systemColorScheme

    @Bindable var appModel: AppModel
    @State private var selectedSection: SidekickSection = .threads

    private var theme: SidekickTheme {
        SidekickTheme.resolve(
            settings: appModel.appearanceSettings,
            hostAppearance: appModel.hostAppearance,
            systemColorScheme: systemColorScheme
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            theme.background
                .ignoresSafeArea()

            Group {
                if appModel.hasSavedPairing {
                    SidekickHomeView(
                        appModel: appModel,
                        selectedSection: $selectedSection
                    )
                } else {
                    PairingView(appModel: appModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.sidekickTheme, theme)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.textPrimary)
        .onChange(of: appModel.pendingApprovals.count) { oldCount, newCount in
            if oldCount == 0, newCount > 0 {
                selectedSection = .approvals
            }
        }
        .onChange(of: appModel.hasSavedPairing) { _, hasSavedPairing in
            if !hasSavedPairing {
                selectedSection = .threads
            }
        }
    }
}
