import Foundation
import XCNetwork

public actor IpInfoRequestWork: @preconcurrency XCWork {
    
    public let key: String = "ip_config_info"
    internal var task: Task<IPConfig, Never>?
    private var retryCount = 0
    
    public func run() async throws -> [Sendable & Codable] {
        if self.retryCount == 0 {
            if let oldTask = await XCBusiness.share.rmWork(self.key) {
                await oldTask.shotdown()
            }
        }
        let task = Task.detached {
            await IPInfoRequest.fire()
        }
        self.task = task
        let result = await task.value
        await self.shotdown()
        return [result as Sendable & Codable]
    }
    
    public func shotdown() async {
        self.task?.cancel()
        self.task = nil
        await XCBusiness.share.rmWork(self.key)
    }
}
