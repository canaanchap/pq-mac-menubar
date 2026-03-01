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
            let activeCharacter = appState.state.activeCharacter
            let progressPercent = appState.sessionStarted ? appState.menubarProgressPercent(for: activeCharacter) : 0
            let trackMode = appState.sessionStarted ? appState.menubarTrackMode(for: activeCharacter) : .level
            let trackColor: Color = switch trackMode {
            case .level: .green
            case .currentTask: .red
            case .currentQuest: .yellow
            case .encumbrance: .orange
            }

            HStack(spacing: 6) {
                ShieldXPView(percent: progressPercent, rightFillColor: trackColor)
                    .frame(width: 14, height: 16)
                if appState.sessionStarted && appState.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(appState.sessionStarted ? "Lv \(appState.state.activeCharacter.level)" : "Lv ?")
                    .foregroundStyle(appState.sessionStarted ? .primary : .secondary)
                if !appState.compactMode {
                    if appState.sessionStarted {
                        let pct = Int(appState.state.activeCharacter.taskProgressPercent)
                        Text(miniBar(percent: pct))
                            .foregroundStyle(.secondary)
                        Text("\(pct)%")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .opacity(appState.sessionStarted && appState.state.isPaused ? 0.55 : (appState.sessionStarted ? 1.0 : 0.7))
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
    let rightFillColor: Color

    var body: some View {
        GeometryReader { geo in
            let ratio = max(0, min(100, percent)) / 100.0
            let halfWidth = geo.size.width * 0.5

            ZStack(alignment: .bottom) {
                ShieldShape()
                    .fill(Color.primary)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: halfWidth)
                    }

                ShieldShape()
                    .fill(rightFillColor)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: halfWidth)
                    }
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: geo.size.height * ratio)
                    }

                ShieldShape()
                    .stroke(Color.primary, lineWidth: 1.2)
            }
        }
        .frame(width: 13, height: 15)
    }
}

private struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let top = CGPoint(x: rect.midX, y: rect.minY + h * 0.05)
        let rightTop = CGPoint(x: rect.minX + w * 0.85, y: rect.minY + h * 0.20)
        let rightMid = CGPoint(x: rect.minX + w * 0.86, y: rect.minY + h * 0.57)
        let bottom = CGPoint(x: rect.midX, y: rect.minY + h * 0.95)
        let leftMid = CGPoint(x: rect.minX + w * 0.14, y: rect.minY + h * 0.57)
        let leftTop = CGPoint(x: rect.minX + w * 0.15, y: rect.minY + h * 0.20)

        var p = Path()
        p.move(to: top)
        p.addLine(to: rightTop)
        p.addCurve(
            to: rightMid,
            control1: CGPoint(x: rect.minX + w * 0.89, y: rect.minY + h * 0.30),
            control2: CGPoint(x: rect.minX + w * 0.91, y: rect.minY + h * 0.46)
        )
        p.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.minX + w * 0.82, y: rect.minY + h * 0.75),
            control2: CGPoint(x: rect.minX + w * 0.63, y: rect.minY + h * 0.92)
        )
        p.addCurve(
            to: leftMid,
            control1: CGPoint(x: rect.minX + w * 0.37, y: rect.minY + h * 0.92),
            control2: CGPoint(x: rect.minX + w * 0.18, y: rect.minY + h * 0.75)
        )
        p.addCurve(
            to: leftTop,
            control1: CGPoint(x: rect.minX + w * 0.09, y: rect.minY + h * 0.46),
            control2: CGPoint(x: rect.minX + w * 0.11, y: rect.minY + h * 0.30)
        )
        p.closeSubpath()
        return p
    }
}
