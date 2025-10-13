import Testing
import Foundation
@testable import XCBusiness
@testable import XCNetwork
@testable import XCCache
@testable import Alamofire

@Test func example() async throws {
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}

@Test("set_network")
func setNetwork() async throws {
    try await XCNetwork.share.setEnDe(.init(key: "kJolMg7JMLK2nJ31oK6P5+okn26aoJmKRwMX5GOynz0=", iv: "YC3IYFlVgc7kPlAAWTvPmw=="))
    try await XCNetwork.share.setIpconfig(.init(url_1: "SZtor7k74u4prgV/wb92JIf84RkO0pSrqYAlOG73/tk=", url_2: "nMvzOk4mW4Nq5H3ZQL+0fYnRqoTzEbgrkApOMF79Tnk=", url_3: ""))
    try await XCNetwork.share.setUA(.init(ua: "PMZz9g1hVUSbc8TOzpN8rf0mN1Khi1S+/qPSBrDUH9rXyg2cCIWBsWi6yj6iJrl3lwe/BLDzUV6tqRANXbEOQjTUElKRswqCsPUay8Ffq3ixBdiZuyUXgcgcVRbIkUT+mm4nW6Fv/MV2/DCxSIU0QE/w0Yvji3/uflgtUt31R6A="))
    try await XCNetwork.share.setHttpApi(
        .init(
            host: "7fQeVDwzefo4ZaLRqKbH3YxHx6LG1D7I3bV3uUoyY/GyD3n9qS406dFg72tSLoNKMccTr0QlmRizKh90bE7HMCVmXbVPH3RqryyDJFxM55s=",
            citys: "G+kcAB4Q2u5RJVPCYvarQQ==",
            global_config: "Pbb0c4kHsxFaeVAkO35Ukw==",
            node: "Ltq0HEyzSjhnAUNbeTIRLw==",
            report: "a4/1T8A8xmtmumoF98xY8w=="
        )
    )
    try await XCNetwork.share.setUD(.init(first_install_time: "X/qc0jEzO6OzCNueV3KezSbb7T3pSu/jrQtjr3I/kX0=", last_update_time: "xB2Nh3ACwkmx0Fld9WLk/RYQVrf4Xy6THFTXddlNAXQ="))
    try await XCNetwork.share.setKeyChain(.init(key_uuid: "mnCm0wLU/h33Tk+O445HRz2+T/NzQePrVAYU5FOnzRg="))
    try await XCNetwork.share.setAppGroups(.init(id: "BiAg8f2bX/ANU8J8Ngd+iZQequSB8dHbXgJ2a5XNrAGDdHRTECik/Ch2Zeld5qHp"))
    await XCNetwork.share.setCache_decrypt_data_preprocessor(.init())
    await XCNetwork.share.setCache_encrypt_data_preprocessor(.init())
    await XCNetwork.share.setNEDataPreprocessor(.init())
    await XCNetwork.share.setNERequestInterceptor(.init())
}

@Test("host")
func host() async throws {
    try await setNetwork()
    let work = HostRequestWork()
    let result = try await XCBusiness.share.run(work, returnType: Host_response.self)
    alog(result)
}

@Test("citys")
func citys() async throws {
    try await setNetwork()
    let work = CitysRequestWork()
    let result = try await XCBusiness.share.run(work, returnType: Citys_response.self)
    alog(result)
}

@Test("global_config")
func global_config() async throws {
    try await setNetwork()
    let work = GlobalConfigRequestWork()
    let result = try await XCBusiness.share.run(work, returnType: Global_config_response.self)
    alog(result)
}

@Test("ipconfig")
func ipconfig() async throws {
    try await setNetwork()
    let work = IpconfigRequestWork()
    let result_1 = try? await XCBusiness.share.run(work, returnType: Ip_api_response.self)
    let result_2 = try? await XCBusiness.share.run(work, returnType: Ip_info_response.self)
    if (result_1?.isEmpty ?? true) == true && (result_2?.isEmpty ?? true) == true {
        throw NSError.init(domain: "err", code: -1)
    }
    alog(1)
}

@Test("nodes")
func nodes() async throws {
    try await setNetwork()
    let citys_work = CitysRequestWork()
    let citys_result = try await XCBusiness.share.run(citys_work, returnType: Citys_response.self)
    guard let city_id = citys_result.first?.id else {
        throw NSError.init(domain: "err", code: -1)
    }
    let work = NodeRequestWork(city_id: city_id)
    let result = try await XCBusiness.share.run(work, returnType: Node_response.self)
    alog(result)
}

@Test("report")
func report() async throws {
    try await setNetwork()
    
    let citys_work = CitysRequestWork()
    let citys_result = try await XCBusiness.share.run(citys_work, returnType: Citys_response.self)
    guard let city_id = citys_result.first?.id else {
        throw NSError.init(domain: "err", code: -1)
    }
    
    let node_work = NodeRequestWork(city_id: city_id)
    let node_result = try await XCBusiness.share.run(node_work, returnType: Node_response.self)
    guard let node = node_result.first else {
        throw NSError.init(domain: "err", code: -1)
    }
    
    let report_work = ReportRequestWork(name: node.name, retry: 0, core: node.core, agreement: node.agreement, event: "connect")
    let _:[Node_response] = try await XCBusiness.share.run(report_work, returnType: nil)
    alog(1)
}

@Test("urls_test")
func urls_test() async throws {
    try await setNetwork()
    let result = await ConnectSuccess.isSuccess()
    alog(result)
}

@Test("chose_city")
func chose_city() async throws {
    try await setNetwork()
    let citys_work = CitysRequestWork()
    let citys_result = try await XCBusiness.share.run(citys_work, returnType: Citys_response.self)
    guard let city = citys_result.first else {
        throw NSError.init(domain: "err", code: -1)
    }
    
    let chose_city_work = CityChoseWork(city: city)
    let _:[Citys_response] = try await XCBusiness.share.run(chose_city_work, returnType: nil)
    alog(1)
}

@Test("chose_node")
func chose_node() async throws {
    try await setNetwork()
    let citys_work = CitysRequestWork()
    let citys_result = try await XCBusiness.share.run(citys_work, returnType: Citys_response.self)
    guard let city = citys_result.first else {
        throw NSError.init(domain: "err", code: -1)
    }
    
    let chose_city_work = CityChoseWork(city: city)
    let _:[Citys_response] = try await XCBusiness.share.run(chose_city_work, returnType: nil)
    
    let nodes_work = NodeRequestWork(city_id: city.id)
    let nodes_result = try await XCBusiness.share.run(nodes_work, returnType: Node_response.self)
    guard let node = nodes_result.first else {
        throw NSError.init(domain: "err", code: -1)
    }
    
    let chose_node_work = NodeChoseWork(node: node)
    let _:[Node_response] = try await XCBusiness.share.run(chose_node_work, returnType: nil)
    alog(1)
}

@Test("get_city")
func get_city() async throws {
    try await setNetwork()
    let get_city_work = CityGetWork()
    let city_result = try await XCBusiness.share.run(get_city_work, returnType: Citys_response.self)
    guard let city = city_result.first else {
        throw NSError.init(domain: "err", code: -1)
    }
    alog(city)
}

@Test("get_node")
func get_city() async throws {
    try await setNetwork()
    let get_node_work = NodeGetWork()
    let node_result = try await XCBusiness.share.run(get_node_work, returnType: Node_response.self)
    guard let node = node_result.first else {
        throw NSError.init(domain: "err", code: -1)
    }
    alog(node)
}
