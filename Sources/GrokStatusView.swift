import Cocoa

final class GrokStatusView: NSView {
    static let preferredHeight: CGFloat = 168

    var health: GrokHealth? {
        didSet {
            setAccessibilityLabel(health?.accessibilitySummary ?? "Grok 상태")
            setAccessibilityHelp("Grok 주간 풀 남은 쿼터")
            needsDisplay = true
        }
    }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Grok 상태")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bg = NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.10, alpha: 0.97)
        let panel = NSColor(calibratedRed: 0.095, green: 0.115, blue: 0.15, alpha: 1.0)
        let line = NSColor(calibratedRed: 0.23, green: 0.27, blue: 0.34, alpha: 1.0)
        let text = NSColor(calibratedRed: 0.92, green: 0.95, blue: 0.98, alpha: 1.0)
        let muted = NSColor(calibratedRed: 0.55, green: 0.61, blue: 0.70, alpha: 1.0)
        let dim = NSColor(calibratedRed: 0.40, green: 0.46, blue: 0.55, alpha: 1.0)
        let green = NSColor(calibratedRed: 0.18, green: 0.82, blue: 0.48, alpha: 1.0)
        let yellow = NSColor(calibratedRed: 0.93, green: 0.76, blue: 0.22, alpha: 1.0)
        let red = NSColor(calibratedRed: 0.96, green: 0.26, blue: 0.32, alpha: 1.0)
        // Grok 은 Codex(파랑)·Claude 와 구분되게 보라 계열.
        let accent = NSColor(calibratedRed: 0.60, green: 0.52, blue: 0.95, alpha: 1.0)

        let titleFont = NSFont.systemFont(ofSize: 18, weight: .bold)
        let subFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        let headFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let smallFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        func attrs(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color]
        }
        func drawText(_ value: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor) {
            value.draw(at: NSPoint(x: x, y: y), withAttributes: attrs(font, color))
        }
        func drawRight(_ value: String, _ x: CGFloat, _ y: CGFloat, _ font: NSFont, _ color: NSColor) {
            let a = attrs(font, color)
            let s = value.size(withAttributes: a)
            value.draw(at: NSPoint(x: x - s.width, y: y), withAttributes: a)
        }
        func fillRound(_ rect: NSRect, _ color: NSColor, _ radius: CGFloat) {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
        func strokeRound(_ rect: NSRect, _ color: NSColor, _ radius: CGFloat) {
            color.setStroke()
            let p = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            p.lineWidth = 1
            p.stroke()
        }
        func pill(_ value: String, x: CGFloat, y: CGFloat, color: NSColor) -> CGFloat {
            let size = value.size(withAttributes: attrs(subFont, color))
            let rect = NSRect(x: x, y: y, width: size.width + 16, height: 22)
            fillRound(rect, color.withAlphaComponent(0.14), 11)
            strokeRound(rect, color.withAlphaComponent(0.38), 11)
            drawText(value, x + 8, y + 3.5, subFont, color)
            return rect.width
        }
        func metric(_ title: String, _ value: String, _ detail: String, percent: Double? = nil, x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor) {
            let rect = NSRect(x: x, y: y, width: width, height: 54)
            fillRound(rect, panel, 9)
            strokeRound(rect, line.withAlphaComponent(0.8), 9)
            drawText(title.uppercased(), x + 10, y + 8, headFont, muted)
            let font = NSFont.monospacedSystemFont(ofSize: value.count > 12 ? 15 : 18, weight: .bold)
            drawText(value, x + 10, y + 25, font, color)
            drawRight(detail, x + width - 10, y + 31, smallFont, dim)
            if let percent = percent {
                let track = NSRect(x: x + 10, y: y + 45, width: width - 20, height: 4)
                fillRound(track, NSColor.white.withAlphaComponent(0.10), 2)
                let fillWidth = track.width * CGFloat(max(0, min(100, percent)) / 100)
                if fillWidth > 0 {
                    fillRound(NSRect(x: track.minX, y: track.minY, width: max(2, fillWidth), height: track.height), color, 2)
                }
            }
        }

        let card = bounds.insetBy(dx: 8, dy: 4)
        fillRound(card, bg, 14)
        strokeRound(card, line, 14)

        guard let health = health else {
            drawText("Grok", card.minX + 16, card.minY + 16, titleFont, text)
            drawText("상태 데이터를 기다리는 중입니다", card.minX + 16, card.minY + 56, subFont, muted)
            return
        }

        let tone = health.isError ? red : (health.isWarning ? yellow : green)
        let innerX = card.minX + 16
        let topY = card.minY + 14

        drawText("Grok 사용량", innerX, topY, titleFont, text)
        var pillX = innerX + 118
        pillX += pill(health.statusLabel, x: pillX, y: topY - 2, color: tone) + 6
        if let tier = health.subscriptionTier {
            _ = pill(tier, x: pillX, y: topY - 2, color: accent)
        }
        drawRight("최근 \(formatCodexAge(health.lastUsedAt))", card.maxX - 16, topY + 2, subFont, muted)

        let periodLabel = formatGrokPeriodLabel(health.periodType)
        let accountText = health.account ?? "-"
        drawText("계정 \(accountText)  ·  \(periodLabel) 창  ·  세션 \(health.sessions)개  ·  턴 \(health.week.turns)회",
                 innerX, topY + 29, subFont, muted)

        // ── 지표 4개 ─────────────────────────────────────────────────────────
        // 퍼센트 바가 붙는 건 '창 경과'뿐이다. 사용률이 아니라 시간 경과라는 걸
        // detail 문구로 명시한다 — xAI 는 한도를 안 주므로 사용률 바는 만들 수 없다.
        let statY = topY + 58
        let gap: CGFloat = 9
        let statW = (card.width - 32 - gap * 3) / 4

        func limitTone(_ value: Double?) -> NSColor {
            guard let value = value else { return muted }
            if value >= 90 { return red }
            if value >= 70 { return yellow }
            return green
        }
        let usedColor = limitTone(health.creditUsedPercent)
        if let remaining = health.creditRemainingPercent {
            metric("주간 남음", formatCodexPercent(remaining), "사용 \(formatCodexPercent(health.creditUsedPercent))",
                   percent: remaining, x: innerX, y: statY, width: statW, color: usedColor)
        } else {
            metric("주간 남음", "측정 전", "billing 미수신",
                   x: innerX, y: statY, width: statW, color: muted)
        }
        metric("오늘", formatGrokUsd(health.today.costUsd), "\(formatCodexTokens(health.today.totalTokens)) · \(health.today.turns)턴",
               x: innerX + (statW + gap), y: statY, width: statW, color: health.today.turns > 0 ? green : muted)
        metric("주간 사용", formatCodexPercent(health.creditUsedPercent), "\(formatCodexTokens(health.week.totalTokens))",
               percent: health.creditUsedPercent, x: innerX + (statW + gap) * 2, y: statY, width: statW, color: usedColor)

        var elapsedPercent: Double?
        if let start = health.periodStart, let end = health.periodEnd, end > start {
            let span = end.timeIntervalSince(start)
            elapsedPercent = max(0, min(100, Date().timeIntervalSince(start) / span * 100))
        }
        let elapsedDetail = elapsedPercent.map { "경과 \(Int($0))%" } ?? "-"
        metric("창 리셋", formatGrokRemaining(health.periodEnd), elapsedDetail,
               percent: elapsedPercent, x: innerX + (statW + gap) * 3, y: statY, width: statW, color: yellow)

        let footerY = card.maxY - 22
        if let hint = health.hint, health.isError {
            drawText(hint, innerX, footerY, smallFont, red)
        } else {
            drawText("주간 풀    일일 한도 없음    초록 <70% 사용", innerX, footerY, smallFont, muted)
        }
    }
}
