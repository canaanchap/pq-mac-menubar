import AppKit
import SwiftUI
import Foundation

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
            let trackMode = appState.currentMenubarTrackMode
            let progressPercent = appState.sessionStarted ? appState.menubarProgressPercent(for: activeCharacter) : 0
            let labelText = appState.menubarLabelText(started: appState.sessionStarted, character: activeCharacter)
            let shieldImage = MenubarShieldIconCatalog.shared.image(
                started: appState.sessionStarted,
                mode: trackMode,
                percent: progressPercent
            )

            HStack(spacing: 5) {
                if let shieldImage {
                    Image(nsImage: shieldImage)
                        .renderingMode(.original)
                        .interpolation(.none)
                } else {
                    Image(systemName: "shield")
                }
                Text(labelText)
                if appState.sessionStarted && appState.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                }
            }
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
}

@MainActor
private final class MenubarShieldIconCatalog {
    static let shared = MenubarShieldIconCatalog()

    private var cache: [String: NSImage] = [:]
    private let pointSize = NSSize(width: 18, height: 18)

    func image(started: Bool, mode: MenubarIconTrackMode, percent: Double) -> NSImage? {
        let relativePath: String
        if !started {
            relativePath = "blank/shield-blank-18px.png"
        } else {
            let bucket = bucketForPercent(percent)
            switch mode {
            case .level:
                relativePath = "level/18px/shield-green-18px-\(bucket).png"
            case .currentTask:
                relativePath = "current_task/18px/shield-red-18px-\(bucket).png"
            case .currentQuest:
                relativePath = "current_quest/18px/shield-yellow-18px-\(bucket).png"
            case .plotDevelopment:
                relativePath = "plot_development/18px/shield-blue-18px-\(bucket).png"
            case .encumbrance:
                relativePath = "encumbrance/18px/shield-orange-18px-\(bucket).png"
            }
        }

        if let cached = cache[relativePath] {
            return cached
        }

        for root in assetRoots() {
            let url = root.appendingPathComponent(relativePath)
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = false
                image.size = pointSize
                cache[relativePath] = image
                return image
            }
        }
        return nil
    }

    private func bucketForPercent(_ percent: Double) -> Int {
        let clamped = max(0, min(100, percent))
        if clamped <= 0 {
            return 1
        }
        return max(1, min(10, Int(ceil(clamped / 10.0))))
    }

    private func assetRoots() -> [URL] {
        let fm = FileManager.default
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        var roots: [URL] = [
            cwd.appendingPathComponent("assets/exports", isDirectory: true),
            cwd.appendingPathComponent("../assets/exports", isDirectory: true),
            cwd.appendingPathComponent("../../assets/exports", isDirectory: true),
        ]

        if let resources = Bundle.main.resourceURL {
            roots.append(resources.appendingPathComponent("assets/exports", isDirectory: true))
            roots.append(resources.appendingPathComponent("Resources/assets/exports", isDirectory: true))
        }
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/assets/exports", isDirectory: true))

        return roots
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
