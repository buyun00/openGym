import Foundation
import JavaScriptCore
import Observation
import Security

private struct GymSyncError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

private struct GymConnection: Codable {
    var base: String
    var token: String
    var userID: String
    var name: String
}

private enum GymKeychain {
    static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.lin0.opengym.sync", kSecAttrAccount as String: "connection-v1"]

    static func load() throws -> GymConnection? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw GymSyncError(message: "暂时无法读取连接凭据，请解锁设备后重试。")
        }
        return try JSONDecoder().decode(GymConnection.self, from: data)
    }

    static func save(_ connection: GymConnection) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(connection),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw GymSyncError(message: "连接凭据未能安全保存，请重试。")
            }
        } else if status != errSecSuccess { throw GymSyncError(message: "连接凭据未能安全保存，请重试。") }
    }
}

// Never forward a bearer credential to a redirect destination or accept an HTML login page.
private final class GymNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
@Observable
final class GymCloudSync {
    static let defaultServer = "https://h3.lin0.org/gym"
    var server = defaultServer
    var status = "正在连接个人数据"
    var errorMessage: String?
    var busy = false
    var connected = false
    var lastSync: Date?
    @ObservationIgnored private var connection: GymConnection?
    @ObservationIgnored private var cache: Cache?
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var bridge: JSContext?
    @ObservationIgnored private var storageError: String?
    @ObservationIgnored private let session = URLSession(configuration: .ephemeral, delegate: GymNoRedirect(), delegateQueue: nil)

    // One atomic file owns both the last downloaded baseline and the pending local snapshot.
    // A process kill cannot advance the baseline while leaving an older local snapshot behind.
    private struct Cache: Codable {
        var base: String
        var userID: String
        var remote: Data
        var baseline: Data
        var local: GymStore.Snapshot
        var syncedAt: Date?
    }
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("openGym", isDirectory: true)
    }
    private var cacheURL: URL { directory.appendingPathComponent("gym-cloud-cache.json") }
    var ownsCache: Bool { connection != nil && cache != nil }

    func restore(into store: GymStore) {
        storageError = nil
        do {
            let savedConnection = try GymKeychain.load()
            guard let url = Bundle.main.url(forResource: "GymPersonalConnection", withExtension: "json") else {
                throw GymSyncError(message: "安装包缺少个人连接配置，请在 Xcode 配置后重新安装。")
            }
            var personal = try JSONDecoder().decode(GymConnection.self, from: Data(contentsOf: url))
            personal.base = try Self.normalize(personal.base)
            guard !personal.userID.isEmpty, personal.token.hasPrefix("ios:") else {
                throw GymSyncError(message: "安装包的个人连接配置无效，请重新配置后安装。")
            }
            if let savedConnection, savedConnection.userID != personal.userID || savedConnection.base != personal.base {
                throw GymSyncError(message: "连接配置与本机数据来源不一致，已保留原文件，未上传。")
            }
            // The private build configuration also replaces a revoked credential on reinstall.
            try GymKeychain.save(personal)
            connection = personal
            if let connection {
                connected = true; server = connection.base
                if FileManager.default.fileExists(atPath: cacheURL.path) {
                    let saved = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: cacheURL))
                    guard saved.userID == connection.userID, saved.base == connection.base else {
                        throw GymSyncError(message: "本机缓存与连接配置不一致，已保留原文件，未上传。")
                    }
                    cache = saved; store.apply(snapshot: saved.local); lastSync = saved.syncedAt
                }
                status = "等待同步"
            }
        } catch { storageError = error.localizedDescription; errorMessage = error.localizedDescription; status = "连接数据未能读取" }
    }

    static func normalize(_ text: String) throws -> String {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: input.contains("://") ? input : "https://" + input),
              parts.scheme == "https", parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            throw GymSyncError(message: "请输入完整 HTTPS 网页地址，例如 https://h3.lin0.org/gym。")
        }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        guard let value = parts.url?.absoluteString else { throw GymSyncError(message: "服务器地址无效。") }
        return value
    }

    func persistLocal(_ snapshot: GymStore.Snapshot) throws {
        guard var next = cache else { throw GymSyncError(message: "尚未下载网页数据。") }
        next.local = snapshot
        try persist(next)
        status = "本机已保存，等待同步"
    }

    func schedule(store: GymStore) {
        guard ownsCache else { return }
        scheduled?.cancel()
        scheduled = Task { [weak self, weak store] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, let store else { return }
            self.scheduled = nil
            await self.sync(store: store)
        }
    }

    func sync(store: GymStore) async {
        guard !busy else { return }
        if connection == nil || storageError != nil { restore(into: store) }
        guard connection != nil else { return }
        busy = true; errorMessage = nil; status = "正在同步"
        defer { busy = false }
        do { try await exchange(store: store) }
        catch { errorMessage = error.localizedDescription; status = "未同步 · 本机记录已保留" }
    }

    private func exchange(store: GymStore) async throws {
        if let storageError { throw GymSyncError(message: storageError) }
        await store.refreshWorkoutHealth()
        guard var auth = connection else { return }
        let me = try await request(base: auth.base, path: "/api/me", token: auth.token)
        guard let user = me["user"] as? [String: Any], user["id"] as? String == auth.userID else {
            throw GymSyncError(message: "服务器返回的数据来源与连接配置不一致，未上传。")
        }
        if let token = me["token"] as? String { auth.token = token; try GymKeychain.save(auth); connection = auth }
        // Revision races are bounded. Each retry fetches the latest state and repeats the
        // three-way merge; it never retries a stale whole-document overwrite.
        for _ in 0..<3 {
            let response = try await request(base: auth.base, path: "/api/data", token: auth.token)
            let remote = try state(from: response)
            let projected = try call("projection", [remote, catalogue])
            if cache == nil {
                // First connection is download-only. Archive even a nonempty local account,
                // then adopt the server. No blank/default native state can be uploaded here.
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let backup = directory.appendingPathComponent("before-cloud-\(UUID().uuidString).json")
                try JSONEncoder().encode(store.snapshot()).write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen])
                let adopted = try decodeSnapshot(projected, keeping: nil)
                try persist(Cache(base: auth.base, userID: auth.userID, remote: try data(remote), baseline: try data(projected), local: adopted, syncedAt: Date()))
                store.apply(snapshot: adopted); status = "已与网页同步"; lastSync = Date()
                return
            }
            guard let saved = cache else { return }
            let local = try snapshotObject(store.snapshot())
            let baseline = try object(saved.baseline)
            let prepared = try call("prepare", [baseline, local, remote, catalogue])
            if prepared["changed"] as? Bool == true {
                guard let rev = response["rev"] as? Int else { throw GymSyncError(message: "服务器缺少数据版本，未上传。") }
                var body: [String: Any] = ["state": prepared["state"] ?? remote, "baseRev": rev]
                if let wid = remote["_wid"] as? String { body["baseWid"] = wid }
                let result = try await request(base: auth.base, path: "/api/data", token: auth.token, method: "PUT", body: body, allowConflict: true)
                if result["conflict"] as? Bool == true { continue }
                guard result["ok"] as? Bool == true else { throw GymSyncError(message: "服务器未确认保存，本机修改已保留。") }
                // An edit may happen while the upload is in flight. Rebase those newer local
                // edits over the actual readback, and retain them in the same atomic cache.
                let readback = try await request(base: auth.base, path: "/api/data", token: auth.token)
                let actual = try state(from: readback)
                let pending = try call("prepare", [local, try snapshotObject(store.snapshot()), actual, catalogue])
                let view = pending["snapshot"] as? [String: Any] ?? [:]
                let next = try decodeSnapshot(view, keeping: store.snapshot())
                let downloaded = try call("projection", [actual, catalogue])
                try persist(Cache(base: auth.base, userID: auth.userID, remote: try data(actual), baseline: try data(downloaded), local: next, syncedAt: Date()))
                store.apply(snapshot: next)
                if pending["changed"] as? Bool == true { status = "新修改等待同步"; schedule(store: store) }
                else { status = "已与网页同步" }
            } else {
                let next = try decodeSnapshot(projected, keeping: store.snapshot())
                try persist(Cache(base: auth.base, userID: auth.userID, remote: try data(remote), baseline: try data(projected), local: next, syncedAt: Date()))
                store.apply(snapshot: next); status = "已与网页同步"
            }
            lastSync = Date(); return
        }
        throw GymSyncError(message: "网页数据正在变化，本机修改已保留，请稍后同步。")
    }

    // Explicit conflict recovery preserves the pending native copy before adopting the server.
    func downloadServerCopy(store: GymStore) async {
        guard let auth = connection, !busy else { return }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            if let storageError { throw GymSyncError(message: storageError) }
            let response = try await request(base: auth.base, path: "/api/data", token: auth.token)
            let remote = try state(from: response), projected = try call("projection", [remote, catalogue])
            let backup = directory.appendingPathComponent("before-redownload-\(UUID().uuidString).json")
            try JSONEncoder().encode(store.snapshot()).write(to: backup, options: [.atomic, .completeFileProtectionUnlessOpen])
            let next = try decodeSnapshot(projected, keeping: store.snapshot())
            try persist(Cache(base: auth.base, userID: auth.userID, remote: try data(remote), baseline: try data(projected), local: next, syncedAt: Date()))
            store.apply(snapshot: next); lastSync = Date(); status = "已下载网页数据；旧本机副本已备份"
        } catch { errorMessage = error.localizedDescription }
    }

    private func persist(_ next: Cache) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: cacheURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        cache = next
    }

    private var catalogue: [String: [String: String]] {
        Dictionary(uniqueKeysWithValues: Catalogue.exercises.map { ($0.id, ["name": $0.name, "mode": $0.workoutMode.rawValue]) })
    }
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
    private func object(_ value: Data) throws -> [String: Any] {
        guard let result = try JSONSerialization.jsonObject(with: value) as? [String: Any] else { throw GymSyncError(message: "同步数据格式无效。") }
        return result
    }
    private func snapshotObject(_ snapshot: GymStore.Snapshot) throws -> [String: Any] {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        return try object(encoder.encode(snapshot))
    }
    private func decodeSnapshot(_ value: [String: Any], keeping local: GymStore.Snapshot?) throws -> GymStore.Snapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        var snapshot = try decoder.decode(GymStore.Snapshot.self, from: data(value))
        snapshot.active = local?.active // Running workouts remain device-local, just like the web client.
        return snapshot
    }
    private func call(_ name: String, _ arguments: [Any]) throws -> [String: Any] {
        if bridge == nil {
            guard let context = JSContext(), let url = Bundle.main.url(forResource: "GymSyncBridge", withExtension: "js") else {
                throw GymSyncError(message: "App 缺少同步组件，请更新安装包。")
            }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8)); bridge = context
        }
        guard let context = bridge else { throw GymSyncError(message: "同步组件不可用。") }
        context.exception = nil
        let result = context.objectForKeyedSubscript("GymSyncBridge")?.forProperty(name)?.call(withArguments: arguments)
        if let exception = context.exception { throw GymSyncError(message: exception.toString() ?? "数据转换失败，未上传。") }
        guard let value = result?.toDictionary() as? [String: Any] else { throw GymSyncError(message: "数据转换失败，未上传。") }
        return value
    }
    private func state(from response: [String: Any]) throws -> [String: Any] {
        if response["state"] is NSNull { return ["unit": "kg", "routines": [], "workouts": [], "bodyweight": [], "measurements": []] }
        guard let state = response["state"] as? [String: Any] else { throw GymSyncError(message: "服务器没有返回个人数据。") }
        for key in ["routines", "workouts", "bodyweight", "measurements"] {
            if let value = state[key], !(value is NSNull), !(value is [Any]) { throw GymSyncError(message: "服务器记录格式异常，未上传。") }
        }
        return state
    }
    private func request(base: String, path: String, token: String?, method: String = "POST",
                         body: [String: Any]? = nil, allowConflict: Bool = false) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw GymSyncError(message: "服务器地址无效。") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: body == nil ? 20 : 60)
        request.httpMethod = body == nil ? "GET" : method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try data(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GymSyncError(message: "服务器没有响应。") }
        if http.statusCode == 409 && allowConflict { return ["conflict": true] }
        if http.statusCode == 401 || http.statusCode == 403 { throw GymSyncError(message: "个人连接凭据已失效，请更新安装包中的连接配置。本机记录已保留。") }
        guard (200..<300).contains(http.statusCode) else { throw GymSyncError(message: "服务器返回 HTTP \(http.statusCode)，请稍后重试。") }
        return try object(bytes)
    }
}
