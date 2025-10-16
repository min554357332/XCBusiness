import Foundation
import NetworkExtension
import XCTunnelManager
import XCNetwork
import VPNConnectionChecker

extension NEVPNManager: @unchecked Sendable {}

public actor ConnectSuccess {
    public static func isSuccess() async throws -> Bool {
        for index in 0 ..< 3 {
            alog("🧪 ConnectWork: Network test start")
            let sysStatus_pre = try await XCTunnelManager.share.getManager().connection.status
            if sysStatus_pre != .connected {
                alog("🧪 ConnectWork: Network test result: ❌ Failed sys status: \(sysStatus_pre)")
                return false
            }
            let result = await ConnectSuccess._isSuccess()
            if result {
                let sysStatus_next = try await XCTunnelManager.share.getManager().connection.status
                if sysStatus_next != .connected {
                    alog("🧪 ConnectWork: Network test result: ❌ Failed sys status: \(sysStatus_pre)")
                    return false
                } else {
                    alog("🧪 ConnectWork: Network test result: ✅ Success")
                    return true
                }
            }
            alog("🧪 ConnectWork: Network test result: ❌ Failed nexting")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }
    
    private static func _isSuccess() async -> Bool {
        let global_config_work = GlobalConfigRequestWork()
        let global_config_result = try? await XCBusiness.share.run(global_config_work, returnType: Global_config_response.self)
        guard let global_config_result_first = global_config_result?.first else {
            return false
        }
        
        let success_rate = (global_config_result_first.success_rate ?? 0.2)
        let test_urls = global_config_result_first.test_urls ?? []
        
        
        let result: Bool = await withCheckedContinuation { c in
            Task {
                await withTaskGroup(of: Bool.self) { group in
                    var success_count = 0
                    var failed_count = 0
                    let count = test_urls.count
                    for test_url in test_urls {
                        group.addTask {
                            try Task.checkCancellation()
                            let result =  await ConnectSuccess.test(test_url)
                            alog("🧪 ConnectWork: Network test sub result: \(result)")
                            return result
                        }
                    }
                    for await res in group {
                        if res {
                            success_count += 1
                        } else {
                            failed_count += 1
                        }
                        // 达到成功率就取消剩余任务
                        if (Double(success_count) / Double(count)) >= success_rate {
                            group.cancelAll()
                            alog("🧪 ConnectWork: Network test sub result: true, group.cancelAll()")
                            c.resume(returning: true)
                        }
                        
                        // 达到失败率就取消剩余任务
                        if (Double(failed_count) / Double(count)) > (1 - success_rate) {
                            group.cancelAll()
                            alog("🧪 ConnectWork: Network test sub result: false, group.cancelAll()")
                            c.resume(returning: false)
                        }
                    }
                    c.resume(returning: false)
                }
            }
        }
#if DEBUG
        return false
#endif
        return result
    }
    
    public static func test(_ url: String) async -> Bool {
        let work = URLTestWork(url: url)
        do {
            let _:[Node_response] = try await XCBusiness.share.run(work, returnType: nil)
            alog("true === \(url)")
            return true
        } catch {
            alog("false === \(url)")
            return false
        }
    }
}
