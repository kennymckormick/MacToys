import SwiftUI
import UniformTypeIdentifiers

struct CloudSyncView: View {
    @ObservedObject var store: CloudSyncStore
    @ObservedObject private var language = Localization.shared

    var body: some View {
        Form {
            Section {
                Text(L("云端同步")).font(.title2.bold())
                Text(L("把配置和数据备份到自己的 GitHub 私有仓库，在另一台 Mac 上恢复。仅手动同步，不在后台轮询。"))
                    .foregroundStyle(.secondary)
            }
            if let repository = store.repository {
                Section(L("GitHub 私有仓库")) {
                    HStack {
                        Label(repository.fullName, systemImage: "lock.fill")
                        Spacer()
                        Link(L("打开仓库"), destination: repository.webURL)
                        Button(L("断开连接")) { store.disconnect() }
                    }
                    HStack {
                        Button { store.prepareUpload() } label: { Label(L("上传备份…"), systemImage: "icloud.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                        Button { store.prepareDownload() } label: { Label(L("从云端恢复…"), systemImage: "icloud.and.arrow.down") }
                    }
                    if let last = store.lastSync {
                        LabeledContent(L("上次操作")) { Text(last, format: .dateTime.year().month().day().hour().minute()) }
                    }
                    Text(L("上传会更新云端快照；恢复会替换本机数据，不自动合并。GitHub 会保留以前的提交版本。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Section(L("连接 GitHub")) {
                    HStack {
                        Text(L("1. 创建专用私有仓库"))
                        Spacer()
                        Link(L("创建仓库 ↗"), destination: URL(string: "https://github.com/new?name=mactoys-data&visibility=private")!)
                    }
                    TextField(L("仓库"), text: $store.repositoryDraft, prompt: Text("username/mactoys-data"))
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                    HStack {
                        Text(L("2. 创建仓库访问令牌"))
                        Spacer()
                        Link(L("在 GitHub 授权 ↗"), destination: store.authorizationURL)
                    }
                    Text(L("选择 Only select repositories，并且只选上面的仓库。Contents 权限设为 Read and write，然后生成令牌。"))
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField(L("3. 粘贴访问令牌"), text: $store.tokenDraft)
                        .textFieldStyle(.roundedBorder).onSubmit { store.connect() }
                    HStack {
                        Text(L("令牌只保存在这台 Mac 的钥匙串中，不会进入备份。"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("连接仓库")) { store.connect() }.buttonStyle(.borderedProminent)
                            .disabled(store.tokenDraft.isEmpty || store.repositoryDraft.isEmpty)
                    }
                }
            }
            Section(L("同步内容")) {
                Label(L("待办清单、长期目标与笔记"), systemImage: "checklist")
                Label(L("输入统计历史（仅计数）"), systemImage: "chart.bar")
                Label(L("语言、小菜单、颜色收藏与工具偏好"), systemImage: "slider.horizontal.3")
                Text(L("Portman 规则、SSH 密钥、系统授权、登录启动和正在运行的防休眠会话不参与同步。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("本地备份")) {
                Text(L("每次恢复前，自动保存当前数据。可以随时选取本地备份恢复。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("打开本地备份")) {
                        if FileManager.default.fileExists(atPath: store.backupsDirectory.path) { NSWorkspace.shared.open(store.backupsDirectory) }
                        else { NSWorkspace.shared.open(store.backupsDirectory.deletingLastPathComponent()) }
                    }
                    Button(L("恢复本地备份…")) {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
                        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                        panel.directoryURL = store.backupsDirectory
                        panel.begin { response in
                            if response == .OK, let url = panel.url { store.prepareLocalRestore(url) }
                        }
                    }
                }
            }
            if store.busy {
                HStack { ProgressView().controlSize(.small); Text(L("正在处理…")).foregroundStyle(.secondary) }
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if let message = store.message { Text(message).foregroundStyle(.secondary) }
        }.formStyle(.grouped).disabled(store.busy).environment(\.locale, language.locale)
            .alert(store.confirmation?.isRestore == true ? L("恢复这份备份？") : L("上传本机备份？"),
                   isPresented: Binding(get: { store.confirmation != nil }, set: { if !$0 { store.confirmation = nil } }), presenting: store.confirmation) { action in
                Button(L("取消"), role: .cancel) { store.confirmation = nil }
                Button(action.isRestore ? L("备份本机并恢复") : L("上传")) { store.confirm(action) }
            } message: { action in
                Text(confirmationText(action))
            }
    }

    private func confirmationText(_ action: CloudSyncStore.Confirmation) -> String {
        var text = action.isRestore
            ? L("将替换本机的待办、长期目标、笔记、统计和应用偏好。恢复前会自动备份当前数据，并结束当前防休眠会话。")
            : L("将本机配置和数据上传到私有仓库。已有云端备份会被更新，历史版本仍保留在 GitHub。")
        if let snapshot = action.snapshot {
            text += "\n\n" + L("备份时间：%@", snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
            text += "\n" + L("%@ 项待办 · %@ 个目标 · %@ 篇笔记 · %@ 条分钟统计", String(snapshot.todos.count), String(snapshot.goals.count), String(snapshot.notes.count), String(snapshot.statistics.count))
        }
        return text
    }
}
