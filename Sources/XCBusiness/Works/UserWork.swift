import Foundation
import XCNetwork
import XCBuy

public actor UserWork: @preconcurrency XCWork {
    public let key: String = "user"
    internal var task: Task<XCUser, Never>?
    
    public func run() async throws -> [Sendable & Codable] {
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            await oldTask.shotdown()
        }
        let task = Task.detached {
            await self.fire()
        }
        self.task = task
        let result = await task.value
        await self.shotdown()
        return [result] as [Sendable & Codable]
    }
    
    public func shotdown() async {
        self.task?.cancel()
        self.task = nil
        await XCBusiness.share.rmWork(self.key)
    }
    
}

extension UserWork {
    func fire() async -> XCUser {
        var user = await XCNetwork.share.app_groups_decorator.get_user()
        do {
            let expiryDate = try await XCBuy.fetchExpiryDate(await XCBusiness.share.productIds)
            if user.expiry == expiryDate.timeIntervalSince1970 { return user }
            user.expiry = expiryDate.timeIntervalSince1970
            try await XCNetwork.share.app_groups_decorator.set_user(user)
            return user
        } catch {
            return user
        }
    }
}

public extension UserWork {
    static func fire() async throws -> XCUser {
        let work = UserWork()
        let result:[XCUser] = try await XCBusiness.share.run(work, returnType: XCUser.self)
        return result.first ?? .init(expiry: 0)
    }
}
