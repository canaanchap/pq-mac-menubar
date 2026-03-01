import SwiftUI
import AppKit
import PQCore

struct PopoverView: View {
    private enum DashboardRoute: String {
        case overview
        case settings
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var creatingCharacter: Bool = false
    @State private var newCharacterName: String = ""
    @State private var suggestedCharacterName: String = ""
    @State private var newCharacterRace: String = ""
    @State private var newCharacterClass: String = ""
    @State private var rolledStats: Stats?
    @State private var previousRolledStats: Stats?

    var body: some View {
        if appState.sessionStarted {
            startedView
        } else if creatingCharacter {
            createCharacterView
        } else {
            launchMenuView
        }
    }

    private var launchMenuView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress Quest")
                .font(.title3.weight(.bold))

            Text("Choose a character to start.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Character", selection: Binding(
                get: { appState.selectedCharacterID },
                set: {
                    appState.selectedCharacterID = $0
                    appState.refreshPortraitForCurrentCharacter()
                }
            )) {
                Text("-").tag(Optional<UUID>.none)
                ForEach(appState.roster, id: \.id) { c in
                    Text("\(c.name) • Lv \(c.level) \(c.race) \(c.characterClass)")
                        .tag(Optional(c.id))
                }
            }
            .pickerStyle(.menu)

            HStack {
                Button("Start") {
                    appState.startSelectedCharacter()
                }
                .disabled(appState.selectedCharacterID == nil)

                Button("New Character") {
                    beginCreateCharacter()
                }

                Button("Delete") {
                    appState.deleteSelectedCharacter()
                }
                .disabled(appState.selectedCharacterID == nil)
            }

            HStack {
                Button("Upload") {
                    appState.importCharacterInteractive()
                }
                Button("Download") {
                    appState.exportCharacterInteractive()
                }
                .disabled(appState.selectedCharacterID == nil)
            }

            Divider()

            HStack {
                Button("View Progress") {
                    openDashboardWindow(route: .overview)
                }
                Button("Settings") {
                    openDashboardWindow(route: .settings)
                }
            }

            Toggle("Low CPU", isOn: Binding(
                get: { appState.state.lowCPUMode },
                set: { _ in appState.toggleLowCPU() }
            ))
            .toggleStyle(.switch)

            Divider()
            Button("Quit Progress Quest") {
                appState.quitApp()
            }
        }
        .padding(12)
        .frame(width: 480)
    }

    private var createCharacterView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Character")
                .font(.title3.weight(.bold))

            TextField(suggestedCharacterName.isEmpty ? "Name" : suggestedCharacterName, text: $newCharacterName)

            Picker("Race", selection: $newCharacterRace) {
                ForEach(Array(appState.dataBundle.races.map(\.name).enumerated()), id: \.offset) { _, race in
                    Text(race).tag(race)
                }
            }
            .pickerStyle(.menu)

            Picker("Class", selection: $newCharacterClass) {
                ForEach(Array(appState.dataBundle.classes.map(\.name).enumerated()), id: \.offset) { _, cls in
                    Text(cls).tag(cls)
                }
            }
            .pickerStyle(.menu)

            GroupBox("Rolled Stats") {
                VStack(alignment: .leading, spacing: 2) {
                    if let s = rolledStats {
                        statLine("STR", s[.strength])
                        statLine("CON", s[.condition])
                        statLine("DEX", s[.dexterity])
                        statLine("INT", s[.intelligence])
                        statLine("WIS", s[.wisdom])
                        statLine("CHA", s[.charisma])
                        statLine("HP Max", s[.hpMax])
                        statLine("MP Max", s[.mpMax])
                    }
                }
            }

            HStack {
                Button("Roll") {
                    previousRolledStats = rolledStats
                    rolledStats = appState.rollStats()
                }
                Button("Unroll") {
                    guard let previousRolledStats else { return }
                    rolledStats = previousRolledStats
                    self.previousRolledStats = nil
                }
                .disabled(previousRolledStats == nil)
                Button("Create") {
                    let name = newCharacterName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalName = name.isEmpty ? (suggestedCharacterName.isEmpty ? appState.generateFantasyName() : suggestedCharacterName) : name
                    appState.createCharacter(
                        name: finalName,
                        race: newCharacterRace,
                        className: newCharacterClass,
                        stats: rolledStats
                    )
                    creatingCharacter = false
                    previousRolledStats = nil
                    suggestedCharacterName = ""
                }
                Button("Randomize + Start") {
                    let randomRace = appState.dataBundle.races.randomElement()?.name ?? "Half Orc"
                    let randomClass = appState.dataBundle.classes.randomElement()?.name ?? "Ur-Paladin"
                    let randomStats = appState.rollStats()
                    let randomName = appState.generateFantasyName()

                    newCharacterRace = randomRace
                    newCharacterClass = randomClass
                    newCharacterName = randomName
                    rolledStats = randomStats
                    previousRolledStats = nil

                    appState.createCharacter(
                        name: randomName,
                        race: randomRace,
                        className: randomClass,
                        stats: randomStats
                    )
                    creatingCharacter = false
                }
                Button("Cancel") {
                    creatingCharacter = false
                    previousRolledStats = nil
                    suggestedCharacterName = ""
                }
            }
        }
        .padding(12)
        .frame(width: 480)
    }

    private var startedView: some View {
        let player = appState.state.activeCharacter

        return VStack(alignment: .leading, spacing: 10) {
            Text(player.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text("Lv \(player.level) • \(player.race) \(player.characterClass)")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Quest: \(player.questBook.currentQuest ?? "?")")
                .font(.body)
                .foregroundStyle(.primary)
            Text("Task: \((player.task?.description ?? "?"))...")
                .font(.body)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Task Progress \(Int(player.taskProgressPercent))%")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        appState.togglePause()
                    } label: {
                        Image(systemName: appState.state.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(appState.state.isPaused ? "Start" : "Pause")
                }
                PopoverTaskProgressBar(percent: player.taskProgressPercent)
            }

            Divider()

            HStack {
                Button("View Progress") {
                    openDashboardWindow(route: .overview)
                }
                Button("Settings") {
                    openDashboardWindow(route: .settings)
                }
                Button("Close Character") {
                    appState.closeCurrentCharacter()
                }
            }

            Toggle("Low CPU", isOn: Binding(
                get: { appState.state.lowCPUMode },
                set: { _ in appState.toggleLowCPU() }
            ))
            .toggleStyle(.switch)

            Divider()
            Button("Quit Progress Quest") {
                appState.quitApp()
            }
        }
        .padding(12)
        .frame(width: 420)
    }

    private func beginCreateCharacter() {
        if newCharacterRace.isEmpty {
            newCharacterRace = appState.dataBundle.races.first?.name ?? "Half Orc"
        }
        if newCharacterClass.isEmpty {
            newCharacterClass = appState.dataBundle.classes.first?.name ?? "Ur-Paladin"
        }
        suggestedCharacterName = appState.generateFantasyName()
        newCharacterName = ""
        rolledStats = appState.rollStats()
        previousRolledStats = nil
        creatingCharacter = true
    }

    private func statLine(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .leading)
            Text("\(value)")
            Spacer()
        }
    }

    private func openDashboardWindow(route: DashboardRoute) {
        appState.requestDashboardTab(route.rawValue)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "dashboard")
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let window = NSApp.windows.first(where: { $0.title == "Dashboard" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

private struct PopoverTaskProgressBar: View {
    let percent: Double
    @State private var displayed: Double
    @State private var appearedAt: Date = .distantPast

    init(percent: Double) {
        self.percent = percent
        _displayed = State(initialValue: max(0, min(100, percent)))
    }

    var body: some View {
        ProgressView(value: displayed, total: 100)
            .tint(.red)
            .onAppear {
                appearedAt = Date()
                displayed = clamped(percent)
            }
            .onChange(of: percent) { _, newValue in
                if Date().timeIntervalSince(appearedAt) < 0.25 {
                    displayed = clamped(newValue)
                } else {
                    withAnimation(.easeOut(duration: 0.22)) {
                        displayed = clamped(newValue)
                    }
                }
            }
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(100, value))
    }
}
