import Foundation
import XCNetwork

public actor CityGetWork: @preconcurrency XCWork {
    public let key: String = "city_get"
    internal var task: Task<[Citys_response?], Error>?
    
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

extension CityGetWork {
    func fire() async throws -> Citys_response? {
        try await XCNetwork.share.app_groups_decorator.get_chose_city()
    }
}

extension CityGetWork {
    public static func fire() async throws -> Citys_response? {
        let work = CityGetWork()
        await XCBusiness.share.addWork(work)
        let result = try await XCBusiness.share.run(work.key, returnType: Citys_response.self)
        return result.first
    }
}
