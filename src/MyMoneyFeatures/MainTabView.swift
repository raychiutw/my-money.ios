import SwiftUI

/// 登入後的 5 個 tab。
enum AppTab: Hashable {
    case overview
    case transactions
    case accounts
    case statistics
    case planning
}

/// 登入後的 tab 外殼(ADR-0003、DESIGN.md「導覽」)。iPad 用 sidebar,入口跟 iPhone 同一套。
struct MainTabView: View {
    let screens: MainScreens
    @State private var selection = AppTab.overview

    var body: some View {
        TabView(selection: $selection) {
            Tab("總覽", systemImage: "house", value: .overview) {
                OverviewScreen(model: screens.overview, quickEntry: screens.quickEntry, household: screens.household) { selection = $0 }
            }
            Tab("交易", systemImage: "list.bullet.rectangle", value: .transactions) {
                TransactionsScreen(model: screens.transactions, quickEntry: screens.quickEntry)
            }
            Tab("帳戶", systemImage: "creditcard", value: .accounts) {
                AccountsScreen(model: screens.accounts)
            }
            Tab("統計", systemImage: "chart.bar", value: .statistics) {
                StatisticsScreen(model: screens.statistics)
            }
            Tab("規劃", systemImage: "calendar", value: .planning) {
                PlanningScreen(screens: screens)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// 規劃：固定收支、儲蓄目標、現金流預測的列表。
private struct PlanningScreen: View {
    let screens: MainScreens

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("固定收支") {
                    RecurringScreen(model: screens.recurring)
                }
                NavigationLink("儲蓄目標") {
                    SavingsGoalsScreen(model: screens.goals)
                }
                NavigationLink("現金流預測") {
                    ForecastScreen(model: screens.forecast)
                }
            }
            .navigationTitle("規劃")
        }
    }
}
