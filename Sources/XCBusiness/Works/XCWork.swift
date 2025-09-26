import Foundation
import XCCache

public protocol XCWork: Sendable {
    
    var key: String { get }
    func run() async throws -> [Sendable & Codable]
    func shotdown() async
    
}
