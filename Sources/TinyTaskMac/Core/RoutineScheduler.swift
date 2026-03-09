import Foundation

public final class RoutineScheduler {
    public let routine: RoutineDocument
    public private(set) var runtimeState: RoutineRuntimeState
    public private(set) var currentExecution: RoutineExecutionRequest?

    private var interruptStates: [UUID: InterruptRuntimeEntry] = [:]
    private var waitingToStopMainForInterrupts = false

    public init(routine: RoutineDocument) {
        self.routine = routine
        self.runtimeState = RoutineRuntimeState(
            routineName: routine.name,
            isRunning: false,
            currentEntryName: nil,
            statusText: "Routine ready",
            nextDueText: nil
        )
    }

    public func start(at date: Date) -> RoutineSchedulerCommand {
        interruptStates = [:]
        waitingToStopMainForInterrupts = false

        for entry in routine.interruptEntries where entry.isEnabled {
            let intervalSeconds = TimeInterval(max(1, entry.intervalMinutes)) * 60.0
            interruptStates[entry.id] = InterruptRuntimeEntry(
                entry: entry,
                nextDueAt: date.addingTimeInterval(intervalSeconds),
                isPending: false
            )
        }

        let request = RoutineExecutionRequest(kind: .main, entryName: mainEntryName())
        currentExecution = request
        refreshRuntimeState(now: date)
        return .startMain
    }

    public func tick(now: Date) -> RoutineSchedulerCommand? {
        guard runtimeState.isRunning else {
            return nil
        }

        markDueInterrupts(now: now)
        refreshRuntimeState(now: now)

        guard hasPendingInterrupts,
              case .main = currentExecution?.kind,
              !waitingToStopMainForInterrupts
        else {
            return nil
        }

        waitingToStopMainForInterrupts = true
        refreshRuntimeState(now: now)
        return .stopCurrentForInterrupts
    }

    public func playbackFinished(at date: Date) -> RoutineSchedulerCommand? {
        guard runtimeState.isRunning else {
            return nil
        }

        waitingToStopMainForInterrupts = false
        markDueInterrupts(now: date)

        if let nextInterruptID = nextPendingInterruptID(),
           let interruptState = interruptStates[nextInterruptID] {
            interruptStates[nextInterruptID]?.isPending = false
            currentExecution = RoutineExecutionRequest(
                kind: .interrupt(nextInterruptID),
                entryName: displayName(for: interruptState.entry)
            )
            refreshRuntimeState(now: date)
            return .startInterrupt(nextInterruptID)
        }

        currentExecution = RoutineExecutionRequest(kind: .main, entryName: mainEntryName())
        refreshRuntimeState(now: date)
        return .startMain
    }

    public func playbackFailed(message: String, at date: Date) {
        currentExecution = nil
        waitingToStopMainForInterrupts = false
        runtimeState = RoutineRuntimeState(
            routineName: routine.name,
            isRunning: false,
            currentEntryName: nil,
            statusText: message,
            nextDueText: nextDueText(now: date)
        )
    }

    public func stop(at date: Date) {
        currentExecution = nil
        waitingToStopMainForInterrupts = false
        runtimeState = RoutineRuntimeState(
            routineName: routine.name,
            isRunning: false,
            currentEntryName: nil,
            statusText: "Routine stopped",
            nextDueText: nextDueText(now: date)
        )
    }

    public func entryName(for kind: RoutineExecutionKind) -> String {
        switch kind {
        case .main:
            return mainEntryName()
        case let .interrupt(id):
            guard let interruptState = interruptStates[id] else {
                return "Interrupt Macro"
            }
            return displayName(for: interruptState.entry)
        }
    }

    private var hasPendingInterrupts: Bool {
        interruptStates.values.contains(where: \.isPending)
    }

    private func markDueInterrupts(now: Date) {
        for id in interruptStates.keys {
            guard var state = interruptStates[id] else {
                continue
            }

            let intervalSeconds = TimeInterval(max(1, state.entry.intervalMinutes)) * 60.0
            if now >= state.nextDueAt {
                state.isPending = true
                while state.nextDueAt <= now {
                    state.nextDueAt = state.nextDueAt.addingTimeInterval(intervalSeconds)
                }
            }

            interruptStates[id] = state
        }
    }

    private func nextPendingInterruptID() -> UUID? {
        interruptStates.values
            .filter(\.isPending)
            .sorted { lhs, rhs in
                if lhs.entry.priority != rhs.entry.priority {
                    return lhs.entry.priority < rhs.entry.priority
                }
                return displayName(for: lhs.entry).localizedCaseInsensitiveCompare(displayName(for: rhs.entry)) == .orderedAscending
            }
            .first?
            .entry
            .id
    }

    private func refreshRuntimeState(now: Date) {
        let statusText: String
        if let currentExecution {
            switch currentExecution.kind {
            case .main:
                statusText = waitingToStopMainForInterrupts ? "Interrupt pending" : "Running Main Macro"
            case .interrupt:
                statusText = "Running \(currentExecution.entryName)"
            }
        } else if interruptStates.isEmpty {
            statusText = "Routine ready"
        } else {
            statusText = "Routine idle"
        }

        runtimeState = RoutineRuntimeState(
            routineName: routine.name,
            isRunning: currentExecution != nil,
            currentEntryName: currentExecution?.entryName,
            statusText: statusText,
            nextDueText: nextDueText(now: now)
        )
    }

    private func nextDueText(now: Date) -> String? {
        if let pendingID = nextPendingInterruptID(),
           let pendingState = interruptStates[pendingID] {
            return "\(displayName(for: pendingState.entry)) pending"
        }

        guard let nextState = interruptStates.values.min(by: { lhs, rhs in
            lhs.nextDueAt < rhs.nextDueAt
        }) else {
            return nil
        }

        let secondsRemaining = max(0, Int(nextState.nextDueAt.timeIntervalSince(now)))
        let minutesRemaining = max(1, Int(ceil(Double(secondsRemaining) / 60.0)))
        return "Next \(displayName(for: nextState.entry)) in \(minutesRemaining)m"
    }

    private func mainEntryName() -> String {
        routine.mainEntry?.macroReference.displayName ?? "Main Macro"
    }

    private func displayName(for entry: RoutineInterruptEntry) -> String {
        let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? entry.macroReference.displayName : trimmed
    }
}

private struct InterruptRuntimeEntry {
    var entry: RoutineInterruptEntry
    var nextDueAt: Date
    var isPending: Bool
}
