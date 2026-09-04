import Foundation

// Grok 사용량 모델.
//
// 5시간 창은 없다. 유료 플랜은 주간 풀 하나(creditUsagePercent, 0–100).
// 남은 % = 100 - used. 토큰 분모는 여전히 없다.

enum GrokServiceState: Equatable {
    case notInstalled   // 사이드카 미설치 — Grok 섹션 자체를 숨긴다
    case unreachable    // 설치돼 있는데 응답 없음 = 사이드카 다운
    case noData         // 응답은 오는데 집계된 턴이 0
    case ok
}

struct GrokUsageAgg: Equatable {
    var turns = 0
    var errorTurns = 0
    var modelCalls = 0
    var inputTokens = 0
    var outputTokens = 0
    var totalTokens = 0
    var cachedReadTokens = 0
    var reasoningTokens = 0
    var costUsd: Double = 0
    /// 서버가 비용을 각인하지 않은 턴 수. OAuth/세션 경로에서 생길 수 있고,
    /// 이 값이 0 보다 크면 costUsd 는 하한이지 정확한 값이 아니다.
    var costUnstampedTurns = 0
}

struct GrokModelUsage: Equatable {
    let model: String
    let agg: GrokUsageAgg
}

struct GrokHealth: Equatable {
    let checkedAt: Date
    let serviceState: GrokServiceState
    let port: Int?
    let account: String?
    let subscriptionTier: String?

    /// 청구 창. xAI 는 주간 창을 쓴다 (USAGE_PERIOD_TYPE_WEEKLY).
    let periodType: String?
    let periodStart: Date?
    let periodEnd: Date?

    let today: GrokUsageAgg
    let week: GrokUsageAgg
    let total: GrokUsageAgg
    let models: [GrokModelUsage]

    let sessions: Int
    let lastUsedAt: Date?
    let scanError: String?

    /// billing creditUsagePercent (0–100). nil = 아직 못 읽음.
    let creditUsedPercent: Double?
    let creditRemainingPercent: Double?
    let quotaAvailable: Bool

    var isError: Bool { serviceState == .unreachable || scanError != nil }
    var isWarning: Bool {
        serviceState == .noData || (creditUsedPercent ?? 0) >= 70
    }

    var statusLabel: String {
        switch serviceState {
        case .notInstalled: return "미설치"
        case .unreachable: return "오프라인"
        case .noData: return "기록 없음"
        case .ok: return scanError == nil ? "정상" : "주의"
        }
    }

    var hint: String? {
        switch serviceState {
        case .unreachable:
            return "teamgrok 사이드카(:\(port ?? 3458)) 응답 없음 — launchctl kickstart -k gui/$UID/com.westwave.teamgrok"
        case .noData:
            return "Grok 세션 사용 기록 없음 — grok 을 한 번 쓰면 집계된다"
        default:
            if let scanError = scanError { return "사이드카 스캔 오류: \(scanError)" }
            if !quotaAvailable { return "주간 풀 % 를 아직 못 읽음 — grok 을 한 번 더 열면 billing 이 갱신된다" }
            return nil
        }
    }

    var titleSlot: String {
        switch serviceState {
        case .notInstalled: return "Grok -"
        case .unreachable: return "Grok 오프라인"
        case .noData: return "Grok 0/d"
        case .ok: break
        }
        if let remaining = creditRemainingPercent { return "Grok 남음 \(Int(remaining.rounded()))%" }
        if today.costUsd > 0 { return "Grok \(formatGrokUsd(today.costUsd))/d" }
        if today.totalTokens > 0 { return "Grok \(formatCodexTokens(today.totalTokens))/d" }
        if week.costUsd > 0 { return "Grok \(formatGrokUsd(week.costUsd))/wk" }
        return "Grok 0/d"
    }

    var accessibilitySummary: String {
        "Grok \(statusLabel), tier \(subscriptionTier ?? "unknown"), today cost \(formatGrokUsd(today.costUsd)), week cost \(formatGrokUsd(week.costUsd)), week tokens \(week.totalTokens), turns \(week.turns)"
    }
}

// MARK: - 포맷터

/// 비용은 센트 미만이 흔해서(한 턴이 $0.0076) 소수 둘째 자리로 자르면 전부 0.00 이 된다.
func formatGrokUsd(_ usd: Double) -> String {
    if usd <= 0 { return "$0" }
    if usd < 0.01 { return String(format: "$%.4f", usd) }
    if usd < 1 { return String(format: "$%.3f", usd) }
    if usd < 100 { return String(format: "$%.2f", usd) }
    return String(format: "$%.0f", usd)
}

/// 남은 시간. 이미 지났으면 "지남" — 사이드카가 오래된 billing 줄만 본 경우다.
func formatGrokRemaining(_ date: Date?) -> String {
    guard let date = date else { return "-" }
    let seconds = date.timeIntervalSinceNow
    if seconds <= 0 { return "지남" }
    let days = Int(seconds) / 86400
    let hours = (Int(seconds) % 86400) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    if days > 0 { return "\(days)일 \(hours)시간" }
    if hours > 0 { return "\(hours)시간 \(minutes)분" }
    return "\(minutes)분"
}

func formatGrokPeriodLabel(_ type: String?) -> String {
    switch type {
    case "USAGE_PERIOD_TYPE_WEEKLY": return "주간"
    case "USAGE_PERIOD_TYPE_MONTHLY": return "월간"
    case .some(let raw) where !raw.isEmpty: return raw
    default: return "청구"
    }
}

/// grok-4.6-build 처럼 접미사가 붙은 실제 사용 모델 id 를 짧게.
func grokShortenModelName(_ model: String) -> String {
    model.hasPrefix("grok-") ? String(model.dropFirst("grok-".count)) : model
}
