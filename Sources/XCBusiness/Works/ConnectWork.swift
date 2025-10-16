@preconcurrency import Foundation
import NetworkExtension
import XCNetwork
import XCTunnelManager
import VPNConnectionChecker
import XCEvents

// MARK: - VPN Status Monitoring Extension
public extension NEVPNStatus {
    static func asyncStream() -> AsyncStream<NEVPNStatus> {
        AsyncStream<NEVPNStatus> { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange,
                object: nil,
                queue: .main
            ) { notification in
                let vpnStatus = (notification.object as? NEVPNConnection)?.status ?? .disconnected
                continuation.yield(vpnStatus)
            }
            
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

public struct ConnectContext {
    var nodes: [Node_response]
    let city: Citys_response
    var node: Node_response?
    var retry: Int
    var node_index: Int
}

public enum ConnectStatus {
    case fetchCity
    case fetchNode(context: ConnectContext)
    case fetchGithubNode(context: ConnectContext)
    case connecting(context: ConnectContext)
    case test_network(context: ConnectContext)
    case connect(context: ConnectContext)
    case faile(context: ConnectContext)
}

public actor ConnectWork: @preconcurrency XCWork {
    public let key: String = "connect"
    internal var task: Task<(), Error>?
    private let city: Citys_response?
    
    public init(_ city: Citys_response?) {
        self.city = city
    }
    
    public func run() async throws -> [Sendable & Codable] {
        alog("🚀 ConnectWork: Starting connection work...")
        
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            alog("🔄 ConnectWork: Shutting down existing connection task")
            await oldTask.shotdown()
        }
        
        let task = Task.detached {
            try await self.fire()
        }
        self.task = task
        
        do {
            _ = try await task.value
            alog("✅ ConnectWork: Connection work completed successfully")
            await self.shotdown()
            return []
        } catch {
            alog("❌ ConnectWork: Connection work failed with error: \(error)")
            await self.shotdown()
            throw error
        }
    }
    
    public func shotdown() async {
        alog("🛑 ConnectWork: Shutting down connection work")
        self.task?.cancel()
        self.task = nil
        await XCBusiness.share.rmWork(self.key)
        alog("🛑 ConnectWork: Shutdown complete")
    }
    
    private var status: ConnectStatus = .fetchCity

}

extension ConnectWork {
    func fire() async throws {
        alog("🚀 ConnectWork: Starting connection process")
        do {
            try await self.setStatus(.fetchCity)
            Events.connect_session_success.fire()
        } catch {
            Events.connect_session_failed.fire()
            throw error
        }
    }

    func setStatus(_ status: ConnectStatus) async throws {

        self.status = status
        
        // 打印状态变化
        switch status {
        case .fetchCity:
            alog("📍 ConnectWork: Status changed to fetchCity")
        case .fetchNode(let context):
            alog("🌐 ConnectWork: Status changed to fetchNode, retry: \(context.retry), index: \(context.node_index)")
        case .fetchGithubNode(let context):
            alog("🐙 ConnectWork: Status changed to fetchGithubNode, retry: \(context.retry), index: \(context.node_index)")
        case .connecting(let context):
            alog("🔗 ConnectWork: Status changed to connecting, node: \(context.node?.name ?? "unknown")")
        case .test_network(let context):
            alog("🧪 ConnectWork: Status changed to test_network")
        case .connect(let context):
            alog("✅ ConnectWork: Status changed to connect (success)")
        case .faile(let context):
            alog("❌ ConnectWork: Status changed to failed")
        }
        
        // 状态进入处理
        switch status {
        case .fetchCity:
            try await self.fetchCity()
        case .fetchNode(let context):
            try await self.fetchNode(context: context)
        case .fetchGithubNode(let context):
            try await self.fetchGithubNode(context: context)
        case .connecting(let context):
            try await connecting(context: context)
        case .test_network(let context):
            try await self.test_network(context: context)
        case .connect(let context):
            try await self.connect(context: context)
        case .faile(let context):
            try await self.faile(context: context)
        }
    }
    
}

extension ConnectWork {
    func fetchCity() async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        alog("📍 ConnectWork: Fetching city information...")
        
        let city: Citys_response
        if let c = self.city {
            alog("📍 ConnectWork: Using provided city: \(c.city)")
            city = c
        } else {
            alog("📍 ConnectWork: Fetching available cities...")
            let citys_result = try await CitysRequestWork.fire()
            let user = await UserWork().fire()
            let is_vip = user.isVip
            alog("📍 ConnectWork: User VIP status: \(is_vip ? "VIP" : "Free")")
            
            if is_vip {
                guard let c = citys_result.first(where: { $0.premium == true }) else {
                    alog("❌ ConnectWork: No VIP city available")
                    throw NSError.init(domain: "No VIP city", code: -1)
                }
                alog("📍 ConnectWork: Selected VIP city: \(c.city)")
                city = c
            } else {
                guard let c = citys_result.first(where: { $0.premium == false }) else {
                    alog("❌ ConnectWork: No free city available")
                    throw NSError.init(domain: "No available city", code: -1)
                }
                alog("📍 ConnectWork: Selected free city: \(c.city)")
                city = c
            }
        }
        
        alog("📍 ConnectWork: Choosing city: \(city.city)")
        let chose_city_work = CityChoseWork(city: city)
        let _:[Citys_response] = try await XCBusiness.share.run(chose_city_work, returnType: nil)
        
        try await self.setStatus(.fetchNode(
            context: .init(nodes: [],city: city, node: nil, retry: 1, node_index: 0)
        ))
    }
    
    func fetchNode(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        alog("🌐 ConnectWork: Fetching nodes for city: \(context.city.city), retry: \(context.retry)")
        
        try await XCTunnelManager.share.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        var ctx = context
        let nodes_result: [Node_response]
        // 节点索引越界时
        if context.nodes.count <= context.node_index {
            alog("🌐 ConnectWork: Node index out of bounds (\(context.node_index) >= \(context.nodes.count)), retrying...")
            var ctx = context
            ctx.retry += 1
            ctx.node_index = 0
            nodes_result = try await NodeRequestWork.fire(
                city_id: ctx.city.id,
                retry: ctx.retry
            )
        } else {
            nodes_result = ctx.nodes
        }
        
        alog("🌐 ConnectWork: Received \(nodes_result.count) nodes")
        
        // 节点为空时，尝试从 GitHub 获取
        if nodes_result.isEmpty && ctx.retry == 1 {
            alog("🌐 ConnectWork: No nodes available, switching to GitHub nodes")
            var ctx = context
            ctx.nodes = []
            ctx.node = nil
            ctx.node_index = 0
            ctx.retry = 1000
            try await self.setStatus(.fetchGithubNode(context: ctx))
            return
        } else if nodes_result.isEmpty {
            throw NSError(domain: "nodes empty", code: -1)
        }
        
        let node = nodes_result[ctx.node_index]
        alog("🌐 ConnectWork: Selected node: \(node.name) (index: \(ctx.node_index))")
        
        try await NodeChoseWork.fire(node)
        ctx.nodes = nodes_result
        ctx.node = node
        try await self.setStatus(.connecting(
            context: ctx
        ))
    }
    
    func fetchGithubNode(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        alog("🐙 ConnectWork: Fetching GitHub nodes...")
        
        try await XCTunnelManager.share.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        
        let nodes_result = try await NodeGetGithubWork.fire()
        alog("🐙 ConnectWork: Received \(nodes_result.count) GitHub nodes")
        
        if nodes_result.isEmpty {
            alog("❌ ConnectWork: No GitHub nodes available, connection failed")
            try await self.setStatus(.faile(context: context))
            return
        }
        if nodes_result.count <= context.node_index {
            alog("❌ ConnectWork: GitHub node index out of bounds, connection failed")
            try await self.setStatus(.faile(context: context))
            return
        }
        
        let node = nodes_result[context.node_index]
        alog("🐙 ConnectWork: Selected GitHub node: \(node.name) (index: \(context.node_index))")
        
        try await NodeChoseWork.fire(node)
        var ctx = context
        ctx.nodes = nodes_result
        ctx.node = node
        try await self.setStatus(.connecting(
            context: ctx
        ))
    }
    
    func connecting(context: ConnectContext) async throws {
        guard let node = context.node else {
            alog("❌ ConnectWork: Node is nil, cannot connect")
            throw NSError(domain: "node encode error", code: -1)
        }
        
        alog("🔗 ConnectWork: Starting connection to node: \(node.name)")
        
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        let data = try encoder.encode(node)
        guard let jsonStr = String(data: data, encoding: .utf8) else {
            alog("❌ ConnectWork: Failed to encode node data")
            throw NSError(domain: "node encode error", code: -1)
        }
        
        alog("🔗 ConnectWork: Initiating tunnel connection...")
        try await XCTunnelManager.share.connect(jsonStr)
        
        alog("✅ ConnectWork: VPN connected successfully")
        try await self.setStatus(.test_network(context: context))

    }

    func test_network(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        await XCTunnelManager.share.setStatus(.network_availability_testing)
        
        alog("🧪 ConnectWork: Testing network connectivity...")
        if let node = context.node {
            alog("🧪 ConnectWork: Testing node: \(node.name)")
        }
        
        // 添加小延迟，等待连接稳定
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
        alog("🧪 ConnectWork: Starting network test after 2s delay...")
        
        // 为网络测试添加超时保护
        let startTime = Date()
        var result = await ConnectSuccess.isSuccess()
        await XCTunnelManager.share.setStatus(.network_availability_testing)
        let duration = Date().timeIntervalSince(startTime)
        
        alog("🧪 ConnectWork: Network test completed in \(String(format: "%.2f", duration))s")
        alog("🧪 ConnectWork: Network test result: \(result ? "✅ Success" : "❌ Failed")")
        
        if result {
            alog("🎉 ConnectWork: Connection successful!")
            try await self.setStatus(.connect(context: context))
        } else {
            Events.connect_failed.fire()
            let status = await XCTunnelManager.share.getStatus()
            if status == .disconnected || status == .disconnecting {
                try await self.setStatus(.faile(context: context))
                return
            }
            
            
            alog("🔄 ConnectWork: Network test failed, trying next node...")
            if let node = context.node {
                alog("🔄 ConnectWork: Failed node: \(node.name)")
            }
            
            var ctx = context
            ctx.node = nil
            ctx.node_index += 1
            try await self.setStatus(.fetchNode(context: ctx))
        }
    }

    func connect(context: ConnectContext) async throws {
        alog("🎉 ConnectWork: Connection established successfully!")
        if let node = context.node {
            alog("🎉 ConnectWork: Connected to node: \(node.name)")
        }
        await XCTunnelManager.share.setStatus(.connected)
    }
    
    func faile(context: ConnectContext) async throws {
        alog("❌ ConnectWork: Connection failed completely")
        if let node = context.node {
            alog("❌ ConnectWork: Last attempted node: \(node.name)")
        }
        alog("❌ ConnectWork: Setting status to failed and stopping tunnel")
        await XCTunnelManager.share.setStatus(.realFaile)
        try await XCTunnelManager.share.stop()
        throw NSError(domain: "Connect faile", code: -1)
    }
}

extension ConnectWork {
    public static func fire(_ city: Citys_response?) async throws {
        alog("🔥 ConnectWork: Static fire method called")
        if let city = city {
            alog("🔥 ConnectWork: Using specified city: \(city.city)")
        } else {
            alog("🔥 ConnectWork: No city specified, will auto-select")
        }
        
        let work = ConnectWork(city)
        let _: [Citys_response] = try await XCBusiness.share.run(work, returnType: nil)
    }
}


#if DEBUG
func alog(_ format: String, _ args: any CVarArg...) {
    NSLog(format, args)
}
#else
func alog(_ format: String, _ args: any CVarArg...) {}
#endif
