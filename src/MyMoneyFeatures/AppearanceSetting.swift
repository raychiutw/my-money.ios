import Foundation
import Observation

/// 外觀的三個選項(DESIGN.md「原則」)。
public enum Appearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: "跟隨系統"
        case .light: "淺色"
        case .dark: "深色"
        }
    }
}

/// 「我的」的「外觀」設定，由 composition root 建立，用 `Environment` 往下傳，並由 composition root 套到整個 app。
///
/// 只記在這台裝置(composition root 注入的 UserDefaults),不送後端;沒動過設定時是跟隨系統。
@MainActor
@Observable
public final class AppearanceSetting {
    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.key) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private static let key = "appearance"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Self.key).flatMap(Appearance.init(rawValue:)) ?? .system
    }
}
