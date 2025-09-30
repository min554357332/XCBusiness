import Foundation
import XCNetwork

public actor ReportRequestWork: @preconcurrency XCWork {
    public let key = "nodes"
    internal var task: Task<(), Error>?
    private var retryCount = 0
    let name: String
    let retry: Int
    let core: String
    let agreement: String
    let event: String
    let duration: Int?
    
    public init(
        name: String,
        retry: Int,
        core: String,
        agreement: String,
        event: String,
        duration: Int? = nil
    ) {
        self.name = name
        self.retry = retry
        self.core = core
        self.agreement = agreement
        self.event = event
        self.duration = duration
    }
    
    public func run() async throws -> [Sendable & Codable] {
        if self.retryCount == 0 {
            if let oldTask = await XCBusiness.share.rmWork(self.key) {
                await oldTask.shotdown()
            }
        }
        let task = Task.detached {
            try await Report_request.fire(name: self.name, retry: self.retry, core: self.core, agreement: self.agreement, event: self.event, duration: self.duration)
        }
        self.task = task
        do {
            _ = try await task.value
            await self.shotdown()
            return []
        } catch {
            self.retryCount += 1
            if self.retryCount <= 3 {
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

public extension ReportRequestWork {
    static func fire(
        name: String,
        retry: Int,
        core: String,
        agreement: String,
        event: String,
        duration: Int? = nil
    ) async throws {
        let report_work = ReportRequestWork(name: name, retry: retry, core: core, agreement: agreement, event: event)
        let _:[Node_response] = try await XCBusiness.share.run(report_work, returnType: nil)
    }
}
