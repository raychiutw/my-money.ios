/// 讓 in-memory repository 在回應前停住，測試才能觀察「送出期間」的畫面狀態。
///
/// repository 呼叫 `pass()`;測試用 `waitUntilReached()` 等到請求送達，檢查完畫面再 `open()` 放行。
public actor Gate {
    private var reached = false
    private var isOpen = false
    /// 停住的等待者:每一個有自己的編號,取消只放行被取消的那一個(以前一律放行全部,切 tab 取消一個請求會讓別的畫面停住的請求也提早回來)。
    private var passWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var nextWaiterID = 0
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// repository 端：通知請求已送達，然後停在這裡直到測試放行。
    ///
    /// 也會回應取消:測試寫錯、永遠不放行時，`.timeLimit` 取消測試後這個等待者就放行，測試記下失敗後結束，
    /// 不會讓整個測試程序卡住;**只放行被取消的這一個**。
    public func pass() async {
        reached = true
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters.removeAll()
        guard !isOpen else { return }
        let id = nextWaiterID
        nextWaiterID += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    passWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.release(waiter: id) }
        }
    }

    private func release(waiter id: Int) {
        passWaiters.removeValue(forKey: id)?.resume()
    }

    /// 測試端：等到 repository 收到請求。
    ///
    /// 會回應取消：請求一直沒送到 repository 時，測試的 `.timeLimit` 才能讓它失敗，而不是整個測試卡住。
    public func waitUntilReached() async {
        guard !reached else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // 取消可能發生在登記之前(onCancel 先跑完),這時直接放行。
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    arrivalWaiters.append(continuation)
                }
            }
        } onCancel: {
            Task { await self.releaseArrivalWaiters() }
        }
    }

    private func releaseArrivalWaiters() {
        arrivalWaiters.forEach { $0.resume() }
        arrivalWaiters.removeAll()
    }

    /// 測試端：讓停住的請求繼續回應;之後的請求也不再停。
    public func open() {
        isOpen = true
        passWaiters.values.forEach { $0.resume() }
        passWaiters.removeAll()
    }

    /// 測試端：讓下一個請求重新停住。
    public func close() {
        isOpen = false
        reached = false
    }
}
