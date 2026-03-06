import Foundation

public enum StatType: String, Codable, CaseIterable {
    case strength = "STR"
    case condition = "CON"
    case dexterity = "DEX"
    case intelligence = "INT"
    case wisdom = "WIS"
    case charisma = "CHA"
    case hpMax = "HP Max"
    case mpMax = "MP Max"
}

public enum EquipmentType: String, Codable, CaseIterable {
    case weapon = "Weapon"
    case shield = "Shield"
    case helm = "Helm"
    case hauberk = "Hauberk"
    case brassairts = "Brassairts"
    case vambraces = "Vambraces"
    case gauntlets = "Gauntlets"
    case gambeson = "Gambeson"
    case cuisses = "Cuisses"
    case greaves = "Greaves"
    case sollerets = "Sollerets"
}

public struct Modifier: Codable, Hashable {
    public var name: String
    public var quality: Int
}

public struct EquipmentPreset: Codable, Hashable {
    public var name: String
    public var quality: Int
}

public struct MonsterDef: Codable, Hashable {
    public var name: String
    public var level: Int
    public var item: String?
}

public struct RaceDef: Codable, Hashable {
    public var name: String
    public var attr: [String]
}

public struct ClassDef: Codable, Hashable {
    public var name: String
    public var attr: [String]
}

public struct PQDataBundle: Codable, Hashable {
    public var spells: [String]
    public var offenseAttrib: [Modifier]
    public var defenseAttrib: [Modifier]
    public var offenseBad: [Modifier]
    public var defenseBad: [Modifier]
    public var shields: [EquipmentPreset]
    public var armors: [EquipmentPreset]
    public var weapons: [EquipmentPreset]
    public var specials: [String]
    public var itemAttrib: [String]
    public var itemOfs: [String]
    public var boringItems: [String]
    public var monsters: [MonsterDef]
    public var races: [RaceDef]
    public var classes: [ClassDef]
    public var titles: [String]
    public var impressiveTitles: [String]
    public var primeStats: [String]
    public var equipmentTypes: [String]
}

public struct Bar: Codable, Hashable {
    public var max: Double
    public var position: Double

    public init(max: Double, position: Double = 0) {
        self.max = max
        self.position = position
    }

    public var done: Bool { position >= max }

    public mutating func reset(max: Double, position: Double = 0) {
        self.max = max
        self.position = position
    }

    public mutating func increment(_ inc: Double) {
        reposition(position + inc)
    }

    public mutating func reposition(_ value: Double) {
        position = min(value, max)
    }
}

public struct Stats: Codable, Hashable {
    public var values: [String: Int]

    public init(values: [String: Int]) {
        self.values = values
    }

    public subscript(_ stat: StatType) -> Int {
        get { values[stat.rawValue] ?? 0 }
        set { values[stat.rawValue] = newValue }
    }

    public var best: StatType {
        StatType.allCases.max(by: { self[$0] < self[$1] }) ?? .strength
    }

    public var bestPrime: StatType {
        let prime = [StatType.strength, .condition, .dexterity, .intelligence, .wisdom, .charisma]
        return prime.max(by: { self[$0] < self[$1] }) ?? .strength
    }
}

public struct InventoryItem: Codable, Hashable {
    public var name: String
    public var quantity: Int
}

public struct QuestBook: Codable, Hashable {
    public var act: Int
    public var quests: [String]
    public var plotBar: Bar
    public var questBar: Bar
    public var monster: MonsterDef?

    public init(act: Int = 0, quests: [String] = [], plotBar: Bar = .init(max: 1), questBar: Bar = .init(max: 1), monster: MonsterDef? = nil) {
        self.act = act
        self.quests = quests
        self.plotBar = plotBar
        self.questBar = questBar
        self.monster = monster
    }

    public var currentQuest: String? { quests.last }
}

public struct Spell: Codable, Hashable {
    public var name: String
    public var level: Int
}

public enum TaskKind: String, Codable, Hashable {
    case kill
    case buy
    case headingToKillingFields
    case headingToMarket
    case sell
    case regular
    case plot
}

public struct GameTask: Codable, Hashable {
    public var kind: TaskKind
    public var description: String
    public var duration: Double
    public var monster: MonsterDef?

    public init(kind: TaskKind, description: String, duration: Double, monster: MonsterDef? = nil) {
        self.kind = kind
        self.description = description
        self.duration = duration
        self.monster = monster
    }
}

public struct PlayerState: Codable, Hashable {
    public var id: UUID
    public var name: String
    public var birthday: Date
    public var race: String
    public var characterClass: String
    public var stats: Stats
    public var elapsed: Double

    public var expBar: Bar
    public var level: Int

    public var questBook: QuestBook
    public var inventoryGold: Int
    public var inventoryItems: [InventoryItem]
    public var inventoryCapacity: Int

    public var equipment: [String: String]
    public var bestEquipment: String
    public var spells: [Spell]

    public var taskBar: Bar
    public var task: GameTask?
    public var queue: [GameTask]

    // Multiplayer metadata (v1 scaffold). These fields are persisted with the character save.
    public var networkMode: String?
    public var networkLocked: Bool?
    public var realmId: String?
    public var accountId: String?
    public var serverCharacterId: String?
    public var lastCheckinAt: Date?
    public var lastAcceptedCheckpointId: String?
    public var cheatRiskState: String?

    public init(
        id: UUID = UUID(),
        name: String,
        birthday: Date = .now,
        race: String,
        characterClass: String,
        stats: Stats
    ) {
        self.id = id
        self.name = name
        self.birthday = birthday
        self.race = race
        self.characterClass = characterClass
        self.stats = stats
        self.elapsed = 0

        self.expBar = Bar(max: Self.levelUpTime(1))
        self.level = 1

        self.questBook = QuestBook()
        self.inventoryGold = 0
        self.inventoryItems = []
        self.inventoryCapacity = 10 + stats[.strength]

        self.equipment = [
            EquipmentType.weapon.rawValue: "Sharp Rock",
            EquipmentType.hauberk.rawValue: "-3 Burlap",
        ]
        self.bestEquipment = "Sharp Rock"
        self.spells = []

        self.taskBar = Bar(max: 1)
        self.task = nil
        self.queue = []

        self.networkMode = "offline"
        self.networkLocked = false
        self.realmId = nil
        self.accountId = nil
        self.serverCharacterId = nil
        self.lastCheckinAt = nil
        self.lastAcceptedCheckpointId = nil
        self.cheatRiskState = nil
    }

    public static func levelUpTime(_ level: Int) -> Double {
        Double(20 * level * 60)
    }

    public mutating func setTask(_ next: GameTask) {
        task = next
        taskBar.reset(max: next.duration)
    }

    public mutating func addInventoryItem(_ itemName: String, quantity: Int) {
        if let idx = inventoryItems.firstIndex(where: { $0.name == itemName }) {
            inventoryItems[idx].quantity += quantity
        } else {
            inventoryItems.append(.init(name: itemName, quantity: quantity))
        }
        syncEncumbrance()
    }

    public mutating func popInventory(index: Int) -> InventoryItem? {
        guard inventoryItems.indices.contains(index) else { return nil }
        let item = inventoryItems.remove(at: index)
        syncEncumbrance()
        return item
    }

    public mutating func syncEncumbrance() {
        let total = inventoryItems.reduce(0) { $0 + $1.quantity }
        taskBar.reposition(taskBar.position)
        if total > inventoryCapacity {
            // represented via check in engine by comparing total >= capacity
        }
    }

    public var encumbered: Bool {
        inventoryItems.reduce(0) { $0 + $1.quantity } >= inventoryCapacity
    }

    public mutating func addGold(_ amount: Int) {
        inventoryGold += amount
    }

    public mutating func setEquipment(_ type: EquipmentType, name: String) {
        equipment[type.rawValue] = name
        if type == .weapon || type == .shield {
            bestEquipment = name
        } else {
            bestEquipment = "\(name) \(type.rawValue)"
        }
    }

    public mutating func addSpell(_ spellName: String, levelInc: Int) {
        if let idx = spells.firstIndex(where: { $0.name == spellName }) {
            spells[idx].level += levelInc
        } else {
            spells.append(.init(name: spellName, level: levelInc))
        }
    }

    public var taskProgressPercent: Double {
        taskBar.max > 0 ? (taskBar.position / taskBar.max) * 100 : 0
    }

    public var xpProgressPercent: Double {
        expBar.max > 0 ? (expBar.position / expBar.max) * 100 : 0
    }

    public var isOnlineMultiplayer: Bool {
        networkMode == "online" && (networkLocked ?? false)
    }
}

public struct GameEvent: Codable, Hashable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), message: String) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
    }
}

public struct GameState: Codable, Hashable {
    public var activeCharacter: PlayerState
    public var isPaused: Bool
    public var lowCPUMode: Bool
    public var lastTickAt: Date
    public var rngState: UInt64

    public init(activeCharacter: PlayerState, isPaused: Bool = false, lowCPUMode: Bool = false, lastTickAt: Date = .now, rngState: UInt64 = 0) {
        self.activeCharacter = activeCharacter
        self.isPaused = isPaused
        self.lowCPUMode = lowCPUMode
        self.lastTickAt = lastTickAt
        self.rngState = rngState
    }
}
