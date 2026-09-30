import MyMoneyDomain
import SwiftUI

/// 帳戶選擇列(DESIGN.md「列與欄位」第 7 條，#78):選擇值只放帳戶名稱，選單項目的副標題是類型。
/// 餘額不放進選項，需要時由表單另起一列「可用餘額」。原本的「名稱(類型，餘額 $X)」在大字級會被從中間截斷。
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
    /// 「無特定帳戶」「請選擇扣款帳戶」這類不選帳戶的項目。
    var noneTitle: String?

    var body: some View {
        Picker(selection: $selection) {
            if let noneTitle {
                Text(noneTitle).tag(AccountID?.none)
            }
            ForEach(options) { option in
                VStack(alignment: .leading) {
                    Text(option.name)
                    if let subtitle = option.subtitle {
                        Text(subtitle)
                    }
                }
                .tag(AccountID?.some(option.id))
            }
        } label: {
            Text(title)
        } currentValueLabel: {
            Text(selectedName)
        }
    }

    private var selectedName: String {
        options.first { $0.id == selection }?.name ?? noneTitle ?? ""
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
