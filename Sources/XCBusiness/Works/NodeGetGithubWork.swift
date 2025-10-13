import Foundation
import XCNetwork
import XCEvents

public actor NodeGetGithubWork: @preconcurrency XCWork {
    public let key: String
    internal var task: Task<[Node_response], Error>?
    private let countryCode: String?
    
    init(
        countryCode: String?
    ) {
        self.key = if let code = countryCode {
            "node_github_\(code)"
        } else {
            "node_github"
        }
        self.countryCode = countryCode
    }
    
    public func run() async throws -> [Sendable & Codable] {
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            await oldTask.shotdown()
        }
        let task = Task.detached {
            try await self.fire()
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

private extension NodeGetGithubWork {
    func fire() async throws -> [Node_response] {
        return try await Node_github_request.fire(self.countryCode)
    }
}

public extension NodeGetGithubWork {
    static func fire() async throws -> [Node_response] {
        
        let ipconfig = try await IpconfigRequestWork.fire()
        let countryCode = ipconfig.ipcountry
        
        let work_1 = NodeGetGithubWork(countryCode: nil)
        let work_2 = NodeGetGithubWork(countryCode: countryCode)
        
        var err: Error?
        
        do {
            let result = try await XCBusiness.share.run(work_2, returnType: Node_response.self)
            if result.isEmpty == false {
                return result
            }
        } catch {
            err = error
        }
        
        do {
            let result = try await XCBusiness.share.run(work_1, returnType: Node_response.self)
            return result
        } catch {
            err = error
        }
        if let err {
            Events.error_node_git.fire()
            throw err
        }
        return []
    }
}
