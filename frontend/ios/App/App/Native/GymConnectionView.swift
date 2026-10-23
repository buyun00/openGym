import SwiftUI

struct GymConnectionView: View {
    @Environment(GymStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var server = GymCloudSync.defaultServer
    @State private var code = ""
    @State private var confirmDownload = false

    var body: some View {
        Form {
            Section("同一账户 · 同一份数据") {
                Text("连接后会先下载网页上的计划、训练、体重、围度和器械。之后自动同步修改，离线记录保存在此设备。")
                Text("首次连接前的本机训练数据会另存备份，以网页账户为准。正在进行的训练留在当前设备。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("连接状态") {
                if store.cloud.connected {
                    LabeledContent("账户", value: store.cloud.accountName)
                    Text(store.cloud.server).font(.footnote).textSelection(.enabled)
                }
                Label(store.cloud.status, systemImage: store.cloud.busy ? "arrow.triangle.2.circlepath" : "icloud")
                if let date = store.cloud.lastSync {
                    LabeledContent("最近同步") { Text(date, format: .dateTime.month().day().hour().minute()) }
                }
                if let error = store.cloud.errorMessage { Text(error).foregroundStyle(.red) }
                if store.cloud.connected {
                    Button("立即同步") { Task { await store.cloud.sync(store: store) } }.disabled(store.cloud.busy)
                    Button("重新下载网页数据") { confirmDownload = true }.disabled(store.cloud.busy)
                }
            }
            Section(store.cloud.connected ? "重新配对" : "连接网页账户") {
                TextField("服务器网页地址", text: $server)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("打开网页，获取配对码") {
                    if let base = try? GymCloudSync.normalize(server), let url = URL(string: base + "/") { openURL(url) }
                }
                Text("在网页登录你原来的账户，打开设置 → 配对移动 App，将有效期内的配对码填在下面。")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("配对码", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("连接并下载") {
                    Task { await store.cloud.connect(server: server, code: code, store: store); code = "" }
                }.disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.cloud.busy)
            }
            Section {
                Text("饮水与服用提醒目前保存在此设备；现有网页尚无这些功能。它们不会被训练数据同步覆盖。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("网页账户与同步")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { server = store.cloud.server }
        .confirmationDialog("用网页数据更新此设备？", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("备份本机副本并下载网页数据") { Task { await store.cloud.downloadServerCopy(store: store) } }
        } message: { Text("尚未同步的训练修改会另存本机备份，然后显示网页最新数据。网页数据不会被改动。") }
    }
}
