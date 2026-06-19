// Pomodoro.swift — port of the pomodoor.lua state machine (work/rest countdown, the
// 3-press disable: pause → reset → shutdown, work counting, menubar title string). The 1s
// timer, menubar item, color-bar drawing, and alerts are the system boundary; this owns the
// state and reports phase-completion events.

import Foundation

public final class Pomodoro {

    public enum Phase: String { case work, rest }

    public struct Config {
        public var workPeriodSec: Int
        public var restPeriodSec: Int
        public var enableColorBar: Bool
        public init(workPeriodSec: Int, restPeriodSec: Int, enableColorBar: Bool = true) {
            self.workPeriodSec = workPeriodSec; self.restPeriodSec = restPeriodSec
            self.enableColorBar = enableColorBar
        }
    }

    /// What `disable()` did, so the system layer can stop/teardown the timer + menubar.
    public enum DisableResult: Equatable {
        case paused(wasActive: Bool)
        case reset
        case shutdown
        case noop
    }

    public enum TickEvent: Equatable { case workCompleted, restCompleted }

    public private(set) var isActive = false
    public private(set) var disableCount = 0
    public private(set) var workCount = 0
    public private(set) var phase: Phase = .work
    public private(set) var timeLeft: Int
    public private(set) var maxTimeSec: Int
    public private(set) var hasMenu = false

    private var config: Config

    public init(config: Config) {
        self.config = config
        self.timeLeft = config.workPeriodSec
        self.maxTimeSec = config.workPeriodSec
    }

    /// Start (or no-op if already active). The system layer creates the menubar + 1s timer.
    public func enable() {
        disableCount = 0
        if isActive { return }
        hasMenu = true
        isActive = true
    }

    /// 3-press semantics: 0 → pause, 1 → reset, ≥2 → shutdown (teardown menubar/timer).
    @discardableResult
    public func disable() -> DisableResult {
        let wasActive = isActive
        isActive = false

        if disableCount == 0 {
            disableCount += 1
            return .paused(wasActive: wasActive)
        } else if disableCount == 1 {
            timeLeft = config.workPeriodSec
            phase = .work
            disableCount += 1
            return .reset
        } else { // >= 2
            if !hasMenu {
                disableCount = 2   // matches Lua: stays at 2, no increment
                return .noop
            }
            hasMenu = false
            disableCount += 1
            return .shutdown
        }
    }

    /// One second elapsed. Returns a completion event when a period ends (alert trigger).
    @discardableResult
    public func tick() -> TickEvent? {
        if !isActive { return nil }
        timeLeft -= 1
        guard timeLeft <= 0 else { return nil }

        _ = disable()   // completion pauses (disableCount 0 → paused, →1), matching Lua
        if phase == .work {
            workCount += 1
            phase = .rest
            timeLeft = config.restPeriodSec
            maxTimeSec = config.restPeriodSec
            return .workCompleted
        } else {
            phase = .work
            timeLeft = config.workPeriodSec
            maxTimeSec = config.workPeriodSec
            return .restCompleted
        }
    }

    public func resetWork() { workCount = 0 }

    /// Apply a new config on a live reload. An active countdown keeps its remaining time; an
    /// idle timer re-baselines to the new work period so the next start reflects the change.
    public func updateConfig(_ newConfig: Config) {
        config = newConfig
        if !isActive {
            phase = .work
            timeLeft = newConfig.workPeriodSec
            maxTimeSec = newConfig.workPeriodSec
        }
    }

    /// Menubar title, e.g. "[work|52:00|#03]".
    public var displayString: String {
        let minutes = timeLeft / 60
        let seconds = timeLeft - minutes * 60
        return String(format: "[%@|%02d:%02d|#%02d]", phase.rawValue, minutes, seconds, workCount)
    }
}
