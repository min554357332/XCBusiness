import Foundation
import XCNetwork
import XCCache

public actor XCBusiness {
    public static let share = XCBusiness()
    private init() {}
    
    internal var works: [String: any XCWork] = [:]
    public var response: [String: [Sendable & Codable]] = [:]
}

extension XCBusiness {
    internal func isExist(_ key: String) async -> Bool {
        return self.works[key] != nil
    }
}

extension XCBusiness {
    public func addWork(_ work: any XCWork) async {
        if await self.isExist(work.key) { return }
        self.works[work.key] = work
    }
    
    @discardableResult
    public func rmWork(_ key: String) async -> (any XCWork)? {
        return self.works.removeValue(forKey: key)
    }
    
    // 根据传入的key, 执行对应work
    public func run<R: NECache>(_ key: String, returnType: R.Type?) async throws -> [R] {
        if (await returnType?.expired() ?? true) {
            guard let work = self.works[key] else {
                throw NSError(domain: "\(key) Key does not exist", code: -1)
            }
            let result = try await work.run()
            if returnType == nil {
                return []
            }
            guard let res = result as? [R] else {
                throw NSError(domain: "Type conversion failed", code: -1)
            }
            self.response[key] = result
            return res
        }
        if returnType == nil {
            return []
        }
        guard let result = try await returnType?.r(key, encode: await XCNetwork.share.cache_encrypt_data_preprocessor, decode: await XCNetwork.share.cache_decrypt_data_preprocessor) else {
            throw NSError(domain: "does not exist, Please check the resource file: \(key)", code: -1)
        }
        return [result]
    }
    
}


