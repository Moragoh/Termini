//
//  WidgetReloadManager.swift
//  Termini
//
//  Purpose: Manages WidgetCenter reload calls based on app visibility state.
//           Implements debouncing and adaptive refresh rates to conserve
//           the system's daily widget reload budget.
//
//  How Widget Budgets Work:
//  - iOS/macOS gives each app a limited number of widget reloads per day
//  - Calling reloadAllTimelines() too often causes the system to throttle
//  - When the app is visible, the system is more lenient with reloads
//  - This manager enforces our own limits ON TOP OF system limits
//

import Foundation
import AppKit
import WidgetKit
import Combine

/// Manages widget reloads with visibility-aware throttling and debouncing.
///
/// Why a dedicated manager?
/// 1. Centralizes all widget reload logic in one place
/// 2. Prevents accidental excessive reloads from multiple sources
/// 3. Adapts to app state (foreground gets more frequent updates)
/// 4. Implements debouncing for rapid terminal output
///
/// Usage:
/// ```swift
/// // In TerminalViewModel or wherever output changes:
/// WidgetReloadManager.shared.requestReload()
/// ```
final class WidgetReloadManager {

    // MARK: - Singleton

    /// Shared instance - use this to request widget reloads.
    static let shared = WidgetReloadManager()

    // MARK: - Configuration

    /// Minimum interval between reloads when app is in foreground.
    /// 30 seconds allows responsive updates while conserving budget.
    private let foregroundInterval: TimeInterval = 30.0

    /// Minimum interval between reloads when app is in background.
    /// 20 minutes (1200 seconds) preserves budget when user isn't looking.
    private let backgroundInterval: TimeInterval = 20.0 * 60.0

    /// Debounce delay for coalescing rapid updates.
    /// If multiple requests come within this window, only one reload fires.
    private let debounceDelay: TimeInterval = 2.0

    /// The widget kind identifier (must match WidgetConfiguration).
    private let widgetKind = "TerminiWidget"

    // MARK: - State

    /// Whether the app is currently in the foreground.
    /// Updated by NSApplication notifications.
    private(set) var isAppActive: Bool = true

    /// Timestamp of the last successful widget reload.
    private var lastReloadTime: Date = .distantPast

    /// Pending debounced work item.
    /// Cancelled if a new request comes in before it fires.
    private var debounceWorkItem: DispatchWorkItem?

    /// Queue for thread-safe state access.
    private let queue = DispatchQueue(label: "com.termini.widgetReloadManager")

    /// Cancellables for Combine subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Debug / Monitoring

    /// Total reload requests received (for debugging).
    private(set) var totalRequestsReceived: Int = 0

    /// Total reloads actually performed (for debugging).
    private(set) var totalReloadsPerformed: Int = 0

    // MARK: - Initialization

    private init() {
        setupNotifications()
    }

    deinit {
        debounceWorkItem?.cancel()
    }

    // MARK: - Public API

    /// Request a widget reload.
    ///
    /// This method implements debouncing and throttling:
    /// 1. Rapid calls within `debounceDelay` are coalesced into one
    /// 2. Even after debouncing, reloads respect the visibility-based interval
    ///
    /// Safe to call frequently - the manager handles rate limiting.
    ///
    /// - Parameter force: If true, bypasses debouncing (but not throttling).
    ///                    Use sparingly, e.g., when the user explicitly clears terminal.
    func requestReload(force: Bool = false) {
        queue.async { [weak self] in
            self?.handleReloadRequest(force: force)
        }
    }

    /// Returns the current effective reload interval based on app state.
    var currentInterval: TimeInterval {
        isAppActive ? foregroundInterval : backgroundInterval
    }

    /// Returns time until next reload is allowed.
    var timeUntilNextReloadAllowed: TimeInterval {
        let elapsed = Date().timeIntervalSince(lastReloadTime)
        let remaining = currentInterval - elapsed
        return max(0, remaining)
    }

    /// Returns debug info about the manager's current state.
    var debugInfo: String {
        """
        WidgetReloadManager State:
        - App Active: \(isAppActive)
        - Current Interval: \(currentInterval)s
        - Last Reload: \(lastReloadTime)
        - Time Until Next Allowed: \(String(format: "%.1f", timeUntilNextReloadAllowed))s
        - Requests Received: \(totalRequestsReceived)
        - Reloads Performed: \(totalReloadsPerformed)
        """
    }

    // MARK: - Private Implementation

    /// Sets up NSApplication notifications for visibility tracking.
    private func setupNotifications() {
        let center = NotificationCenter.default

        // App became active (user switched to it or unminimized)
        center.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppBecameActive()
            }
            .store(in: &cancellables)

        // App resigned active (user switched away)
        center.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppResignedActive()
            }
            .store(in: &cancellables)

        // App was hidden (Cmd+H or Hide menu)
        center.publisher(for: NSApplication.didHideNotification)
            .sink { [weak self] _ in
                self?.handleAppResignedActive()
            }
            .store(in: &cancellables)

        // App was unhidden
        center.publisher(for: NSApplication.didUnhideNotification)
            .sink { [weak self] _ in
                self?.handleAppBecameActive()
            }
            .store(in: &cancellables)
    }

    /// Handles the app becoming active/visible.
    private func handleAppBecameActive() {
        queue.async { [weak self] in
            guard let self = self else { return }

            let wasInactive = !self.isAppActive
            self.isAppActive = true

            if wasInactive {
                print("[WidgetReloadManager] App became active - switching to foreground interval (\(self.foregroundInterval)s)")
                // Trigger an immediate reload when coming to foreground
                // so the widget shows current state
                self.performReloadIfAllowed()
            }
        }
    }

    /// Handles the app becoming inactive/hidden.
    private func handleAppResignedActive() {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.isAppActive = false
            print("[WidgetReloadManager] App resigned active - switching to background interval (\(self.backgroundInterval)s)")

            // Cancel any pending debounced work
            self.debounceWorkItem?.cancel()
            self.debounceWorkItem = nil
        }
    }

    /// Processes a reload request with debouncing.
    /// Must be called on `queue`.
    private func handleReloadRequest(force: Bool) {
        totalRequestsReceived += 1

        if force {
            // Force request - skip debouncing but still respect throttle
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            performReloadIfAllowed()
            return
        }

        // Cancel any existing debounce
        debounceWorkItem?.cancel()

        // Schedule new debounced reload
        let workItem = DispatchWorkItem { [weak self] in
            self?.queue.async {
                self?.debounceWorkItem = nil
                self?.performReloadIfAllowed()
            }
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: workItem)
    }

    /// Performs a widget reload if the throttle interval has passed.
    /// Must be called on `queue`.
    private func performReloadIfAllowed() {
        let now = Date()
        let timeSinceLastReload = now.timeIntervalSince(lastReloadTime)
        let requiredInterval = currentInterval

        guard timeSinceLastReload >= requiredInterval else {
            let remaining = requiredInterval - timeSinceLastReload
            print("[WidgetReloadManager] Throttled - next reload allowed in \(String(format: "%.1f", remaining))s")

            // Schedule a reload for when the interval passes
            scheduleDelayedReload(delay: remaining)
            return
        }

        // Perform the reload
        lastReloadTime = now
        totalReloadsPerformed += 1

        DispatchQueue.main.async {
            // Note: WidgetCenter calls should be on main thread
            WidgetCenter.shared.reloadTimelines(ofKind: self.widgetKind)
            print("[WidgetReloadManager] Reloaded widget (total: \(self.totalReloadsPerformed))")
        }
    }

    /// Schedules a reload after a delay (for when throttled).
    /// Only schedules if no debounce work is pending.
    private func scheduleDelayedReload(delay: TimeInterval) {
        // Don't schedule if something is already pending
        guard debounceWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.queue.async {
                self?.debounceWorkItem = nil
                self?.performReloadIfAllowed()
            }
        }

        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

// MARK: - Notes on Widget Budget "Bypass"

/*
 IMPORTANT: You cannot truly bypass the system's widget reload budget.

 Apple's WidgetKit applies its own throttling on top of any reloads you request:
 - The system may ignore reloadTimelines() calls if you've exceeded your budget
 - Budget is more generous when the app is in the foreground
 - Background apps get significantly fewer allowed reloads

 What this manager does:
 1. Applies our OWN throttling to avoid hitting system limits
 2. Uses more aggressive throttling in background to preserve budget
 3. Takes advantage of foreground leniency when the app is visible

 Best practices for responsive widgets:
 - Use TimelineProvider with appropriate refresh dates
 - Combine reload requests with data changes (save to App Group THEN reload)
 - Consider using push notifications for critical updates (requires server)
 - For foreground apps, the system is fairly responsive to reloads

 The 30-second foreground interval was chosen because:
 - Terminal output changes frequently, but sub-second updates aren't needed in widget
 - Gives ~120 reloads per hour if continuously in foreground (well within typical budgets)
 - Balances responsiveness with battery/system resource conservation
 */
