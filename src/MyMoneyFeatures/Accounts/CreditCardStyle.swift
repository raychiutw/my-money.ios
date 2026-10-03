import MyMoneyDomain

extension CreditCard {
    /// 精簡列的第 2 行，只放一項(#73):信用卡待繳總額是 0 時是「已全數結清」,有待繳時是繳款日;
    /// 有待繳但沒有設定繳款日時沒有第 2 行。
    public var summaryLine: String? {
        guard totalDue > .zero else { return "已全數結清" }
        return paymentDueDay.map { "每月 \($0) 日繳款" }
    }

    /// VoiceOver 念的整句，例如「iOS 測試信用卡，私帳，信用卡待繳總額 15,500 元，每月 5 日繳款」。
    var spokenSummary: String {
        var parts = [name, ownershipTitle, "信用卡待繳總額 \(totalDue.spokenText)"]
        if let line = summaryLine { parts.append(line) }
        return parts.joined(separator: "，")
    }

    /// 公帳範圍裡的個人卡:卡片小字寫「私卡代墊」加繳款日(上游 ADR 0015)。
    func advanceCaption() -> String {
        ["私卡代墊", paymentDueDay.map { "\($0) 日繳" }].compactMap { $0 }.joined(separator: "・")
    }

    /// 公帳範圍裡的個人卡，VoiceOver 念「私卡代墊」代替歸屬;脫敏的卡再改念持卡人與家庭代墊待繳額，不念被遮蔽的欄位。
    func spokenAdvanceSummary(isMasked: Bool) -> String {
        var parts: [String?]
        if isMasked {
            parts = [name, "私卡代墊", ownerName.map { "持卡人 \($0)" }, "家庭代墊待繳額 \(sharedDebt.spokenText)", summaryLine]
        } else {
            parts = [name, "私卡代墊", "信用卡待繳總額 \(totalDue.spokenText)", summaryLine]
        }
        return parts.compactMap { $0 }.joined(separator: "，")
    }

    /// 有待繳款:卡片上的金額用警示色(#119)。
    public var isDue: Bool { totalDue > .zero }

    /// 帳戶頁卡片上金額下面的小字(#119、#138):歸屬(公帳或私帳)加繳款日，例如「私帳・5 日繳」。
    public var cardCaption: String {
        [ownershipTitle, paymentDueDay.map { "\($0) 日繳" }].compactMap { $0 }.joined(separator: "・")
    }

    /// 歸屬：公帳或私帳(web 的 `bd0507b` 起一律標示，上游 ADR 0014 起叫公帳、私帳)。
    var ownershipTitle: String { isJointFund ? "公帳" : "私帳" }
}
