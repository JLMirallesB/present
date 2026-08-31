import AppKit

/// What a key press does while presenting.
enum PresentationCommand: Equatable {
    case next
    case previous
    case first
    case last
    case exit
    case zoomIn
    case zoomOut
    case zoomReset
    case toggleBlackout
}

/// Pulled out of the event monitor so the mapping can be tested without
/// synthesising NSEvents.
enum PresentationKeymap {

    // macOS virtual key codes.
    private enum Key {
        static let space: UInt16 = 49
        static let escape: UInt16 = 53
        static let b: UInt16 = 11
        static let equals: UInt16 = 24
        static let minus: UInt16 = 27
        static let zero: UInt16 = 29
        static let keypadPlus: UInt16 = 69
        static let keypadMinus: UInt16 = 78
        static let keypadZero: UInt16 = 82
        static let home: UInt16 = 115
        static let pageUp: UInt16 = 116
        static let end: UInt16 = 119
        static let pageDown: UInt16 = 121
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    static func command(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> PresentationCommand? {
        let command = modifiers.contains(.command)

        if command {
            switch keyCode {
            case Key.equals, Key.keypadPlus: return .zoomIn
            case Key.minus, Key.keypadMinus: return .zoomOut
            case Key.zero, Key.keypadZero: return .zoomReset
            // Documented alternative to the arrows, for pages that use them.
            case Key.up: return .previous
            case Key.down: return .next
            default: return nil
            }
        }

        switch keyCode {
        case Key.right, Key.pageDown: return .next
        case Key.left, Key.pageUp: return .previous
        case Key.home: return .first
        case Key.end: return .last
        case Key.escape: return .exit
        case Key.b: return .toggleBlackout
        default: return nil
        }

        // Deliberately not mapped:
        //
        //   Up / Down       scroll the page, which matters when a slide is a
        //                   long article rather than a single screen.
        //   Space           same reason. Presentation clickers send Page Up and
        //                   Page Down, which are handled above.
    }
}
