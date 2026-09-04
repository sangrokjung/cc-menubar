import Foundation

struct CodexModelRecommendation: Equatable {
    let task: String
    let model: String
    let effort: String
}

let codexModelRecommendations = [
    CodexModelRecommendation(task: "구현·설계", model: "gpt-5.6", effort: "medium · 복잡하면 high"),
    CodexModelRecommendation(task: "리뷰·보안", model: "gpt-5.6-sol", effort: "high / xhigh"),
    CodexModelRecommendation(task: "탐색·병렬", model: "gpt-5.6-terra", effort: "low / medium"),
    CodexModelRecommendation(task: "분류·반복", model: "gpt-5.6-luna", effort: "none / low"),
]

struct CodexProxyAccount: Equatable {
    let name: String
    let enabled: Bool
    let status: String
    /// 0–100. nil = 리셋 없어 측정 전. 프록시 unified* 는 0–1이라 로더에서 *100 한다.
    let sessionPercent: Double?
    let weeklyPercent: Double?
    let sessionResetAt: Date?
    let weeklyResetAt: Date?
}

struct CodexProfileHealth {
    let profile: String
    let todayCalls: Int
    let weekCalls: Int
    let totalCalls: Int
    let todayTokens: Int
    let weekTokens: Int
    let totalTokens: Int
    let quotaEvents: Int
    let errorEvents: Int
    let lastVerdict: String
    let lastAt: Date?
}

struct CodexCallStats {
    let todayCalls: Int
    let weekCalls: Int
    let totalCalls: Int
    let todayTokens: Int
    let weekTokens: Int
    let totalTokens: Int
    let quotaEvents: Int
    let errorEvents: Int
    let lastCallAt: Date?
    let latestModel: String?
    let planType: String?
    let contextWindow: Int?
    let primaryUsedPercent: Double?
    let secondaryUsedPercent: Double?
    let primaryResetAt: Date?
    let secondaryResetAt: Date?
    let scannedLogFiles: Int
    let scannedLogBytes: Int64
    let profiles: [CodexProfileHealth]
}

enum CodexProxyState: Equatable {
    case notConfigured   // server.json 없음 — 프록시 미사용 머신, 기존 동작 그대로
    case unreachable     // server.json 있는데 HTTP 응답 없음 = 프록시 다운
    case accountError    // 응답은 오는데 사용 가능한 계정 0
    case blocked         // 계정은 살아있는데 전부 한도 차단
    case ok
}

struct CodexHealth {
    let checkedAt: Date
    let overallStatus: String
    let configPresent: Bool
    let authPresent: Bool
    let authMode: String?
    let authLabel: String
    let hasApiKey: Bool
    let hasTokens: Bool
    let lastRefresh: Date?
    let model: String?
    let reasoningEffort: String?
    let serviceTier: String?
    let contextWindow: Int?
    let todayCalls: Int
    let weekCalls: Int
    let totalCalls: Int
    let todayTokens: Int
    let weekTokens: Int
    let totalTokens: Int
    let quotaEvents: Int
    let errorEvents: Int
    let lastCallAt: Date?
    let planType: String?
    let primaryUsedPercent: Double?
    let secondaryUsedPercent: Double?
    let primaryResetAt: Date?
    let secondaryResetAt: Date?
    let scannedLogFiles: Int
    let scannedLogBytes: Int64
    let profiles: [CodexProfileHealth]
    let proxyAccounts: [CodexProxyAccount]
    let hints: [String]
    var proxyState: CodexProxyState = .notConfigured

    var isWarning: Bool { overallStatus == "warning" || proxyState == .blocked }
    var isError: Bool {
        overallStatus == "error" || proxyState == .unreachable || proxyState == .accountError
    }

    var titleSlot: String {
        switch proxyState {
        case .unreachable: return "Codex 오프라인"
        case .accountError: return "Codex 재인증"
        case .blocked: return "Codex 한도대기"
        default: break
        }
        if isError { return "Codex 재인증" }
        if !authPresent || (!hasApiKey && !hasTokens) { return "Codex 로그인" }
        if quotaEvents > 0 { return "Codex 쿼터 \(quotaEvents)" }
        if errorEvents > 0 { return "Codex 주의 \(errorEvents)" }
        if let limits = formatCodexLimitPair(primaryUsedPercent, secondaryUsedPercent) {
            if max(primaryUsedPercent ?? 0, secondaryUsedPercent ?? 0) >= 90 {
                return "Codex 경고 \(limits)"
            }
            return "Codex \(limits)"
        }
        if todayTokens > 0 { return "Codex \(formatCodexTokens(todayTokens))/d" }
        if isWarning { return "Codex 주의" }
        return "Codex 정상 \(todayCalls)/d"
    }

    var statusLabel: String {
        if proxyState == .unreachable { return "오프라인" }
        if isError { return "재인증" }
        if isWarning { return "주의" }
        return "정상"
    }

    var accessibilitySummary: String {
        let modelText = model ?? "default"
        return "Codex \(statusLabel), auth \(authLabel), model \(modelText), today calls \(todayCalls), week calls \(weekCalls), today tokens \(todayTokens), week tokens \(weekTokens), quota events \(quotaEvents), error events \(errorEvents)"
    }
}

struct CodexConfigSummary {
    let present: Bool
    let model: String?
    let reasoningEffort: String?
    let serviceTier: String?
    let contextWindow: Int?
}

struct CodexMutableProfile {
    var todayCalls = 0
    var weekCalls = 0
    var totalCalls = 0
    var todayTokens = 0
    var weekTokens = 0
    var totalTokens = 0
    var quotaEvents = 0
    var errorEvents = 0
    var lastVerdict = "-"
    var lastAt: Date?
}
