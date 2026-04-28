import CodexBarCore
import Foundation

enum MenuBarDisplayText {
    static func percentText(window: RateWindow?, showUsed: Bool) -> String? {
        guard let window else { return nil }
        let percent = showUsed ? window.usedPercent : window.remainingPercent
        let clamped = min(100, max(0, percent))
        return String(format: "%.0f%%", clamped)
    }

    static func cursorRequestText(cursorRequests: CursorRequestUsage?, showUsed _: Bool) -> String? {
        guard let requests = cursorRequests else { return nil }
        return "\(requests.used)/\(requests.limit)"
    }

    static func paceText(pace: UsagePace?) -> String? {
        guard let pace else { return nil }
        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        let sign = pace.deltaPercent >= 0 ? "+" : "-"
        return "\(sign)\(deltaValue)%"
    }

    static func displayText(
        mode: MenuBarDisplayMode,
        provider: UsageProvider? = nil,
        percentWindow: RateWindow?,
        pace: UsagePace? = nil,
        showUsed: Bool,
        cursorRequests: CursorRequestUsage? = nil) -> String?
    {
        switch mode {
        case .percent:
            if provider == .cursor,
               let requestText = self.cursorRequestText(cursorRequests: cursorRequests, showUsed: showUsed)
            {
                return requestText
            }
            return self.percentText(window: percentWindow, showUsed: showUsed)
        case .pace:
            return self.paceText(pace: pace)
        case .both:
            let percentPart: String? = {
                if provider == .cursor,
                   let requestText = self.cursorRequestText(cursorRequests: cursorRequests, showUsed: showUsed)
                {
                    return requestText
                }
                return self.percentText(window: percentWindow, showUsed: showUsed)
            }()
            guard let percent = percentPart else { return nil }
            // Fall back to percent-only when pace is unavailable (e.g. Copilot, legacy Cursor plans).
            guard let paceText = Self.paceText(pace: pace) else { return percent }
            return "\(percent) · \(paceText)"
        }
    }
}
