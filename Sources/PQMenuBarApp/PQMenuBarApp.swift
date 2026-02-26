import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct PQMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(appState)
        } label: {
            HStack(spacing: 6) {
                ShieldXPView(percent: appState.state.activeCharacter.xpProgressPercent)
                    .frame(width: 14, height: 16)
                if appState.sessionStarted && appState.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                Text("Lv \(appState.state.activeCharacter.level)")
                if !appState.compactMode {
                    if appState.sessionStarted {
                        let pct = Int(appState.state.activeCharacter.taskProgressPercent)
                        Text(miniBar(percent: pct))
                            .foregroundStyle(.secondary)
                        Text("\(pct)%")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Ready")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .opacity(appState.sessionStarted && appState.state.isPaused ? 0.55 : 1.0)
            .help("Progress Quest")
        }
        .menuBarExtraStyle(.window)

        Window("Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(appState)
                .background(
                    DashboardWindowConfigurator(
                        persistentMode: appState.persistentDashboardWindow
                    )
                )
        }
        .defaultSize(width: 980, height: 620)
    }

    private func miniBar(percent: Int) -> String {
        let clamped = max(0, min(100, percent))
        let fill = Int(round(Double(clamped) / 20.0))
        return "[" + String(repeating: "=", count: fill) + String(repeating: " ", count: max(0, 5 - fill)) + "]"
    }
}

private struct DashboardWindowConfigurator: NSViewRepresentable {
    let persistentMode: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            apply(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            apply(window: nsView.window)
        }
    }

    private func apply(window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.miniaturizable)
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        if persistentMode {
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("PQDashboardWindow")
        } else {
            window.isReleasedWhenClosed = true
        }
    }
}

private struct ShieldXPView: View {
    let percent: Double

    var body: some View {
        ZStack {
            Image(systemName: "shield.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: 6.5)
                }
            Image(systemName: "shield")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
        }
        .frame(width: 13, height: 15)
    }
}
