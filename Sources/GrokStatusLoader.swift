import Foundation

// teamgrok-usage 사이드카(:3458)에서 Grok 사용량을 읽어온다.
//
// 왜 사이드카를 거치나: ~/.grok/sessions 의 updates.jsonl 은 세션 하나가 1MB 를 넘고
// 세션 수는 계속 는다. 이 파싱을 메뉴바의 10초 statusTimer 에 올리면 ccusage 폴링
// 버스트(commit e8b2e73)와 똑같은 CPU 사고가 난다. 사이드카가 자기 주기(20초)로
// 증분 스캔해 두고, 메뉴바는 HTTP GET 한 번만 한다.
//
// 응답은 teamclaude 의 /teamclaude/status 와 같은 모양이라 tc* 헬퍼를 그대로 쓴다.

func teamGrokServerPort() -> Int? {
    // ~/.config/teamgrok.server.json = {"pid":N,"port":3458,...} — 비밀 없음.
    // 이 파일은 사이드카가 graceful 종료될 때 남아 있을 수 있으므로, 부재를
    // "미설치"로 읽되 스크립트가 있으면 기본 포트로 계속 찔러본다
    // (teamcodex 쪽에서 배운 것: 부재를 미설치로 단정하면 내려간 서비스가 정상으로 보인다).
    if let port = tcInt(readCodexJSON("\(NSHomeDirectory())/.config/teamgrok.server.json")?["port"]) {
        return port
    }
    let script = "\(NSHomeDirectory())/.claude/bin/teamgrok-usage"
    return FileManager.default.fileExists(atPath: script) ? 3458 : nil
}

private func grokAgg(_ raw: [String: Any]?) -> GrokUsageAgg {
    var agg = GrokUsageAgg()
    guard let raw = raw else { return agg }
    agg.turns = tcInt(raw["turns"]) ?? 0
    agg.errorTurns = tcInt(raw["errorTurns"]) ?? 0
    agg.modelCalls = tcInt(raw["modelCalls"]) ?? 0
    agg.inputTokens = tcInt(raw["inputTokens"]) ?? 0
    agg.outputTokens = tcInt(raw["outputTokens"]) ?? 0
    agg.totalTokens = tcInt(raw["totalTokens"]) ?? 0
    agg.cachedReadTokens = tcInt(raw["cachedReadTokens"]) ?? 0
    agg.reasoningTokens = tcInt(raw["reasoningTokens"]) ?? 0
    agg.costUsd = tcDouble(raw["costUsd"]) ?? 0
    agg.costUnstampedTurns = tcInt(raw["costUnstampedTurns"]) ?? 0
    return agg
}

private func grokDate(_ value: Any?) -> Date? {
    guard let ms = parseTeamClaudeTimeMs(value) else { return nil }
    return Date(timeIntervalSince1970: Double(ms) / 1000)
}

func loadGrokHealth() -> GrokHealth? {
    let now = Date()

    guard let port = teamGrokServerPort() else {
        // 사이드카가 이 머신에 없다 — 섹션 자체를 만들지 않는다.
        return nil
    }

    guard let status = fetchTeamClaudeStatus(port: port) else {
        return GrokHealth(
            checkedAt: now, serviceState: .unreachable, port: port,
            account: nil, subscriptionTier: nil,
            periodType: nil, periodStart: nil, periodEnd: nil,
            today: GrokUsageAgg(), week: GrokUsageAgg(), total: GrokUsageAgg(), models: [],
            sessions: 0, lastUsedAt: nil, scanError: nil, quotaAvailable: false
        )
    }

    let grok = tcDict(status["grok"])
    let period = tcDict(grok?["period"])
    let account = tcString(status["currentAccount"])

    let today = grokAgg(tcDict(grok?["today"]))
    let week = grokAgg(tcDict(grok?["week"]))
    let total = grokAgg(tcDict(grok?["total"]))

    var models: [GrokModelUsage] = []
    if let byModel = tcDict(grok?["byModel"]) {
        for (model, raw) in byModel {
            models.append(GrokModelUsage(model: model, agg: grokAgg(tcDict(raw))))
        }
        // 이번 주 토큰이 많은 순. 같으면 이름순이라 매 렌더 순서가 흔들리지 않는다.
        models.sort { ($0.agg.totalTokens, $1.model) > ($1.agg.totalTokens, $0.model) }
    }

    // lastUsed 는 teamclaude 계약 쪽(accounts[0].usage.lastUsed)에 있다.
    let lastUsed = grokDate(tcArray(status["accounts"])?.first.flatMap { tcDict($0["usage"])?["lastUsed"] })

    let scanError = tcString(grok?["lastScanError"])
    let state: GrokServiceState = total.turns == 0 ? .noData : .ok

    return GrokHealth(
        checkedAt: now,
        serviceState: state,
        port: port,
        account: account,
        subscriptionTier: tcString(grok?["subscriptionTier"]),
        periodType: tcString(period?["type"]),
        periodStart: grokDate(period?["startMs"]),
        periodEnd: grokDate(period?["endMs"]),
        today: today,
        week: week,
        total: total,
        models: models,
        sessions: tcInt(grok?["sessions"]) ?? 0,
        lastUsedAt: lastUsed,
        scanError: scanError,
        quotaAvailable: tcBool(grok?["quotaAvailable"]) ?? false
    )
}
