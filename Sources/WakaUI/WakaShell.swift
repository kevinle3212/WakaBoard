import SwiftUI
import WakaCore

/// Top-level routes.
///
/// Five, not nine. The five data dimensions live behind one picker on the Breakdown
/// screen rather than as five sidebar rows that differ only in which array they
/// read — a distinction that is invisible on a Mac sidebar and fatal on a watch.
public enum WakaRoute: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case activity = "Activity"
    case breakdown = "Breakdown"
    case insights = "Insights"
    case settings = "Settings"

    public var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .activity: "chart.xyaxis.line"
        case .breakdown: "chart.pie"
        case .insights: "lightbulb"
        case .settings: "gearshape"
        }
    }

    /// Maps a validated deep link onto a route.
    ///
    /// `/projects` and `/languages` are older links still live in shipped widgets;
    /// they resolve to the Breakdown screen, which then opens on their dimension.
    public init(_ deepLink: DeepLink) {
        switch deepLink {
        case .overview: self = .overview
        case .activity: self = .activity
        case .breakdown, .projects, .languages: self = .breakdown
        case .insights: self = .insights
        case .settings: self = .settings
        }
    }
}

/// The app shell. Owns the model and routes between screens.
///
/// One type, three layouts. A split view is right on a Mac, an iPad, an iPhone, and
/// in the Vision Pro's shared space; it is wrong on a watch, where there is no room
/// for a sidebar, and wrong on a television, where navigation is a focus engine and
/// a remote rather than a pointer. Those two get shells of their own rather than a
/// shrunk copy of this one.
public struct WakaShellView: View {
    @State private var model: WakaUIModel
    @State private var selection: WakaRoute? = .overview

    /// - Parameter environment: Defaults to the live environment; tests and previews
    ///   inject their own.
    public init(environment: WakaEnvironment = .live()) {
        _model = State(initialValue: WakaUIModel(environment: environment))
    }

    /// Accepts a model owned by the app, so a menu command and the views share state.
    public init(model: WakaUIModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        platformShell
            .task { await model.start() }
            .onOpenURL { url in
                guard let link = DeepLink(url: url, scheme: WakaIdentifiers.urlScheme) else { return }
                if let dimension = link.dimension { model.selectedDimension = dimension }
                selection = WakaRoute(link)
            }
    }

    @ViewBuilder private var platformShell: some View {
        #if os(watchOS)
        WatchShell(model: model, selection: $selection)
        #elseif os(tvOS)
        TelevisionShell(model: model, selection: $selection)
        #else
        SplitShell(model: model, selection: $selection)
        #endif
    }
}

// MARK: - Split shell (macOS, iOS, iPadOS, visionOS)

#if !os(watchOS) && !os(tvOS)
/// The sidebar-and-detail shell used everywhere a sidebar makes sense.
private struct SplitShell: View {
    let model: WakaUIModel
    @Binding var selection: WakaRoute?

    var body: some View {
        NavigationSplitView {
            List(WakaRoute.allCases, selection: $selection) { route in
                Label(route.rawValue, systemImage: route.icon)
                    .frame(minHeight: WakaAccessibility.minimumTargetSize)
                    .tag(route)
            }
            .navigationTitle("WakaBoard")
            #if os(macOS)
            // Bound the sidebar so it can neither be dragged narrow enough to clip a
            // route label nor wide enough to starve the detail pane.
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            #endif
        } detail: {
            WakaDetailView(model: model, selection: selection, onConnect: { selection = .overview })
                #if os(visionOS)
                // The platform's own surface treatment, rather than an iPad window
                // floating in space with an opaque background.
                .glassBackgroundEffect()
                #endif
        }
        #if os(macOS)
        // The floor the window's `.contentSize` resizability enforces: below this the
        // metric grid and the charts start to clip.
        .frame(minWidth: 640, minHeight: 480)
        #endif
    }
}
#endif

// MARK: - Watch shell

#if os(watchOS)
/// The watch shell: a stack over a list, because a watch has no sidebar.
///
/// Sign-in is deliberately absent. Typing a forty-character secret on a watch is not
/// a real flow, and offering it would be a worse answer than saying plainly that the
/// key is entered on the iPhone or the Mac.
private struct WatchShell: View {
    let model: WakaUIModel
    @Binding var selection: WakaRoute?

    /// Settings is a full page of legal links; the watch shows the three data routes.
    private var routes: [WakaRoute] { [.overview, .activity, .breakdown] }

    var body: some View {
        NavigationStack {
            if model.isSignedIn {
                List {
                    ForEach(routes) { route in
                        NavigationLink(value: route) {
                            Label(route.rawValue, systemImage: route.icon)
                                .frame(minHeight: WakaAccessibility.minimumTargetSize)
                        }
                    }
                }
                .navigationTitle("WakaBoard")
                .navigationDestination(for: WakaRoute.self) { route in
                    WakaDetailView(model: model, selection: route)
                }
            } else {
                WakaStateView(
                    title: "Sign In on iPhone",
                    message: "Open WakaBoard on your iPhone or Mac and connect your WakaTime account. "
                        + "This watch reads the analytics that device has already loaded."
                )
                .navigationTitle("WakaBoard")
            }
        }
    }
}
#endif

// MARK: - Television shell

#if os(tvOS)
/// The television shell: a tab bar the focus engine can traverse.
///
/// No sidebar, no pull-to-refresh, and no control that assumes a pointer. Every
/// screen here is reachable with a remote's four directions and a select button,
/// which is the only input this platform guarantees.
private struct TelevisionShell: View {
    let model: WakaUIModel
    @Binding var selection: WakaRoute?

    var body: some View {
        TabView(selection: Binding(get: { selection ?? .overview }, set: { selection = $0 })) {
            ForEach(WakaRoute.allCases) { route in
                WakaDetailView(model: model, selection: route)
                    .tabItem { Label(route.rawValue, systemImage: route.icon) }
                    .tag(route)
            }
        }
    }
}
#endif

// MARK: - Detail

/// The screen for one route, including what to show before the user has signed in.
struct WakaDetailView: View {
    let model: WakaUIModel
    let selection: WakaRoute?
    /// Sends the user to the screen that carries the sign-in form.
    ///
    /// Optional because the watch and the television have no sign-in form to send
    /// anyone to, and a button that goes nowhere is worse than no button.
    var onConnect: (() -> Void)?

    var body: some View {
        // Settings stays reachable when signed out, and each data screen explains
        // itself rather than the whole app collapsing into the sign-in form — which
        // made the sidebar look broken.
        if !model.isSignedIn, selection != .settings {
            signedOut
        } else {
            switch selection {
            case .overview: WakaDashboardView(model: model)
            case .activity: WakaActivityView(model: model)
            case .breakdown: WakaBreakdownView(model: model)
            case .insights: WakaInsightsView(model: model)
            case .settings: WakaSettingsView(model: model)
            case nil:
                WakaStateView(title: "WakaBoard", message: "Choose a section from the sidebar.")
            }
        }
    }

    @ViewBuilder private var signedOut: some View {
        #if os(watchOS)
        WakaStateView(
            title: "Not Connected",
            message: "Connect your WakaTime account on your iPhone or Mac to see your analytics here."
        )
        #else
        switch selection {
        case .overview, nil:
            WakaSignInView(model: model)
        default:
            WakaStateView(
                title: "Not Connected",
                message: "Connect your WakaTime account to see \((selection ?? .overview).rawValue.lowercased()).",
                actionLabel: onConnect == nil ? nil : "Connect WakaTime",
                action: onConnect
            )
        }
        #endif
    }
}
