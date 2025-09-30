import Foundation
import XCNetwork

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
        let ipconfig_work_1 = IpconfigRequestWork()
        let ipconfig_work_2 = IpconfigRequestWork()
        await XCBusiness.share.addWork(ipconfig_work_1)
        await XCBusiness.share.addWork(ipconfig_work_2)
        let ipconfig_work_1_result = try? await XCBusiness.share.run(ipconfig_work_1.key, returnType: Ip_api_response.self)
        let ipconfig_work_2_result = try? await XCBusiness.share.run(ipconfig_work_2.key, returnType: Ip_info_response.self)
        let countryCode: String? = if let ip_1 = ipconfig_work_1_result?.first {
            ip_1.ipcountry
        } else if let ip_2 = ipconfig_work_2_result?.first {
            ip_2.ipcountry
        } else {
            if #available(iOS 16, *) {
                Locale.current.region?.identifier ?? "US"
            } else {
                Locale.current.regionCode ?? "US"
            }
        }
        
        let work_1 = NodeGetGithubWork(countryCode: nil)
        let work_2 = NodeGetGithubWork(countryCode: countryCode)
        
        await XCBusiness.share.addWork(work_1)
        await XCBusiness.share.addWork(work_2)
        
        let work_1_result = try await XCBusiness.share.run(work_1.key, returnType: Node_response.self)
        let work_2_result = try await XCBusiness.share.run(work_2.key, returnType: Node_response.self)
        if work_2_result.isEmpty {
            return work_1_result
        }
        return work_2_result
    }
}
