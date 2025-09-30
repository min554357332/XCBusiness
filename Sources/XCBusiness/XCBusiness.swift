import Foundation
import Combine
import XCNetwork
import XCCache

public actor XCBusiness {
    public static let share = XCBusiness()
    private init() {}
    
    internal var works: [String: any XCWork] = [:]
    public var response: [String: [Sendable & Codable]] = [:]
    public var productIds: Set<String> = []
    
    private var userSubject = PassthroughSubject<XCUser,Never>()
}

extension XCBusiness {
    public func set_productIds(_ ids: Set<String>) async {
        self.productIds = ids
    }
}

extension XCBusiness {
    public func userSubject(send user: XCUser) async {
        self.userSubject.send(user)
    }
    public func userSubjectSink() async -> PassthroughSubject<XCUser,Never> {
        return self.userSubject
    }
}

extension XCBusiness {
    internal func isExist(_ key: String) async -> Bool {
        return self.works[key] != nil
    }
}

extension XCBusiness {
    private func addWork(_ work: any XCWork) async {
        if await self.isExist(work.key) { return }
        self.works[work.key] = work
    }
    
    @discardableResult
    public func rmWork(_ key: String) async -> (any XCWork)? {
        return self.works.removeValue(forKey: key)
    }
    
    // 根据传入的key, 执行对应work
    public func run<R: NECache>(_ work: XCWork, returnType: R.Type?) async throws -> [R] {
        await self.addWork(work)
        if (await returnType?.expired() ?? true) {
            let result = try await work.run()
            if returnType == nil {
                return []
            }
            guard let res = result as? [R] else {
                throw NSError(domain: "Type conversion failed", code: -1)
            }
            self.response[work.key] = result
            return res
        }
        if returnType == nil {
            return []
        }
        guard let result = try await returnType?.r(work.key, encode: await XCNetwork.share.cache_encrypt_data_preprocessor, decode: await XCNetwork.share.cache_decrypt_data_preprocessor) else {
            throw NSError(domain: "does not exist, Please check the resource file: \(work.key)", code: -1)
        }
        return [result]
    }
    
}


