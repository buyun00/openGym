import Foundation
import HealthKit
import Security
import Observation
import SwiftUI

private struct BodySyncError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

private struct BodyHookConnection: Codable {
    var base: String
    var token: String
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.lin0.opengym.body-hook", kSecAttrAccount as String: "hook-v1"]
    }
    static func load() throws -> Self? {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &value)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = value as? Data else {
            throw BodySyncError(message: "请解锁设备后读取身体同步凭据。")
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws {
        let attrs: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(self),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(Self.query as CFDictionary, attrs as CFDictionary)
        if result == errSecItemNotFound {
            guard SecItemAdd(Self.query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw BodySyncError(message: "未能保存 Hook 凭据。")
            }
        } else if result != errSecSuccess { throw BodySyncError(message: "未能保存 Hook 凭据。") }
    }
}

private final class BodyHookNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
@Observable
final class BodyHealthSync {
    static let shared = BodyHealthSync()
    var status = "由快捷指令定时打开 App，同步当天身体数据。"
    var busy = false
    private let health = HKHealthStore()
    private let session = URLSession(configuration: .ephemeral, delegate: BodyHookNoRedirect(), delegateQueue: nil)
    private let metrics: [(HKQuantityType, HKUnit, String)] = [
        (HKQuantityType(.bodyMass), .gramUnit(with: .kilo), "weight_kg"),
        (HKQuantityType(.bodyFatPercentage), .percent(), "body_fat_pct"),
        (HKQuantityType(.leanBodyMass), .gramUnit(with: .kilo), "lean_mass_kg")
    ]

    func configure(base: String, token: String) {
        do {
            let base = try GymCloudSync.normalize(base)
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !token.contains(where: { $0.isNewline }) else {
                throw BodySyncError(message: "请输入现有快捷指令使用的 WEIGHT_HOOK_TOKEN。")
            }
            try BodyHookConnection(base: base, token: token).save()
            status = "Hook 凭据已安全保存，可以同步。"
        } catch { status = error.localizedDescription }
    }

    func upload() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            guard let connection = try BodyHookConnection.load() else {
                throw BodySyncError(message: "请先在「数据同步 → 身体数据快捷指令」配置 Hook 地址与令牌。")
            }
            guard HKHealthStore.isHealthDataAvailable() else { throw BodySyncError(message: "此设备不支持健康数据。") }
            status = "正在读取健康数据"
            try await health.requestAuthorization(toShare: [], read: Set(metrics.map { $0.0 as HKObjectType }))
            // Match the existing hook's Asia/Shanghai date contract; never relabel an old sample as today.
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let end = Date(), start = calendar.startOfDay(for: end)
            let formatter = DateFormatter()
            formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
            var payload: [String: Any] = ["date": formatter.string(from: end)]
            for (type, unit, key) in metrics {
                if let sample = try await latest(type, start: start, end: end) {
                    let raw = sample.quantity.doubleValue(for: unit)
                    let value = key == "body_fat_pct" ? raw * 100 : raw
                    if value.isFinite && value > 0 { payload[key] = value }
                }
            }
            guard payload.count > 1 else {
                throw BodySyncError(message: "今天没有可读取的身体样本。请检查健康权限或稍后重试；未上传空值。")
            }
            var request = URLRequest(url: URL(string: connection.base + "/api/hook/body")!, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("Bearer " + connection.token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            status = "正在上传身体数据"
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let result = try JSONSerialization.jsonObject(with: data) as? [String: Any], result["ok"] as? Bool == true else {
                throw BodySyncError(message: "上传未确认成功（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)），请检查 Hook 配置并重试。")
            }
            status = "身体数据已上传 · \(formatter.string(from: end))"
            return true
        } catch { status = error.localizedDescription; return false }
    }

    private func latest(_ type: HKQuantityType, start: Date, end: Date) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let gate = BodySampleGate(continuation)
            let query = HKSampleQuery(sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate]),
                limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                    if let error { gate.resolve(.failure(error)) }
                    else { gate.resolve(.success(samples?.first as? HKQuantitySample)) }
                }
            health.execute(query)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if gate.resolve(.failure(BodySyncError(message: "健康数据读取超时，请重试。"))) { self.health.stop(query) }
            }
        }
    }
}

private final class BodySampleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HKQuantitySample?, Error>?
    init(_ continuation: CheckedContinuation<HKQuantitySample?, Error>) { self.continuation = continuation }
    @discardableResult func resolve(_ result: Result<HKQuantitySample?, Error>) -> Bool {
        lock.lock(); let pending = continuation; continuation = nil; lock.unlock()
        pending?.resume(with: result)
        return pending != nil
    }
}

struct BodySyncSettings: View {
    @Environment(GymStore.self) private var store
    @State private var base = GymCloudSync.defaultServer
    @State private var token = ""
    private var sync: BodyHealthSync { .shared }
    var body: some View {
        Section("身体数据快捷指令") {
            Text("每天定时打开 opengym://sync-body，读取当天体重、体脂率和去脂体重并上传。首次使用请在解锁状态授权健康读取。")
                .font(.footnote)
            TextField("HTTPS 地址（以 /gym 结尾）", text: $base).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("WEIGHT_HOOK_TOKEN", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("保存 Hook 配置") { sync.configure(base: base, token: token); token = "" }.disabled(sync.busy)
            Button("立即同步身体数据") {
                Task { if await sync.upload() { await store.cloud.sync(store: store) } }
            }.disabled(sync.busy)
            Text(sync.status).font(.footnote).foregroundStyle(.secondary)
            Text("仅使用已有 Hook 的专用令牌；按 Hook 配置的账号上传。原来的快捷指令 POST 上传仍然可用。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
