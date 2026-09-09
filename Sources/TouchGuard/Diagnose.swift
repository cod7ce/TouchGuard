import AppKit
import CoreGraphics

/// `TouchGuard --diagnose` prints how each pointer event is classified, so you can
/// check whether trackpad detection actually works on this hardware before turning
/// on "only block the trackpad".
private func eventLabel(_ type: CGEventType) -> String {
    switch type {
    case .leftMouseDown: return "leftMouseDown"
    case .leftMouseUp: return "leftMouseUp"
    case .rightMouseDown: return "rightMouseDown"
    case .rightMouseUp: return "rightMouseUp"
    case .otherMouseDown: return "otherMouseDown"
    case .otherMouseUp: return "otherMouseUp"
    case .mouseMoved: return "mouseMoved"
    case .scrollWheel: return "scrollWheel"
    default: return "type(\(type.rawValue))"
    }
}

enum Diagnose {
    static func run() -> Never {
        let mask: CGEventMask = [
            CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel,
        ].reduce(into: CGEventMask(0)) { $0 |= (1 << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, _ -> Unmanaged<CGEvent>? in
            let source = InputGuard.classify(type: type, event: event)
            let subtype = event.getIntegerValueField(.mouseEventSubtype)
            let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            print(String(format: "%-16@ source=%-16@ subtype=%d continuous=%d",
                         eventLabel(type) as NSString,
                         String(describing: source) as NSString,
                         subtype, continuous))
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: nil) else {
            FileHandle.standardError.write(Data("Could not create the event tap. Grant Accessibility permission to this binary (or the terminal running it) and try again.\n".utf8))
            exit(1)
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("Click and scroll with the built-in trackpad, then with an external mouse. Ctrl-C to stop.")
        CFRunLoopRun()
        exit(0)
    }
}
