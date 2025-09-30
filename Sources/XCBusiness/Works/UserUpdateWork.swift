import Foundation
import XCNetwork
import XCBuy

public actor UserUpdateWork: @preconcurrency XCWork {
    public let key: String = "user_update"
    internal var task: Task<(), Error>?
    
    private var user: XCUser = .init(expiry: 0)
    
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

extension UserUpdateWork {
    func fire() async throws {
        let expiryDate = try await XCBuy.fetchExpiryDate(await XCBusiness.share.productIds)
        if self.user.expiry == expiryDate.timeIntervalSince1970 { return }
        self.user.expiry = expiryDate.timeIntervalSince1970
        try await XCNetwork.share.app_groups_decorator.set_user(self.user)
        await XCBusiness.share.userSubject(send: self.user)
    }
}

public extension UserUpdateWork {
    static func fire() async throws {
        let work = UserUpdateWork()
        await XCBusiness.share.addWork(work)
        let _:[XCUser] = try await XCBusiness.share.run(work.key, returnType: nil)
    }
}
