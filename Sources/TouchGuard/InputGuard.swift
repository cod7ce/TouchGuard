import AppKit
import CoreGraphics
import QuartzCore

/// Where a pointer event most likely came from.
enum PointerSource {
    case trackpad
    case externalPointer
    case unknown
}

private func tapCallback(proxy: CGEventTapProxy,
                         type: CGEventType,
                         event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let guardObject = Unmanaged<InputGuard>.fromOpaque(refcon).takeUnretainedValue()
    return guardObject.handle(type: type, event: event)
}

/// Watches the keyboard and swallows trackpad events that arrive too soon after a keystroke.
final class InputGuard {
    static let shared = InputGuard()

    private let settings = Settings.shared
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private var lastKeyTime: CFTimeInterval = 0
    /// Buttons whose mouse-down we swallowed. Their drags and mouse-up must be
    /// swallowed too, otherwise apps are left holding a button that never went down.
    private var suppressedButtons = Set<Int64>()

    private(set) var blockedClicks = 0
    private(set) var blockedOther = 0

    /// Called on the main thread whenever something was actually suppressed.
    var onBlock: (() -> Void)?

    var isRunning: Bool { tap != nil }

    /// Seconds left in the current mute window, 0 when the trackpad is live.
    var remainingMute: CFTimeInterval {
        max(0, settings.delay - (CACurrentMediaTime() - lastKeyTime))
    }

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [
            .keyDown,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel,
        ]
        return types.reduce(into: CGEventMask(0)) { $0 |= (1 << $1.rawValue) }
    }()

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: Self.eventMask,
                                          callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        source = nil
        tap = nil
        suppressedButtons.removeAll()
    }

    // MARK: - Event handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disarms slow taps; just switch it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .keyDown:
            let flags = event.flags
            // Cmd/Ctrl chords are commands, not typing, so they must not mute the trackpad.
            if !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
                lastKeyTime = CACurrentMediaTime()
            }
            return pass

        default:
            break
        }

        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        switch type {
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if suppressedButtons.remove(button) != nil { return nil }
            return pass

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return suppressedButtons.contains(button) ? nil : pass

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard settings.blockClicks, shouldMute(type: type, event: event) else { return pass }
            suppressedButtons.insert(button)
            blockedClicks += 1
            onBlock?()
            return nil

        case .mouseMoved:
            guard settings.blockMovement, shouldMute(type: type, event: event) else { return pass }
            blockedOther += 1
            return nil

        case .scrollWheel:
            guard settings.blockScroll, shouldMute(type: type, event: event) else { return pass }
            blockedOther += 1
            onBlock?()
            return nil

        default:
            return pass
        }
    }

    private func shouldMute(type: CGEventType, event: CGEvent) -> Bool {
        guard settings.enabled else { return false }
        guard CACurrentMediaTime() - lastKeyTime < settings.delay else { return false }

        if settings.allowModifierChords {
            let flags = event.flags
            if flags.contains(.maskCommand) || flags.contains(.maskControl)
                || flags.contains(.maskAlternate) || flags.contains(.maskShift) {
                return false
            }
        }

        switch InputGuard.classify(type: type, event: event) {
        case .trackpad: return true
        case .externalPointer: return false
        case .unknown: return !settings.strictTrackpadOnly
        }
    }

    /// Best-effort device identification from the event itself.
    static func classify(type: CGEventType, event: CGEvent) -> PointerSource {
        if type == .scrollWheel {
            // Pixel-precise scrolling means a touch surface; a wheel sends line deltas.
            return event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
                ? .trackpad : .externalPointer
        }
        switch event.getIntegerValueField(.mouseEventSubtype) {
        case 3: return .trackpad          // NSEventSubtypeTouch
        case 1, 2: return .externalPointer // tablet point / proximity
        default: return .unknown
        }
    }
}
