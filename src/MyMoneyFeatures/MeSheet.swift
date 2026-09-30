import MyMoneyDomain
import SwiftUI

/// 「我的」的兩個分頁。
private enum MePage: CaseIterable {
    case settings
    case planning

    var title: String {
        switch self {
        case .settings: "設定"
        case .planning: "規劃"
        }
    }
}

/// 「我的」sheet:姓名與 email，下面是分頁「設定｜規劃」(ADR-0004、CONTEXT.md)。
///
/// **每次打開都先顯示「設定」，不記憶上次的分頁**:`page` 是這個 sheet 自己的狀態，sheet 關掉就丟掉。
/// 設定有機器人記帳、外觀(三列打勾)、登出、版本;規劃有週期收支、儲蓄目標、現金流預測。
/// 「家庭」入口暫時留在設定裡，等家庭升為 tab(#85)再移除。
struct MeSheet: View {
    let screens: MainScreens
    @Environment(AppSession.self) private var session
    @Environment(AppearanceSetting.self) private var appearanceSetting
    @Environment(\.appVersion) private var appVersion
    @Environment(\.dismiss) private var dismiss
    @State private var page = MePage.settings

    var body: some View {
        @Bindable var appearance = appearanceSetting
        NavigationStack {
            List {
                if let user = session.current?.user {
                    header(of: user)
                }
                Section {
                    Picker("分頁", selection: $page) {
                        ForEach(MePage.allCases, id: \.self) { page in
                            Text(page.title).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("me.page")
                }
                .listRowBackground(Color.clear)

                switch page {
                case .settings:
                    settings(appearance: $appearance.appearance)
                case .planning:
                    planning
                }
            }
            .navigationTitle("我的")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                    .accessibilityIdentifier("me.close")
                }
            }
        }
    }

    /// 頭像、姓名(`headline`)、email(`subheadline`)。頭像上的字是裝飾，VoiceOver 只念姓名與 email。
    private func header(of user: User) -> some View {
        Section {
            VStack(spacing: 4) {
                AvatarView(initial: AvatarInitial.text(for: user.name), baseSize: 72, font: .title.weight(.semibold), relativeTo: .title)
                    .accessibilityHidden(true)
                VStack(spacing: 2) {
                    Text(user.name)
                        .font(.headline)
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func settings(appearance: Binding<Appearance>) -> some View {
        Section {
            // UI 測試用 identifier 找入口，不依賴文字。
            NavigationLink("家庭群組") {
                HouseholdScreen(model: screens.household)
            }
            .accessibilityIdentifier("me.household")
            NavigationLink("機器人記帳") {
                BotScreen(model: screens.bot)
            }
            .accessibilityIdentifier("me.bot")
        }

        // 三列打勾，點一下就生效;字級是 body,不縮小(ADR-0004)。
        Section("外觀") {
            Picker("外觀", selection: appearance) {
                ForEach(Appearance.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Section {
            // 登出不跳確認、不打 API(parity.md「全域」)。
            Button("登出", role: .destructive) {
                session.signOut()
            }
            .accessibilityIdentifier("me.signOut")
        } footer: {
            Text(appVersion.text)
                .frame(maxWidth: .infinity)
        }
    }

    private var planning: some View {
        Section {
            NavigationLink {
                RecurringScreen(model: screens.recurring)
            } label: {
                Label("週期收支", systemImage: "arrow.triangle.2.circlepath")
            }
            NavigationLink {
                SavingsGoalsScreen(model: screens.goals)
            } label: {
                Label("儲蓄目標", systemImage: "target")
            }
            NavigationLink {
                ForecastScreen(model: screens.forecast)
            } label: {
                Label("現金流預測", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
    }
}
