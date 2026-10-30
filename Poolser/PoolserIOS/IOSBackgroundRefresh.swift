import BackgroundTasks
import Foundation
import PoolserKit

enum IOSBackgroundRefresh {
    private static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "PoolserIOS") + ".refresh"
    }

    @MainActor
    static func register(service: UniswapService) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let work = Task { @MainActor in
                schedule()
                await service.refreshAndWait()
                task.setTaskCompleted(success: !Task.isCancelled && service.lastError == nil)
            }
            task.expirationHandler = {
                work.cancel()
                Task { @MainActor in service.cancelRefresh() }
            }
        }
    }

    @MainActor
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
