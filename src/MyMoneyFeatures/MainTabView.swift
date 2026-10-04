import SwiftUI

/// 登入後的 tab,依序是總覽、交易、帳戶、家庭、統計。規劃已經收進「我的」,家庭升為 tab(ADR-0004)。
enum AppTab: Hashable {
    case overview
    case transactions
    case accounts
    case household
    case statistics
}

/// 登入後的 tab 外殼(ADR-0004、DESIGN.md「導覽」)。iPad 用 sidebar,入口跟 iPhone 同一套。
///
/// 每個 tab 主頁面 toolbar 最右邊的頭像按鈕都呼叫同一個動作，由這裡打開同一個「我的」sheet;
/// sheet 的 model 由這一層持有，各 tab 不必各自傳遞。
struct MainTabView: View {
    let screens: MainScreens
    @State private var selection = AppTab.overview
    @State private var isAccountPresented = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("總覽", systemImage: "house", value: .overview) {
                OverviewScreen(model: screens.overview, quickEntry: screens.quickEntry) { selection = $0 }
                    .tint(.primary)
            }
            Tab(Terms.ledger, systemImage: "list.bullet.rectangle", value: .transactions) {
                TransactionsScreen(model: screens.transactions, quickEntry: screens.quickEntry)
                    .tint(.primary)
            }
            Tab("帳戶", systemImage: "creditcard", value: .accounts) {
                AccountsScreen(model: screens.accounts) { selection = $0 }
                    .tint(.primary)
            }
            Tab("家庭", systemImage: "person.2", value: .household) {
                HouseholdScreen(model: screens.household)
                    .tint(.primary)
            }
            Tab("統計", systemImage: "chart.bar", value: .statistics) {
                StatisticsScreen(model: screens.statistics)
                    .tint(.primary)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        // tab bar 目前所在的 tab 用品牌粉紅(使用者要求，底色維持淺色白、深色黑);tint 會往下傳，
        // 每個 tab 的內容與 sheet 都改回單色(ADR-0007)，粉紅只留在 tab bar。
        .tint(.ciText)
        .environment(\.openAccount, OpenAccountAction { isAccountPresented = true })
        .sheet(isPresented: $isAccountPresented) {
            MeSheet(screens: screens)
                .tint(.primary)
        }
    }
}
