import SwiftUI

/// 登入後的 tab 外殼(ADR-0003、DESIGN.md「導覽」)。iPad 用 sidebar,入口跟 iPhone 同一套。
struct MainTabView: View {
    let screens: MainScreens

    var body: some View {
        TabView {
            Tab("總覽", systemImage: "house") {
                OverviewScreen()
            }
            Tab("交易", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    ComingSoonView(title: "交易")
                }
            }
            Tab("帳戶", systemImage: "creditcard") {
                AccountsScreen(model: screens.accounts)
            }
            Tab("統計", systemImage: "chart.bar") {
                NavigationStack {
                    ComingSoonView(title: "統計")
                }
            }
            Tab("規劃", systemImage: "calendar") {
                PlanningScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// 總覽：toolbar 右上角的帳號按鈕打開帳號 sheet。
private struct OverviewScreen: View {
    @State private var isAccountSheetPresented = false

    var body: some View {
        NavigationStack {
            ComingSoonView(title: "總覽")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAccountSheetPresented = true
                        } label: {
                            Label("帳號", systemImage: "person.crop.circle")
                        }
                        .accessibilityIdentifier("overview.account")
                    }
                }
                .sheet(isPresented: $isAccountSheetPresented) {
                    AccountSheet()
                }
        }
    }
}

/// 規劃：固定收支、儲蓄目標、現金流預測的列表。
private struct PlanningScreen: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(["固定收支", "儲蓄目標", "現金流預測"], id: \.self) { title in
                    NavigationLink(title) {
                        ComingSoonView(title: title)
                    }
                }
            }
            .navigationTitle("規劃")
        }
    }
}
