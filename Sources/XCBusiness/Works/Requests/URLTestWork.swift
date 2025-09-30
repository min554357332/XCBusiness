import Foundation
import XCNetwork
import Alamofire

public actor URLTestWork: @preconcurrency XCWork {
    public let key: String
    internal var task: Task<(), Error>?
    let url: String
    
    public init(
        url: String
    ) {
        self.url = url
        self.key = "url_test_\(self.url)"
    }
    
    public func run() async throws -> [Sendable & Codable] {
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            await oldTask.shotdown()
        }
        let task = Task {
            try await self.fire()
        }
        self.task = task
        do {
            _ = try await task.value
            await self.shotdown()
            return []
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

private extension URLTestWork {
    func fire() async throws {
        let request = AF.request(self.url)
        let task = request.serializingData()
        let response = await task.response
        if response.response?.statusCode == nil {
            throw NSError(domain: "not 204", code: response.response?.statusCode ?? -1)
        }
    }
}
