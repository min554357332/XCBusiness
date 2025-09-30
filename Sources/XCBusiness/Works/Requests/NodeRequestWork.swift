import Foundation
import XCNetwork

public actor NodeRequestWork: @preconcurrency XCWork {
    public let key = "nodes"
    internal var task: Task<[Node_response], Error>?
    private var retryCount = 1
    let city_id: Int
    
    public init(
        city_id: Int,
        retry: Int
    ) {
        self.city_id = city_id
        self.retryCount = retry
    }
    
    public func run() async throws -> [Sendable & Codable] {
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            await oldTask.shotdown()
        }
        let task = Task.detached {
            try await Node_request.fire(self.city_id, retry: self.retryCount)
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

public extension NodeRequestWork {
    static func fire(city_id: Int,retry: Int) async throws -> [Node_response] {
        let work = NodeRequestWork(city_id: city_id, retry: retry)
        let result = try await XCBusiness.share.run(work, returnType: Node_response.self)
        return result
    }
}
