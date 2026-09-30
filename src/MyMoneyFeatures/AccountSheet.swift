import SwiftUI

/// 帳號 sheet:名稱與 email、家庭、機器人記帳、外觀、登出(ADR-0003)。
struct AccountSheet: View {
    let household: HouseholdModel
    let bot: BotModel
    @Environment(AppSession.self) private var session
    @Environment(AppearanceSetting.self) private var appearanceSetting
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var appearance = appearanceSetting
        NavigationStack {
            List {
                if let user = session.current?.user {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.name)
                                .font(.headline)
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section {
                    // UI 測試用 identifier 找入口，不依賴文字。
                    NavigationLink("家庭群組") {
                        HouseholdScreen(model: household)
                    }
                    .accessibilityIdentifier("account.household")
                    NavigationLink("機器人記帳") {
                        BotScreen(model: bot)
                    }
                }

                Section {
                    Picker("外觀", selection: $appearance.appearance) {
                        ForEach(Appearance.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .accessibilityIdentifier("account.appearance")
                }

                Section {
                    // 登出不跳確認、不打 API(parity.md「全域」)。
                    Button("登出", role: .destructive) {
                        session.signOut()
                    }
                    .accessibilityIdentifier("account.signOut")
                }
            }
            .navigationTitle("帳號")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
    }
}
