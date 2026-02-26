import AppKit
import Foundation
import PQCore
import UniformTypeIdentifiers

private struct RosterFile: Codable {
    var activeCharacterID: UUID?
    var characters: [PlayerState]
}

@MainActor
final class AppState: ObservableObject {
    @Published var state: GameState
    @Published var events: [GameEvent]
    @Published var compactMode: Bool = false
    @Published var persistentDashboardWindow: Bool {
        didSet {
            UserDefaults.standard.set(persistentDashboardWindow, forKey: Self.persistentDashboardWindowDefaultsKey)
        }
    }

    @Published var roster: [PlayerState]
    @Published var selectedCharacterID: UUID?
    @Published var sessionStarted: Bool
    @Published var statusMessage: String?
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

    let dataDirectory: DataDirectory
    let saveStore: SaveStore
    let logStore: EventLogStore
    let runtime: GameRuntime
    let dataBundle: PQDataBundle

    private let rosterURL: URL
    private let portraitsURL: URL
    private let portraitPromptTemplateURL: URL
    private static let openAIAPIKeyDefaultsKey = "pq.openai.apiKey"
    private static let tickRateDefaultsKey = "pq.runtime.tickRate"
    private static let persistentDashboardWindowDefaultsKey = "pq.dashboard.persistentWindow"
    private var portraitGenerationInFlightCharacterIDs: Set<UUID> = []
    private var lastSeenLevelByCharacterID: [UUID: Int] = [:]
    private var logArchiveTimer: DispatchSourceTimer?
    private var lastRosterPersistAt: Date = .distantPast

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
            persistentDashboardWindow = UserDefaults.standard.bool(forKey: Self.persistentDashboardWindowDefaultsKey)

            let userDataURL = dataDirectory.data.appendingPathComponent("default-data.json")
            try Self.ensureDefaultData(at: userDataURL)
            dataBundle = try PQDataLoader.load(from: userDataURL)
            portraitPromptTemplateURL = dataDirectory.data.appendingPathComponent("portrait-prompt.txt")
            try Self.ensurePortraitPromptTemplate(at: portraitPromptTemplateURL)

            let loaded = try Self.loadRoster(from: rosterURL, saveStore: saveStore, data: dataBundle)
            roster = loaded.characters
            selectedCharacterID = nil
            sessionStarted = false
            statusMessage = nil
            portraitImageURL = nil

            let initialCharacter = loaded.characters.first ?? Self.defaultCharacter(from: dataBundle)
            let initialState = GameState(activeCharacter: initialCharacter, isPaused: true)
            state = initialState
            events = []

            runtime = GameRuntime(initialState: initialState, data: dataBundle, saveStore: saveStore, logStore: logStore)
            runtime.setTickRateMultiplier(tickRateMultiplier)
            startLogArchiveTimer()

            runtime.onStateChange = { [weak self] newState in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.state = newState
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
                    self?.events.insert(event, at: 0)
                    self?.events = Array(self?.events.prefix(100) ?? [])
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

    func startSelectedCharacter() {
        guard let c = selectedCharacter ?? roster.first else {
            flash("No character available to start.")
            return
        }
        start(character: c)
    }

    func start(character: PlayerState) {
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
        selectedCharacterID = character.id
        lastSeenLevelByCharacterID[character.id] = character.level
        persistRoster()
        refreshPortraitForCurrentCharacter()
        handleAutomaticPortraitUpdate(character: character, previousLevel: nil)
        flash("Started \(character.name).")
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
        selectedCharacterID = nil
        portraitGenerationInFlightCharacterIDs.remove(state.activeCharacter.id)
        persistRoster()
        refreshPortraitForCurrentCharacter()
        flash("Saved and closed \(currentName).")
    }

    func deleteSelectedCharacter() {
        guard let id = selectedCharacterID else { return }
        roster.removeAll(where: { $0.id == id })
        selectedCharacterID = nil
        persistRoster()
        refreshPortraitForCurrentCharacter()
    }

    func createCharacter(name: String, race: String, className: String, stats: Stats? = nil) {
        let newStats = stats ?? rollStats()
        let c = PlayerState(name: name, race: race, characterClass: className, stats: newStats)
        roster.append(c)
        selectedCharacterID = c.id
        persistRoster()
        refreshPortraitForCurrentCharacter()
    }

    func togglePause() {
        guard sessionStarted else { return }
        let next = !state.isPaused
        runtime.setPaused(next)
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

        do {
            if url.pathExtension.lowercased() == "json" {
                try importFromJSON(url)
            } else {
                let imported = try importLegacyCharacterFile(url)
                try importFromJSON(imported)
            }
        } catch {
            events.insert(.init(message: "Import failed: \(error.localizedDescription)"), at: 0)
        }
    }

    func exportCharacterInteractive() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json, UTType(filenameExtension: "pkl")!, UTType(filenameExtension: "pqw")!]
        panel.nameFieldStringValue = "character.pkl"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let ext = url.pathExtension.lowercased()
            if ext == "json" {
                try exportSelectedCharacterJSON(to: url)
            } else {
                let tempJSON = dataDirectory.saves.appendingPathComponent("export-\(UUID().uuidString).json")
                try exportSelectedCharacterJSON(to: tempJSON)
                try legacyBridge().exportPKL(from: tempJSON, to: url)
                try? FileManager.default.removeItem(at: tempJSON)
            }
            events.insert(.init(message: "Exported character to \(url.lastPathComponent)."), at: 0)
        } catch {
            events.insert(.init(message: "Export failed: \(error.localizedDescription)"), at: 0)
        }
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

    private func importFromJSON(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let gameState = try? decoder.decode(GameState.self, from: data) {
            mergeImportedCharacter(gameState.activeCharacter)
            events.insert(.init(message: "Imported JSON save: \(url.lastPathComponent)"), at: 0)
            return
        }

        if let player = try? decoder.decode(PlayerState.self, from: data) {
            mergeImportedCharacter(player)
            events.insert(.init(message: "Imported character: \(player.name)"), at: 0)
            return
        }

        let imported = try decoder.decode(ImportedPayload.self, from: data)
        var importedCount = 0
        for p in imported.players {
            mergeImportedCharacter(p.toPlayerState(defaultData: dataBundle))
            importedCount += 1
        }
        events.insert(.init(message: "Imported \(importedCount) character(s)."), at: 0)
    }

    private func exportSelectedCharacterJSON(to url: URL) throws {
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
        try payload.write(to: url, options: .atomic)
    }

    private func mergeImportedCharacter(_ c: PlayerState) {
        if let idx = roster.firstIndex(where: { $0.id == c.id }) {
            roster[idx] = c
        } else {
            roster.append(c)
        }
        selectedCharacterID = c.id
        persistRoster()
        refreshPortraitForCurrentCharacter()
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

    private func persistRoster() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let payload = RosterFile(activeCharacterID: selectedCharacterID, characters: roster)
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
        return try resizePNG(decoded, width: 100, height: 125)
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
        return try resizePNG(decoded, width: 100, height: 125)
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
        let output = NSImage(size: target)
        output.lockFocus()
        input.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1.0)
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

    private static func loadRoster(from url: URL, saveStore: SaveStore, data: PQDataBundle) throws -> RosterFile {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if fm.fileExists(atPath: url.path) {
            let dataBlob = try Data(contentsOf: url)
            return try decoder.decode(RosterFile.self, from: dataBlob)
        }

        if let save = saveStore.load() {
            return RosterFile(activeCharacterID: save.activeCharacter.id, characters: [save.activeCharacter])
        }

        let initial = defaultCharacter(from: data)
        return RosterFile(activeCharacterID: initial.id, characters: [initial])
    }

    private static func defaultCharacter(from data: PQDataBundle) -> PlayerState {
        let stats = Stats(values: [
            StatType.strength.rawValue: 10,
            StatType.condition.rawValue: 10,
            StatType.dexterity.rawValue: 10,
            StatType.intelligence.rawValue: 10,
            StatType.wisdom.rawValue: 10,
            StatType.charisma.rawValue: 10,
            StatType.hpMax.rawValue: 8,
            StatType.mpMax.rawValue: 8,
        ])

        let race = data.races.first?.name ?? "Half Orc"
        let cls = data.classes.first?.name ?? "Ur-Paladin"
        return PlayerState(name: "New Hero", race: race, characterClass: cls, stats: stats)
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