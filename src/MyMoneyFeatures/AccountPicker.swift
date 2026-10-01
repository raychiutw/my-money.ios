import MyMoneyDomain
import SwiftUI

/// 帳戶選擇列(DESIGN.md「列與欄位」第 7 條，#78):列上的值只放帳戶名稱，點了推入清單頁(ADR-0004、#88),
/// 清單頁每一列是名稱加類型副標題，目前的選擇打勾，選了自動返回。帳戶的數量不固定，所以不用下拉選單。
/// 餘額不放進選項，需要時由表單另起一列「可用餘額」。原本的「名稱(類型，餘額 $X)」在大字級會被從中間截斷。
///
/// **自己控制推入與返回**(不用系統 Picker 的 navigation link 樣式):還沒選時列上顯示佔位文字(上游 ADR 0011，#109),
/// 而系統 Picker 在選擇是空值、又有一列停用的佔位項目時，選了帳戶會把整個 sheet 關掉。
struct AccountPicker: View {
    struct Option: Identifiable {
        let id: AccountID
        let name: String
        /// 選單項目的副標題(類型);選項都是同一種帳戶時不放。
        let subtitle: String?
    }

    let title: String
    @Binding var selection: AccountID?
    let options: [Option]
    /// 「無特定帳戶」這類**可以不選**的項目(選填的欄位，例如週期收支的關聯帳戶);選了之後可以再改回來。
    var noneTitle: String?
    /// 「請選擇扣款／存入帳戶」這類**必填**欄位的佔位文字(上游 ADR 0011，#109):還沒選時顯示在列上(次要文字色);
    /// 清單頁裡沒有「無」這個選項，所以選了帳戶之後不能再選回空值。
    var placeholder: String?

    var body: some View {
        NavigationLink {
            AccountChoiceList(title: title, selection: $selection, options: options, noneTitle: noneTitle)
        } label: {
            LabeledContent(title) {
                if let valueText {
                    Text(valueText)
                } else if let placeholder, selection == nil {
                    Text(placeholder)
                }
            }
        }
    }

    /// 已選的帳戶還不在選項裡(例如帳戶還沒載入完)時留白，不能顯示成「無特定帳戶」。
    private var valueText: String? {
        if let name = options.first(where: { $0.id == selection })?.name { return name }
        if selection == nil, let noneTitle { return noneTitle }
        return nil
    }
}

/// 帳戶選擇的清單頁:每列名稱加類型副標題，目前的選擇打勾，點了設值並返回。
private struct AccountChoiceList: View {
    let title: String
    @Binding var selection: AccountID?
    let options: [AccountPicker.Option]
    let noneTitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let noneTitle {
                row(noneTitle, subtitle: nil, isSelected: selection == nil) { selection = nil }
            }
            ForEach(options) { option in
                row(option.name, subtitle: option.subtitle, isSelected: selection == option.id) { selection = option.id }
            }
        }
        .navigationTitle(title)
        .inlineNavigationTitle()
    }

    private func row(_ name: String, subtitle: String?, isSelected: Bool, choose: @escaping () -> Void) -> some View {
        Button {
            choose()
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(name)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension AccountPicker.Option {
    init(_ account: Account) {
        self.init(id: account.id, name: account.name, subtitle: account.menuSubtitle)
    }

    init(_ account: ReceivingAccount) {
        self.init(id: account.id, name: account.name, subtitle: account.menuSubtitle)
    }

    /// 信用卡扣款還款的扣款帳戶都是銀行存款帳戶，不放副標題。
    init(_ bank: BankAccount) {
        self.init(id: bank.id, name: bank.name, subtitle: nil)
    }
}
