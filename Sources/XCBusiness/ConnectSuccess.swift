import Foundation
import XCNetwork
import VPNConnectionChecker

public actor ConnectSuccess {
    public static func isSuccess() async -> Bool {
        for _ in 1 ... 3 {
            let result = await ConnectSuccess._isSuccess()
            if await VPNConnectionChecker.checker() {
                if result {
                    return true
                }
            } else {
                return false
            }
        }
        return false
    }
    
    private static func _isSuccess() async -> Bool {
        let global_config_work = GlobalConfigRequestWork()
        await XCBusiness.share.addWork(global_config_work)
        let global_config_result = try? await XCBusiness.share.run(global_config_work.key, returnType: Global_config_response.self)
        guard let global_config_result_first = global_config_result?.first else {
            return false
        }
        
        let success_rate = (global_config_result_first.success_rate ?? 0.2)
        let test_urls = global_config_result_first.test_urls ?? []
        
        
        let result: Bool = await withTaskGroup { group in
            var success_count = 0
            var failed_count = 0
            let count = test_urls.count
            for test_url in test_urls {
                group.addTask {
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
                if (Double(success_count) / Double(count)) > success_rate {
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
        let work = URLTestWork(url: url)
        await XCBusiness.share.addWork(work)
        do {
            let _:[Node_response] = try await XCBusiness.share.run(work.key, returnType: nil)
            print("true === \(url)")
            return true
        } catch {
            print("false === \(url)")
            return false
        }
    }
}
