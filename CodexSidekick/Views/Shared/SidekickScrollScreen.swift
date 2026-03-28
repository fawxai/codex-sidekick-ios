import SwiftUI

struct SidekickScrollScreen<Content: View, TopBar: View, BottomBar: View>: View {
    private let maxContentWidth: CGFloat?
    private let horizontalPadding: CGFloat
    private let topSpacing: CGFloat
    private let bottomSpacing: CGFloat
    private let scrollTargetID: String?
    private let scrollTargetToken: String?
    private let scrollTargetAnchor: UnitPoint
    private let animateScrollTarget: Bool
    private let onRefresh: (() async -> Void)?
    private let showsTopBar: Bool
    private let showsBottomBar: Bool
    private let content: Content
    private let topBar: TopBar
    private let bottomBar: BottomBar

    private init(
        maxContentWidth: CGFloat?,
        horizontalPadding: CGFloat,
        topSpacing: CGFloat,
        bottomSpacing: CGFloat,
        scrollTargetID: String?,
        scrollTargetToken: String?,
        scrollTargetAnchor: UnitPoint,
        animateScrollTarget: Bool,
        onRefresh: (() async -> Void)?,
        showsTopBar: Bool,
        showsBottomBar: Bool,
        content: Content,
        topBar: TopBar,
        bottomBar: BottomBar
    ) {
        self.maxContentWidth = maxContentWidth
        self.horizontalPadding = horizontalPadding
        self.topSpacing = topSpacing
        self.bottomSpacing = bottomSpacing
        self.scrollTargetID = scrollTargetID
        self.scrollTargetToken = scrollTargetToken
        self.scrollTargetAnchor = scrollTargetAnchor
        self.animateScrollTarget = animateScrollTarget
        self.onRefresh = onRefresh
        self.showsTopBar = showsTopBar
        self.showsBottomBar = showsBottomBar
        self.content = content
        self.topBar = topBar
        self.bottomBar = bottomBar
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if showsTopBar {
                    topBar
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.bottom, topSpacing)
                }

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        content
                            .frame(maxWidth: maxContentWidth, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, showsTopBar ? 0 : topSpacing)
                            .padding(.bottom, showsBottomBar ? 0 : bottomSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .scrollIndicators(.hidden)
                    .modifier(SidekickRefreshableModifier(onRefresh: onRefresh))
                    .onAppear {
                        scrollToTarget(with: scrollProxy)
                    }
                    .onChange(of: scrollTargetID) { _, _ in
                        scrollToTarget(with: scrollProxy)
                    }
                    .onChange(of: scrollTargetToken) { _, _ in
                        scrollToTarget(with: scrollProxy)
                    }
                }

                if showsBottomBar {
                    bottomBar
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .padding(.top, bottomSpacing)
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .top
            )
        }
    }

    private func scrollToTarget(with proxy: ScrollViewProxy) {
        guard let scrollTargetID else {
            return
        }

        Task { @MainActor in
            await Task.yield()
            if animateScrollTarget {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(scrollTargetID, anchor: scrollTargetAnchor)
                }
            } else {
                proxy.scrollTo(scrollTargetID, anchor: scrollTargetAnchor)
            }
        }
    }
}

extension SidekickScrollScreen where BottomBar == EmptyView {
    init(
        maxContentWidth: CGFloat? = nil,
        horizontalPadding: CGFloat = 16,
        topSpacing: CGFloat = 6,
        bottomSpacing: CGFloat = 14,
        scrollTargetID: String? = nil,
        scrollTargetToken: String? = nil,
        scrollTargetAnchor: UnitPoint = .top,
        animateScrollTarget: Bool = false,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder topBar: () -> TopBar,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            maxContentWidth: maxContentWidth,
            horizontalPadding: horizontalPadding,
            topSpacing: topSpacing,
            bottomSpacing: bottomSpacing,
            scrollTargetID: scrollTargetID,
            scrollTargetToken: scrollTargetToken,
            scrollTargetAnchor: scrollTargetAnchor,
            animateScrollTarget: animateScrollTarget,
            onRefresh: onRefresh,
            showsTopBar: true,
            showsBottomBar: false,
            content: content(),
            topBar: topBar(),
            bottomBar: EmptyView()
        )
    }
}

extension SidekickScrollScreen where TopBar == EmptyView, BottomBar == EmptyView {
    init(
        maxContentWidth: CGFloat? = nil,
        horizontalPadding: CGFloat = 16,
        topSpacing: CGFloat = 6,
        bottomSpacing: CGFloat = 14,
        scrollTargetID: String? = nil,
        scrollTargetToken: String? = nil,
        scrollTargetAnchor: UnitPoint = .top,
        animateScrollTarget: Bool = false,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            maxContentWidth: maxContentWidth,
            horizontalPadding: horizontalPadding,
            topSpacing: topSpacing,
            bottomSpacing: bottomSpacing,
            scrollTargetID: scrollTargetID,
            scrollTargetToken: scrollTargetToken,
            scrollTargetAnchor: scrollTargetAnchor,
            animateScrollTarget: animateScrollTarget,
            onRefresh: onRefresh,
            showsTopBar: false,
            showsBottomBar: false,
            content: content(),
            topBar: EmptyView(),
            bottomBar: EmptyView()
        )
    }
}

extension SidekickScrollScreen {
    init(
        maxContentWidth: CGFloat? = nil,
        horizontalPadding: CGFloat = 16,
        topSpacing: CGFloat = 6,
        bottomSpacing: CGFloat = 14,
        scrollTargetID: String? = nil,
        scrollTargetToken: String? = nil,
        scrollTargetAnchor: UnitPoint = .top,
        animateScrollTarget: Bool = false,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder topBar: () -> TopBar,
        @ViewBuilder bottomBar: () -> BottomBar,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            maxContentWidth: maxContentWidth,
            horizontalPadding: horizontalPadding,
            topSpacing: topSpacing,
            bottomSpacing: bottomSpacing,
            scrollTargetID: scrollTargetID,
            scrollTargetToken: scrollTargetToken,
            scrollTargetAnchor: scrollTargetAnchor,
            animateScrollTarget: animateScrollTarget,
            onRefresh: onRefresh,
            showsTopBar: true,
            showsBottomBar: true,
            content: content(),
            topBar: topBar(),
            bottomBar: bottomBar()
        )
    }
}

private struct SidekickRefreshableModifier: ViewModifier {
    let onRefresh: (() async -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onRefresh {
            content.refreshable {
                await onRefresh()
            }
        } else {
            content
        }
    }
}
