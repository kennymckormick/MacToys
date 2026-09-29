# Portman

MacToys 内置的端口转发模块。Python 3.9+，仅使用标准库和系统 OpenSSH。

## 命令行

在本目录运行 `python3 -m portman -h`；或 `python3 -m pip install .` 后使用 `portman`。

```sh
# 本机 TCP 转发
portman add api --listen 18080 --target localhost:8080

# SSH 本地转发：本机 :18000 → my-server 侧 localhost:8000
portman add notebook --via my-server --listen 18000 --target localhost:8000

# SSH 反向转发：my-server 侧 :13000 → 本机 :3000
portman add preview --mode ssh-remote --via my-server \
  --listen 127.0.0.1:13000 --target localhost:3000

portman list
portman edit notebook --listen 18001
portman stop notebook
portman start notebook
portman restart notebook
portman logs notebook
portman check notebook --http-path /
portman remove notebook
portman gui
```

`my-server` 是示例 SSH 别名，使用前替换为自己的主机。`portman hosts` 读取已有别名。所有命令支持 `--json`；`add --no-start` 只保存配置。

GUI 与 CLI 共用本机后台。关闭页面不停止转发；`portman daemon stop` 停止当前实例的后台和所有转发，下次启动恢复已启用记录。不会接管、关闭其他工具的 SSH master 或抢占已被占用的端口。

## 运行边界

- 仅支持 TCP，不含 UDP、SOCKS、NAT / UPnP 或防火墙配置。
- SSH 使用系统配置、已信任的主机密钥和现有密钥 / agent；不保存密码。每条转发使用独立连接及私有控制 socket。
- 默认只监听 loopback；反向监听受服务端 GatewayPorts 等设置约束，不修改服务端配置。
- `running` 表示监听 / SSH 转发已建立，并不代表目标应用健康。`check --http-path /` 分别报告传输结果和 HTTP 状态。
- 断线按 1、2、4、8、16、30 秒退避重连；停止的映射不会自行重连。
- 状态目录默认 `~/.local/state/portman`；配置原子保存。`runtime.json` 含管理 token，不应公开。管理 API 校验 token、Host、Origin，不允许跨域。
- 每条映射最多两个 256 KiB 日志；后台诊断日志启动时按 1 MiB 轮换。
- `--home PATH` 或 `PORTMAN_HOME` 指定隔离实例。没有自动添加登录启动项。

## 验证

```sh
python3 -m unittest discover -s tests -v
node --check portman/static/app.js
```

集成测试使用临时目录、loopback 端口和临时 SSH 密钥 / 服务，不修改已有映射或 SSH 配置。完整 SSH 测试需要本机 `/usr/sbin/sshd`。
