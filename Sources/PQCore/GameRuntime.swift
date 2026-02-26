import Foundation

public final class GameRuntime {
    public private(set) var state: GameState
    public private(set) var events: [GameEvent] = []

    private var engine: TickEngine
    private let saveStore: SaveStore
    private let logStore: EventLogStore
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "pq.runtime", qos: .background)
    private var tickRateMultiplier: Double = 1.0
    private var stateDirty: Bool = true
    private var lastPersistAt: Date = .distantPast
    private let persistInterval: TimeInterval = 60

    public var onStateChange: ((GameState) -> Void)?
    public var onEvent: ((GameEvent) -> Void)?

    public init(initialState: GameState, data: PQDataBundle, saveStore: SaveStore, logStore: EventLogStore) {
        self.state = initialState
        self.engine = TickEngine(data: data)
        self.saveStore = saveStore
        self.logStore = logStore

        if self.state.rngState == 0 {
            self.state.rngState = PQRNG.seed(from: "\(initialState.activeCharacter.birthday.timeIntervalSince1970)")
        }
    }

    public func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let baseInterval = state.lowCPUMode ? 0.5 : 0.1
        let interval = max(0.01, baseInterval)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            self?.performTick()
        }
        timer.resume()
        self.timer = timer
    }

    public func stop() {
        queue.async {
            self.stopOnQueue()
        }
    }

    public func replaceState(_ newState: GameState) {
        queue.async {
            self.state = newState
            self.persistAndPublish(forceSave: true)
        }
    }

    public func setPaused(_ paused: Bool) {
        queue.async {
            self.state.isPaused = paused
            self.state.lastTickAt = Date()
            self.persistAndPublish(forceSave: paused)
        }
    }

    public func setLowCPUMode(_ enabled: Bool) {
        queue.async {
            self.state.lowCPUMode = enabled
            self.stopOnQueue()
            self.start()
            self.persistAndPublish()
        }
    }

    public func manualSave() {
        queue.async {
            self.persistState()
        }
    }

    public func setTickRateMultiplier(_ multiplier: Double) {
        queue.async {
            self.tickRateMultiplier = max(0.25, multiplier)
            self.stopOnQueue()
            self.start()
            self.persistAndPublish()
        }
    }

    private func performTick() {
        let previous = state
        let now = Date()
        let elapsed = now.timeIntervalSince(state.lastTickAt)
        let scaledElapsed = elapsed * max(0.25, tickRateMultiplier)
        let tickEvents = engine.tick(state: &state, elapsed: scaledElapsed)
        for event in tickEvents {
            events.append(event)
            logStore.append(event)
            onEvent?(event)
        }
        let milestone = shouldForceSave(previous: previous, current: state)
        persistAndPublish(forceSave: milestone)
    }

    private func persistAndPublish(forceSave: Bool = false) {
        stateDirty = true
        if forceSave {
            persistState()
        } else if Date().timeIntervalSince(lastPersistAt) >= persistInterval {
            persistState()
        }
        onStateChange?(state)
    }

    private func flushDirtyNow() {
        if stateDirty {
            persistState()
        }
    }

    private func stopOnQueue() {
        timer?.cancel()
        timer = nil
        flushDirtyNow()
    }

    private func persistState() {
        try? saveStore.save(state)
        stateDirty = false
        lastPersistAt = Date()
    }

    private func shouldForceSave(previous: GameState, current: GameState) -> Bool {
        let prevPlayer = previous.activeCharacter
        let currPlayer = current.activeCharacter

        if prevPlayer.level != currPlayer.level { return true }
        if prevPlayer.questBook.act != currPlayer.questBook.act { return true }
        if prevPlayer.questBook.currentQuest != currPlayer.questBook.currentQuest { return true }

        let prevTask = prevPlayer.task?.kind
        let currTask = currPlayer.task?.kind
        if prevTask != currTask {
            if currTask == .headingToMarket || currTask == .sell { return true }
            if prevTask == .sell && currTask != .sell { return true }
        }

        if prevPlayer.inventoryGold != currPlayer.inventoryGold {
            if prevTask == .sell || currTask == .sell || prevTask == .headingToMarket || currTask == .headingToMarket {
                return true
            }
        }

        let prevPlotBucket = Int((percent(from: prevPlayer.questBook.plotBar) / 10.0).rounded(.down))
        let currPlotBucket = Int((percent(from: currPlayer.questBook.plotBar) / 10.0).rounded(.down))
        if prevPlotBucket != currPlotBucket { return true }

        return false
    }

    private func percent(from bar: Bar) -> Double {
        guard bar.max > 0 else { return 0 }
        return max(0, min(100, (bar.position / bar.max) * 100))
    }
}
