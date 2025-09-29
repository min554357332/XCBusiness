import Foundation
import XCNetwork

public actor CityChoseWork: @preconcurrency XCWork {
    public let key: String = "city_chose"
    internal var task: Task<(), Error>?
    private let city: Citys_response?
    
    init(
        city: Citys_response?
    ) {
        self.city = city
    }
    
    public func run() async throws -> [Sendable & Codable] {
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            await oldTask.shotdown()
        }
        let task = Task.detached {
            try await self.fire()
        }
        self.task = task
        await XCBusiness.share.addWork(self)
        do {
            try await task.value
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

extension CityChoseWork {
    func fire() async throws {
        try await XCNetwork.share.app_groups_decorator.chose_city(self.city)
    }
}
