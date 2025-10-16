import Foundation
import XCNetwork

public actor GlobalConfigRequestWork: @preconcurrency XCWork {
    
    public let key = "global_config"
    internal var task: Task<Global_config_response, Error>?
    private var retryCount = 0
    
    private let retryMax = 3
    
    public init(_ retryMax: Int = 3) {
        self.retryMax = retryMax
    }
    
    public func run() async throws -> [Sendable & Codable] {
        if self.retryCount == 0 {
            if let oldTask = await XCBusiness.share.rmWork(self.key) {
                await oldTask.shotdown()
            }
        }
        let task = Task.detached {
            try await Global_config_request.fire()
        }
        self.task = task
        do {
            let result = try await task.value
            await self.shotdown()
            return [result as Sendable & Codable]
        } catch {
            self.retryCount += 1
            if self.retryCount <= self.retryMax {
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

public extension GlobalConfigRequestWork {
    static func fire(_ retryMax: Int = 3) async throws -> Global_config_response {
        let work = GlobalConfigRequestWork()
        let result = try await XCBusiness.share.run(work, returnType: Global_config_response.self)
        guard let first = result.first else { throw NSError(domain: "err", code: -1) }
        return first
    }
}
