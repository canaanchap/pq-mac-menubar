import AppKit
import Foundation
import PQCore
import UniformTypeIdentifiers

private struct RosterFile: Codable {
    var activeCharacterID: UUID?
    var characters: [PlayerState]
    var recentEventsByCharacterID: [String: [GameEvent]]?
}

private struct ModPatchBundle: Codable {
    var spells: [String]?
    var offenseAttrib: [Modifier]?
    var defenseAttrib: [Modifier]?
    var offenseBad: [Modifier]?
    var defenseBad: [Modifier]?
    var shields: [EquipmentPreset]?
    var armors: [EquipmentPreset]?
    var weapons: [EquipmentPreset]?
    var specials: [String]?
    var itemAttrib: [String]?
    var itemOfs: [String]?
    var boringItems: [String]?
    var monsters: [MonsterDef]?
    var races: [RaceDef]?
    var classes: [ClassDef]?
    var titles: [String]?
    var impressiveTitles: [String]?
    var primeStats: [String]?
    var equipmentTypes: [String]?
}

enum RuntimeStateMarker: String, Codable {
    case idle
    case running
    case paused
    case reloadingData
}

enum MenubarIconTrackMode: String, Codable, CaseIterable, Identifiable {
    case level = "Level"
    case currentTask = "Current Task"
    case currentQuest = "Current Quest"
    case plotDevelopment = "Plot Development"
    case encumbrance = "Encumbrance"

    var id: String { rawValue }
}

@MainActor
final class AppState: ObservableObject {
    @Published var state: GameState
    @Published var events: [GameEvent]
    @Published var compactMode: Bool {
        didSet {
            UserDefaults.standard.set(compactMode, forKey: Self.compactModeDefaultsKey)
        }
    }
    @Published var persistentDashboardWindow: Bool {
        didSet {
            UserDefaults.standard.set(persistentDashboardWindow, forKey: Self.persistentDashboardWindowDefaultsKey)
        }
    }

    @Published var roster: [PlayerState]
    @Published var selectedCharacterID: UUID?
    @Published var sessionStarted: Bool
    @Published var statusMessage: String?
    @Published private(set) var runtimeStateMarker: RuntimeStateMarker = .idle
    @Published var dashboardRequestedTab: String = "overview"
    @Published var dashboardRouteToken: Int = 0
    @Published var dataValidationReport: String = "No validation run yet."
    @Published var betaReentryLoadMaskEnabled: Bool {
        didSet {
            UserDefaults.standard.set(betaReentryLoadMaskEnabled, forKey: Self.betaReentryMaskDefaultsKey)
        }
    }
    @Published var portraitImageURL: URL?
    @Published var openAIAPIKey: String {
        didSet {
            UserDefaults.standard.set(openAIAPIKey, forKey: Self.openAIAPIKeyDefaultsKey)
        }
    }
    @Published var tickRateMultiplier: Double {
        didSet {
            UserDefaults.standard.set(tickRateMultiplier, forKey: Self.tickRateDefaultsKey)
        }
    }
    @Published var showLevelLabelInMenubar: Bool {
        didSet {
            UserDefaults.standard.set(showLevelLabelInMenubar, forKey: Self.showLevelLabelInMenubarDefaultsKey)
        }
    }
    @Published var modsFeatureEnabled: Bool {
        didSet {
            UserDefaults.standard.set(modsFeatureEnabled, forKey: Self.modsFeatureEnabledDefaultsKey)
            if modsFeatureEnabled {
                runModDryRunAndEnableIfValid()
            } else {
                modsActive = false
                modsValidationPassed = false
                modDryRunReport = "Mods disabled."
                reloadDataAndMods()
            }
        }
    }
    @Published var modsActive: Bool {
        didSet {
            UserDefaults.standard.set(modsActive, forKey: Self.modsActiveDefaultsKey)
            if modsFeatureEnabled {
                reloadDataAndMods()
            }
        }
    }
    @Published var modsValidationPassed: Bool = false
    @Published var modDryRunReport: String = "No mod validation run yet."

    let dataDirectory: DataDirectory
    let saveStore: SaveStore
    let logStore: EventLogStore
    let runtime: GameRuntime
    @Published var dataBundle: PQDataBundle

    private let rosterURL: URL
    private let portraitsURL: URL
    private let portraitPromptTemplateURL: URL
    private static let openAIAPIKeyDefaultsKey = "pq.openai.apiKey"
    private static let tickRateDefaultsKey = "pq.runtime.tickRate"
    private static let persistentDashboardWindowDefaultsKey = "pq.dashboard.persistentWindow"
    private static let betaReentryMaskDefaultsKey = "pq.debug.betaReentryMask"
    private static let menubarTrackByCharacterDefaultsKey = "pq.menubar.trackByCharacter"
    private static let showLevelLabelInMenubarDefaultsKey = "pq.menubar.showLevelLabel"
    private static let compactModeDefaultsKey = "pq.menubar.compactMode"
    private static let modsFeatureEnabledDefaultsKey = "pq.mods.featureEnabled"
    private static let modsActiveDefaultsKey = "pq.mods.active"
    private var portraitGenerationInFlightCharacterIDs: Set<UUID> = []
    private var lastSeenLevelByCharacterID: [UUID: Int] = [:]
    private var logArchiveTimer: DispatchSourceTimer?
    private var lastRosterPersistAt: Date = .distantPast
    private var menubarTrackByCharacterID: [UUID: MenubarIconTrackMode] = [:]
    private var recentEventsByCharacterID: [UUID: [GameEvent]] = [:]

    init() {
        do {
            dataDirectory = try DataDirectory()
            saveStore = SaveStore(dataDirectory: dataDirectory)
            logStore = EventLogStore(dataDirectory: dataDirectory)
            rosterURL = dataDirectory.saves.appendingPathComponent("characters.json")
            portraitsURL = dataDirectory.data.appendingPathComponent("portraits", isDirectory: true)
            try FileManager.default.createDirectory(at: portraitsURL, withIntermediateDirectories: true)
            openAIAPIKey = UserDefaults.standard.string(forKey: Self.openAIAPIKeyDefaultsKey) ?? ""
            let savedTickRate = UserDefaults.standard.double(forKey: Self.tickRateDefaultsKey)
            tickRateMultiplier = savedTickRate > 0 ? savedTickRate : 1.0
            compactMode = UserDefaults.standard.bool(forKey: Self.compactModeDefaultsKey)
            persistentDashboardWindow = UserDefaults.standard.bool(forKey: Self.persistentDashboardWindowDefaultsKey)
            if UserDefaults.standard.object(forKey: Self.betaReentryMaskDefaultsKey) == nil {
                betaReentryLoadMaskEnabled = true
            } else {
                betaReentryLoadMaskEnabled = UserDefaults.standard.bool(forKey: Self.betaReentryMaskDefaultsKey)
            }
            menubarTrackByCharacterID = Self.loadMenubarTrackMap()
            if UserDefaults.standard.object(forKey: Self.showLevelLabelInMenubarDefaultsKey) == nil {
                showLevelLabelInMenubar = true
            } else {
                showLevelLabelInMenubar = UserDefaults.standard.bool(forKey: Self.showLevelLabelInMenubarDefaultsKey)
            }
            let modsFeatureEnabledLoaded = UserDefaults.standard.bool(forKey: Self.modsFeatureEnabledDefaultsKey)
            let modsActiveLoaded = UserDefaults.standard.bool(forKey: Self.modsActiveDefaultsKey)
            modsFeatureEnabled = modsFeatureEnabledLoaded
            modsActive = modsActiveLoaded

            let userDataURL = dataDirectory.data.appendingPathComponent("default-data.json")
            try Self.ensureDefaultData(at: userDataURL)
            try Self.repairUserDataIfInvalid(at: userDataURL)
            let (initialDataBundle, initialModFiles, initialWarnings) = try Self.loadDataWithMods(
                baseURL: userDataURL,
                modsDirectory: dataDirectory.mods,
                applyMods: modsFeatureEnabledLoaded && modsActiveLoaded
            )
            dataBundle = initialDataBundle
            dataValidationReport = Self.buildValidationReport(
                for: initialDataBundle,
                modFiles: initialModFiles,
                warnings: initialWarnings,
                modsEnabled: modsFeatureEnabledLoaded,
                modsActive: modsFeatureEnabledLoaded && modsActiveLoaded
            )
            let initialModsValidationPassed = initialWarnings.isEmpty
            modsValidationPassed = initialModsValidationPassed
            modDryRunReport = Self.buildDryRunReport(modFiles: initialModFiles, warnings: initialWarnings, accepted: initialModsValidationPassed)
            portraitPromptTemplateURL = dataDirectory.data.appendingPathComponent("portrait-prompt.txt")
            try Self.ensurePortraitPromptTemplate(at: portraitPromptTemplateURL)

            let loaded = try Self.loadRoster(from: rosterURL, saveStore: saveStore)
            roster = loaded.characters
            recentEventsByCharacterID = loaded.recentEventsByCharacterID
            selectedCharacterID = nil
            sessionStarted = false
            statusMessage = nil
            runtimeStateMarker = .idle
            portraitImageURL = nil

            let initialCharacter = loaded.characters.first ?? Self.placeholderCharacter()
            let initialState = GameState(activeCharacter: initialCharacter, isPaused: true)
            state = initialState
            events = []

            runtime = GameRuntime(initialState: initialState, data: initialDataBundle, saveStore: saveStore, logStore: logStore)
            runtime.setTickRateMultiplier(tickRateMultiplier)
            startLogArchiveTimer()
            if modsFeatureEnabledLoaded {
                runModDryRunAndEnableIfValid()
            }

            runtime.onStateChange = { [weak self] newState in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.state = newState
                    if self.sessionStarted {
                        self.runtimeStateMarker = newState.isPaused ? .paused : .running
                    }
                    guard self.sessionStarted else { return }
                    if let idx = self.roster.firstIndex(where: { $0.id == newState.activeCharacter.id }) {
                        let previousLevel = self.roster[idx].level
                        var updated = newState.activeCharacter
                        let minCapacity = 10 + updated.stats[.strength]
                        if updated.inventoryCapacity < minCapacity {
                            updated.inventoryCapacity = minCapacity
                        }
                        let levelChanged = self.roster[idx].level != updated.level
                        self.roster[idx] = updated
                        self.persistRosterIfDue(force: levelChanged)
                        self.handleAutomaticPortraitUpdate(character: updated, previousLevel: previousLevel)
                    }
                }
            }

            runtime.onEvent = { [weak self] event in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.events.insert(event, at: 0)
                    self.events = Array(self.events.prefix(100))
                    guard self.sessionStarted else { return }
                    let id = self.state.activeCharacter.id
                    var history = self.recentEventsByCharacterID[id] ?? []
                    history.insert(event, at: 0)
                    self.recentEventsByCharacterID[id] = Array(history.prefix(10))
                    self.persistRosterIfDue()
                }
            }

            let workspace = NSWorkspace.shared.notificationCenter
            workspace.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    if self.sessionStarted {
                        self.runtime.setPaused(true)
                    }
                }
            }

            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    if self.sessionStarted {
                        self.runtime.setPaused(false)
                    }
                }
            }
        } catch {
            fatalError("Failed to initialize AppState: \(error)")
        }
    }

    var selectedCharacter: PlayerState? {
        guard let selectedCharacterID else { return nil }
        return roster.first(where: { $0.id == selectedCharacterID })
    }

    var currentContextCharacter: PlayerState? {
        if sessionStarted {
            return state.activeCharacter
        }
        return selectedCharacter
    }

    var currentMenubarTrackMode: MenubarIconTrackMode {
        guard let character = currentContextCharacter else { return .level }
        return menubarTrackByCharacterID[character.id] ?? .level
    }

    func setCurrentMenubarTrackMode(_ mode: MenubarIconTrackMode) {
        guard let character = currentContextCharacter else { return }
        menubarTrackByCharacterID[character.id] = mode
        persistMenubarTrackMap()
    }

    func menubarProgressPercent(for character: PlayerState) -> Double {
        switch menubarTrackMode(for: character) {
        case .level:
            return character.xpProgressPercent
        case .currentTask:
            return character.taskProgressPercent
        case .currentQuest:
            let bar = character.questBook.questBar
            guard bar.max > 0 else { return 0 }
            return (bar.position / bar.max) * 100.0
        case .plotDevelopment:
            let bar = character.questBook.plotBar
            guard bar.max > 0 else { return 0 }
            return (bar.position / bar.max) * 100.0
        case .encumbrance:
            guard character.inventoryCapacity > 0 else { return 0 }
            let used = character.inventoryItems.reduce(0) { $0 + $1.quantity }
            return (Double(used) / Double(character.inventoryCapacity)) * 100.0
        }
    }

    func menubarLabelText(started: Bool, character: PlayerState) -> String {
        guard started else { return "Lv ?" }
        let mode = menubarTrackMode(for: character)
        if mode == .level || showLevelLabelInMenubar {
            return "Lv \(character.level)"
        }
        switch mode {
        case .level:
            return "Lv \(character.level)"
        case .currentTask:
            return leadingWordLabel(from: character.task?.description, fallback: "Task")
        case .currentQuest:
            return leadingWordLabel(from: character.questBook.currentQuest, fallback: "Quest")
        case .plotDevelopment:
            if character.questBook.act <= 0 {
                return "Act 0"
            }
            return "Act \(PQLingo.toRoman(character.questBook.act))"
        case .encumbrance:
            return "Inventory"
        }
    }

    private func leadingWordLabel(from source: String?, fallback: String) -> String {
        guard let source else { return "\(fallback)..." }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(fallback)..." }
        let first = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? fallback
        return "\(first)..."
    }

    func menubarTrackMode(for character: PlayerState) -> MenubarIconTrackMode {
        menubarTrackByCharacterID[character.id] ?? .level
    }

    func startSelectedCharacter() {
        guard let c = selectedCharacter ?? roster.first else {
            flash("No character available to start.")
            return
        }
        start(character: c)
    }

    func start(character: PlayerState) {
        start(character: character, emitFlash: true)
    }

    func loadAndStartSelectedCharacter() {
        guard let target = selectedCharacter else {
            flash("No character selected.")
            return
        }

        if sessionStarted {
            let current = state.activeCharacter
            if current.id == target.id {
                flash("\(target.name) is already running.")
                return
            }

            runtime.manualSave()
            portraitGenerationInFlightCharacterIDs.remove(current.id)
            start(character: target, emitFlash: false)
            flash("\(current.name) was saved! Closing. Loaded \(target.name), starting!")
            return
        }

        start(character: target, emitFlash: true)
    }

    private func start(character: PlayerState, emitFlash: Bool) {
        var next = GameState(
            activeCharacter: character,
            isPaused: false,
            lowCPUMode: state.lowCPUMode,
            lastTickAt: Date(),
            rngState: state.rngState
        )
        if next.rngState == 0 {
            next.rngState = PQRNG.seed(from: "\(character.birthday.timeIntervalSince1970)")
        }

        runtime.replaceState(next)
        runtime.start()
        runtime.setPaused(false)

        sessionStarted = true
        runtimeStateMarker = .running
        selectedCharacterID = character.id
        lastSeenLevelByCharacterID[character.id] = character.level
        events = recentEventsByCharacterID[character.id] ?? []
        persistRoster()
        portraitImageURL = latestPortraitURL(for: character.id)
        if emitFlash {
            flash("Started \(character.name).")
        }
    }

    func closeCurrentCharacter() {
        guard sessionStarted else { return }
        let currentName = state.activeCharacter.name
        saveNow()
        var closed = state
        closed.isPaused = true
        runtime.replaceState(closed)
        runtime.setPaused(true)
        runtime.stop()
        sessionStarted = false
        runtimeStateMarker = .idle
        selectedCharacterID = nil
        events = []
        portraitGenerationInFlightCharacterIDs.remove(state.activeCharacter.id)
        persistRoster()
        refreshPortraitForCurrentCharacter()
        flash("Saved and closed \(currentName).")
    }

    func deleteSelectedCharacter() {
        guard let id = selectedCharacterID else { return }
        roster.removeAll(where: { $0.id == id })
        recentEventsByCharacterID[id] = nil
        selectedCharacterID = nil
        persistRoster()
        refreshPortraitForCurrentCharacter()
    }

    func createCharacter(name: String, race: String, className: String, stats: Stats? = nil, startImmediately: Bool = true) {
        let newStats = stats ?? rollStats()
        let c = PlayerState(name: name, race: race, characterClass: className, stats: newStats)
        roster.append(c)
        selectedCharacterID = c.id
        recentEventsByCharacterID[c.id] = []
        persistRoster()
        if startImmediately {
            start(character: c)
        } else {
            portraitImageURL = latestPortraitURL(for: c.id)
            flash("Created \(c.name) in roster.")
        }
    }

    func requestDashboardTab(_ tab: String) {
        dashboardRequestedTab = tab
        dashboardRouteToken &+= 1
    }

    func reloadDataAndMods() {
        flash("Reloading data...")
        let previousRuntimeState = runtimeStateMarker
        runtimeStateMarker = .reloadingData
        let dataURL = dataDirectory.data.appendingPathComponent("default-data.json")
        let modsURL = dataDirectory.mods
        let applyMods = modsFeatureEnabled && modsActive
        let modsFeatureEnabledSnapshot = modsFeatureEnabled

        Task.detached(priority: .utility) {
            do {
                let (bundle, modFiles, warnings) = try Self.loadDataWithMods(baseURL: dataURL, modsDirectory: modsURL, applyMods: applyMods)
                let report = Self.buildValidationReport(
                    for: bundle,
                    modFiles: modFiles,
                    warnings: warnings,
                    modsEnabled: modsFeatureEnabledSnapshot,
                    modsActive: applyMods
                )
                await MainActor.run {
                    self.dataBundle = bundle
                    self.runtime.setDataBundle(bundle)
                    self.dataValidationReport = report
                    self.modsValidationPassed = warnings.isEmpty
                    self.modDryRunReport = Self.buildDryRunReport(modFiles: modFiles, warnings: warnings, accepted: warnings.isEmpty)
                    self.runtimeStateMarker = self.sessionStarted ? (self.state.isPaused ? .paused : .running) : .idle
                    self.flash("Data reloaded (\(modFiles.count) mod file\(modFiles.count == 1 ? "" : "s")).")
                }
            } catch {
                await MainActor.run {
                    self.runtimeStateMarker = previousRuntimeState
                    self.flash("Reload failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func runModDryRunAndEnableIfValid() {
        let dataURL = dataDirectory.data.appendingPathComponent("default-data.json")
        let modsURL = dataDirectory.mods
        Task.detached(priority: .utility) {
            do {
                let (_, modFiles, warnings) = try Self.loadDataWithMods(
                    baseURL: dataURL,
                    modsDirectory: modsURL,
                    applyMods: true
                )
                let passed = warnings.isEmpty
                let report = Self.buildDryRunReport(modFiles: modFiles, warnings: warnings, accepted: passed)
                await MainActor.run {
                    self.modsValidationPassed = passed
                    self.modDryRunReport = report
                    if !passed {
                        self.modsActive = false
                        self.flash("Mods disabled: validation warnings found.")
                    } else if self.modsActive {
                        self.reloadDataAndMods()
                    }
                }
            } catch {
                await MainActor.run {
                    self.modsValidationPassed = false
                    self.modsActive = false
                    self.modDryRunReport = "Dry run failed: \(error.localizedDescription)"
                    self.flash("Mod dry run failed.")
                }
            }
        }
    }

    func togglePause() {
        guard sessionStarted else { return }
        let next = !state.isPaused
        runtime.setPaused(next)
        runtimeStateMarker = next ? .paused : .running
        flash(next ? "Game paused!" : "Resuming!")
    }

    func toggleLowCPU() {
        runtime.setLowCPUMode(!state.lowCPUMode)
    }

    func setTickRateMultiplier(_ multiplier: Double) {
        tickRateMultiplier = multiplier
        runtime.setTickRateMultiplier(multiplier)
        flash(String(format: "Tick rate set to %.2fx", multiplier))
    }

    func saveNow() {
        runtime.manualSave()
        flash("Character saved!")
    }

    func quitApp() {
        if sessionStarted {
            saveNow()
        } else {
            runtime.manualSave()
        }
        persistRoster()

        // Give the runtime queue a brief moment to flush writes before termination.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    func flashDebug(_ message: String) {
        flash(message)
    }

    func openInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func refreshPortraitForCurrentCharacter() {
        guard let character = currentCharacterForPortrait else {
            portraitImageURL = nil
            return
        }
        portraitImageURL = latestPortraitURL(for: character.id)
    }

    func portraitNSImage() -> NSImage? {
        guard let url = portraitImageURL else { return nil }
        return NSImage(contentsOf: url)
    }

    func chooseBaseImageForCurrentCharacter() {
        guard let character = currentCharacterForPortrait else {
            flash("No character selected.")
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let ext = source.pathExtension.lowercased().isEmpty ? "png" : source.pathExtension.lowercased()
        let destination = portraitsURL.appendingPathComponent("base-\(character.id.uuidString).\(ext)")

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            flash("Base image set for \(character.name).")
        } catch {
            flash("Failed to set base image: \(error.localizedDescription)")
        }
    }

    func generatePortraitForCurrentCharacter() {
        guard let character = currentCharacterForPortrait else {
            flash("No character selected.")
            return
        }
        guard openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            flash("Set OpenAI API key first.")
            return
        }
        generatePortrait(for: character, forceForCurrentLevel: true, announceStart: true)
    }

    private func handleAutomaticPortraitUpdate(character: PlayerState, previousLevel: Int?) {
        lastSeenLevelByCharacterID[character.id] = character.level

        guard openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        guard portraitGenerationInFlightCharacterIDs.contains(character.id) == false else { return }

        let levelChanged = (previousLevel == nil) || (character.level != previousLevel)
        guard levelChanged else { return }
        generatePortrait(for: character, forceForCurrentLevel: false, announceStart: true)
    }

    var hasOpenAIAPIKey: Bool {
        !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveOpenAIAPIKey(_ newKey: String) {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            flash("API key is empty.")
            return
        }
        openAIAPIKey = trimmed
        flash("API key saved.")
        if let character = currentCharacterForPortrait {
            generatePortrait(for: character, forceForCurrentLevel: true, announceStart: true)
        }
    }

    func clearOpenAIAPIKey() {
        openAIAPIKey = ""
        flash("API key removed.")
    }

    func importCharacterInteractive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json, UTType(filenameExtension: "pkl")!, UTType(filenameExtension: "pqw")!]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard NSAlert.runAskYesNo(
            title: "Warning: Characters can be imported once only.",
            message: "Are you sure you want to do this?"
        ) else {
            flash("Import canceled.")
            return
        }

        do {
            let importedPlayers = try parseImportedPlayers(from: url)
            guard !importedPlayers.isEmpty else {
                flash("Import failed: file contains no players.")
                return
            }

            let decision = showImportPreview(players: importedPlayers, sourceFilename: url.lastPathComponent)
            switch decision {
            case .cancel:
                return
            case .importToRosterOnly:
                guard confirmOverwriteByNameIfNeeded(players: importedPlayers) else {
                    flash("Import canceled.")
                    return
                }
                importedPlayers.forEach { mergeImportedCharacter($0) }
                flash("Imported \(importedPlayers.count) character(s) to roster.")
                burnImportedFile(url)
            case .importAndStart:
                guard confirmOverwriteByNameIfNeeded(players: importedPlayers) else {
                    flash("Import canceled.")
                    return
                }
                importedPlayers.forEach { mergeImportedCharacter($0) }
                if let first = importedPlayers.first {
                    selectedCharacterID = first.id
                    loadAndStartSelectedCharacter()
                    requestDashboardTab("overview")
                }
                burnImportedFile(url)
            }
        } catch {
            flash("Import failed: \(error.localizedDescription)")
        }
    }

    func exportCharacterInteractive() {
        let selectedForFilename = selectedCharacter ?? (sessionStarted ? state.activeCharacter : nil)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json, UTType(filenameExtension: "pkl")!, UTType(filenameExtension: "pqw")!]
        let base = selectedForFilename.map { "\($0.name)_\($0.level)" } ?? "character"
        panel.nameFieldStringValue = "\(sanitizeFilename(base)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let ext = url.pathExtension.lowercased()
            if ext == "json" {
                try exportSelectedCharacterJSON(to: url)
            } else {
                let tempJSON = dataDirectory.saves.appendingPathComponent("export-\(UUID().uuidString).json")
                try exportSelectedCharacterJSON(to: tempJSON, addTrailingNoise: false)
                try legacyBridge().exportPKL(from: tempJSON, to: url)
                try? FileManager.default.removeItem(at: tempJSON)
            }
            events.insert(.init(message: "Exported character to \(url.lastPathComponent)."), at: 0)
        } catch {
            events.insert(.init(message: "Export failed: \(error.localizedDescription)"), at: 0)
        }
    }

    private func sanitizeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let parts = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let built = String(parts).replacingOccurrences(of: "__", with: "_")
        return built.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    func rollStats() -> Stats {
        func d6() -> Int { Int.random(in: 0..<6) }
        var values: [String: Int] = [
            StatType.strength.rawValue: 3 + d6() + d6() + d6(),
            StatType.condition.rawValue: 3 + d6() + d6() + d6(),
            StatType.dexterity.rawValue: 3 + d6() + d6() + d6(),
            StatType.intelligence.rawValue: 3 + d6() + d6() + d6(),
            StatType.wisdom.rawValue: 3 + d6() + d6() + d6(),
            StatType.charisma.rawValue: 3 + d6() + d6() + d6(),
        ]
        values[StatType.hpMax.rawValue] = Int.random(in: 0..<8) + (values[StatType.condition.rawValue] ?? 0) / 6
        values[StatType.mpMax.rawValue] = Int.random(in: 0..<8) + (values[StatType.intelligence.rawValue] ?? 0) / 6
        return Stats(values: values)
    }

    func generateFantasyName() -> String {
        let starts = ["br", "cr", "dr", "el", "fa", "ga", "ka", "mor", "nar", "or", "ra", "sha", "tha", "val", "wyr", "zir"]
        let vowels = ["a", "a", "e", "e", "i", "o", "u", "ae"]
        let middles = ["d", "g", "k", "l", "m", "n", "r", "s", "th", "v", "z"]
        let ends = ["", "n", "r", "s", "th", "dor", "mir", "ion", "eth", "ael", "orn", "wyn"]

        var name = starts.randomElement() ?? "ar"
        let syllables = Int.random(in: 1...3)
        for _ in 0..<syllables {
            name += vowels.randomElement() ?? "a"
            if Bool.random() {
                name += middles.randomElement() ?? "n"
            }
        }
        name += ends.randomElement() ?? ""

        if name.count < 4 {
            name += "an"
        }
        if name.count > 12 {
            name = String(name.prefix(12))
        }
        return name.prefix(1).uppercased() + name.dropFirst().lowercased()
    }

    @discardableResult
    private func importFromJSON(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        let players = try parsePlayersFromJSONData(data)
        for player in players {
            mergeImportedCharacter(player)
        }
        return players.map(\.name)
    }

    private func parseImportedPlayers(from url: URL) throws -> [PlayerState] {
        if url.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: url)
            return try parsePlayersFromJSONData(data)
        }

        let raw = try Data(contentsOf: url)
        if let webData = Self.decodeWebsitePayload(from: raw),
           let webPlayer = try decodeWebsiteExportPlayer(from: webData) {
            return [webPlayer]
        }

        let imported = try importLegacyCharacterFile(url)
        let data = try Data(contentsOf: imported)
        return try parsePlayersFromJSONData(data)
    }

    private func parsePlayersFromJSONData(_ data: Data) throws -> [PlayerState] {
        let normalized = Self.trimTrailingJSONNoise(data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let gameState = try? decoder.decode(GameState.self, from: normalized) {
            return [gameState.activeCharacter]
        }

        if let roster = try? decoder.decode(RosterFile.self, from: normalized) {
            return roster.characters
        }

        if let player = try? decoder.decode(PlayerState.self, from: normalized) {
            return [player]
        }

        if let wrappedPlayers = try? decoder.decode(PlayerStateWrapperPayload.self, from: normalized) {
            return wrappedPlayers.players
        }

        if let imported = try? decoder.decode(ImportedPayload.self, from: normalized) {
            var players: [PlayerState] = []
            for p in imported.players {
                let player = p.toPlayerState(defaultData: dataBundle)
                players.append(player)
            }
            return players
        }

        if let webPlayer = try decodeWebsiteExportPlayer(from: normalized) {
            return [webPlayer]
        }

        throw NSError(
            domain: "pq-menubar",
            code: 91,
            userInfo: [NSLocalizedDescriptionKey: "The data couldn't be read because it's missing or unsupported fields."]
        )
    }

    private func exportSelectedCharacterJSON(to url: URL, addTrailingNoise: Bool = true) throws {
        guard let c = selectedCharacter ?? (sessionStarted ? state.activeCharacter : nil) else {
            throw NSError(domain: "pq-menubar", code: 30, userInfo: [NSLocalizedDescriptionKey: "No character selected"])
        }

        let exportState = GameState(activeCharacter: c, isPaused: true, lowCPUMode: state.lowCPUMode, lastTickAt: Date(), rngState: state.rngState)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(exportState)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var out = payload
        if addTrailingNoise, let randomByte = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8.randomElement() {
            out.append(randomByte)
        }
        try out.write(to: url, options: .atomic)
    }

    private enum ImportDecision {
        case importAndStart
        case importToRosterOnly
        case cancel
    }

    private func showImportPreview(players: [PlayerState], sourceFilename: String) -> ImportDecision {
        let alert = NSAlert()
        alert.messageText = "Import Preview"
        alert.informativeText = importPreviewText(players: players, sourceFilename: sourceFilename)
        alert.addButton(withTitle: "Import and Start")
        alert.addButton(withTitle: "Import To Roster Only")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .importAndStart
        case .alertSecondButtonReturn: return .importToRosterOnly
        default: return .cancel
        }
    }

    private func importPreviewText(players: [PlayerState], sourceFilename: String) -> String {
        guard let first = players.first else { return "No player found in \(sourceFilename)." }
        let quest = first.questBook.currentQuest ?? "-"
        let task = (first.task?.description ?? "-") + "..."
        var lines: [String] = [
            "Source: \(sourceFilename)",
            "Characters in file: \(players.count)",
            "",
            "\(first.name)",
            "Lv \(first.level) • \(first.race) \(first.characterClass)",
            "Quest: \(quest)",
            "Task: \(task)"
        ]
        if players.count > 1 {
            lines.append("")
            lines.append("Additional: \(players.dropFirst().map(\.name).joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func mergeImportedCharacter(_ c: PlayerState) {
        if let idx = roster.firstIndex(where: { $0.id == c.id }) {
            roster[idx] = c
            if recentEventsByCharacterID[c.id] == nil {
                recentEventsByCharacterID[c.id] = []
            }
            selectedCharacterID = c.id
        } else if let idx = roster.firstIndex(where: { $0.name.caseInsensitiveCompare(c.name) == .orderedSame }) {
            var replaced = c
            replaced.id = roster[idx].id
            roster[idx] = replaced
            if recentEventsByCharacterID[replaced.id] == nil {
                recentEventsByCharacterID[replaced.id] = []
            }
            selectedCharacterID = replaced.id
        } else {
            roster.append(c)
            recentEventsByCharacterID[c.id] = []
            selectedCharacterID = c.id
        }
        persistRoster()
        refreshPortraitForCurrentCharacter()
    }

    private func confirmOverwriteByNameIfNeeded(players: [PlayerState]) -> Bool {
        for incoming in players {
            if let existing = roster.first(where: {
                $0.name.caseInsensitiveCompare(incoming.name) == .orderedSame
            }) {
                let overwrite = NSAlert.runAskYesNo(
                    title: "Overwrite \"\(existing.name)\"?",
                    message: "A character with this name already exists. Overwrite it with imported data?"
                )
                if !overwrite {
                    return false
                }
            }
        }
        return true
    }

    private func burnImportedFile(_ url: URL) {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let token = String((0..<8).map { _ in alphabet.randomElement() ?? "Z" })
        let consumedText = "CONSUMED_IMPORT_\(token)\n"
        do {
            try consumedText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            events.insert(.init(message: "Warning: imported file was not burned (\(error.localizedDescription))."), at: 0)
        }
    }

    private func importLegacyCharacterFile(_ input: URL) throws -> URL {
        let output = dataDirectory.saves.appendingPathComponent("imported-\(UUID().uuidString).json")
        try legacyBridge().importPKL(from: input, to: output)
        return output
    }

    private func legacyBridge() throws -> LegacyPKLBridge {
        guard let converter = Self.findBundledResource(named: "convert_pkl", withExtension: "py", subdirectory: "tools") else {
            throw NSError(domain: "pq-menubar", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing convert_pkl.py"])
        }
        return LegacyPKLBridge(converterPath: converter)
    }

    nonisolated private static func loadDataWithMods(baseURL: URL, modsDirectory: URL, applyMods: Bool) throws -> (PQDataBundle, [String], [String]) {
        var bundle = try PQDataLoader.load(from: baseURL)
        if !applyMods {
            return (bundle, [], [])
        }
        let fm = FileManager.default
        let modURLs = (try? fm.contentsOfDirectory(at: modsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        var warnings: [String] = []
        var modNames: [String] = []
        for modURL in modURLs {
            do {
                let data = try Data(contentsOf: modURL)
                let key = modURL.deletingPathExtension().lastPathComponent
                if Self.supportedModKeys.contains(key) {
                    let obj = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let arr = obj as? [Any] else {
                        warnings.append("Skipped \(modURL.lastPathComponent): expected top-level array for key '\(key)'")
                        continue
                    }
                    try Self.applyArrayMod(key: key, entries: arr, bundle: &bundle, sourceName: modURL.lastPathComponent, warnings: &warnings)
                } else {
                    // Backward compatibility: old patch-bundle format.
                    let decoder = JSONDecoder()
                    let patch = try decoder.decode(ModPatchBundle.self, from: data)
                    bundle = merge(base: bundle, patch: patch)
                }
                modNames.append(modURL.lastPathComponent)
            } catch {
                warnings.append("Skipped \(modURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (bundle, modNames, warnings)
    }

    nonisolated private static func merge(base: PQDataBundle, patch: ModPatchBundle) -> PQDataBundle {
        var out = base
        out.spells.append(contentsOf: patch.spells ?? [])
        out.offenseAttrib.append(contentsOf: patch.offenseAttrib ?? [])
        out.defenseAttrib.append(contentsOf: patch.defenseAttrib ?? [])
        out.offenseBad.append(contentsOf: patch.offenseBad ?? [])
        out.defenseBad.append(contentsOf: patch.defenseBad ?? [])
        out.shields.append(contentsOf: patch.shields ?? [])
        out.armors.append(contentsOf: patch.armors ?? [])
        out.weapons.append(contentsOf: patch.weapons ?? [])
        out.specials.append(contentsOf: patch.specials ?? [])
        out.itemAttrib.append(contentsOf: patch.itemAttrib ?? [])
        out.itemOfs.append(contentsOf: patch.itemOfs ?? [])
        out.boringItems.append(contentsOf: patch.boringItems ?? [])
        out.monsters.append(contentsOf: patch.monsters ?? [])
        out.races.append(contentsOf: patch.races ?? [])
        out.classes.append(contentsOf: patch.classes ?? [])
        out.titles.append(contentsOf: patch.titles ?? [])
        out.impressiveTitles.append(contentsOf: patch.impressiveTitles ?? [])
        out.primeStats.append(contentsOf: patch.primeStats ?? [])
        out.equipmentTypes.append(contentsOf: patch.equipmentTypes ?? [])
        return out
    }

    private nonisolated static let supportedModKeys: Set<String> = [
        "spells", "offenseAttrib", "defenseAttrib", "offenseBad", "defenseBad",
        "shields", "armors", "weapons", "specials", "itemAttrib", "itemOfs",
        "boringItems", "monsters", "races", "classes", "titles",
        "impressiveTitles", "primeStats", "equipmentTypes",
    ]

    nonisolated private static func applyArrayMod(
        key: String,
        entries: [Any],
        bundle: inout PQDataBundle,
        sourceName: String,
        warnings: inout [String]
    ) throws {
        switch key {
        case "spells":
            mergeStringEntries(existing: &bundle.spells, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "specials":
            mergeStringEntries(existing: &bundle.specials, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "itemAttrib":
            mergeStringEntries(existing: &bundle.itemAttrib, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "itemOfs":
            mergeStringEntries(existing: &bundle.itemOfs, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "boringItems":
            mergeStringEntries(existing: &bundle.boringItems, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "titles":
            mergeStringEntries(existing: &bundle.titles, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "impressiveTitles":
            mergeStringEntries(existing: &bundle.impressiveTitles, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "primeStats":
            mergeStringEntries(existing: &bundle.primeStats, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "equipmentTypes":
            mergeStringEntries(existing: &bundle.equipmentTypes, entries: entries, sourceName: sourceName, warnings: &warnings)
        case "offenseAttrib":
            try mergeNamedObjects(existing: &bundle.offenseAttrib, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "defenseAttrib":
            try mergeNamedObjects(existing: &bundle.defenseAttrib, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "offenseBad":
            try mergeNamedObjects(existing: &bundle.offenseBad, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "defenseBad":
            try mergeNamedObjects(existing: &bundle.defenseBad, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "shields":
            try mergeNamedObjects(existing: &bundle.shields, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "armors":
            try mergeNamedObjects(existing: &bundle.armors, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "weapons":
            try mergeNamedObjects(existing: &bundle.weapons, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "monsters":
            try mergeNamedObjects(existing: &bundle.monsters, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "races":
            try mergeNamedObjects(existing: &bundle.races, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        case "classes":
            try mergeNamedObjects(existing: &bundle.classes, entries: entries, sourceName: sourceName, warnings: &warnings) { $0.name }
        default:
            warnings.append("Skipped \(sourceName): unsupported mod key '\(key)'")
        }
    }

    nonisolated private static func mergeStringEntries(
        existing: inout [String],
        entries: [Any],
        sourceName: String,
        warnings: inout [String]
    ) {
        for (idx, raw) in entries.enumerated() {
            var value: String?
            var include = true
            var mask = false
            if let s = raw as? String {
                value = s
            } else if let dict = raw as? [String: Any] {
                value = (dict["value"] as? String) ?? (dict["name"] as? String)
                include = dict["include"] as? Bool ?? true
                mask = dict["mask"] as? Bool ?? false
            } else {
                warnings.append("Skipped \(sourceName)[\(idx)]: expected string or object")
                continue
            }

            guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
                warnings.append("Skipped \(sourceName)[\(idx)]: missing value/name")
                continue
            }

            if !include {
                existing.removeAll(where: { $0.caseInsensitiveCompare(v) == .orderedSame })
                continue
            }
            if mask {
                existing.removeAll(where: { $0.caseInsensitiveCompare(v) == .orderedSame })
                existing.append(v)
                continue
            }
            if !existing.contains(where: { $0.caseInsensitiveCompare(v) == .orderedSame }) {
                existing.append(v)
            }
        }
    }

    nonisolated private static func mergeNamedObjects<T: Decodable>(
        existing: inout [T],
        entries: [Any],
        sourceName: String,
        warnings: inout [String],
        nameFor: (T) -> String
    ) throws {
        func normalized(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        for (idx, raw) in entries.enumerated() {
            guard let dict = raw as? [String: Any] else {
                warnings.append("Skipped \(sourceName)[\(idx)]: expected object entry")
                continue
            }

            let include = dict["include"] as? Bool ?? true
            let mask = dict["mask"] as? Bool ?? false
            let rawName = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var clean = dict
            clean.removeValue(forKey: "mask")
            clean.removeValue(forKey: "include")

            let data = try JSONSerialization.data(withJSONObject: clean, options: [])
            let item: T
            do {
                item = try JSONDecoder().decode(T.self, from: data)
            } catch {
                warnings.append("Skipped \(sourceName)[\(idx)]: decode error (\(error.localizedDescription))")
                continue
            }

            let id = normalized(rawName.isEmpty ? nameFor(item) : rawName)
            guard !id.isEmpty else {
                warnings.append("Skipped \(sourceName)[\(idx)]: missing name")
                continue
            }

            if !include {
                existing.removeAll(where: { normalized(nameFor($0)) == id })
                continue
            }

            if mask {
                existing.removeAll(where: { normalized(nameFor($0)) == id })
                existing.append(item)
                continue
            }

            if !existing.contains(where: { normalized(nameFor($0)) == id }) {
                existing.append(item)
            }
        }
    }

    nonisolated private static func buildValidationReport(
        for bundle: PQDataBundle,
        modFiles: [String],
        warnings: [String],
        modsEnabled: Bool,
        modsActive: Bool
    ) -> String {
        var lines: [String] = []
        lines.append("Mods enabled: \(modsEnabled ? "yes" : "no")")
        lines.append("Mods active: \(modsActive ? "yes" : "no")")
        lines.append("Loaded base data + \(modFiles.count) mod file(s).")
        if !modFiles.isEmpty {
            lines.append("Mods: \(modFiles.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("Counts:")
        lines.append("Classes \(bundle.classes.count), Races \(bundle.races.count), Monsters \(bundle.monsters.count), Spells \(bundle.spells.count)")
        lines.append("Weapons \(bundle.weapons.count), Armors \(bundle.armors.count), Shields \(bundle.shields.count)")
        lines.append("ItemAttrib \(bundle.itemAttrib.count), ItemOfs \(bundle.itemOfs.count), BoringItems \(bundle.boringItems.count)")

        var checks: [String] = []
        if bundle.classes.isEmpty { checks.append("ERROR: classes is empty") }
        if bundle.races.isEmpty { checks.append("ERROR: races is empty") }
        if bundle.monsters.isEmpty { checks.append("ERROR: monsters is empty") }
        if bundle.spells.isEmpty { checks.append("ERROR: spells is empty") }
        if bundle.weapons.isEmpty || bundle.armors.isEmpty || bundle.shields.isEmpty {
            checks.append("ERROR: one or more equipment pools are empty")
        }
        let badMonsters = bundle.monsters.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.level < 0 }
        if !badMonsters.isEmpty {
            checks.append("WARN: \(badMonsters.count) monster entries have blank name or negative level")
        }
        let missingDrops = bundle.monsters.filter {
            ($0.item?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        }
        if !missingDrops.isEmpty {
            checks.append("WARN: \(missingDrops.count) monster entries have missing item drop; runtime uses special-item fallback")
        }
        checks.append(contentsOf: warnings.map { "WARN: \($0)" })
        if checks.isEmpty {
            checks.append("Validation OK")
        }

        lines.append("")
        lines.append(contentsOf: checks)
        return lines.joined(separator: "\n")
    }

    nonisolated private static func buildDryRunReport(modFiles: [String], warnings: [String], accepted: Bool) -> String {
        var lines: [String] = []
        lines.append("Dry run result: \(accepted ? "PASS" : "FAIL")")
        lines.append("Mod files found: \(modFiles.count)")
        if !modFiles.isEmpty {
            lines.append("Files: \(modFiles.joined(separator: ", "))")
        }
        if warnings.isEmpty {
            lines.append("No warnings.")
        } else {
            lines.append("Warnings:")
            lines.append(contentsOf: warnings.map { "- \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    private static func decodeWebsitePayload(from raw: Data) -> Data? {
        if let first = raw.first, first == UInt8(ascii: "{") || first == UInt8(ascii: "[") {
            return raw
        }
        guard let textRaw = String(data: raw, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !textRaw.isEmpty else {
            return nil
        }
        if textRaw.first == "{" || textRaw.first == "[" {
            return textRaw.data(using: .utf8)
        }
        if let direct = Data(base64Encoded: textRaw) {
            return direct
        }
        let urlSafe = textRaw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = urlSafe + String(repeating: "=", count: (4 - urlSafe.count % 4) % 4)
        return Data(base64Encoded: padded)
    }

    private func decodeWebsiteExportPlayer(from data: Data) throws -> PlayerState? {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let traits = obj["Traits"] as? [String: Any],
              let rawName = traits["Name"] as? String else {
            return nil
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let race = (traits["Race"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let className = (traits["Class"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let level = max(1, Self.intFromAny(traits["Level"], fallback: 1))
        let statsObj = obj["Stats"] as? [String: Any] ?? [:]
        let stats = Stats(values: [
            StatType.strength.rawValue: Self.intFromAny(statsObj[StatType.strength.rawValue], fallback: 10),
            StatType.condition.rawValue: Self.intFromAny(statsObj[StatType.condition.rawValue], fallback: 10),
            StatType.dexterity.rawValue: Self.intFromAny(statsObj[StatType.dexterity.rawValue], fallback: 10),
            StatType.intelligence.rawValue: Self.intFromAny(statsObj[StatType.intelligence.rawValue], fallback: 10),
            StatType.wisdom.rawValue: Self.intFromAny(statsObj[StatType.wisdom.rawValue], fallback: 10),
            StatType.charisma.rawValue: Self.intFromAny(statsObj[StatType.charisma.rawValue], fallback: 10),
            StatType.hpMax.rawValue: Self.intFromAny(statsObj[StatType.hpMax.rawValue], fallback: 8),
            StatType.mpMax.rawValue: Self.intFromAny(statsObj[StatType.mpMax.rawValue], fallback: 8),
        ])

        var player = PlayerState(
            name: name,
            birthday: Self.dateFromAny(obj["birthday"]) ?? Date(),
            race: (race?.isEmpty == false ? race! : (dataBundle.races.first?.name ?? "Half Orc")),
            characterClass: (className?.isEmpty == false ? className! : (dataBundle.classes.first?.name ?? "Ur-Paladin")),
            stats: stats
        )

        player.level = level
        player.elapsed = Self.doubleFromAny(obj["elapsed"], fallback: 0)
        if let exp = obj["ExpBar"] as? [String: Any] {
            player.expBar = Bar(
                max: max(1, Self.doubleFromAny(exp["max"], fallback: PlayerState.levelUpTime(level))),
                position: max(0, Self.doubleFromAny(exp["position"], fallback: 0))
            )
        }

        let plot = obj["PlotBar"] as? [String: Any]
        let quest = obj["QuestBar"] as? [String: Any]
        player.questBook = QuestBook(
            act: max(0, Self.intFromAny(obj["act"], fallback: 0)),
            quests: (obj["Quests"] as? [String]) ?? [],
            plotBar: Bar(
                max: max(1, Self.doubleFromAny(plot?["max"], fallback: 1)),
                position: max(0, Self.doubleFromAny(plot?["position"], fallback: 0))
            ),
            questBar: Bar(
                max: max(1, Self.doubleFromAny(quest?["max"], fallback: 1)),
                position: max(0, Self.doubleFromAny(quest?["position"], fallback: 0))
            ),
            monster: nil
        )

        var gold = 0
        if let inv = obj["Inventory"] as? [[Any]] {
            for row in inv where row.count >= 2 {
                let itemName = String(describing: row[0])
                let qty = Self.intFromAny(row[1], fallback: 0)
                if itemName.caseInsensitiveCompare("Gold") == .orderedSame {
                    gold = qty
                } else if qty > 0 {
                    player.addInventoryItem(itemName, quantity: qty)
                }
            }
        }
        player.inventoryGold = gold
        player.inventoryCapacity = max(1, Self.intFromAny((obj["EncumBar"] as? [String: Any])?["max"], fallback: 10 + player.stats[.strength]))

        if let equips = obj["Equips"] as? [String: Any] {
            var mapped: [String: String] = [:]
            for (k, v) in equips {
                mapped[k] = String(describing: v)
            }
            player.equipment = mapped
        }
        if let best = obj["bestequip"] as? String, !best.isEmpty {
            player.bestEquipment = best
        }

        if let spellRows = obj["Spells"] as? [[Any]] {
            player.spells = []
            for row in spellRows where row.count >= 2 {
                let spellName = String(describing: row[0])
                let lvl = max(1, Self.romanOrIntToInt(row[1], fallback: 1))
                player.addSpell(spellName, levelInc: lvl)
            }
        }

        player.task = GameTask(kind: .regular, description: (obj["kill"] as? String) ?? "Working", duration: 1, monster: nil)
        if let task = obj["TaskBar"] as? [String: Any] {
            player.taskBar = Bar(
                max: max(1, Self.doubleFromAny(task["max"], fallback: 1)),
                position: max(0, Self.doubleFromAny(task["position"], fallback: 0))
            )
        }
        player.queue = []
        return player
    }

    private static func intFromAny(_ value: Any?, fallback: Int) -> Int {
        switch value {
        case let n as Int: return n
        case let n as Double: return Int(n)
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s) ?? fallback
        default: return fallback
        }
    }

    private static func doubleFromAny(_ value: Any?, fallback: Double) -> Double {
        switch value {
        case let n as Double: return n
        case let n as Float: return Double(n)
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s) ?? fallback
        default: return fallback
        }
    }

    private static func dateFromAny(_ value: Any?) -> Date? {
        if let d = value as? Date { return d }
        guard let s = value as? String, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)
    }

    private static func romanOrIntToInt(_ value: Any?, fallback: Int) -> Int {
        if let n = value as? Int { return n }
        guard let s = value as? String else { return fallback }
        if let n = Int(s) { return n }
        return romanToInt(s) ?? fallback
    }

    private static func romanToInt(_ s: String) -> Int? {
        let map: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50, "C": 100, "D": 500, "M": 1000]
        let chars = Array(s.uppercased())
        guard !chars.isEmpty else { return nil }
        var total = 0
        var i = 0
        while i < chars.count {
            guard let curr = map[chars[i]] else { return nil }
            if i + 1 < chars.count, let next = map[chars[i + 1]], next > curr {
                total += (next - curr)
                i += 2
            } else {
                total += curr
                i += 1
            }
        }
        return total
    }

    private func persistRoster() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let eventMap = recentEventsByCharacterID.reduce(into: [String: [GameEvent]]()) { partial, item in
                partial[item.key.uuidString] = Array(item.value.prefix(10))
            }
            let payload = RosterFile(activeCharacterID: selectedCharacterID, characters: roster, recentEventsByCharacterID: eventMap)
            try encoder.encode(payload).write(to: rosterURL, options: .atomic)
            lastRosterPersistAt = Date()
        } catch {
            events.insert(.init(message: "Failed to save roster: \(error.localizedDescription)"), at: 0)
        }
    }

    private func persistRosterIfDue(force: Bool = false) {
        if force || Date().timeIntervalSince(lastRosterPersistAt) >= 5.0 {
            persistRoster()
        }
    }

    private func flash(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.statusMessage == message {
                self?.statusMessage = nil
            }
        }
    }

    private var currentCharacterForPortrait: PlayerState? {
        if sessionStarted {
            return state.activeCharacter
        }
        return selectedCharacter
    }

    private func baseImageURL(for characterID: UUID) -> URL? {
        let prefix = "base-\(characterID.uuidString)."
        let files = (try? FileManager.default.contentsOfDirectory(at: portraitsURL, includingPropertiesForKeys: nil)) ?? []
        return files.first(where: { $0.lastPathComponent.hasPrefix(prefix) })
    }

    private func preferredBaseImageURL(for characterID: UUID) -> URL? {
        if let explicit = baseImageURL(for: characterID) {
            return explicit
        }
        return latestPortraitURL(for: characterID)
    }

    private func latestPortraitURL(for characterID: UUID) -> URL? {
        let prefix = "\(characterID.uuidString)-"
        let files = (try? FileManager.default.contentsOfDirectory(at: portraitsURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidates = files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension.lowercased() == "png" }
        return candidates.sorted { lhs, rhs in
            let ld = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rd = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return ld > rd
        }.first
    }

    private func portraitExists(for characterID: UUID, level: Int) -> Bool {
        let prefix = "\(characterID.uuidString)-L\(level)-"
        let files = (try? FileManager.default.contentsOfDirectory(at: portraitsURL, includingPropertiesForKeys: nil)) ?? []
        return files.contains(where: { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension.lowercased() == "png" })
    }

    private func portraitPrompt(for character: PlayerState, usingBaseImage: Bool) -> String {
        let template = (try? String(contentsOf: portraitPromptTemplateURL, encoding: .utf8))
            ?? Self.defaultPortraitPromptTemplate
        let base = template
            .replacingOccurrences(of: "{{character_name}}", with: character.name)
            .replacingOccurrences(of: "{{player_level}}", with: "\(character.level)")
            .replacingOccurrences(of: "{{player_class}}", with: character.characterClass)
            .replacingOccurrences(of: "{{player_race}}", with: character.race)
            .replacingOccurrences(of: "{{current_quest}}", with: character.questBook.currentQuest ?? "?")
            .replacingOccurrences(of: "{{current_task}}", with: character.task?.description ?? "?")
            .replacingOccurrences(of: "{{best_equipment}}", with: character.bestEquipment)
            .replacingOccurrences(of: "{{best_prime_stat}}", with: character.stats.bestPrime.rawValue)
        if usingBaseImage {
            return base + " Using the picture as a base, create me a pixel art feature image of my character using all of the details I provided. No border, no name or letters, just the character."
        }
        return base + " Create me a pixel art feature image of my character using all of the details I provided. No border, no name or letters, just the character."
    }

    private func generatePortrait(for character: PlayerState, forceForCurrentLevel: Bool, announceStart: Bool) {
        guard hasOpenAIAPIKey else { return }
        guard portraitGenerationInFlightCharacterIDs.contains(character.id) == false else { return }
        if !forceForCurrentLevel && portraitExists(for: character.id, level: character.level) {
            return
        }

        portraitGenerationInFlightCharacterIDs.insert(character.id)
        if announceStart {
            flash("Generating portrait for level \(character.level)...")
        }

        let prompt = portraitPrompt(for: character, usingBaseImage: preferredBaseImageURL(for: character.id) != nil)
        let apiKey = openAIAPIKey
        let baseImage = preferredBaseImageURL(for: character.id)

        Task {
            defer {
                Task { @MainActor in
                    self.portraitGenerationInFlightCharacterIDs.remove(character.id)
                }
            }

            do {
                let png = try await requestPortraitPNG(prompt: prompt, apiKey: apiKey, baseImageURL: baseImage)
                let filename = "\(character.id.uuidString)-L\(character.level)-\(Int(Date().timeIntervalSince1970)).png"
                let output = portraitsURL.appendingPathComponent(filename)
                try png.write(to: output, options: .atomic)
                await MainActor.run {
                    self.portraitImageURL = output
                    self.flash("Portrait updated for level \(character.level).")
                }
            } catch {
                await MainActor.run {
                    let message = "Portrait generation failed: \(error.localizedDescription)"
                    self.events.insert(.init(message: message), at: 0)
                    self.flash(message)
                }
            }
        }
    }

    private func requestPortraitPNG(prompt: String, apiKey: String, baseImageURL: URL?) async throws -> Data {
        if let baseImageURL {
            do {
                return try await requestImageEditPNG(prompt: prompt, apiKey: apiKey, baseImageURL: baseImageURL, model: "gpt-image-1-mini")
            } catch {
                return try await requestImageEditPNG(prompt: prompt, apiKey: apiKey, baseImageURL: baseImageURL, model: "gpt-image-1")
            }
        }
        do {
            return try await requestImageGenerationPNG(prompt: prompt, apiKey: apiKey, model: "gpt-image-1-mini")
        } catch {
            return try await requestImageGenerationPNG(prompt: prompt, apiKey: apiKey, model: "gpt-image-1")
        }
    }

    private func requestImageGenerationPNG(prompt: String, apiKey: String, model: String) async throws -> Data {
        let endpoint = URL(string: "https://api.openai.com/v1/images/generations")!
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": model,
            "prompt": prompt,
            // API supports standard dimensions; we resize down to 100x125 afterward.
            "size": "1024x1024",
            "n": 1,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response, data: data)
        let decoded = try await decodeImageData(from: data)
        return try resizePNG(decoded, width: 256, height: 256)
    }

    private func requestImageEditPNG(prompt: String, apiKey: String, baseImageURL: URL, model: String) async throws -> Data {
        let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        let boundary = "----pqmenubar\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let imageData = try pngData(from: baseImageURL)
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("model", model)
        appendField("prompt", prompt)
        appendField("size", "1024x1024")
        appendField("n", "1")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"base.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTP(response, data: data)
        let decoded = try await decodeImageData(from: data)
        return try resizePNG(decoded, width: 256, height: 256)
    }

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            var details = "Image API request failed with status \(http.statusCode)"
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                details += ": \(text)"
                print("[Portrait API Error] \(text)")
            }
            throw NSError(domain: "pq-menubar", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: details])
        }
    }

    private func decodeImageData(from data: Data) async throws -> Data {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard
            let dict = obj as? [String: Any],
            let items = dict["data"] as? [[String: Any]],
            let first = items.first
        else {
            throw NSError(domain: "pq-menubar", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid image API response"])
        }

        if let b64 = first["b64_json"] as? String, let decoded = Data(base64Encoded: b64) {
            return decoded
        }
        if let urlString = first["url"] as? String, let url = URL(string: urlString) {
            let (downloaded, _) = try await URLSession.shared.data(from: url)
            return downloaded
        }
        throw NSError(domain: "pq-menubar", code: 501, userInfo: [NSLocalizedDescriptionKey: "No image payload in API response"])
    }

    private func pngData(from imageURL: URL) throws -> Data {
        let raw = try Data(contentsOf: imageURL)
        if imageURL.pathExtension.lowercased() == "png" {
            return raw
        }
        guard let image = NSImage(data: raw),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "pq-menubar",
                code: 612,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert base image to PNG"]
            )
        }
        return png
    }

    private func resizePNG(_ data: Data, width: Int, height: Int) throws -> Data {
        guard let input = NSImage(data: data) else {
            throw NSError(domain: "pq-menubar", code: 610, userInfo: [NSLocalizedDescriptionKey: "Failed to decode generated image"])
        }
        let target = NSSize(width: width, height: height)
        let source = input.size
        guard source.width > 0, source.height > 0 else {
            throw NSError(domain: "pq-menubar", code: 613, userInfo: [NSLocalizedDescriptionKey: "Invalid source image size"])
        }

        let scale = max(target.width / source.width, target.height / source.height)
        let drawSize = NSSize(width: source.width * scale, height: source.height * scale)
        let drawOrigin = NSPoint(
            x: (target.width - drawSize.width) / 2.0,
            y: (target.height - drawSize.height) / 2.0
        )

        let output = NSImage(size: target)
        output.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: target)).fill()
        input.draw(
            in: NSRect(origin: drawOrigin, size: drawSize),
            from: NSRect(origin: .zero, size: source),
            operation: .copy,
            fraction: 1.0
        )
        output.unlockFocus()

        guard
            let tiff = output.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "pq-menubar", code: 611, userInfo: [NSLocalizedDescriptionKey: "Failed to encode portrait PNG"])
        }
        return png
    }

    private func startLogArchiveTimer() {
        logArchiveTimer?.cancel()
        logArchiveTimer = makeLogArchiveTimer(logStore: logStore)
    }

    private static func loadRoster(from url: URL, saveStore: SaveStore) throws -> (characters: [PlayerState], recentEventsByCharacterID: [UUID: [GameEvent]]) {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if fm.fileExists(atPath: url.path) {
            let dataBlob = try Data(contentsOf: url)
            let decoded = try decoder.decode(RosterFile.self, from: dataBlob)
            let eventMap = (decoded.recentEventsByCharacterID ?? [:]).reduce(into: [UUID: [GameEvent]]()) { partial, item in
                guard let id = UUID(uuidString: item.key) else { return }
                partial[id] = Array(item.value.prefix(10))
            }
            return (decoded.characters, eventMap)
        }

        if let save = saveStore.load() {
            return ([save.activeCharacter], [save.activeCharacter.id: []])
        }

        return ([], [:])
    }

    private static func placeholderCharacter() -> PlayerState {
        let stats = Stats(values: [
            StatType.strength.rawValue: 0,
            StatType.condition.rawValue: 0,
            StatType.dexterity.rawValue: 0,
            StatType.intelligence.rawValue: 0,
            StatType.wisdom.rawValue: 0,
            StatType.charisma.rawValue: 0,
            StatType.hpMax.rawValue: 0,
            StatType.mpMax.rawValue: 0,
        ])
        return PlayerState(name: "-", race: "-", characterClass: "-", stats: stats)
    }

    private static func ensureDefaultData(at destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            return
        }
        let candidates: [URL?] = [
            findBundledResource(named: "default-data", withExtension: "json", subdirectory: "data"),
            findBundledResource(named: "default-data", withExtension: "json"),
        ]

        if let source = candidates.compactMap({ $0 }).first(where: { fm.fileExists(atPath: $0.path) }) {
            try fm.copyItem(at: source, to: destination)
            return
        }

        throw NSError(
            domain: "pq-menubar",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Missing bundled default-data.json",
                "checked_paths": candidates.compactMap { $0?.path },
            ]
        )
    }

    private static func repairUserDataIfInvalid(at dataURL: URL) throws {
        do {
            _ = try PQDataLoader.load(from: dataURL)
            return
        } catch {
            let fm = FileManager.default
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupURL = dataURL.deletingLastPathComponent().appendingPathComponent("default-data.invalid-\(timestamp).json")
            if fm.fileExists(atPath: dataURL.path) {
                try? fm.removeItem(at: backupURL)
                try fm.moveItem(at: dataURL, to: backupURL)
            }

            let candidates: [URL?] = [
                findBundledResource(named: "default-data", withExtension: "json", subdirectory: "data"),
                findBundledResource(named: "default-data", withExtension: "json"),
            ]
            if let source = candidates.compactMap({ $0 }).first(where: { fm.fileExists(atPath: $0.path) }) {
                try fm.copyItem(at: source, to: dataURL)
                _ = try PQDataLoader.load(from: dataURL)
                return
            }

            throw NSError(
                domain: "pq-menubar",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "default-data.json invalid and no bundled fallback found (\(error.localizedDescription))"]
            )
        }
    }

    private static func findBundledResource(named name: String, withExtension ext: String, subdirectory: String? = nil) -> URL? {
        let fm = FileManager.default
        let filename = "\(name).\(ext)"
        var roots: [URL] = []

        if let r = Bundle.main.resourceURL { roots.append(r) }
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
        roots.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Sources/PQMenuBarApp/Resources", isDirectory: true))

        // De-duplicate candidate roots while preserving order.
        var uniqueRoots: [URL] = []
        var seen = Set<String>()
        for root in roots {
            let key = root.standardizedFileURL.path
            if seen.insert(key).inserted {
                uniqueRoots.append(root)
            }
        }

        var candidates: [URL] = []
        for root in uniqueRoots {
            if let subdirectory {
                candidates.append(root.appendingPathComponent(subdirectory, isDirectory: true).appendingPathComponent(filename))
            }
            candidates.append(root.appendingPathComponent(filename))

            let bundles = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for bundle in bundles where bundle.pathExtension == "bundle" {
                if let subdirectory {
                    candidates.append(bundle.appendingPathComponent(subdirectory, isDirectory: true).appendingPathComponent(filename))
                }
                candidates.append(bundle.appendingPathComponent(filename))
                candidates.append(bundle.appendingPathComponent("Contents/Resources", isDirectory: true).appendingPathComponent(filename))
                if let subdirectory {
                    candidates.append(bundle.appendingPathComponent("Contents/Resources", isDirectory: true).appendingPathComponent(subdirectory, isDirectory: true).appendingPathComponent(filename))
                }
            }
        }

        return candidates.first(where: { fm.fileExists(atPath: $0.path) })
    }

    private static let defaultPortraitPromptTemplate = """
this is my character for a simple idle RPG. my name is {{character_name}}, a level {{player_level}} class {{player_class}}, who is also is playing a player race of {{player_race}}, I am currently on the {{current_quest}} quest doing the {{current_task}}. My best piece of equipment is {{best_equipment}}, and my best stat is {{best_prime_stat}}.
"""

    private static func ensurePortraitPromptTemplate(at destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination.path) == false else { return }
        try defaultPortraitPromptTemplate.write(to: destination, atomically: true, encoding: .utf8)
    }

    private nonisolated static func trimTrailingJSONNoise(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return data }
        if (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [])) != nil {
            return Data(text.utf8)
        }
        while !text.isEmpty {
            _ = text.removeLast()
            let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { break }
            if (try? JSONSerialization.jsonObject(with: Data(candidate.utf8), options: [])) != nil {
                return Data(candidate.utf8)
            }
        }
        return data
    }

    private static func loadMenubarTrackMap() -> [UUID: MenubarIconTrackMode] {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.menubarTrackByCharacterDefaultsKey) as? [String: String] else {
            return [:]
        }
        var map: [UUID: MenubarIconTrackMode] = [:]
        for (key, value) in raw {
            guard let id = UUID(uuidString: key), let mode = MenubarIconTrackMode(rawValue: value) else { continue }
            map[id] = mode
        }
        return map
    }

    private func persistMenubarTrackMap() {
        let raw = menubarTrackByCharacterID.reduce(into: [String: String]()) { partial, item in
            partial[item.key.uuidString] = item.value.rawValue
        }
        UserDefaults.standard.set(raw, forKey: Self.menubarTrackByCharacterDefaultsKey)
    }
}

private func makeLogArchiveTimer(logStore: EventLogStore) -> DispatchSourceTimer {
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now() + .seconds(60), repeating: .seconds(3600), leeway: .seconds(15))
    timer.setEventHandler {
        logStore.archiveCurrentLogIfNeededForCurrentHour()
    }
    timer.resume()
    return timer
}

private struct ImportedPayload: Codable {
    var players: [ImportedPlayer]
}

private struct PlayerStateWrapperPayload: Codable {
    var players: [PlayerState]
}

private struct ImportedPlayer: Codable {
    var name: String
    var race: String
    var characterClass: String
    var stats: [String: Int]?

    func toPlayerState(defaultData: PQDataBundle) -> PlayerState {
        let baseStats = Stats(values: stats ?? [
            StatType.strength.rawValue: 10,
            StatType.condition.rawValue: 10,
            StatType.dexterity.rawValue: 10,
            StatType.intelligence.rawValue: 10,
            StatType.wisdom.rawValue: 10,
            StatType.charisma.rawValue: 10,
            StatType.hpMax.rawValue: 8,
            StatType.mpMax.rawValue: 8,
        ])
        let raceName = race.isEmpty ? (defaultData.races.first?.name ?? "Half Orc") : race
        let className = characterClass.isEmpty ? (defaultData.classes.first?.name ?? "Ur-Paladin") : characterClass
        return PlayerState(name: name, race: raceName, characterClass: className, stats: baseStats)
    }
}

extension NSAlert {
    static func runAskYesNo(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
