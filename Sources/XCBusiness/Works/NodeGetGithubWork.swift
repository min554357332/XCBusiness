import Foundation
import XCNetwork
import XCEvents

public actor NodeGetGithubWork: @preconcurrency XCWork {
    public let key: String
    internal var task: Task<[Node_response], Error>?
    private let countryCode: String?
    
    private var fire_retry = 0
    
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

private extension NodeGetGithubWork {
    func fire() async throws -> [Node_response] {
        return try await Node_github_request.fire(self.countryCode, timeout: 20)
    }
}

public extension NodeGetGithubWork {
    static func fire() async throws -> [Node_response] {
        
        let ipconfig = try await IpconfigRequestWork.fire()
        let countryCode = ipconfig.ipcountry
        
        let work_1 = NodeGetGithubWork(countryCode: nil)
        let work_2 = NodeGetGithubWork(countryCode: countryCode)
        
        let result: (NodeGetGithubWork, [Node_response]) = await withTaskGroup { group in
            group.addTask {
                do {
                    return (work_1, try await XCBusiness.share.run(work_1, returnType: Node_response.self))
                } catch {
                    alog("ConnectWork: github node countryCode: \(countryCode), err: \(error)")
                    return (work_1, [])
                }
            }
            group.addTask {
                do {
                    return (work_2, try await XCBusiness.share.run(work_1, returnType: Node_response.self))
                } catch {
                    alog("ConnectWork: github node err: \(error)")
                    return (work_2, [])
                }
            }
            var results: [(NodeGetGithubWork, [Node_response])] = []
            for await res in group {
                results.append(res)
            }
            return results.first { res in
                if res.0.key == work_1.key && res.1.isEmpty == false {
                    return true
                } else {
                    return false
                }
            } ?? results.first(where: { res in
                return !res.1.isEmpty
            }) ?? (work_1, [])
        }
        return result.1
    }
}
