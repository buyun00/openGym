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
            let dailyTypes: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.restingHeartRate),
                HKQuantityType(.heartRateVariabilitySDNN), HKCategoryType(.sleepAnalysis)]
            try await health.requestAuthorization(toShare: [], read: Set(metrics.map { $0.0 as HKObjectType }).union(dailyTypes))
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
            for (type, unit, key, options) in [
                (HKQuantityType(.stepCount), HKUnit.count(), "steps", HKStatisticsOptions.cumulativeSum),
                (HKQuantityType(.restingHeartRate), HKUnit.count().unitDivided(by: .minute()), "resting_hr", .discreteAverage),
                (HKQuantityType(.heartRateVariabilitySDNN), HKUnit.secondUnit(with: .milli), "hrv_ms", .discreteAverage)
            ] {
                if let value = try await statistic(type, unit: unit, options: options, start: start, end: end),
                   value.isFinite && value >= 0 { payload[key] = value }
            }
            for (key, value) in Self.sleepSummary(try await sleepSamples(start: start, end: end), start: start, end: end) {
                payload[key] = value
            }
            guard payload.count > 1 else {
                throw BodySyncError(message: "今天没有可读取的身体或健康样本。请检查健康权限或稍后重试；未上传空值。")
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

    private func statistic(_ type: HKQuantityType, unit: HKUnit, options: HKStatisticsOptions,
                           start: Date, end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let gate = BodySampleGate<Double?>(continuation)
            let query = HKStatisticsQuery(quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate]),
                options: options) { _, statistics, error in
                    if let error { gate.resolve(.failure(error)) }
                    else {
                        let quantity = options == .cumulativeSum ? statistics?.sumQuantity() : statistics?.averageQuantity()
                        gate.resolve(.success(quantity?.doubleValue(for: unit)))
                    }
                }
            health.execute(query)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if gate.resolve(.failure(BodySyncError(message: "健康数据读取超时，请重试。"))) { self.health.stop(query) }
            }
        }
    }

    private func sleepSamples(start: Date, end: Date) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let gate = BodySampleGate<[HKCategorySample]>(continuation)
            let query = HKSampleQuery(sampleType: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []),
                limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error { gate.resolve(.failure(error)) }
                    else { gate.resolve(.success(samples as? [HKCategorySample] ?? [])) }
                }
            health.execute(query)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if gate.resolve(.failure(BodySyncError(message: "睡眠数据读取超时，请重试。"))) { self.health.stop(query) }
            }
        }
    }

    // Clip to Shanghai's calendar day and count overlapping sources only once.
    // Detailed stages beat unspecified sleep; later-ending samples break stage conflicts.
    private static func sleepSummary(_ samples: [HKCategorySample], start: Date, end: Date) -> [String: Double] {
        let keys: [Int: String] = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: "asleep_min",
            HKCategoryValueSleepAnalysis.asleepCore.rawValue: "core_min",
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue: "deep_min",
            HKCategoryValueSleepAnalysis.asleepREM.rawValue: "rem_min",
            HKCategoryValueSleepAnalysis.awake.rawValue: "awake_min"]
        let usable = samples.filter { keys[$0.value] != nil && $0.endDate > start && $0.startDate < end }
        let boundaries = Set(usable.flatMap { [max(start, $0.startDate), min(end, $0.endDate)] }).sorted()
        var minutes: [String: Double] = [:]
        guard boundaries.count > 1 else { return [:] }
        for i in 1..<boundaries.count {
            let a = boundaries[i - 1], b = boundaries[i]
            let covering = usable.filter { $0.startDate < b && $0.endDate > a }.sorted {
                let left = $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ? 0 : 1
                let right = $1.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ? 0 : 1
                if left != right { return left > right }
                if $0.endDate != $1.endDate { return $0.endDate > $1.endDate }
                return $0.uuid.uuidString < $1.uuid.uuidString
            }
            if let sample = covering.first, let key = keys[sample.value] {
                minutes[key, default: 0] += b.timeIntervalSince(a) / 60
            }
        }
        let asleep = minutes.filter { $0.key != "awake_min" }.values.reduce(0, +)
        if asleep > 0 { minutes["sleep_hours"] = asleep / 60 }
        return minutes
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

private final class BodySampleGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    @discardableResult func resolve(_ result: Result<Value, Error>) -> Bool {
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
            Text("每天定时打开 opengym://sync-body，读取当天体重、体脂、去脂体重、睡眠分期、步数、静息心率与 HRV 并一次上传。首次使用请在解锁状态授权健康读取。")
                .font(.footnote)
            TextField("HTTPS 地址（以 /gym 结尾）", text: $base).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("WEIGHT_HOOK_TOKEN", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("保存 Hook 配置") { sync.configure(base: base, token: token); token = "" }.disabled(sync.busy)
            Button("立即同步身体数据") {
                Task { if await sync.upload() { await store.cloud.sync(store: store) } }
            }.disabled(sync.busy)
            Text(sync.status).font(.footnote).foregroundStyle(.secondary)
            Text("仅使用已有 Hook 的专用令牌；按 Hook 配置的账号上传。请将旧的「读健康 → POST」快捷指令替换为打开 opengym://sync-body。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
