import Foundation
import XCNetwork

public struct IpconfigRequestWork {
    static func fire() async throws -> IPConfig {
        let config: IPConfig = try await withThrowingTaskGroup(of: IPConfig.self, returning: IPConfig.self) { group in
            group.addTask {
                let result: [Ip_api_response] = try await XCBusiness.share.run(IpApiRequestWork(), returnType: Ip_api_response.self)
                guard let first = result.first else { throw NSError.init(domain: "err", code: -1) }
                return first
            }
            group.addTask {
                let result: [Ip_info_response] = try await XCBusiness.share.run(IpInfoRequestWork(), returnType: Ip_info_response.self)
                guard let first = result.first else { throw NSError.init(domain: "err", code: -1) }
                return first
            }
            for try await result in group {
                group.cancelAll()
                return result
            }
            throw NSError.init(domain: "err", code: -1)
        }
        return config
    }
}
