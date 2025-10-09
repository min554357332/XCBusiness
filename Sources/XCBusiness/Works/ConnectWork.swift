@preconcurrency import Foundation
import NetworkExtension
import XCNetwork
import XCTunnelManager
import VPNConnectionChecker

// MARK: - VPN Status Monitoring Extension
extension NEVPNStatus {
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
            
            // 注意：这是一个无限流，依赖消费者取消来结束
            // 在 VPN 状态监听场景中这是正常的，因为我们需要持续监听状态变化
        }
    }
}

internal struct ConnectContext {
    var nodes: [Node_response]
    let city: Citys_response
    var node: Node_response?
    var retry: Int
    var node_index: Int
}

internal enum ConnectStatus {
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
        print("🚀 ConnectWork: Starting connection work...")
        
        if let oldTask = await XCBusiness.share.rmWork(self.key) {
            print("🔄 ConnectWork: Shutting down existing connection task")
            await oldTask.shotdown()
        }
        
        let task = Task.detached {
            try await self.fire()
        }
        self.task = task
        
        do {
            _ = try await task.value
            print("✅ ConnectWork: Connection work completed successfully")
            await self.shotdown()
            return []
        } catch {
            print("❌ ConnectWork: Connection work failed with error: \(error)")
            await self.shotdown()
            throw error
        }
    }
    
    public func shotdown() async {
        print("🛑 ConnectWork: Shutting down connection work")
        self.task?.cancel()
        self.task = nil
        await XCBusiness.share.rmWork(self.key)
        print("🛑 ConnectWork: Shutdown complete")
    }
    
    private var status: ConnectStatus = .fetchCity

}

extension ConnectWork {
    func fire() async throws {
        print("🚀 ConnectWork: Starting connection process")
        try await self.setStatus(.fetchCity)
    }

    func setStatus(_ status: ConnectStatus) async throws {

        self.status = status
        
        // 打印状态变化
        switch status {
        case .fetchCity:
            print("📍 ConnectWork: Status changed to fetchCity")
        case .fetchNode(let context):
            print("🌐 ConnectWork: Status changed to fetchNode, retry: \(context.retry), index: \(context.node_index)")
        case .fetchGithubNode(let context):
            print("🐙 ConnectWork: Status changed to fetchGithubNode, retry: \(context.retry), index: \(context.node_index)")
        case .connecting(let context):
            print("🔗 ConnectWork: Status changed to connecting, node: \(context.node?.name ?? "unknown")")
        case .test_network(let context):
            print("🧪 ConnectWork: Status changed to test_network")
        case .connect(let context):
            print("✅ ConnectWork: Status changed to connect (success)")
        case .faile(let context):
            print("❌ ConnectWork: Status changed to failed")
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
        
        print("📍 ConnectWork: Fetching city information...")
        
        let city: Citys_response
        if let c = self.city {
            print("📍 ConnectWork: Using provided city: \(c.city)")
            city = c
        } else {
            print("📍 ConnectWork: Fetching available cities...")
            let citys_result = try await CitysRequestWork.fire()
            let user = await UserWork().fire()
            let is_vip = user.isVip
            print("📍 ConnectWork: User VIP status: \(is_vip ? "VIP" : "Free")")
            
            if is_vip {
                guard let c = citys_result.first(where: { $0.premium == true }) else {
                    print("❌ ConnectWork: No VIP city available")
                    throw NSError.init(domain: "No VIP city", code: -1)
                }
                print("📍 ConnectWork: Selected VIP city: \(c.city)")
                city = c
            } else {
                guard let c = citys_result.first(where: { $0.premium == false }) else {
                    print("❌ ConnectWork: No free city available")
                    throw NSError.init(domain: "No available city", code: -1)
                }
                print("📍 ConnectWork: Selected free city: \(c.city)")
                city = c
            }
        }
        
        print("📍 ConnectWork: Choosing city: \(city.city)")
        let chose_city_work = CityChoseWork(city: city)
        let _:[Citys_response] = try await XCBusiness.share.run(chose_city_work, returnType: nil)
        
        try await self.setStatus(.fetchNode(
            context: .init(nodes: [],city: city, node: nil, retry: 1, node_index: 0)
        ))
    }
    
    func fetchNode(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        print("🌐 ConnectWork: Fetching nodes for city: \(context.city.city), retry: \(context.retry)")
        
        let nodes_result = try await NodeRequestWork.fire(
            city_id: context.city.id,
            retry: context.retry
        )
        
        print("🌐 ConnectWork: Received \(nodes_result.count) nodes")
        
        // 节点为空时，尝试从 GitHub 获取
        if nodes_result.isEmpty {
            print("🌐 ConnectWork: No nodes available, switching to GitHub nodes")
            var ctx = context
            ctx.nodes = []
            ctx.node = nil
            ctx.node_index = 0
            ctx.retry = 1
            try await self.setStatus(.fetchGithubNode(context: ctx))
            return
        }
        // 节点索引越界时，重试获取节点，会一直到节点列表为空，不会返回相同的节点列表
        if nodes_result.count <= context.node_index {
            print("🌐 ConnectWork: Node index out of bounds (\(context.node_index) >= \(nodes_result.count)), retrying...")
            var ctx = context
            ctx.retry += 1
            ctx.node_index = 0
            try await self.setStatus(.fetchNode(context: ctx))
            return
        }
        
        let node = nodes_result[context.node_index]
        print("🌐 ConnectWork: Selected node: \(node.name) (index: \(context.node_index))")
        
        try await NodeChoseWork.fire(node)
        var ctx = context
        ctx.nodes = nodes_result
        ctx.node = node
        try await self.setStatus(.connecting(
            context: ctx
        ))
    }
    
    func fetchGithubNode(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        print("🐙 ConnectWork: Fetching GitHub nodes...")
        
        let nodes_result = try await NodeGetGithubWork.fire()
        print("🐙 ConnectWork: Received \(nodes_result.count) GitHub nodes")
        
        if nodes_result.isEmpty {
            print("❌ ConnectWork: No GitHub nodes available, connection failed")
            try await self.setStatus(.faile(context: context))
            return
        }
        if nodes_result.count <= context.node_index {
            print("❌ ConnectWork: GitHub node index out of bounds, connection failed")
            try await self.setStatus(.faile(context: context))
            return
        }
        
        let node = nodes_result[context.node_index]
        print("🐙 ConnectWork: Selected GitHub node: \(node.name) (index: \(context.node_index))")
        
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
            print("❌ ConnectWork: Node is nil, cannot connect")
            throw NSError(domain: "node encode error", code: -1)
        }
        
        print("🔗 ConnectWork: Starting connection to node: \(node.name)")
        
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        let data = try encoder.encode(node)
        guard let jsonStr = String(data: data, encoding: .utf8) else {
            print("❌ ConnectWork: Failed to encode node data")
            throw NSError(domain: "node encode error", code: -1)
        }
        


        // 使用 TaskGroup 来处理连接、超时和状态监听
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.add {
                print("🔗 ConnectWork: Initiating tunnel connection...")
                try await XCTunnelManager.share.connect(jsonStr)
            }

            // 添加状态监听任务
            group.addTask {
                print("👂 ConnectWork: Starting VPN status monitoring...")
                // 监听 VPN 状态变化，添加超时保护
                for await vpnStatus in NEVPNStatus.asyncStream() {
                    // 检查任务是否被取消
                    try Task.checkCancellation()
                    
                    print("📡 ConnectWork: VPN status changed to: \(vpnStatus)")
                    
                    switch vpnStatus {
                    case .connected:
                        print("✅ ConnectWork: VPN connected successfully")
                        try await self.setStatus(.test_network(context: context))
                        return
                    case .disconnected, .disconnecting:
                        print("🔌 ConnectWork: VPN disconnected/disconnecting")
                        continue
                    case .connecting:
                        print("🔄 ConnectWork: VPN connecting...")
                        continue
                    default:
                        print("⚠️ ConnectWork: Unknown VPN status: \(vpnStatus)")
                        continue
                    }
                }
            }
            
            try await group.next()
        }
    }

    func test_network(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        print("🧪 ConnectWork: Testing network connectivity...")
        if let node = context.node {
            print("🧪 ConnectWork: Testing node: \(node.name)")
        }
        
        // 添加小延迟，等待连接稳定
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2秒
        print("🧪 ConnectWork: Starting network test after 2s delay...")
        
        // 为网络测试添加超时保护
        let startTime = Date()
        let result = await ConnectSuccess.isSuccess()
        let duration = Date().timeIntervalSince(startTime)
        
        print("🧪 ConnectWork: Network test completed in \(String(format: "%.2f", duration))s")
        print("🧪 ConnectWork: Network test result: \(result ? "✅ Success" : "❌ Failed")")
        
        if result {
            print("🎉 ConnectWork: Connection successful!")
            try await self.setStatus(.connect(context: context))
        } else {
            print("🔄 ConnectWork: Network test failed, trying next node...")
            if let node = context.node {
                print("🔄 ConnectWork: Failed node: \(node.name)")
            }
            
            var ctx = context
            ctx.node = nil
            if ctx.nodes.isEmpty {
                print("🐙 ConnectWork: No more regular nodes, switching to GitHub nodes")
                ctx.retry = 1
                ctx.node_index = 0
                try await self.setStatus(.fetchGithubNode(context: ctx))
            } else {
                if ctx.node_index + 1 >= ctx.nodes.count {
                    print("🔄 ConnectWork: Reached end of node list, retrying with next batch")
                    ctx.retry += 1
                    ctx.node_index = 0
                } else {
                    print("🔄 ConnectWork: Trying next node in list (index: \(ctx.node_index + 1))")
                    ctx.node_index += 1
                }
                try await self.setStatus(.fetchNode(context: ctx))
            }
        }
    }

    func connect(context: ConnectContext) async throws {
        print("🎉 ConnectWork: Connection established successfully!")
        if let node = context.node {
            print("🎉 ConnectWork: Connected to node: \(node.name)")
        }
        await XCTunnelManager.share.setStatus(.realConnected)
    }
    
    func faile(context: ConnectContext) async throws {
        print("❌ ConnectWork: Connection failed completely")
        if let node = context.node {
            print("❌ ConnectWork: Last attempted node: \(node.name)")
        }
        print("❌ ConnectWork: Setting status to failed and stopping tunnel")
        await XCTunnelManager.share.setStatus(.realFaile)
        try await XCTunnelManager.share.stop()
    }
}

extension ConnectWork {
    public static func fire(_ city: Citys_response?) async throws {
        print("🔥 ConnectWork: Static fire method called")
        if let city = city {
            print("🔥 ConnectWork: Using specified city: \(city.city)")
        } else {
            print("🔥 ConnectWork: No city specified, will auto-select")
        }
        
        let work = ConnectWork(city)
        let _: [Citys_response] = try await XCBusiness.share.run(work, returnType: nil)
    }
}



