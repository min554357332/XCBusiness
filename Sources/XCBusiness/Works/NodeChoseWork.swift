import Foundation
import XCNetwork

public actor NodeChoseWork: @preconcurrency XCWork {
    public let key: String = "node_chose"
    internal var task: Task<(), Error>?
    private let node: Node_response?
    
    init(
        node: Node_response?
    ) {
        self.node = node
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

private extension NodeChoseWork {
    func fire() async throws {
        try await XCNetwork.share.app_groups_decorator.chose_node(self.node)
    }
}

public extension NodeChoseWork {
    public static func fire(_ node: Node_response) async throws {
        let chose_node_work = NodeChoseWork(node: node)
        await XCBusiness.share.addWork(chose_node_work)
        let _:[Node_response] = try await XCBusiness.share.run(chose_node_work.key, returnType: nil)
    }
}
