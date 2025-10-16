import Foundation
import XCNetwork
import XCEvents

public actor NodeRequestWork: @preconcurrency XCWork {
    public let key = "nodes"
    internal var task: Task<[Node_response], Error>?
    private var retryCount = 1
    let city_id: Int
    
    private var fire_retry = 0
    
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
            try await Node_request.fire(self.city_id, retry: self.retryCount, timeout: 20)
        }
        self.task = task
        do {
            let result = try await task.value
            await self.shotdown()
            return result as [Sendable & Codable]
        } catch {
            self.fire_retry += 1
            if self.fire_retry <= 3 {
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

public extension NodeRequestWork {
    static func fire(city_id: Int,retry: Int) async throws -> [Node_response] {
        let work = NodeRequestWork(city_id: city_id, retry: retry)
        do {
            let result = try await XCBusiness.share.run(work, returnType: Node_response.self)
            return result
        } catch {
            Events.error_node_api.fire()
            throw error
        }
    }
}
