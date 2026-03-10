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
        case multiplayer
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
        case mainProgress
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
    @State private var mainProgressLoadingActive: Bool = false
    @State private var lastObservedTaskProgressPercent: Double = 0
    @State private var lastObservedTaskDescription: String = ""
    @State private var showCreateCharacterDialog: Bool = false
    @State private var newCharacterNameDraft: String = ""
    @State private var newCharacterNameSuggestion: String = ""
    @State private var newCharacterRaceDraft: String = ""
    @State private var newCharacterClassDraft: String = ""
    @State private var newCharacterStatsDraft: Stats?
    @State private var previousCharacterStatsDraft: Stats?
    @State private var newCharacterOnlineModeDraft: Bool = false
    @State private var multiplayerEmailDraft: String = ""
    @State private var multiplayerPasswordDraft: String = ""
    @State private var multiplayerPublicNameDraft: String = ""
    @State private var multiplayerWantsNewsDraft: Bool = true
    @State private var multiplayerSignInEmailDraft: String = ""
    @State private var multiplayerSignInPasswordDraft: String = ""
    @State private var showCreateAccountSheet: Bool = false
    @State private var showAccountSettingsSheet: Bool = false
    @State private var showDeleteCharacterConfirm: Bool = false
    @State private var guildFormalNameDraft: String = ""
    @State private var guildShortTagDraft: String = ""
    @State private var guildAlignmentDraft: String = "Neutral"
    @State private var guildTypeDraft: String = "Guild"
    @State private var guildMottoDraft: String = ""
    @State private var guildSelectedToJoin: String = ""
    @State private var guildMajorityTypeDraft: String = "functional_50"
    @State private var guildMajorityBasisDraft: String = "present"
    @State private var guildQuorumEnabledDraft: Bool = false
    @State private var guildQuorumPercentDraft: String = "60"
    @State private var guildNoConfidenceEnabledDraft: Bool = false
    @State private var showMPGovernancePanel: Bool = false
    @State private var showMPProceduralPanel: Bool = false

    private let tickRateOptions: [Double] = [0.25, 0.5, 1, 2, 4, 8, 16, 32]
    private var canShowMultiplayerTab: Bool {
        let candidate: PlayerState? = appState.sessionStarted ? appState.state.activeCharacter : appState.selectedCharacter
        guard let candidate else { return false }
        return candidate.isOnlineMultiplayer
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            overview
                .tabItem { Text("Overview") }
                .tag(Tab.overview)

            if canShowMultiplayerTab {
                multiplayer
                    .tabItem { Text("Multiplayer") }
                    .tag(Tab.multiplayer)
            }

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
            } else if newTab == .multiplayer {
                appState.refreshMultiplayerRealmAndGuildState()
            } else {
                stopReentryMask()
            }
        }
        .onChange(of: canShowMultiplayerTab) { _, show in
            if !show && selectedTab == .multiplayer {
                selectedTab = .overview
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
        .onChange(of: appState.state.activeCharacter.taskProgressPercent) { _, newPercent in
            handleMainProgressLoadingGate(newPercent: newPercent, newTaskDescription: appState.state.activeCharacter.task?.description ?? "")
        }
        .onChange(of: appState.state.activeCharacter.task?.description ?? "") { _, newTaskDescription in
            handleMainProgressLoadingGate(newPercent: appState.state.activeCharacter.taskProgressPercent, newTaskDescription: newTaskDescription)
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
        .alert("Delete selected character?", isPresented: $showDeleteCharacterConfirm) {
            Button("Delete", role: .destructive) {
                appState.deleteSelectedCharacter()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the selected character from your roster.")
        }
        .sheet(isPresented: $showCreateCharacterDialog) {
            createCharacterDialog
        }
        .sheet(isPresented: $showCreateAccountSheet) {
            createAccountDialog
        }
        .sheet(isPresented: $showAccountSettingsSheet) {
            accountSettingsDialog
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
                        ScrollViewReader { proxy in
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
                                    Color.clear.frame(height: 1).id("plot-bottom")
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    proxy.scrollTo("plot-bottom", anchor: .bottom)
                                }
                            }
                            .onChange(of: p.questBook.act) { _, _ in
                                DispatchQueue.main.async {
                                    proxy.scrollTo("plot-bottom", anchor: .bottom)
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
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 1) {
                                    ForEach(Array(p.inventoryItems.prefix(40).enumerated()), id: \.offset) { _, item in
                                        HStack {
                                            Text(item.name)
                                            Spacer()
                                            Text("\(item.quantity)")
                                        }
                                    }
                                    Color.clear.frame(height: 1).id("inventory-bottom")
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    proxy.scrollTo("inventory-bottom", anchor: .bottom)
                                }
                            }
                            .onChange(of: p.inventoryItems.count) { _, _ in
                                DispatchQueue.main.async {
                                    proxy.scrollTo("inventory-bottom", anchor: .bottom)
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
                        ScrollViewReader { proxy in
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
                                    Color.clear.frame(height: 1).id("quests-bottom")
                                }
                            }
                            .onAppear {
                                DispatchQueue.main.async {
                                    proxy.scrollTo("quests-bottom", anchor: .bottom)
                                }
                            }
                            .onChange(of: p.questBook.quests.count) { _, _ in
                                DispatchQueue.main.async {
                                    proxy.scrollTo("quests-bottom", anchor: .bottom)
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
                    if overviewMaskVisible && mainProgressLoadingActive {
                        Color.clear
                            .frame(height: 12)
                    } else {
                        plainTaskMetricBar(p.taskProgressPercent)
                    }
                }
            }
            .frame(height: 58)
            .overlay { overviewPanelMask(.mainProgress) }
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

    private var multiplayer: some View {
        let active = appState.state.activeCharacter
        let selected = appState.selectedCharacter
        let target = appState.sessionStarted ? active : selected
        let hasSession = appState.multiplayerSession.map { !$0.isExpired } ?? false

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !hasSession {
                    GroupBox("Multiplayer") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("You are not signed in to a multiplayer account.")
                                .foregroundStyle(.secondary)
                            Button("Open Settings: Multiplayer Account") {
                                selectedTab = .settings
                            }
                        }
                    }
                } else {
                    GroupBox("Online Multiplayer Character Sheet") {
                        VStack(alignment: .leading, spacing: 8) {
                            if let target {
                                if let mismatch = appState.multiplayerOwnershipMismatchMessage(for: target) {
                                    Text(mismatch)
                                        .foregroundStyle(.red)
                                }
                                HStack { Text("Character:"); Text(target.name).foregroundStyle(.secondary) }
                                HStack { Text("Mode:"); Text((target.networkMode ?? "offline").capitalized).foregroundStyle(.secondary) }
                                HStack { Text("Realm ID:"); Text(target.realmId ?? "-").foregroundStyle(.secondary) }
                                HStack { Text("Server Character ID:"); Text(target.serverCharacterId ?? "-").foregroundStyle(.secondary) }
                                HStack { Text("Tracking Status:"); Text(appState.multiplayerOwnershipMismatchMessage(for: target) == nil ? "Eligible" : "Blocked").foregroundStyle(appState.multiplayerOwnershipMismatchMessage(for: target) == nil ? .green : .red) }
                            } else {
                                Text("No character selected.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GroupBox("Guildhall") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Picker("Existing Guild", selection: $guildSelectedToJoin) {
                                    Text("-").tag("")
                                    ForEach(appState.multiplayerGuildDirectory) { g in
                                        Text("\(g.formalName) (\(g.shortTag))").tag(g.guildId)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: guildSelectedToJoin) { _, newID in
                                    guard !newID.isEmpty else { return }
                                    appState.loadGuildProfile(guildId: newID)
                                }
                                Button("Join") {
                                    guard !guildSelectedToJoin.isEmpty else { return }
                                    appState.joinGuild(guildId: guildSelectedToJoin)
                                }
                                .disabled(guildSelectedToJoin.isEmpty)
                            }

                            if let profile = appState.multiplayerGuildProfile {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(profile.formalName) (\(profile.shortTag))")
                                        .font(.headline)
                                    Text("Status: \(profile.status) • Members: \(profile.memberCount) • Chief: \(profile.chiefName)")
                                        .foregroundStyle(.secondary)
                                    Text("Alignment: \(profile.alignmentCode) • Type: \(profile.typeCode)")
                                        .foregroundStyle(.secondary)
                                    Text("Majority: \(profile.rules.majorityType) • Basis: \(profile.rules.majorityBasis)")
                                        .foregroundStyle(.secondary)
                                    Text("Quorum: \(profile.rules.quorumEnabled ? "On \(profile.rules.quorumPercent ?? 0)%" : "Off") • No confidence: \(profile.rules.noConfidenceEnabled ? "On" : "Off")")
                                        .foregroundStyle(.secondary)
                                    if !profile.motto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Motto: \(profile.motto)")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Button("Leave Guild") {
                                    appState.leaveCurrentGuild()
                                }
                            } else {
                                Text("No guild currently loaded.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    GroupBox("Create Guild / Governance") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Formal Name", text: $guildFormalNameDraft)
                                TextField("Short Tag", text: $guildShortTagDraft)
                            }
                            HStack {
                                Picker("Alignment", selection: $guildAlignmentDraft) {
                                    ForEach(appState.multiplayerAlignmentOptions.filter(\.include)) { option in
                                        Text(option.displayName).tag(option.code)
                                    }
                                }
                                Picker("Type", selection: $guildTypeDraft) {
                                    ForEach(appState.multiplayerTypeOptions.filter(\.include)) { option in
                                        Text(option.displayName).tag(option.code)
                                    }
                                }
                            }
                            TextField("Motto", text: $guildMottoDraft)
                            HStack {
                                Picker("Majority", selection: $guildMajorityTypeDraft) {
                                    Text("50%").tag("functional_50")
                                    Text("3/5 (60%)").tag("three_fifths_60")
                                    Text("2/3 (66.7%)").tag("two_thirds_66_7")
                                    Text("3/4 (75%)").tag("three_fourths_75")
                                }
                                Picker("Basis", selection: $guildMajorityBasisDraft) {
                                    Text("Present").tag("present")
                                    Text("Absolute").tag("absolute")
                                }
                            }
                            Toggle("Quorum Enabled", isOn: $guildQuorumEnabledDraft)
                            if guildQuorumEnabledDraft {
                                TextField("Quorum %", text: $guildQuorumPercentDraft)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Toggle("No Confidence Enabled", isOn: $guildNoConfidenceEnabledDraft)
                            Button("Create Guild") {
                                appState.createGuild(
                                    formalName: guildFormalNameDraft,
                                    shortTag: guildShortTagDraft,
                                    alignmentCode: guildAlignmentDraft,
                                    typeCode: guildTypeDraft,
                                    motto: guildMottoDraft,
                                    majorityType: guildMajorityTypeDraft,
                                    majorityBasis: guildMajorityBasisDraft,
                                    quorumEnabled: guildQuorumEnabledDraft,
                                    quorumPercent: Int(guildQuorumPercentDraft),
                                    noConfidenceEnabled: guildNoConfidenceEnabledDraft
                                )
                            }
                            .disabled(guildFormalNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || guildShortTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    GroupBox("Guild Activity") {
                        VStack(alignment: .leading, spacing: 8) {
                            if appState.multiplayerGuildLogs.isEmpty {
                                Text("No guild activity loaded yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(appState.multiplayerGuildLogs) { log in
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(log.message)
                                                Text("\(log.type) • \(log.createdAt?.formatted(.dateTime.hour().minute()) ?? "-")")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 160)
                            }
                        }
                    }

                    GroupBox("Guild Progress (Placeholder Idle Loop)") {
                        VStack(alignment: .leading, spacing: 8) {
                            let pseudo = Double((target?.level ?? 1) % 100) / 100.0
                            ProgressView(value: pseudo)
                            Text("Council drafting charter amendments...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Show Governance Panel (Beta)", isOn: $showMPGovernancePanel)
                            Toggle("Show Procedural Feed (Beta)", isOn: $showMPProceduralPanel)
                        }
                    }

                    GroupBox("Connector") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API connector active.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let session = appState.multiplayerSession {
                                Text("Session: \(session.isExpired ? "Expired" : "Active")")
                                    .foregroundStyle(session.isExpired ? .red : .green)
                                Text("Session Expires: \(session.expiresAt.formatted(.dateTime.year().month().day().hour().minute()))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Session: Not signed in")
                                    .foregroundStyle(.secondary)
                            }
                            if let realms = appState.multiplayerRealmCache?.realms {
                                Text("Realms cached: \(realms.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Connector state: account + guild sync live.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            appState.refreshMultiplayerRealmAndGuildState()
            if let first = appState.multiplayerAlignmentOptions.first {
                guildAlignmentDraft = first.code
            }
            if let first = appState.multiplayerTypeOptions.first {
                guildTypeDraft = first.code
            }
        }
        .onChange(of: target?.id) { _, _ in
            Task {
                await appState.refreshGuildProfileForCurrentCharacter()
            }
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    GroupBox("Character Roster") {
                        VStack(alignment: .leading, spacing: 10) {
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(appState.roster, id: \.id) { c in
                                        Button {
                                            appState.selectedCharacterID = c.id
                                            appState.refreshPortraitForCurrentCharacter()
                                        } label: {
                                            HStack(spacing: 6) {
                                                if c.isOnlineMultiplayer {
                                                    Image(systemName: "globe")
                                                        .foregroundStyle(.gray)
                                                }
                                                Text("\(c.name) • Lv \(c.level) \(c.race) \(c.characterClass)")
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(appState.selectedCharacterID == c.id ? Color.accentColor.opacity(0.18) : Color.clear)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(minHeight: 140, maxHeight: 220)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                            HStack {
                                Button("Load and Start") {
                                    appState.loadAndStartSelectedCharacter()
                                    selectedTab = .overview
                                }
                                .disabled(appState.selectedCharacterID == nil)
                                Button("Delete Selected") {
                                    showDeleteCharacterConfirm = true
                                }
                                .disabled(appState.selectedCharacterID == nil)
                                Button("New Character") {
                                    beginCreateCharacterDialog()
                                }
                            }

                            HStack {
                                Button("Upload (Import)") { appState.importCharacterInteractive() }
                                Button("Download (Export)") { appState.exportCharacterInteractive() }
                                .disabled(appState.selectedCharacterID == nil)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    GroupBox("Gameplay") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Runtime State: \(appState.runtimeStateMarker.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Game Controls")
                                .font(.subheadline.weight(.semibold))
                            HStack {
                                Button(appState.sessionStarted ? (appState.state.isPaused ? "Resume" : "Pause") : "Start") {
                                    if appState.sessionStarted {
                                        appState.togglePause()
                                    } else {
                                        appState.startSelectedCharacter()
                                    }
                                }
                                .help(appState.sessionStarted ? "Loaded character: \(appState.state.activeCharacter.name)" : (appState.selectedCharacter.map { "Loaded character: \($0.name)" } ?? "No character loaded."))
                                .disabled(!appState.sessionStarted && appState.roster.isEmpty)
                                Button("Close Current Character") {
                                    appState.closeCurrentCharacter()
                                }
                                .disabled(appState.selectedCharacterID == nil)
                                Button("Save Now") {
                                    appState.saveNow()
                                }
                                .disabled(!appState.sessionStarted)
                                Button("Quit App") {
                                    appState.quitApp()
                                }
                            }

                            Divider()
                            Text("Display Settings")
                                .font(.subheadline.weight(.semibold))
                            HStack {
                                Text("Track What With Menubar Icon?")
                                Picker("Track What With Menubar Icon?", selection: Binding(
                                    get: { appState.currentMenubarTrackMode },
                                    set: { appState.setCurrentMenubarTrackMode($0) }
                                )) {
                                    ForEach(MenubarIconTrackMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }
                            Toggle("Show Level Instead of Selected Progress?", isOn: $appState.showLevelLabelInMenubar)
                                .toggleStyle(.switch)
                            Toggle("Show Character's Name Instead?", isOn: $appState.showCharacterNameInMenubar)
                                .toggleStyle(.switch)
                            Toggle(
                                "Low CPU mode",
                                isOn: Binding(
                                    get: { appState.state.lowCPUMode },
                                    set: { _ in appState.toggleLowCPU() }
                                )
                            )
                            .toggleStyle(.switch)
                            Toggle("Compact menubar mode (shield only)", isOn: $appState.compactMode)
                                .toggleStyle(.switch)
                            Toggle("Persistent progress window (minimize + frame restore)", isOn: $appState.persistentDashboardWindow)
                                .toggleStyle(.switch)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                GroupBox("Multiplayer Account") {
                    VStack(alignment: .leading, spacing: 10) {
                        let hasActiveSession = appState.multiplayerSession?.isExpired == false
                        if hasActiveSession, let account = appState.multiplayerAccount {
                            Text("Account: \(account.publicName) (\(account.email))")
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Account Settings") {
                                    showAccountSettingsSheet = true
                                }
                                Button("Log Out") {
                                    appState.multiplayerSignOutLocalSession()
                                }
                            }
                        } else {
                            HStack {
                                TextField("Email", text: $multiplayerSignInEmailDraft)
                                SecureField("Password", text: $multiplayerSignInPasswordDraft)
                                Button("Login") {
                                    appState.multiplayerSignIn(email: multiplayerSignInEmailDraft, password: multiplayerSignInPasswordDraft)
                                }
                            }

                            HStack {
                                Text("Don't have an account yet?")
                                    .foregroundStyle(.secondary)
                                Button("Create Account") {
                                    multiplayerEmailDraft = multiplayerSignInEmailDraft
                                    showCreateAccountSheet = true
                                }
                            }

                            HStack {
                                Button("Account Settings") {
                                    showAccountSettingsSheet = true
                                }
                                .disabled(true)
                            }
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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Text("1) Enable mods?")
                                    .frame(width: 170, alignment: .leading)
                                Toggle("", isOn: $appState.modsFeatureEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            HStack(spacing: 10) {
                                Text("2) Dry run validation?")
                                    .frame(width: 170, alignment: .leading)
                                if appState.modsFeatureEnabled {
                                    Button("Re-run") {
                                        appState.runModDryRunAndEnableIfValid()
                                    }
                                }
                                Text(appState.modsFeatureEnabled ? (appState.modsValidationPassed ? "Pass" : "Fail") : "-")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(appState.modsFeatureEnabled ? (appState.modsValidationPassed ? .green : .red) : .secondary)
                            }
                            HStack(spacing: 10) {
                                Text("3) Mods active?")
                                    .frame(width: 170, alignment: .leading)
                                Toggle("", isOn: $appState.modsActive)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .disabled(!(appState.modsFeatureEnabled && appState.modsValidationPassed))
                            }
                        }
                        Text(appState.modDryRunReport)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

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
                        if let debugCode = appState.lastMultiplayerDebugVerificationCode, let email = appState.multiplayerAccount?.email {
                            Text("Debug MP verification code for \(email): \(debugCode)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
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
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 150)
                        .clipped()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(6)
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
                        Toggle("Re-entry load mask", isOn: Binding(
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
        case "multiplayer":
            selectedTab = canShowMultiplayerTab ? .multiplayer : .settings
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
        mainProgressLoadingActive = true
        lastObservedTaskProgressPercent = appState.state.activeCharacter.taskProgressPercent
        lastObservedTaskDescription = appState.state.activeCharacter.task?.description ?? ""

        reentryMaskTask = Task { @MainActor in
            let reveals = OverviewPanel.allCases
                .filter { $0 != .mainProgress }
                .map { panel in
                    (panel, Double.random(in: 0.10...0.24))
                }
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
            if !mainProgressLoadingActive {
                withAnimation(.easeOut(duration: 0.06)) {
                    overviewMaskVisible = false
                }
            }
        }
    }

    private func stopReentryMask() {
        reentryMaskTask?.cancel()
        reentryMaskTask = nil
        overviewMaskVisible = false
        readyOverviewPanels = Set(OverviewPanel.allCases)
        mainProgressLoadingActive = false
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
        let isMainProgressMaskActive = panel == .mainProgress && overviewMaskVisible && mainProgressLoadingActive
        let isRegularMaskActive = panel != .mainProgress && overviewMaskVisible && !readyOverviewPanels.contains(panel)
        if isMainProgressMaskActive || isRegularMaskActive {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.18))
                ProgressView()
                    .controlSize(.small)
            }
            .transition(.opacity)
        }
    }

    private func handleMainProgressLoadingGate(newPercent: Double, newTaskDescription: String) {
        defer {
            lastObservedTaskProgressPercent = newPercent
            lastObservedTaskDescription = newTaskDescription
        }

        guard overviewMaskVisible, mainProgressLoadingActive, overviewMaskEnabled, selectedTab == .overview else { return }

        let taskChanged = !lastObservedTaskDescription.isEmpty && newTaskDescription != lastObservedTaskDescription
        let wrappedToNewCycle = lastObservedTaskProgressPercent > 90 && newPercent < 15
        if taskChanged || wrappedToNewCycle {
            withAnimation(.easeOut(duration: 0.06)) {
                mainProgressLoadingActive = false
            }

            // If every panel has cleared, remove overlay entirely.
            if readyOverviewPanels.count == OverviewPanel.allCases.filter({ $0 != .mainProgress }).count {
                withAnimation(.easeOut(duration: 0.06)) {
                    overviewMaskVisible = false
                }
            }
        }
    }

    private var createCharacterDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("New Character")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    showCreateCharacterDialog = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            TextField(newCharacterNameSuggestion.isEmpty ? "Name" : newCharacterNameSuggestion, text: $newCharacterNameDraft)
            Toggle("Online Multiplayer (immutable)", isOn: $newCharacterOnlineModeDraft)
                .toggleStyle(.switch)
                .disabled(!appState.canUseOnlineMultiplayer)
            if !appState.canUseOnlineMultiplayer {
                Text("Online multiplayer requires a verified signed-in account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Race", selection: $newCharacterRaceDraft) {
                ForEach(Array(appState.dataBundle.races.map(\.name).enumerated()), id: \.offset) { _, race in
                    Text(race).tag(race)
                }
            }
            .pickerStyle(.menu)

            Picker("Class", selection: $newCharacterClassDraft) {
                ForEach(Array(appState.dataBundle.classes.map(\.name).enumerated()), id: \.offset) { _, cls in
                    Text(cls).tag(cls)
                }
            }
            .pickerStyle(.menu)

            GroupBox("Rolled Stats") {
                VStack(alignment: .leading, spacing: 2) {
                    if let s = newCharacterStatsDraft {
                        createStatLine("STR", s[.strength])
                        createStatLine("CON", s[.condition])
                        createStatLine("DEX", s[.dexterity])
                        createStatLine("INT", s[.intelligence])
                        createStatLine("WIS", s[.wisdom])
                        createStatLine("CHA", s[.charisma])
                        createStatLine("HP Max", s[.hpMax])
                        createStatLine("MP Max", s[.mpMax])
                    }
                }
            }

            HStack {
                Button("Roll") {
                    previousCharacterStatsDraft = newCharacterStatsDraft
                    newCharacterStatsDraft = appState.rollStats()
                }
                Button("Unroll") {
                    guard let previousCharacterStatsDraft else { return }
                    newCharacterStatsDraft = previousCharacterStatsDraft
                    self.previousCharacterStatsDraft = nil
                }
                .disabled(previousCharacterStatsDraft == nil)
                Spacer()
            }

            HStack {
                Button("Create to Roster") {
                    createCharacterFromDialog(startImmediately: false, randomize: false)
                }
                Button("Create and Start") {
                    createCharacterFromDialog(startImmediately: true, randomize: false)
                }
            }

            HStack {
                Button("Randomize + Create to Roster") {
                    createCharacterFromDialog(startImmediately: false, randomize: true)
                }
                Button("Randomize + Start") {
                    createCharacterFromDialog(startImmediately: true, randomize: true)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 520)
        .onExitCommand {
            showCreateCharacterDialog = false
        }
    }

    private func beginCreateCharacterDialog() {
        newCharacterNameDraft = ""
        newCharacterNameSuggestion = appState.generateFantasyName()
        newCharacterRaceDraft = appState.dataBundle.races.first?.name ?? "Half Orc"
        newCharacterClassDraft = appState.dataBundle.classes.first?.name ?? "Ur-Paladin"
        newCharacterStatsDraft = appState.rollStats()
        previousCharacterStatsDraft = nil
        newCharacterOnlineModeDraft = appState.canUseOnlineMultiplayer
        showCreateCharacterDialog = true
    }

    private func createCharacterFromDialog(startImmediately: Bool, randomize: Bool) {
        var name = newCharacterNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        var race = newCharacterRaceDraft
        var className = newCharacterClassDraft
        var stats = newCharacterStatsDraft ?? appState.rollStats()

        if randomize {
            name = appState.generateFantasyName()
            race = appState.dataBundle.races.randomElement()?.name ?? race
            className = appState.dataBundle.classes.randomElement()?.name ?? className
            stats = appState.rollStats()
        } else if name.isEmpty {
            name = newCharacterNameSuggestion.isEmpty ? appState.generateFantasyName() : newCharacterNameSuggestion
        }

        if startImmediately && appState.sessionStarted {
            let ok = NSAlert.runAskYesNo(
                title: "Close current character?",
                message: "Current character will be saved and closed before starting the new one."
            )
            if !ok {
                return
            }
            appState.closeCurrentCharacter()
        }

        appState.createCharacter(
            name: name,
            race: race,
            className: className,
            stats: stats,
            startImmediately: startImmediately,
            networkMode: newCharacterOnlineModeDraft ? "online" : "offline"
        )
        newCharacterNameSuggestion = ""
        showCreateCharacterDialog = false
        if startImmediately {
            selectedTab = .overview
        }
    }

    @ViewBuilder
    private func characterPickerLabel(_ c: PlayerState) -> some View {
        if c.isOnlineMultiplayer {
            Label("\(c.name) • Lv \(c.level) \(c.race) \(c.characterClass)", systemImage: "globe")
                .foregroundStyle(.secondary)
        } else {
            Text("\(c.name) • Lv \(c.level) \(c.race) \(c.characterClass)")
        }
    }

    private var createAccountDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Create Multiplayer Account")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    showCreateAccountSheet = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            TextField("Email", text: $multiplayerEmailDraft)
            SecureField("Password", text: $multiplayerPasswordDraft)
            TextField("Public Name", text: $multiplayerPublicNameDraft)

            HStack {
                Button("Create Account") {
                    appState.multiplayerRegisterAccount(
                        email: multiplayerEmailDraft,
                        password: multiplayerPasswordDraft,
                        publicName: multiplayerPublicNameDraft,
                        wantsNews: true
                    )
                    showCreateAccountSheet = false
                }
                .disabled(
                    multiplayerEmailDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || multiplayerPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || multiplayerPublicNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                Button("Cancel") {
                    showCreateAccountSheet = false
                }
            }
        }
        .padding(14)
        .frame(minWidth: 420)
        .onExitCommand {
            showCreateAccountSheet = false
        }
    }

    private var accountSettingsDialog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Account Settings")
                    .font(.title3.weight(.bold))
                Spacer()
                Button {
                    showAccountSettingsSheet = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            if let account = appState.multiplayerAccount {
                Text("Display Name: \(account.publicName)")
                Toggle(
                    "Receive news?",
                    isOn: Binding(
                        get: { account.wantsNews },
                        set: { appState.updateMultiplayerNewsPreference($0) }
                    )
                )
                .toggleStyle(.switch)
                if account.verified {
                    Label("Verified", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not verified (online multiplayer disabled)", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            } else {
                Text("No account configured.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Close") {
                    showAccountSettingsSheet = false
                }
            }
        }
        .padding(14)
        .frame(minWidth: 420)
        .onExitCommand {
            showAccountSettingsSheet = false
        }
    }

    private func createStatLine(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .leading)
            Text("\(value)")
            Spacer()
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
