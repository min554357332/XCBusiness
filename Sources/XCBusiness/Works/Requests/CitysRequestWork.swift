import Foundation
import XCNetwork

public actor CitysRequestWork: @preconcurrency XCWork {
    public let key = "citys"
    internal var task: Task<[Citys_response], Error>?
    private var retryCount = 0
    
    public init() {}
    
    public func run() async throws -> [Sendable & Codable] {
        if self.retryCount == 0 {
            if let oldTask = await XCBusiness.share.rmWork(self.key) {
                await oldTask.shotdown()
            }
        }
        let task = Task.detached {
            try await Citys_request.fire()
        }
        self.task = task
        if self.retryCount == 0 {
            await XCBusiness.share.addWork(self)
        }
        do {
            let result = try await task.value
            await self.shotdown()
            return result as [Sendable & Codable]
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


public extension CitysRequestWork {
    static func fire() async throws -> [Citys_response] {
        let work = CitysRequestWork()
        await XCBusiness.share.addWork(work)
        return try await XCBusiness.share.run(work.key, returnType: Citys_response.self)
    }
}
