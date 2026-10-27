import SwiftUI

struct GymConnectionView: View {
    @Environment(GymStore.self) private var store
    @State private var confirmDownload = false

    var body: some View {
        Form {
            BodySyncSettings()
            Section("我的数据") {
                Text("App 自动连接 H3，与网页共用你的计划、训练、体重、围度和器械。修改会自动同步，离线记录保存在此设备。")
                Text("首次启动会先下载网页记录，本机原有数据另存备份。正在进行的训练留在当前设备。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("连接状态") {
                Text(store.cloud.server).font(.footnote).textSelection(.enabled)
                Label(store.cloud.status, systemImage: store.cloud.busy ? "arrow.triangle.2.circlepath" : "icloud")
                if let date = store.cloud.lastSync {
                    LabeledContent("最近同步") { Text(date, format: .dateTime.month().day().hour().minute()) }
                }
                if let error = store.cloud.errorMessage { Text(error).foregroundStyle(.red) }
                Button("立即同步") { Task { await store.cloud.sync(store: store) } }.disabled(store.cloud.busy)
                if store.cloud.connected {
                    Button("重新下载网页数据") { confirmDownload = true }.disabled(store.cloud.busy)
                }
            }
            Section {
                Text("饮水与服用提醒目前保存在此设备；现有网页尚无这些功能。它们不会被训练数据同步覆盖。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("数据同步")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("用网页数据更新此设备？", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("备份本机副本并下载网页数据") { Task { await store.cloud.downloadServerCopy(store: store) } }
        } message: { Text("尚未同步的训练修改会另存本机备份，然后显示网页最新数据。网页数据不会被改动。") }
    }
}
