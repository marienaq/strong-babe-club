import AVFoundation
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
        let fresh = clock.elapsed(at: Date()) == 0
        clock.start(at: Date())
        if fresh, let cue = plan.cue(enteringPhase: 0) { TimerSound.shared.play(cue) } else { Haptics.play(.tap) }
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
        // Several switches in one tick (e.g. after a hiccup): sound the latest.
        if let last = changes.last, let cue = plan.cue(enteringPhase: last) {
            TimerSound.shared.play(cue)
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
        NotificationScheduler.schedule(upcoming.compactMap { item in
            guard let cue = plan.cue(enteringPhase: item.phaseIndex) else { return nil }
            let round = item.phaseIndex < plan.phases.count ? plan.phases[item.phaseIndex].round : plan.phases.last?.round ?? 0
            let label: String
            switch cue {
            case .workStart: label = "Go: round \(round)"
            case .roundEndRest: label = "Round \(round) done. Rest."
            case .roundEndWork: label = "Round done. Round \(round): go!"
            case .finished: label = "Done! Nice work."
            }
            return (item.date, label, cue)
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

    static func schedule(_ items: [(Date, String, TimerCue)], title: String) {
        let center = UNUserNotificationCenter.current()
        cancelTimerAlerts()
        // iOS keeps at most 64 pending requests per app.
        for (i, item) in items.prefix(60).enumerated() {
            let interval = item.0.timeIntervalSinceNow
            guard interval > 0.5 else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = item.1
            // The matching bundled cue (bell / go / rest); silent when sounds are off.
            content.sound = TimerSound.enabled ? UNNotificationSound(named: UNNotificationSoundName(item.2.soundFile(pack: TimerSound.pack))) : nil
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

/// Plays the synthesized timer cues (see scripts/make-sounds.py) over music
/// and with the silent switch on, each paired with a haptic.
@MainActor
final class TimerSound {
    static let shared = TimerSound()
    nonisolated static let defaultsKey = "timerSounds"

    /// Settings toggle (on by default).
    nonisolated static var enabled: Bool { AppDefaults.store.object(forKey: defaultsKey) as? Bool ?? true }
    nonisolated static let packKey = "timerSoundPack"
    /// Chosen pack (Settings); boxing by default.
    nonisolated static var pack: SoundPack {
        AppDefaults.store.string(forKey: packKey).flatMap(SoundPack.init(rawValue:)) ?? .boxing
    }

    private var players: [String: AVAudioPlayer] = [:]
    private var release: Task<Void, Never>?

    func play(_ cue: TimerCue) {
        Haptics.play(Self.haptic(for: cue))
        guard Self.enabled else { return }
        play(cue, pack: Self.pack)
    }

    /// Plays a cue from a specific pack (Settings preview), even if muted.
    func play(_ cue: TimerCue, pack: SoundPack) {
        guard let player = player(for: cue, pack: pack) else { return }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback ignores the silent switch; mix + duck keeps music going, just quieter.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            Log.timer.error("audio session [\(Log.kind(error), privacy: .public)]")
        }
        #endif
        player.currentTime = 0
        player.play()
        // Release the session (un-duck music) once the cue has finished.
        release?.cancel()
        let wait = UInt64((player.duration + 0.3) * 1_000_000_000)
        release = Task {
            try? await Task.sleep(nanoseconds: wait)
            guard !Task.isCancelled else { return }
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    static func haptic(for cue: TimerCue) -> Haptics.Kind {
        switch cue {
        case .workStart: return .phaseChange
        case .roundEndRest: return .rest
        case .roundEndWork: return .warning
        case .finished: return .success
        }
    }

    private func player(for cue: TimerCue, pack: SoundPack) -> AVAudioPlayer? {
        let file = cue.soundFile(pack: pack)
        if let p = players[file] { return p }
        let name = (file as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let p = try? AVAudioPlayer(contentsOf: url) else {
            Log.timer.error("missing sound \(cue.rawValue, privacy: .public)")
            return nil
        }
        p.prepareToPlay()
        players[file] = p
        return p
    }
}
