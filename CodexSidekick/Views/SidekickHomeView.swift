import Observation
import SwiftUI

struct SidekickHomeView: View {
    @Bindable var appModel: AppModel
    @Binding var selectedSection: SidekickSection

    var body: some View {
        ZStack(alignment: .top) {
            rootSectionContainer(isActive: selectedSection == .threads) {
                ThreadBrowserView(
                    appModel: appModel,
                    selectedSection: $selectedSection
                )
            }

            rootSectionContainer(isActive: selectedSection == .approvals) {
                ApprovalInboxView(
                    appModel: appModel,
                    selectedSection: $selectedSection
                )
            }

            rootSectionContainer(isActive: selectedSection == .settings) {
                SettingsView(
                    appModel: appModel,
                    selectedSection: $selectedSection
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func rootSectionContainer<Content: View>(
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }
}
