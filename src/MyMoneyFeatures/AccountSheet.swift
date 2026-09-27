import SwiftUI

/// 帳號 sheet:名稱與 email、家庭、機器人記帳、登出(ADR-0003)。
struct AccountSheet: View {
    let household: HouseholdModel
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                    // 總覽的視角切換也有「家庭」,UI 測試用 identifier 分辨。
                    NavigationLink("家庭") {
                        HouseholdScreen(model: household)
                    }
                    .accessibilityIdentifier("account.household")
                    NavigationLink("機器人記帳") {
                        ComingSoonView(title: "機器人記帳")
                    }
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
