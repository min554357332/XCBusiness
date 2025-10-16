import Foundation
import XCNetwork

public actor NodeGetWork: @preconcurrency XCWork {
    public let key: String = "node_get"
    internal var task: Task<[Node_response?], Error>?
    
    public init() {}
    
    public func run() async throws -> [Sendable & Codable] {
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            await oldTask.shotdown()
        }
        let task = Task.detached {
            let result = try await self.fire()
            return [result]
        }
        self.task = task
        do {
            let result = try await task.value
            await self.shotdown()
            return result as [Sendable & Codable]
        } catch {
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

public extension NodeGetWork {
    public func fire() async throws -> Node_response? {
        try await XCNetwork.share.app_groups_decorator.get_chose_node()
    }
}
