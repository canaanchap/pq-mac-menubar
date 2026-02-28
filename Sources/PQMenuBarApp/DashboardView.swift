import AppKit
import SwiftUI
import PQCore

private enum VisualTestMode: String {
    case liveRaw = "Test 1: Live Raw Bar"
    case reentrySnapAnimate = "Test 2: Re-entry Snap, then Animate"
    case percentageOnly = "Test 3: Percentage-only smoothing"
    case interpolatedCap = "Test4 : Interpolated display with cap"
    case sessionAnchored = "Test 5: Session-anchored bar (relative cycle view)"
}

struct DashboardView: View {
    private enum Tab: Hashable {
        case overview
        case characterLog
        case settings
    }

    private enum OverviewPanel: CaseIterable, Hashable {
        case characterSheet
        case equipment
        case plotDevelopment
        case spellBook
        case inventory
        case quests
    }

    @EnvironmentObject var appState: AppState
    @State private var apiKeyDraft: String = ""
    @State private var showDeleteAPIKeyAlert: Bool = false
    @State private var selectedTab: Tab = .overview
    @State private var showDeveloperMode: Bool = false
    @State private var keyMonitor: Any?
    @State private var debugTickEdited: Bool = false
    @State private var showDebugSummary: Bool = false
    @State private var visualTestMode: VisualTestMode?
    @State private var overviewMaskEnabled: Bool = false
    @State private var overviewMaskVisible: Bool = false
    @State private var readyOverviewPanels: Set<OverviewPanel> = Set(OverviewPanel.allCases)
    @State private var reentryMaskTask: Task<Void, Never>?

    private let tickRateOptions: [Double] = [0.25, 0.5, 1, 2, 4, 8, 16, 32]

    var body: some View {
        TabView(selection: $selectedTab) {
            overview
                .tabItem { Text("Overview") }
                .tag(Tab.overview)

            characterAndLog
                .tabItem { Text("Character + Log") }
                .tag(Tab.characterLog)

            settings
                .tabItem { Text("Settings") }
                .tag(Tab.settings)
        }
        .frame(minWidth: 980, minHeight: 650)
        .onAppear {
            overviewMaskEnabled = appState.betaReentryLoadMaskEnabled
            installKeyboardMonitorIfNeeded()
            applyRequestedTab()
            if selectedTab == .overview {
                triggerOverviewReentryMaskIfNeeded()
            }
        }
        .onChange(of: appState.dashboardRouteToken) { _, _ in
            applyRequestedTab()
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .overview {
                triggerOverviewReentryMaskIfNeeded()
            } else {
                stopReentryMask()
            }
        }
        .onChange(of: appState.betaReentryLoadMaskEnabled) { _, enabled in
            overviewMaskEnabled = enabled
            if selectedTab == .overview {
                triggerOverviewReentryMaskIfNeeded()
            } else {
                stopReentryMask()
            }
        }
        .onDisappear {
            removeKeyboardMonitor()
            stopReentryMask()
        }
        .overlay(alignment: .top) {
            if let msg = appState.statusMessage {
                Text(msg)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 10)
            }
        }
        .overlay {
            if showDeveloperMode {
                developerOverlay
            }
            if let mode = visualTestMode {
                visualsTesterOverlay(mode: mode)
            }
        }
        .alert("Delete API Key?", isPresented: $showDeleteAPIKeyAlert) {
            Button("Delete", role: .destructive) {
                appState.clearOpenAIAPIKey()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved key and disables automatic portrait generation.")
        }
    }

    private var overview: some View {
        let p = appState.state.activeCharacter

        return VStack(spacing: 6) {
            HStack {
                if showDebugSummary {
                    Text("Debug Active: \(String(format: "%.2fx", appState.tickRateMultiplier))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.25), in: Capsule())
                }
                Spacer()
                Button {
                    if appState.sessionStarted {
                        appState.togglePause()
                    } else {
                        appState.startSelectedCharacter()
                    }
                } label: {
                    Image(systemName: appState.sessionStarted ? (appState.state.isPaused ? "play.fill" : "pause.fill") : "play.fill")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(appState.sessionStarted ? (appState.state.isPaused ? "Resume" : "Pause") : "Start")
                .disabled(!appState.sessionStarted && appState.roster.isEmpty)
            }

            HStack(alignment: .top, spacing: 8) {
                panel("Character Sheet") {
                    VStack(alignment: .leading, spacing: 2) {
                        kv("Name", p.name)
                        kv("Race", p.race)
                        kv("Class", p.characterClass)
                        kv("Level", "\(p.level)")
                        Divider().padding(.vertical, 2)
                        statsGrid(p)
                        Divider().padding(.vertical, 2)
                        kv("Experience", "\(Int(p.expBar.position))/\(Int(p.expBar.max))")
                        metricBar(p.xpProgressPercent, color: .green)
                    }
                }
                .frame(minWidth: 265, maxWidth: 300)
                .overlay { overviewPanelMask(.characterSheet) }

                panel("Equipment") {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(EquipmentType.allCases, id: \.rawValue) { type in
                            HStack(alignment: .top) {
                                Text(type.rawValue)
                                    .frame(width: 100, alignment: .leading)
                                equipmentText(p.equipment[type.rawValue])
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity)
                .overlay { overviewPanelMask(.equipment) }

                panel("Plot Development") {
                    VStack(alignment: .leading, spacing: 2) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                if p.questBook.act <= 0 {
                                    Text("[ ] Prologue")
                                } else {
                                    if p.questBook.act > 1 {
                                        ForEach(Array((1..<(p.questBook.act)).enumerated()), id: \.offset) { _, act in
                                            Text("[x] \(PQLingo.actName(act))")
                                        }
                                    }
                                    Text("[ ] \(PQLingo.actName(p.questBook.act))")
                                }
                            }
                        }
                        Divider().padding(.vertical, 2)
                        metricBar(percentFromBar(p.questBook.plotBar), color: .blue)
                    }
                }
                .frame(minWidth: 190, maxWidth: 220)
                .overlay { overviewPanelMask(.plotDevelopment) }
            }

            HStack(alignment: .top, spacing: 8) {
                panel("Spell Book") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            if p.spells.isEmpty {
                                Text("No spells memorized yet")
                            } else {
                                ForEach(Array(p.spells.sorted(by: { $0.level > $1.level }).prefix(30).enumerated()), id: \.offset) { _, spell in
                                    HStack {
                                        Text(spell.name)
                                        Spacer()
                                        Text(PQLingo.toRoman(spell.level))
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: 265, maxWidth: 300)
                .overlay { overviewPanelMask(.spellBook) }

                panel("Inventory") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Gold")
                            Spacer()
                            Text("\(p.inventoryGold)")
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(p.inventoryItems.prefix(40).enumerated()), id: \.offset) { _, item in
                                    HStack {
                                        Text(item.name)
                                        Spacer()
                                        Text("\(item.quantity)")
                                    }
                                }
                            }
                        }
                        Divider().padding(.vertical, 2)
                        Text("Encumbrance (\(encumbrance(p))/\(p.inventoryCapacity) cubits)")
                        metricBar(encumbrancePercent(p), color: .orange)
                    }
                }
                .frame(minWidth: 300, maxWidth: 340)
                .overlay { overviewPanelMask(.inventory) }

                panel("Quests") {
                    VStack(alignment: .leading, spacing: 2) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 1) {
                                let recent = Array(p.questBook.quests.suffix(25))
                                if recent.count > 1 {
                                    ForEach(Array(recent.dropLast().enumerated()), id: \.offset) { _, quest in
                                        Text("[x] \(quest)")
                                    }
                                }
                                if let current = recent.last {
                                    Text("[ ] \(current)")
                                }
                            }
                        }
                        Divider().padding(.vertical, 2)
                        metricBar(percentFromBar(p.questBook.questBar), color: .yellow)
                    }
                }
                .frame(minWidth: 290, maxWidth: .infinity)
                .overlay { overviewPanelMask(.quests) }
            }

            panel(nil) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((p.task?.description ?? "Loading") + "...")
                    plainTaskMetricBar(p.taskProgressPercent)
                }
            }
            .frame(height: 58)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .textSelection(.enabled)
    }

    private var characterAndLog: some View {
        let player = appState.state.activeCharacter

        return VStack(alignment: .leading, spacing: 12) {
            Text("\(player.name)'s Journal")
                .font(.title3.weight(.bold))

            GroupBox("Score Sheet") {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        keyValue("Name", player.name)
                        keyValue("Race", player.race)
                        keyValue("Current Quest", player.questBook.currentQuest ?? "?")
                        keyValue("Current Task", (player.task?.description ?? "?") + "...")
                    }
                    .frame(maxWidth: 320, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        keyValue("Level", "\(player.level)")
                        keyValue("Class", player.characterClass)
                        keyValue("Best Prime Stat", player.stats.bestPrime.rawValue)
                        keyValue("Best Equipment", player.bestEquipment)
                    }
                    .frame(maxWidth: 320, alignment: .leading)

                    Spacer(minLength: 10)

                    portraitSection
                        .frame(width: 180, height: 180)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Journal") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(appState.events) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.message)
                                Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("Gameplay") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("🚧 Compact menubar mode (Coming soon)", isOn: .constant(false))
                            .toggleStyle(.switch)
                            .disabled(true)
                        Toggle("Persistent progress window (minimize + frame restore)", isOn: $appState.persistentDashboardWindow)
                            .toggleStyle(.switch)
                        Toggle(
                            "Low CPU mode",
                            isOn: Binding(
                                get: { appState.state.lowCPUMode },
                                set: { _ in appState.toggleLowCPU() }
                            )
                        )
                        .toggleStyle(.switch)
                        HStack {
                            Button(appState.sessionStarted ? (appState.state.isPaused ? "Resume" : "Pause") : "Start") {
                                if appState.sessionStarted {
                                    appState.togglePause()
                                } else {
                                    appState.startSelectedCharacter()
                                }
                            }
                            .disabled(!appState.sessionStarted && appState.roster.isEmpty)
                            Button("Close Current Character") {
                                appState.closeCurrentCharacter()
                            }
                            .disabled(!appState.sessionStarted)
                            Button("Save Now") {
                                appState.saveNow()
                            }
                            .disabled(!appState.sessionStarted)
                            Button("Quit App") {
                                appState.quitApp()
                            }
                        }
                    }
                }

                GroupBox("Character Library") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker("Selected", selection: Binding(
                                get: { appState.selectedCharacterID },
                                set: {
                                    appState.selectedCharacterID = $0
                                    appState.refreshPortraitForCurrentCharacter()
                                }
                            )) {
                                Text("-").tag(Optional<UUID>.none)
                                ForEach(appState.roster, id: \.id) { c in
                                    Text("\(c.name) • Lv \(c.level) \(c.race) \(c.characterClass)").tag(Optional(c.id))
                                }
                            }
                            .pickerStyle(.menu)

                            Button("Load and Start") {
                                appState.loadAndStartSelectedCharacter()
                                selectedTab = .overview
                            }
                            .disabled(appState.selectedCharacterID == nil)
                        }

                        HStack {
                            Button("Delete Selected") { appState.deleteSelectedCharacter() }
                                .disabled(appState.selectedCharacterID == nil)
                            Button("Upload (Import)") { appState.importCharacterInteractive() }
                            Button("Download (Export)") { appState.exportCharacterInteractive() }
                                .disabled(appState.selectedCharacterID == nil)
                        }
                    }
                }

                GroupBox("Portraits + API") {
                    VStack(alignment: .leading, spacing: 10) {
                        if appState.hasOpenAIAPIKey {
                            HStack {
                                SecureField("", text: .constant("••••••••••••••••"))
                                    .disabled(true)
                                Button(role: .destructive) {
                                    showDeleteAPIKeyAlert = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                            }
                        } else {
                            HStack {
                                SecureField("OpenAI API Key", text: $apiKeyDraft)
                                Button("Save Key") {
                                    appState.saveOpenAIAPIKey(apiKeyDraft)
                                    apiKeyDraft = ""
                                }
                                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        Text("Portraits auto-generate on level up. If a base image exists for this character, it is used for consistency.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Prompt template: \(appState.dataDirectory.data.appendingPathComponent("portrait-prompt.txt").path)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                GroupBox("Data + Paths") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Reload Data (+Mods)") {
                                appState.reloadDataAndMods()
                            }
                            Spacer()
                        }

                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                pathRow("Data", appState.dataDirectory.data)
                                pathRow("Mods", appState.dataDirectory.mods)
                                pathRow("Saves", appState.dataDirectory.saves)
                                pathRow("Logs", appState.dataDirectory.logs)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                loadedDataTwoColumns
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Divider()
                        Text("Validation Report")
                            .font(.subheadline.weight(.semibold))
                        ScrollView {
                            Text(appState.dataValidationReport)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120, maxHeight: 180)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding()
        }
    }

    private var loadedDataTwoColumns: some View {
        let rows: [(String, Int)] = [
            ("Classes", appState.dataBundle.classes.count),
            ("Races", appState.dataBundle.races.count),
            ("Monsters", appState.dataBundle.monsters.count),
            ("Spells", appState.dataBundle.spells.count),
            ("Weapons", appState.dataBundle.weapons.count),
            ("Armors", appState.dataBundle.armors.count),
            ("Shields", appState.dataBundle.shields.count),
            ("Item Attributes", appState.dataBundle.itemAttrib.count),
            ("Item Of", appState.dataBundle.itemOfs.count),
            ("Boring Items", appState.dataBundle.boringItems.count),
            ("Titles", appState.dataBundle.titles.count),
            ("Impressive Titles", appState.dataBundle.impressiveTitles.count),
        ]

        return Grid(horizontalSpacing: 14, verticalSpacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                if idx % 2 == 0 {
                    GridRow {
                        Text("\(row.0): \(row.1)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if idx + 1 < rows.count {
                            let other = rows[idx + 1]
                            Text("\(other.0): \(other.1)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("")
                        }
                    }
                }
            }
        }
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(key):")
                .fontWeight(.bold)
            Text(value)
        }
    }

    private var portraitPlaceholder: some View {
        EmptyView()
    }

    private var portraitSection: some View {
        GroupBox("Portrait") {
            VStack(spacing: 8) {
                if let image = appState.portraitNSImage() {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "person.crop.square")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .foregroundStyle(.secondary)
                    Text("No portrait")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pathRow(_ label: String, _ url: URL) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .frame(width: 48, alignment: .leading)
            Text(url.path)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open in Finder") {
                appState.openInFinder(url)
            }
        }
    }

    private func panel<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } label: {
            if let title {
                Text(title)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func kv(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statsGrid(_ p: PlayerState) -> some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 2) {
            GridRow {
                Text("STR").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.strength])").frame(width: 46, alignment: .leading)
                Text("DEX").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.dexterity])").frame(width: 46, alignment: .leading)
            }
            GridRow {
                Text("CON").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.condition])").frame(width: 46, alignment: .leading)
                Text("INT").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.intelligence])").frame(width: 46, alignment: .leading)
            }
            GridRow {
                Text("WIS").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.wisdom])").frame(width: 46, alignment: .leading)
                Text("CHA").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.charisma])").frame(width: 46, alignment: .leading)
            }
            GridRow {
                Text("HP Max").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.hpMax])").frame(width: 46, alignment: .leading)
                Text("")
                Text("")
            }
            GridRow {
                Text("MP Max").frame(width: 56, alignment: .leading)
                Text("\(p.stats[.mpMax])").frame(width: 46, alignment: .leading)
                Text("")
                Text("")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricBar(_ percent: Double, color: Color) -> some View {
        AnimatedMetricBar(percent: percent, color: color)
    }

    private func plainTaskMetricBar(_ percent: Double) -> some View {
        ProgressView(value: max(0, min(100, percent)), total: 100)
            .tint(.red)
            .overlay(alignment: .center) {
                Text(String(format: "%.2f%%", max(0, min(100, percent))))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
    }

    private var developerOverlay: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture { closeDeveloperMode() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Developer Mode")
                        .font(.headline)
                    Spacer()
                    Button {
                        closeDeveloperMode()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }

                GroupBox("Portrait Tools") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Send Portrait API Request") {
                            appState.generatePortraitForCurrentCharacter()
                            appState.flashDebug("Debug: portrait request submitted.")
                        }
                    }
                }

                GroupBox("Simulation Rate") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tick Rate")
                            Picker("", selection: Binding(
                                get: { appState.tickRateMultiplier },
                                set: {
                                    appState.setTickRateMultiplier($0)
                                    debugTickEdited = true
                                }
                            )) {
                                ForEach(tickRateOptions, id: \.self) { value in
                                    Text(String(format: "%.2fx", value)).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        Text("Current: \(String(format: "%.2fx", appState.tickRateMultiplier))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Visuals") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Beta re-entry load mask", isOn: Binding(
                            get: { appState.betaReentryLoadMaskEnabled },
                            set: { appState.betaReentryLoadMaskEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        Button(VisualTestMode.liveRaw.rawValue) {
                            visualTestMode = .liveRaw
                        }
                        Button(VisualTestMode.reentrySnapAnimate.rawValue) {
                            visualTestMode = .reentrySnapAnimate
                        }
                        Button(VisualTestMode.percentageOnly.rawValue) {
                            visualTestMode = .percentageOnly
                        }
                        Button(VisualTestMode.interpolatedCap.rawValue) {
                            visualTestMode = .interpolatedCap
                        }
                        Button(VisualTestMode.sessionAnchored.rawValue) {
                            visualTestMode = .sessionAnchored
                        }
                    }
                }
            }
            .padding(14)
            .frame(width: 320)
            .background(Color.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func visualsTesterOverlay(mode: VisualTestMode) -> some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
                .onTapGesture { visualTestMode = nil }

            VisualTestDemoCard(mode: mode)
                .frame(width: 520)
                .padding(16)
                .background(Color.white.opacity(0.98), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
        }
    }

    private func installKeyboardMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                if visualTestMode != nil {
                    visualTestMode = nil
                    return nil
                }
                if showDeveloperMode {
                    closeDeveloperMode()
                    return nil
                }
                NSApp.keyWindow?.performClose(nil)
                return nil
            }
            guard selectedTab == .overview else { return event }
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if event.modifierFlags.contains(.shift), chars == "d" {
                showDeveloperMode = true
                return nil
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func closeDeveloperMode() {
        showDeveloperMode = false
        let hasNonDefaultTick = abs(appState.tickRateMultiplier - 1.0) > 0.001
        showDebugSummary = hasNonDefaultTick

        if hasNonDefaultTick {
            appState.flashDebug("Debug active: tick \(String(format: "%.2fx", appState.tickRateMultiplier))")
        } else if debugTickEdited {
            appState.flashDebug("Debug reset to default (1.00x).")
        }
        debugTickEdited = false
    }

    private func applyRequestedTab() {
        switch appState.dashboardRequestedTab {
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .overview
        }
    }

    private func triggerOverviewReentryMaskIfNeeded() {
        guard overviewMaskEnabled else {
            stopReentryMask()
            return
        }

        reentryMaskTask?.cancel()
        overviewMaskVisible = true
        readyOverviewPanels = []

        reentryMaskTask = Task { @MainActor in
            let reveals = OverviewPanel.allCases
                .map { ($0, Double.random(in: 0.10...0.24)) }
                .sorted { $0.1 < $1.1 }
            var elapsed: Double = 0
            for (panel, delay) in reveals {
                let wait = max(0, delay - elapsed)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                guard !Task.isCancelled else { return }
                _ = withAnimation(.easeOut(duration: 0.08)) {
                    readyOverviewPanels.insert(panel)
                }
                elapsed = delay
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.easeOut(duration: 0.06)) {
                overviewMaskVisible = false
            }
        }
    }

    private func stopReentryMask() {
        reentryMaskTask?.cancel()
        reentryMaskTask = nil
        overviewMaskVisible = false
        readyOverviewPanels = Set(OverviewPanel.allCases)
    }

    private func encumbrance(_ p: PlayerState) -> Int {
        p.inventoryItems.reduce(0) { $0 + $1.quantity }
    }

    private func encumbrancePercent(_ p: PlayerState) -> Double {
        guard p.inventoryCapacity > 0 else { return 0 }
        return (Double(encumbrance(p)) / Double(p.inventoryCapacity)) * 100.0
    }

    private func percentFromBar(_ bar: Bar) -> Double {
        guard bar.max > 0 else { return 0 }
        return (bar.position / bar.max) * 100.0
    }

    private func equipmentText(_ value: String?) -> some View {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AnyView(Text(value))
        }
        return AnyView(Text("(none)").foregroundStyle(.tertiary))
    }

    @ViewBuilder
    private func overviewPanelMask(_ panel: OverviewPanel) -> some View {
        if overviewMaskVisible && !readyOverviewPanels.contains(panel) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.18))
                ProgressView()
                    .controlSize(.small)
            }
            .transition(.opacity)
        }
    }
}

private struct VisualTestDemoCard: View {
    let mode: VisualTestMode
    @State private var selectedPane: Int = 0
    @State private var rawA: Double = 0
    @State private var rawB: Double = 0

    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mode.rawValue)
                .font(.headline)
            Text("Flip tabs to simulate view switching. ESC or click outside to close.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Pane", selection: $selectedPane) {
                Text("Tab A").tag(0)
                Text("Tab B").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedPane == 0 {
                VisualTestPane(mode: mode, title: "Short Task Cycle", rawPercent: rawA)
            } else {
                VisualTestPane(mode: mode, title: "Long Task Cycle", rawPercent: rawB)
            }
        }
        .onReceive(timer) { _ in
            rawA = advance(rawA, by: 2.4)
            rawB = advance(rawB, by: 0.9)
        }
    }

    private func advance(_ value: Double, by delta: Double) -> Double {
        let next = value + delta
        return next > 100 ? 0 : next
    }
}

private struct VisualTestPane: View {
    let mode: VisualTestMode
    let title: String
    let rawPercent: Double

    @State private var displayed: Double = 0
    @State private var smoothedLabel: Double = 0
    @State private var anchor: Double = 0
    @State private var lastRaw: Double = 0
    @State private var reentryAt: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ProgressView(value: displayed, total: 100)
                .tint(.red)
                .overlay(alignment: .center) {
                    Text(String(format: "%.1f%%", labelPercent))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }

            HStack(spacing: 14) {
                Text("Raw: \(Int(rawPercent))%")
                Text("Shown: \(Int(displayed))%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            displayed = rawPercent
            smoothedLabel = rawPercent
            anchor = rawPercent
            lastRaw = rawPercent
            reentryAt = .now
        }
        .onChange(of: rawPercent) { _, newRaw in
            advance(raw: newRaw)
        }
    }

    private var labelPercent: Double {
        mode == .percentageOnly ? smoothedLabel : displayed
    }

    private func advance(raw: Double) {
        let wrapped = raw + 0.001 < lastRaw

        switch mode {
        case .liveRaw:
            displayed = raw
            smoothedLabel = raw

        case .reentrySnapAnimate:
            if Date().timeIntervalSince(reentryAt) > 2.8 {
                reentryAt = .now
                displayed = raw
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    displayed = raw
                }
            }
            smoothedLabel = raw

        case .percentageOnly:
            displayed = raw
            smoothedLabel += (raw - smoothedLabel) * 0.25

        case .interpolatedCap:
            let delta = raw - displayed
            let step = max(-3.5, min(3.5, delta))
            displayed = clamped(displayed + step)
            smoothedLabel = displayed

        case .sessionAnchored:
            if wrapped {
                anchor = 0
                displayed = raw
            } else {
                let denom = max(0.001, 100 - anchor)
                let remapped = ((raw - anchor) / denom) * 100
                displayed = clamped(remapped)
            }
            smoothedLabel = displayed
        }

        if mode == .sessionAnchored, lastRaw <= 0.001, raw > 0 {
            anchor = raw
            displayed = 0
        }
        lastRaw = raw
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(100, value))
    }
}

private struct AnimatedMetricBar: View {
    let percent: Double
    let color: Color

    @State private var displayed: Double
    @State private var appearedAt: Date = .distantPast

    init(percent: Double, color: Color) {
        self.percent = percent
        self.color = color
        _displayed = State(initialValue: max(0, min(100, percent)))
    }

    var body: some View {
        ProgressView(value: displayed, total: 100)
            .tint(color)
            .onAppear {
                appearedAt = Date()
                displayed = clamped(percent)
            }
            .onChange(of: percent) { _, newValue in
                // Re-entry: snap first, then animate future updates.
                if Date().timeIntervalSince(appearedAt) < 0.25 {
                    displayed = clamped(newValue)
                } else {
                    withAnimation(.easeOut(duration: 0.22)) {
                        displayed = clamped(newValue)
                    }
                }
            }
            .overlay(alignment: .center) {
                Text(String(format: "%.2f%%", clamped(percent)))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
    }

    private func clamped(_ value: Double) -> Double {
        max(0, min(100, value))
    }
}
