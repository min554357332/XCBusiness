import Foundation
import XCTunnelManager
import XCNetwork
import VPNConnectionChecker

public actor ConnectSuccess {
    public static func isSuccess(retry: Int = 1) async -> Bool {
        let status_1 = await XCTunnelManager.share.getStatus()
        if status_1 == .network_availability_testing {
            let result = await ConnectSuccess._isSuccess()
            let status_2 = await XCTunnelManager.share.getStatus()
            if status_2 == .network_availability_testing {
                if result {
                    alog("🧪 ConnectWork: Network test result: Success retry: \(retry)")
                    return true
                } else {
                    let status_3 = await XCTunnelManager.share.getStatus()
                    if status_3 == .network_availability_testing {
                        if retry <= 3 {
                            return await ConnectSuccess.isSuccess(retry: retry + 1)
                        } else {
                            // 重试结束，连接失败
                            alog("🧪 ConnectWork: Network test result: faile retry: \(retry)")
                            return false
                        }
                    } else {
                        // VPN未连接
                        alog("🧪 ConnectWork: Network test result: faile retry: \(retry)")
                        return false
                    }
                }
            }
        }
        alog("🧪 ConnectWork: Network test result: faile retry: \(retry)")
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
        
        
        let result: Bool = await withTaskGroup(of: Bool.self) { group in
            var success_count = 0
            var failed_count = 0
            let count = test_urls.count
            for test_url in test_urls {
                group.addTask {
                    if Task.isCancelled {
                        return false
                    }
                    return await ConnectSuccess.test(test_url)
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
                    return true
                }
                
                // 达到失败率就取消剩余任务
                if (Double(failed_count) / Double(count)) > (1 - success_rate) {
                    group.cancelAll()
                    return false
                }
            }
            return false
        }
        return result
    }
    
    public static func test(_ url: String) async -> Bool {
        #if DEBUG
        return false
        #endif
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
