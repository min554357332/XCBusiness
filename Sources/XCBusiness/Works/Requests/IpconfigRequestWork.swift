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

public extension IpconfigRequestWork {
    static func fire() async throws -> IPConfig {
        let work = IpconfigRequestWork()
        await XCBusiness.share.addWork(work)
        let config: IPConfig = try await withThrowingTaskGroup(of: IPConfig.self, returning: IPConfig.self) { group in
            group.addTask {
                let result: [Ip_api_response] = try await XCBusiness.share.run(work.key, returnType: Ip_api_response.self)
                guard let first = result.first else { throw NSError.init(domain: "err", code: -1) }
                return first
            }
            group.addTask {
                let result: [Ip_info_response] = try await XCBusiness.share.run(work.key, returnType: Ip_info_response.self)
                guard let first = result.first else { throw NSError.init(domain: "err", code: -1) }
                return first
            }
            for try await result in group {
                group.cancelAll()
                return result
            }
            throw NSError.init(domain: "err", code: -1)
        }
        return config
    }
}
