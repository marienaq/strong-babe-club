import Foundation
import Observation
import UserNotifications
import WorkoutCore

/// Drives a WorkoutCore `IntervalPlan` with a wall clock: haptics at every
/// work/rest switch, and local notifications for the switches while the app
/// is in the background.
@MainActor
@Observable
final class IntervalTimerModel {
    let plan: IntervalPlan
    let title: String
    private(set) var clock = TimerClock()
    private(set) var snapshot: TimerSnapshot
    private var lastElapsed = 0
    private var ticker: Task<Void, Never>?

    init(plan: IntervalPlan, title: String) {
        self.plan = plan
        self.title = title
        self.snapshot = plan.snapshot(at: 0)
    }

    var isRunning: Bool { clock.isRunning }
    var elapsedSeconds: Int { lastElapsed }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !snapshot.isFinished else { return }
        clock.start(at: Date())
        Haptics.play(.tap)
        NotificationScheduler.requestPermissionIfNeeded()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    func pause() {
        clock.pause(at: Date())
        ticker?.cancel()
        ticker = nil
        tick()
    }

    func reset() {
        pause()
        clock.reset()
        lastElapsed = 0
        snapshot = plan.snapshot(at: 0)
        NotificationScheduler.cancelTimerAlerts()
    }

    func tick() {
        let e = Int(clock.elapsed(at: Date()))
        let changes = plan.transitions(from: lastElapsed, to: e)
        lastElapsed = e
        snapshot = plan.snapshot(at: e)
        if !changes.isEmpty {
            Haptics.play(snapshot.isFinished ? .success : .phaseChange)
        }
        if snapshot.isFinished, clock.isRunning {
            clock.pause(at: Date())
            ticker?.cancel()
            ticker = nil
        }
    }

    /// Called when the scene goes to the background.
    func didEnterBackground() {
        guard isRunning else { return }
        let upcoming = clock.upcomingTransitions(plan, now: Date())
        NotificationScheduler.schedule(upcoming.map { item in
            let label: String
            if item.phaseIndex >= plan.phases.count {
                label = "Done! Nice work."
            } else {
                let p = plan.phases[item.phaseIndex]
                label = p.kind == .work ? "Go: round \(p.round)" : "Rest"
            }
            return (item.date, label)
        }, title: title)
    }

    func willEnterForeground() {
        NotificationScheduler.cancelTimerAlerts()
        tick()
    }
}

/// Local notifications only (no push, no network). Content is generic
/// ("Rest", "Go: round 3"), never personal data.
enum NotificationScheduler {
    static let prefix = "timer."

    static func requestPermissionIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func schedule(_ items: [(Date, String)], title: String) {
        let center = UNUserNotificationCenter.current()
        cancelTimerAlerts()
        // iOS keeps at most 64 pending requests per app.
        for (i, item) in items.prefix(60).enumerated() {
            let interval = item.0.timeIntervalSinceNow
            guard interval > 0.5 else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = item.1
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(prefix)\(i)", content: content, trigger: trigger))
        }
        Log.timer.debug("scheduled \(min(items.count, 60), privacy: .public) timer alerts")
    }

    static func cancelTimerAlerts() {
        let ids = (0..<64).map { "\(prefix)\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
