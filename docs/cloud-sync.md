# Cloud Sync

[English README](../README.md) · [简体中文](#简体中文)

MacToys backs up snapshots to your own **private GitHub repository**, daily or on demand. Uploading updates the cloud snapshot. Restoring is always manual and replaces local data; edits from multiple Macs are not merged.

## Connect

1. Open **Cloud Sync** in the main window. Create a dedicated repository, such as `mactoys-data`, with **Private** visibility. You do not need to add a README.
2. Enter `owner/repository` or its GitHub URL.
3. Click **Authorize on GitHub** to create a fine-grained personal access token. Choose the correct resource owner, **Only select repositories**, and just the backup repository. Grant **Contents: Read and write**; Metadata read access is implicit. No administration or workflow permission is needed.
4. Generate the token, paste it into MacToys, and click **Connect repository**. The token is saved in this Mac's Keychain. It is not included in preferences or backups. This is token authorization, not an OAuth login.

The app checks that the repository is private when connecting, downloading, and uploading. Public and archived repositories are rejected. If the token expires or is revoked, disconnect and connect using a new token. Disconnecting removes the local credential; it does not delete the repository or revoke the token on GitHub.

## Daily backups

Daily automatic backup is enabled by default for a connected private repository. Turn it off in **Cloud Sync → Daily automatic backup** if you prefer manual backups. This choice and the schedule stay on each Mac and are not restored from a backup.

- An empty repository gets its first backup shortly after connecting. Subsequent backups run at **9:00 AM local time** while MacToys is running, including with its windows closed. If the Mac is asleep or MacToys is closed, a missed backup runs shortly after waking or reopening. The app does not wake the computer or install a separate background service.
- Unchanged data is checked without creating a new GitHub commit. Network failures and a locked Keychain retry after 30 minutes, then one, two, four, and at most six hours. Background reads never display a Keychain authorization prompt.
- Automatic uploads only update the cloud revision this Mac last uploaded or explicitly restored. An unfamiliar cloud snapshot pauses automatic uploads unless its contents already match this Mac. This also protects existing backups when upgrading from a version that did not track the cloud revision.
- To resolve that pause, review the backup and choose **Upload backup** to keep this Mac's data in the cloud, or **Restore from cloud** to use the cloud data on this Mac. Daily backups resume after the confirmed operation. There is no automatic download, merge, or forced overwrite.

The settings show the last successful backup check, the next scheduled attempt, and any error requiring attention. Scheduling uses one non-repeating timer and reschedules after waking or changing the clock or time zone.

## Move to another Mac

On the original Mac, choose **Upload backup** and confirm. On the new Mac, connect the same repository with a token authorized for it, choose **Restore from cloud**, inspect the backup date and item counts, and confirm. A new token can be created for each Mac.

Every restore saves the previous local snapshot in `~/Library/Application Support/InputStats/SyncBackups/`. **Restore local backup** can undo a completed restore. A failed restore is rolled back; an interrupted restore leaves `sync-rollback.json`, which the next launch uses to recover the previous state before starting the tools. Keep that file until recovery succeeds.

Concurrent uploads use GitHub's file SHA as a precondition. If another upload changes the backup after you check it, MacToys reports a conflict instead of retrying with an unconditional overwrite. GitHub commit history retains earlier cloud versions.

## Included

- Todo items, completion dates, long-term goals with their current status, and Markdown notes with titles.
- Minute-level input counts, including original legacy corrections. Typed text is never stored in the statistics database.
- Language, Quick Panel tools/default, counting preferences, saved colors, color shortcut, scroll reversal preferences, and Keep Awake preferences.

Portman rules, SSH keys/config, GitHub credentials, system permission grants, launch-at-login registration, and active Keep Awake sessions are not included. Restoring ends any current Keep Awake session without starting a new one. Draft text that has not been saved as a task or goal is not part of the snapshot. Open Notes editors are flushed before backup or restore.

Backups use a versioned JSON file, `mactoys-backup.json`, with a 25 MB limit and up to 250,000 minute records. Future schema versions, malformed records, duplicate identifiers and invalid preferences are rejected before restore. The repository is private, but this is not end-to-end encryption: GitHub and any collaborators you grant repository access can read it. Use a dedicated repository and keep it private.

No service account or MacToys server is involved. Tokens are sent only to `https://api.github.com`; redirects are rejected and the HTTP session does not persist cookies or cache responses.

GitHub documentation: [fine-grained token setup](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens), [repository contents API](https://docs.github.com/en/rest/repos/contents).

## 简体中文

1. 在主窗口打开「云端同步」，创建专用的 **Private** 仓库，例如 `mactoys-data`，不必添加 README。
2. 输入 `用户名/仓库名` 或仓库的 GitHub 网址。
3. 点击「在 GitHub 授权」，创建细粒度访问令牌。选择正确的 Resource owner，选择 **Only select repositories**，只勾选备份仓库，并把 **Contents** 设为 **Read and write**。
4. 把令牌粘贴到 MacToys，点击「连接仓库」。令牌只保存在本机钥匙串，不会写进备份。这一版采用访问令牌授权，不需要注册 OAuth App。
5. 原机器点击「上传备份」。新机器连接同一个仓库后，点击「从云端恢复」，检查备份时间和条目数，再确认恢复。

同步包括：待办与完成记录、长期目标与当前状态、Markdown 笔记与标题、输入统计计数、语言、小菜单、颜色收藏/历史、快捷键和工具偏好。Portman 规则、SSH 密钥、系统授权和登录启动仍由每台机器单独配置。未提交的待办或目标草稿不属于备份；笔记编辑器会在备份或恢复前保存当前内容。

连接私有仓库后，默认开启「每日自动备份」，可在云端同步页面关闭。空仓库会在连接后首次备份，之后在应用运行期间每天本地时间 **9:00** 执行，关闭窗口仍会备份。休眠或退出时错过，会在唤醒或下次启动后补传，不会唤醒电脑，也不会安装独立后台服务。数据未变更时不会重复提交。网络失败或钥匙串锁定后，重试间隔从 30 分钟递增到最多 6 小时；后台不会弹出钥匙串授权框。开关和调度记录只保存在当前 Mac，不参与备份。

自动上传只会更新本机上次上传或确认恢复的云端版本。另一台 Mac 修改了云端，或旧版本升级后尚未记录云端版本时，会暂停上传；本机与云端内容完全一致时可直接确认，无需重复提交。请先检查要保留的数据，再手动「上传备份」或「从云端恢复」，之后自动备份会继续。页面会显示上次检查、下次尝试时间和需要处理的错误。

这是快照备份，不自动下载或合并多台机器的编辑。恢复始终需要确认，会替换本机数据，并结束正在运行的防休眠会话。恢复前会自动保存一份本地备份，之后可用「恢复本地备份」撤回。

本地备份在 `~/Library/Application Support/InputStats/SyncBackups/`。如果恢复中断，下次启动会用 `sync-rollback.json` 回滚到恢复前的状态，不要提前删除它。云端旧版本保留在 GitHub 提交历史中。

每份备份最多 25 MB、250,000 条分钟统计。私有仓库没有端到端加密，GitHub 及有仓库访问权限的协作者可以读取内容，请保持仓库私有。每次上传都会重新检查可见性，云端发生并发修改时会停止覆盖。令牌到期或被撤销后，断开并重新授权即可；断开不会删除云端备份。
