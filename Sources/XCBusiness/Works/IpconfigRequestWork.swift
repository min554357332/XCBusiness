import Foundation
import XCNetwork

public actor IpconfigRequestWork: @preconcurrency XCWork {
    
    public let key = "ip_config"
    internal var task: Task<IPConfig, Error>?
    private var retryCount = 0
    
    public init() {}
    
    public func run() async throws -> [Sendable & Codable] {
        if self.retryCount == 0 {
            if let oldTask = await XCBusiness.share.rmWork(self.key) {
                await oldTask.shotdown()
            }
        }
        let task = Task.detached {
            try await IPConfiguration.fire()
        }
        self.task = task
        if self.retryCount == 0 {
            await XCBusiness.share.addWork(self)
        }
        do {
            let result = try await task.value
            await self.shotdown()
            return [result as Sendable & Codable]
        } catch {
            self.retryCount += 1
            if self.retryCount <= 3 {
                return try await self.run()
            }
            await self.shotdown()
            throw error
        }
    }
    
    public func shotdown() async {
        self.task?.cancel()
        self.task = nil
        await XCBusiness.share.rmWork(self.key)
    }
}

