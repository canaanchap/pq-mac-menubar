import Foundation

public struct TickEngine {
    private let data: PQDataBundle

    public init(data: PQDataBundle) {
        self.data = data
    }

    public mutating func tick(state: inout GameState, elapsed: TimeInterval) -> [GameEvent] {
        guard !state.isPaused else { return [] }

        var rng = PQRNG(seed: state.rngState)
        var events: [GameEvent] = []

        // Keep derived values sane across schema migrations/import edge cases.
        let minCapacity = 10 + state.activeCharacter.stats[.strength]
        if state.activeCharacter.inventoryCapacity < minCapacity {
            state.activeCharacter.inventoryCapacity = minCapacity
        }

        state.activeCharacter.elapsed += elapsed * 1000

        if state.activeCharacter.task == nil {
            state.activeCharacter.setTask(.init(kind: .regular, description: "Loading", duration: 2000))
            events.append(.init(message: "Loading..."))
            state.activeCharacter.queue += [
                .init(kind: .regular, description: "Experiencing an enigmatic and foreboding night vision", duration: 10000),
                .init(kind: .regular, description: "Much is revealed about that wise old knucklehead you'd underestimated", duration: 6000),
                .init(kind: .regular, description: "A shocking series of events leaves you alone and bewildered, but resolute", duration: 6000),
                .init(kind: .regular, description: "Drawing upon an unrealized reserve of determination, you set out on a long and dangerous journey", duration: 4000),
                .init(kind: .plot, description: "Loading \(PQLingo.actName(1))", duration: 2000),
            ]
            state.activeCharacter.questBook.plotBar.reset(max: 28)
            state.rngState = rng.state
            state.lastTickAt = Date()
            return events
        }

        if !state.activeCharacter.taskBar.done {
            state.activeCharacter.taskBar.increment(elapsed * 1000)
            state.rngState = rng.state
            state.lastTickAt = Date()
            return events
        }

        let gain = state.activeCharacter.task?.kind == .kill

        if gain {
            if state.activeCharacter.expBar.done {
                levelUp(player: &state.activeCharacter, rng: &rng, events: &events)
            } else {
                let inc = (state.activeCharacter.taskBar.max / 1000)
                state.activeCharacter.expBar.increment(inc)
            }
        }

        if gain && state.activeCharacter.questBook.act >= 1 {
            if state.activeCharacter.questBook.questBar.done || state.activeCharacter.questBook.currentQuest == nil {
                completeQuest(player: &state.activeCharacter, rng: &rng, events: &events)
            } else {
                state.activeCharacter.questBook.questBar.increment(state.activeCharacter.taskBar.max / 1000)
            }
        }

        if gain {
            if state.activeCharacter.questBook.plotBar.done {
                interplotCinematic(player: &state.activeCharacter, rng: &rng, events: &events)
            } else {
                state.activeCharacter.questBook.plotBar.increment(state.activeCharacter.taskBar.max / 1000)
            }
        }

        dequeue(player: &state.activeCharacter, rng: &rng, events: &events)

        state.rngState = rng.state
        state.lastTickAt = Date()
        return events
    }

    private func dequeue(player: inout PlayerState, rng: inout PQRNG, events: inout [GameEvent]) {
        dequeueLoop: while player.taskBar.done {
            if let task = player.task {
                switch task.kind {
                case .kill:
                    if let m = task.monster, let rawItem = m.item?.trimmingCharacters(in: .whitespacesAndNewlines), !rawItem.isEmpty {
                        let drop = "\(m.name) \(rawItem)".lowercased()
                        player.addInventoryItem(drop, quantity: 1)
                        events.append(.init(message: "Looted \(PQLingo.indefinite(drop, qty: 1))."))
                    } else {
                        let won = specialItem(rng: &rng)
                        player.addInventoryItem(won, quantity: 1)
                        events.append(.init(message: "Gained \(PQLingo.indefinite(won, qty: 1))."))
                    }

                case .buy:
                    let price = equipPrice(level: player.level)
                    player.addGold(-price)
                    winEquipment(player: &player, rng: &rng, events: &events)

                case .headingToMarket, .sell:
                    if task.kind == .sell {
                        if let item = player.inventoryItems.first {
                            var amount = item.quantity * player.level
                            if item.name.contains(" of ") {
                                amount *= (1 + rng.belowLow(10)) * (1 + rng.belowLow(player.level))
                            }
                            _ = player.popInventory(index: 0)
                            player.addGold(amount)
                            events.append(.init(message: "Sold \(PQLingo.indefinite(item.name, qty: item.quantity)) for \(amount) gold."))
                        }
                    }

                    if let item = player.inventoryItems.first {
                        let desc = "Selling \(PQLingo.indefinite(item.name, qty: item.quantity))"
                        player.setTask(.init(kind: .sell, description: desc, duration: 1000))
                        events.append(.init(message: "\(desc)..."))
                        continue dequeueLoop
                    }

                case .plot:
                    completeAct(player: &player, rng: &rng, events: &events)

                default:
                    break
                }
            }

            let old = player.task
            if !player.queue.isEmpty {
                let next = player.queue.removeFirst()
                player.setTask(next)
                events.append(.init(message: "\(next.description)..."))
            } else if player.encumbered && !player.inventoryItems.isEmpty {
                let next = GameTask(kind: .headingToMarket, description: "Heading to market to sell loot", duration: 4000)
                player.setTask(next)
                events.append(.init(message: "\(next.description)..."))
            } else if old?.kind != .kill && old?.kind != .headingToKillingFields {
                if player.inventoryGold > equipPrice(level: player.level) {
                    let next = GameTask(kind: .buy, description: "Negotiating purchase of better equipment", duration: 5000)
                    player.setTask(next)
                    events.append(.init(message: "\(next.description)..."))
                } else {
                    let next = GameTask(kind: .headingToKillingFields, description: "Heading to the killing fields", duration: 4000)
                    player.setTask(next)
                    events.append(.init(message: "\(next.description)..."))
                }
            } else {
                let next = monsterTask(playerLevel: player.level, questMonster: player.questBook.monster, rng: &rng)
                player.setTask(next)
                events.append(.init(message: "\(next.description)..."))
            }
        }
    }

    private func levelUp(player: inout PlayerState, rng: inout PQRNG, events: inout [GameEvent]) {
        player.level += 1
        player.stats[.hpMax] += player.stats[.condition] / 3 + 1 + rng.below(4)
        player.stats[.mpMax] += player.stats[.intelligence] / 3 + 1 + rng.below(4)

        _ = winStat(player: &player, rng: &rng)
        _ = winStat(player: &player, rng: &rng)
        winSpell(player: &player, rng: &rng)

        player.expBar.reset(max: PlayerState.levelUpTime(player.level))
        events.append(.init(message: "Leveled up to level \(player.level)!"))
    }

    private func winStat(player: inout PlayerState, rng: inout PQRNG) -> Bool {
        let chosen: StatType
        if rng.odds(1, 2) {
            chosen = rng.choice(StatType.allCases)
        } else {
            var t = StatType.allCases.reduce(0) { $0 + player.stats[$1] * player.stats[$1] }
            t = rng.below(t)
            var current: StatType = .strength
            for s in StatType.allCases {
                current = s
                t -= player.stats[s] * player.stats[s]
                if t < 0 { break }
            }
            chosen = current
        }

        player.stats[chosen] += 1
        if chosen == .strength {
            player.inventoryCapacity = 10 + player.stats[.strength]
        }
        return true
    }

    private func winSpell(player: inout PlayerState, rng: inout PQRNG) {
        let cap = min(player.stats[.wisdom] + player.level, data.spells.count)
        let idx = rng.belowLow(max(1, cap))
        player.addSpell(data.spells[idx], levelInc: 1)
    }

    private func winEquipment(player: inout PlayerState, rng: inout PQRNG, events: inout [GameEvent]) {
        let choice = rng.choice(EquipmentType.allCases)

        let stuff: [EquipmentPreset]
        let better: [Modifier]
        let worse: [Modifier]

        if choice == .weapon {
            stuff = data.weapons
            better = data.offenseAttrib
            worse = data.offenseBad
        } else {
            stuff = (choice == .shield) ? data.shields : data.armors
            better = data.defenseAttrib
            worse = data.defenseBad
        }

        let equipment = pickEquipment(source: stuff, goal: player.level, rng: &rng)
        var name = equipment.name
        var plus = player.level - equipment.quality
        let modifierPool = plus < 0 ? worse : better

        var count = 0
        while count < 2 && plus != 0 {
            let modifier = rng.choice(modifierPool)
            if name.contains(modifier.name) { break }
            if abs(plus) < abs(modifier.quality) { break }
            name = "\(modifier.name) \(name)"
            plus -= modifier.quality
            count += 1
        }

        if plus < 0 { name = "\(plus) \(name)" }
        if plus > 0 { name = "+\(plus) \(name)" }

        player.setEquipment(choice, name: name)
        events.append(.init(message: "Gained \(name) \(choice.rawValue)."))
    }

    private func completeAct(player: inout PlayerState, rng: inout PQRNG, events: inout [GameEvent]) {
        player.questBook.act += 1
        player.questBook.plotBar.reset(max: Double(60 * 60 * (1 + 5 * player.questBook.act)))
        events.append(.init(message: "Entered \(PQLingo.actName(player.questBook.act))."))

        if player.questBook.act > 1 {
            let item = specialItem(rng: &rng)
            player.addInventoryItem(item, quantity: 1)
            winEquipment(player: &player, rng: &rng, events: &events)
        }
    }

    private func completeQuest(player: inout PlayerState, rng: inout PQRNG, events: inout [GameEvent]) {
        player.questBook.questBar.reset(max: Double(50 + rng.belowLow(1000)))

        if let current = player.questBook.currentQuest {
            events.append(.init(message: "Quest completed: \(current)"))
            let reward = rng.below(4)
            if reward == 0 { winSpell(player: &player, rng: &rng) }
            else if reward == 1 { winEquipment(player: &player, rng: &rng, events: &events) }
            else if reward == 2 { _ = winStat(player: &player, rng: &rng) }
            else {
                let item = specialItem(rng: &rng)
                player.addInventoryItem(item, quantity: 1)
            }
        }

        player.questBook.monster = nil

        var caption = ""
        let choice = rng.below(5)
        if choice == 0 {
            let m = unnamedMonster(level: player.level, iterations: 3, rng: &rng)
            player.questBook.monster = m
            caption = "Exterminate \(PQLingo.definite(m.name, qty: 2))"
        } else if choice == 1 {
            caption = "Seek \(PQLingo.definite(interestingItem(rng: &rng), qty: 1))"
        } else if choice == 2 {
            caption = "Deliver this \(boringItem(rng: &rng))"
        } else if choice == 3 {
            caption = "Fetch me \(PQLingo.indefinite(boringItem(rng: &rng), qty: 1))"
        } else {
            let m = unnamedMonster(level: player.level, iterations: 1, rng: &rng)
            caption = "Placate \(PQLingo.definite(m.name, qty: 2))"
        }

        player.questBook.quests = Array(player.questBook.quests.suffix(100))
        player.questBook.quests.append(caption)
        events.append(.init(message: "Commencing quest: \(caption)"))
    }

    private func interplotCinematic(player: inout PlayerState, rng: inout PQRNG, events: inout [GameEvent]) {
        func enqueue(_ task: GameTask, _ player: inout PlayerState) {
            player.queue.append(task)
        }

        let choice = rng.below(3)
        if choice == 0 {
            enqueue(.init(kind: .regular, description: "Exhausted, you arrive at a friendly oasis in a hostile land", duration: 1000), &player)
            enqueue(.init(kind: .regular, description: "You greet old friends and meet new allies", duration: 2000), &player)
            enqueue(.init(kind: .regular, description: "You are privy to a council of powerful do-gooders", duration: 2000), &player)
            enqueue(.init(kind: .regular, description: "There is much to be done. You are chosen!", duration: 1000), &player)
        } else if choice == 1 {
            enqueue(.init(kind: .regular, description: "Your quarry is in sight, but a mighty enemy bars your path!", duration: 1000), &player)
            let nemesis = namedMonster(level: player.level + 3, rng: &rng)
            enqueue(.init(kind: .regular, description: "A desperate struggle commences with \(nemesis)", duration: 4000), &player)
            var s = rng.below(3)
            var i = 1
            while true {
                if i > rng.below(1 + player.questBook.act + 1) {
                    break
                }
                s += 1 + rng.below(2)
                if s % 3 == 0 {
                    enqueue(.init(kind: .regular, description: "Locked in grim combat with \(nemesis)", duration: 2000), &player)
                } else if s % 3 == 1 {
                    enqueue(.init(kind: .regular, description: "\(nemesis) seems to have the upper hand", duration: 2000), &player)
                } else {
                    enqueue(.init(kind: .regular, description: "You seem to gain the advantage over \(nemesis)", duration: 2000), &player)
                }
                i += 1
            }
            enqueue(.init(kind: .regular, description: "Victory! \(nemesis) is slain! Exhausted, you lose consciousness", duration: 3000), &player)
            enqueue(.init(kind: .regular, description: "You awake in a friendly place, but the road awaits", duration: 2000), &player)
        } else {
            let nemesis = impressiveGuy(rng: &rng)
            enqueue(.init(kind: .regular, description: "Oh sweet relief! You've reached the protection of the good \(nemesis)", duration: 2000), &player)
            enqueue(.init(kind: .regular, description: "There is rejoicing, and an unnerving encounter with \(nemesis) in private", duration: 3000), &player)
            enqueue(.init(kind: .regular, description: "You forget your \(boringItem(rng: &rng)) and go back to get it", duration: 2000), &player)
            enqueue(.init(kind: .regular, description: "What's this!? You overhear something shocking!", duration: 2000), &player)
            enqueue(.init(kind: .regular, description: "Could \(nemesis) be a dirty double-dealer?", duration: 2000), &player)
            enqueue(.init(kind: .regular, description: "Who can possibly be trusted with this news!? ... Oh yes, of course", duration: 3000), &player)
        }

        enqueue(.init(kind: .plot, description: "Loading \(PQLingo.actName(player.questBook.act + 1))", duration: 1000), &player)
        events.append(.init(message: "A plot cinematic unfolds."))
    }

    private func equipPrice(level: Int) -> Int {
        5 * (level * level) + 10 * level + 20
    }

    private func specialItem(rng: inout PQRNG) -> String {
        interestingItem(rng: &rng) + " of " + rng.choice(data.itemOfs)
    }

    private func interestingItem(rng: inout PQRNG) -> String {
        rng.choice(data.itemAttrib) + " " + rng.choice(data.specials)
    }

    private func boringItem(rng: inout PQRNG) -> String {
        rng.choice(data.boringItems)
    }

    private func impressiveGuy(rng: inout PQRNG) -> String {
        let title = rng.choice(data.impressiveTitles)
        if rng.below(2) == 0 {
            return title + " of the " + rng.choice(data.races).name
        }
        return title + " of " + PQLingo.generateName(rng: &rng)
    }

    private func unnamedMonster(level: Int, iterations: Int, rng: inout PQRNG) -> MonsterDef {
        var result = rng.choice(data.monsters)
        for _ in 0..<iterations {
            let alt = rng.choice(data.monsters)
            if abs(level - alt.level) < abs(level - result.level) {
                result = alt
            }
        }
        return result
    }

    private func namedMonster(level: Int, rng: inout PQRNG) -> String {
        let monster = unnamedMonster(level: level, iterations: 4, rng: &rng)
        return PQLingo.generateName(rng: &rng) + " the " + monster.name
    }

    private func pickEquipment(source: [EquipmentPreset], goal: Int, rng: inout PQRNG) -> EquipmentPreset {
        var result = rng.choice(source)
        for _ in 0..<5 {
            let alt = rng.choice(source)
            if abs(goal - alt.quality) < abs(goal - result.quality) {
                result = alt
            }
        }
        return result
    }

    private func monsterTask(playerLevel: Int, questMonster: MonsterDef?, rng: inout PQRNG) -> GameTask {
        var level = playerLevel
        if level > 0 {
            for _ in 0..<level {
                if rng.odds(2, 5) {
                    level += rng.below(2) * 2 - 1
                }
            }
        }
        if level < 1 { level = 1 }

        var isDefinite = false
        var monster: MonsterDef?
        var result = ""
        var lev = level

        if rng.odds(1, 25) {
            let race = rng.choice(data.races)
            if rng.odds(1, 2) {
                result = "passing \(race.name) \(rng.choice(data.classes).name)"
            } else {
                result = rng.choiceLow(data.titles) + " " + PQLingo.generateName(rng: &rng) + " the " + race.name
                isDefinite = true
            }
            lev = level
        } else if let questMonster, rng.odds(1, 4) {
            monster = questMonster
            result = questMonster.name
            lev = questMonster.level
        } else {
            monster = unnamedMonster(level: level, iterations: 5, rng: &rng)
            result = monster?.name ?? "Thing"
            lev = monster?.level ?? level
        }

        var qty = 1
        if level - lev > 10 {
            qty = (level + rng.below(max(lev, 1))) / max(lev, 1)
            if qty < 1 { qty = 1 }
            level /= qty
        }

        if level - lev <= -10 {
            result = "imaginary " + result
        } else if level - lev < -5 {
            var i = 10 + level - lev
            i = 5 - rng.below(i + 1)
            result = PQLingo.sick(i, PQLingo.young(lev - level - i, result))
        } else if level - lev < 0 && rng.below(2) == 1 {
            result = PQLingo.sick(level - lev, result)
        } else if level - lev < 0 {
            result = PQLingo.young(level - lev, result)
        } else if level - lev >= 10 {
            result = "messianic " + result
        } else if level - lev > 5 {
            var i = 10 - (level - lev)
            i = 5 - rng.below(i + 1)
            result = PQLingo.big(i, PQLingo.special(level - lev - i, result))
        } else if level - lev > 0 && rng.below(2) == 1 {
            result = PQLingo.big(level - lev, result)
        } else if level - lev > 0 {
            result = PQLingo.special(level - lev, result)
        }

        lev = level
        level = lev * qty
        if !isDefinite {
            result = PQLingo.indefinite(result, qty: qty)
        }

        let duration = (2 * 3 * level * 1000) / max(playerLevel, 1)
        return .init(kind: .kill, description: "Executing \(result)", duration: Double(duration), monster: monster)
    }
}
