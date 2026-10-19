import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case home, dictionary, voice, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .voice: return "Voice training"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "wand.and.stars"
        case .dictionary: return "book.closed"
        case .voice: return "graduationcap"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @State private var settings = AppSettings.shared
    @State private var page: Page

    init(page: Page = .home) {
        _page = State(initialValue: page)
    }

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                HStack(spacing: 0) {
                    Sidebar(page: $page)
                        .frame(width: 216)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.page)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
                        .shadow(color: .black.opacity(0.04), radius: 6, y: 1)
                        .padding([.top, .trailing, .bottom], 10)
                }
                .background(VisualEffect().ignoresSafeArea())
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 860, minHeight: 580)
        .ignoresSafeArea()
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .home: HomeView(page: $page)
        case .dictionary: DictionaryView()
        case .voice: VoiceTrainingView()
        case .settings: SettingsView()
        }
    }
}

private struct Sidebar: View {
    @Binding var page: Page
    @State private var controller = DictationController.shared
    @State private var permissions = Permissions.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                AppMark(size: 26)
                Text("Inscribo")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
            }
            .padding(.leading, 10)
            .padding(.top, 44)
            .padding(.bottom, 18)

            ForEach(Page.allCases) { item in
                SidebarRow(item: item, selected: page == item) {
                    withAnimation(.easeOut(duration: 0.15)) { page = item }
                }
            }

            Spacer()

            StatusCard(page: $page)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }
}

private struct SidebarRow: View {
    let item: Page
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(item.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? Theme.accent : Color.primary.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.accentSoft : (hovering ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Bottom-of-sidebar card: shows what's blocking dictation, or a reminder of how to use it.
private struct StatusCard: View {
    @Binding var page: Page
    @State private var controller = DictationController.shared
    @State private var permissions = Permissions.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !permissions.allGranted {
                Label("Permissions needed", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.warm)
                Text("Inscribo needs microphone and accessibility access to type for you.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Fix in Settings") { page = .settings }
                    .buttonStyle(SecondaryButtonStyle())
                    .controlSize(.small)
            } else {
                switch controller.engineState {
                case .missing:
                    ModelDownloadStatus(compact: true)
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading model…").font(.system(size: 12))
                    }
                case .failed(let reason):
                    Label(reason, systemImage: "xmark.octagon.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                case .ready:
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("Wand ready").font(.system(size: 12, weight: .semibold))
                    }
                    HStack(spacing: 4) {
                        Text("Hold")
                        KeyCap(text: settings.triggerKey.shortLabel)
                        Text("to talk")
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        .onAppear { permissions.startPolling() }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Standard page scaffold: big serif title, subtitle, scrollable content.
struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Theme.title())
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 30)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
