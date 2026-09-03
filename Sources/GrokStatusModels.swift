import Foundation

// Grok 사용량 모델.
//
// Codex 와 결정적으로 다른 점: xAI 는 한도(분모)를 어디에도 노출하지 않는다.
// 응답 헤더에 x-ratelimit-* 이 없고(바이너리 strings -a 에 0건), 사용량 조회 API 도 없다.
// 그래서 "5시간 87%" 같은 표시는 Grok 에 대해 정직하게 만들 수 없다 — 쓴 양(토큰·비용)과
// 청구 창 리셋 시각만 실측 가능하다. 퍼센트 자리는 비워 두고 그 사실을 화면에 적는다.
//
// 데이터는 teamgrok-usage 사이드카(:3458)가 ~/.grok 의 세션 로그를 훑어 만든 것을
// /teamclaude/status 로 받아온다. 메뉴바는 HTTP GET 한 번만 하므로 10초 statusTimer 에
// 올려도 안전하다 (JSONL 파싱은 사이드카가 자기 주기로 한다).

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

    /// 사이드카가 "한도를 알 수 없다"고 명시했는지. 나중에 xAI 가 한도를 열어주면
    /// 사이드카만 고치면 되고 여기는 그대로 둔다.
    let quotaAvailable: Bool

    var isError: Bool { serviceState == .unreachable || scanError != nil }
    var isWarning: Bool { serviceState == .noData }

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
            if !quotaAvailable { return "xAI 는 한도를 공개하지 않는다 — 잔여량이 아니라 사용량만 표시" }
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
