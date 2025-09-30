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
        try await self.setStatus(.fetchCity)
    }

    func setStatus(_ status: ConnectStatus) async throws {

        self.status = status
        
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
        
        let city: Citys_response
        if let c = self.city {
            city = c
        } else {
            let citys_result = try await CitysRequestWork.fire()
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
        try await self.setStatus(.fetchNode(
            context: .init(nodes: [],city: city, node: nil, retry: 1, node_index: 0)
        ))
    }
    
    func fetchNode(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        let nodes_result = try await NodeRequestWork.fire(
            city_id: context.city.id,
            retry: context.retry
        )
        // 节点为空时，尝试从 GitHub 获取
        if nodes_result.isEmpty {
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
            var ctx = context
            ctx.retry += 1
            ctx.node_index = 0
            try await self.setStatus(.fetchNode(context: ctx))
            return
        }
        
        let node = nodes_result[context.node_index]
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
        
        let nodes_result = try await NodeGetGithubWork.fire()
        if nodes_result.isEmpty {
            try await self.setStatus(.faile(context: context))
            return
        }
        if nodes_result.count <= context.node_index {
            try await self.setStatus(.faile(context: context))
            return
        }
        let node = nodes_result[context.node_index]
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
            throw NSError(domain: "node encode error", code: -1)
        }
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        let data = try encoder.encode(node)
        guard let jsonStr = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "node encode error", code: -1)
        }
        
        // 启动连接任务
        let connectTask = Task {
            try await XCTunnelManager.share.connect(jsonStr)
        }
        
        // 使用 TaskGroup 来处理超时和状态监听
        try await withThrowingTaskGroup(of: Void.self) { group in
            // 添加超时任务
            group.addTask {
                try await Task.sleep(for: .seconds(30)) // 30秒超时
                throw NSError(domain: "VPN connection timeout", code: -2)
            }
            
            // 添加状态监听任务
            group.addTask {
                // 监听 VPN 状态变化，添加超时保护
                for await vpnStatus in NEVPNStatus.asyncStream() {
                    // 检查任务是否被取消
                    try Task.checkCancellation()
                    
                    switch vpnStatus {
                    case .connected:
                        try await self.setStatus(.test_network(context: context))
                        return
                    case .disconnected, .disconnecting:
                        try await self.setStatus(.faile(context: context))
                        return
                    case .connecting:
                        continue
                    default:
                        continue
                    }
                }
            }
            
            // 等待第一个完成的任务
            try await group.next()
            
            // 取消其他任务
            group.cancelAll()
            connectTask.cancel()
        }
    }

    func test_network(context: ConnectContext) async throws {
        // 检查任务是否被取消
        try Task.checkCancellation()
        
        // 为网络测试添加超时保护
        let result = try await withThrowingTaskGroup(of: Bool.self) { group in
            // 添加超时任务
            group.addTask {
                try await Task.sleep(for: .seconds(15)) // 15秒超时
                throw NSError(domain: "Network test timeout", code: -3)
            }
            
            // 添加网络测试任务
            group.addTask {
                return await ConnectSuccess.isSuccess()
            }
            
            // 等待第一个完成的任务
            let result = try await group.next()
            
            // 取消其他任务
            group.cancelAll()
            
            return result ?? false
        }
        
        if result {
            try await self.setStatus(.connect(context: context))
        } else {
            var ctx = context
            ctx.node = nil
            if ctx.nodes.isEmpty {
                ctx.retry = 1
                ctx.node_index = 0
                try await self.setStatus(.fetchGithubNode(context: ctx))
            } else {
                if ctx.node_index + 1 >= ctx.nodes.count {
                    ctx.retry += 1
                    ctx.node_index = 0
                } else {
                    ctx.node_index += 1
                }
                try await self.setStatus(.fetchNode(context: ctx))
            }
        }
    }

    func connect(context: ConnectContext) async throws {
        await XCTunnelManager.share.setStatus(.realConnected)
    }
    
    func faile(context: ConnectContext) async throws {
        await XCTunnelManager.share.setStatus(.realFaile)
        try await XCTunnelManager.share.stop()
    }
}
