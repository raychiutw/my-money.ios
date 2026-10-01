import MyMoneyDomain

extension CreditCard {
    /// 精簡列的第 2 行，只放一項(#73):信用卡待繳總額是 0 時是「已全數結清」,有待繳時是繳款日;
    /// 有待繳但沒有設定繳款日時沒有第 2 行。
    public var summaryLine: String? {
        guard totalDue > .zero else { return "已全數結清" }
        return paymentDueDay.map { "每月 \($0) 日繳款" }
    }

    /// VoiceOver 念的整句，例如「iOS 測試信用卡，個人卡，信用卡待繳總額 15,500 元，每月 5 日繳款」。
    var spokenSummary: String {
        var parts = [name, ownershipTitle, "信用卡待繳總額 \(totalDue.spokenText)"]
        if let line = summaryLine { parts.append(line) }
        return parts.joined(separator: "，")
    }

    /// 有待繳款:卡片上的金額用警示色(#119)。
    public var isDue: Bool { totalDue > .zero }

    /// 帳戶頁卡片上金額下面的小字(#119):歸屬(個人卡或家庭信用卡)加繳款日，例如「個人卡・5 日繳」。
    public var cardCaption: String {
        [ownershipTitle, paymentDueDay.map { "\($0) 日繳" }].compactMap { $0 }.joined(separator: "・")
    }

    /// 歸屬：家庭信用卡或個人卡(web 的 `bd0507b` 起一律標示)。
    var ownershipTitle: String { isJointFund ? "家庭信用卡" : "個人卡" }
}
