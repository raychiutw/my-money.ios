import MyMoneyFeatures
import Observation
import SwiftUI
import UIKit

/// 鎖畫面與隱私遮罩放在**獨立的 UIWindow**(#298、#301,code review):蓋在根畫面的 SwiftUI overlay 蓋不到 sheet 與 alert,
/// 開著「我的」或編輯 sheet 時離開超過寬限時間再回來,帳務還看得到、點得到。獨立 window 的層級比 sheet 與 alert 都高。
@MainActor
final class AppLockWindowPresenter {
    private var window: UIWindow?
    private var appLock: AppLockModel?
    private var isSceneActive = true
    private var isStarted = false

    /// 開始追蹤鎖與場景狀態(可以重複呼叫)。
    func start(appLock: AppLockModel) {
        guard !isStarted else { return }
        isStarted = true
        self.appLock = appLock
        let center = NotificationCenter.default
        center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSceneActive = false
                self?.update()
            }
        }
        center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSceneActive = true
                self?.update()
            }
        }
        track()
    }

    /// 鎖的狀態一變就更新 window(Observation 只通知一次,所以每次重新追蹤)。
    private func track() {
        guard let appLock else { return }
        withObservationTracking {
            _ = appLock.isLocked
            _ = appLock.isEnabled
            _ = appLock.userID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.track()
            }
        }
        update()
    }

    private func update() {
        guard let appLock else { return }
        if appLock.isLocked {
            show(AnyView(AppLockView(model: appLock)))
        } else if appLock.coversContent(sceneIsActive: isSceneActive) {
            show(AnyView(AppLockCover()))
        } else {
            hide()
        }
    }

    private var shownKind: String?

    private func show(_ view: AnyView) {
        let kind = appLock?.isLocked == true ? "lock" : "cover"
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        if window == nil || window?.windowScene !== scene {
            let newWindow = UIWindow(windowScene: scene)
            newWindow.windowLevel = .alert + 1
            // 跟 app 目前的外觀(「我的」設定的淺色、深色或跟隨系統)一致。
            newWindow.overrideUserInterfaceStyle = scene.windows.first { $0 !== window }?.overrideUserInterfaceStyle ?? .unspecified
            window = newWindow
            shownKind = nil
        }
        if shownKind != kind {
            window?.rootViewController = UIHostingController(rootView: view)
            shownKind = kind
        }
        window?.isHidden = false
    }

    private func hide() {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        shownKind = nil
    }
}
