import Foundation
import XCNetwork
import XCTunnelManager
import VPNConnectionChecker

internal enum ConnectStatus {
    case fetchCity
    case fetchNode
    case connecting
    case test_network
    case connect
    case faile
}

public actor ConnectWork: @preconcurrency XCWork {
    public let key: String = "connect"
    internal var task: Task<(), Error>?
    private let city: Citys_response?
    
    public init(_ city: Citys_response?) {
        self.city = city
    }
    
    public func run() async throws -> [Sendable & Codable] {
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            await oldTask.shotdown()
        }
        let task = Task.detached {
            try await self.fire()
        }
        self.task = task
        await XCBusiness.share.addWork(self)
        do {
            _ = try await task.value
            await self.shotdown()
            return []
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
    
    private var status: ConnectStatus = .fetchCity

}

extension ConnectWork {
    func fire() async throws {
        try await self.setStatus(.connecting)
    }

    func setStatus(_ status: ConnectStatus, object: Any? = nil) async throws {

        self.status = status
        
        // 状态进入处理
        switch status {
        case .fetchCity:
            try await fetchCity()
        case .fetchNode:
            guard let city = object as? Citys_response else {
                print("⚠️ Missing city object for fetchNode state")
                return
            }
            try await fetchNode(city_id: city.id, index: 0)
        case .connecting:
            guard let node = object as? Node_response else {
                print("⚠️ Missing node object for connecting state")
                return
            }
            try await connecting(node)
        case .test_network:
            try await self.test_network()
        case .connect:
            try await self.connect()
        case .faile:
            try await self.faile()
        }
    }
    
}

extension ConnectWork {
    func fetchCity() async throws {
        let city: Citys_response
        if let c = self.city {
            city = c
        } else {
            let citys_work = CitysRequestWork()
            await XCBusiness.share.addWork(citys_work)
            let citys_result = try await XCBusiness.share.run(citys_work.key, returnType: Citys_response.self)
            let user = await UserWork().fire()
            let is_vip = user.isVip
            if is_vip {
                guard let c = citys_result.first(where: { $0.premium == true }) else {
                    throw NSError.init(domain: "No VIP city", code: -1)
                }
                city = c
            } else {
                guard let c = citys_result.first(where: { $0.premium == false }) else {
                    throw NSError.init(domain: "No available city", code: -1)
                }
                city = c
            }
        }
        let chose_city_work = CityChoseWork(city: city)
        await XCBusiness.share.addWork(chose_city_work)
        let _:[Citys_response] = try await XCBusiness.share.run(chose_city_work.key, returnType: nil)
        try await self.setStatus(ConnectStatus.fetchNode, object: city)
    }

    func fetchNode(city_id: Int, index: Int) async throws {
        let nodes_work = NodeRequestWork(city_id: city_id)
        await XCBusiness.share.addWork(nodes_work)
        let nodes_result = try await XCBusiness.share.run(nodes_work.key, returnType: Node_response.self)
        if nodes_result.count <= index {
            throw NSError.init(domain: "No available node", code: -1)
        }
        let node = nodes_result[index]
        let chose_node_work = NodeChoseWork(node: node)
        await XCBusiness.share.addWork(chose_node_work)
        let _:[Node_response] = try await XCBusiness.share.run(chose_node_work.key, returnType: nil)
        try await self.setStatus(ConnectStatus.connecting, object: node)
    }
    
    func connecting(_ node: Node_response) async throws {
        //将node解码后转为base64字符串
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        let data = try encoder.encode(node)
        guard let jsonStr = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "node encode error", code: -1)
        }
        Task {
            try await XCTunnelManager.share.connect(jsonStr)
        }
        let statusStream = await XCTunnelManager.share.statusAsyncStream(stopCondition: .connected)
        for await status in statusStream {
            if status == .connected {
                try await self.setStatus(.test_network)
                return
            }
        }
        try await self.setStatus(.faile)
    }

    func test_network(retry: Int = 1) async throws {
        let result = await ConnectSuccess.isSuccess()
        if result {
            try await self.setStatus(.connect)
        } else {
            try await self.setStatus(.faile)
        }
    }

    func connect() async throws {
        await XCTunnelManager.share.setStatus(.realConnected)
    }
    
    func faile() async throws {
        await XCTunnelManager.share.setStatus(.realFaile)
        try await XCTunnelManager.share.stop()
    }
}
