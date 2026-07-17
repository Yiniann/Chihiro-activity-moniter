# Chihiro Activity Agent

原生 macOS 菜单栏 Agent。它监测本机当前活动，在 Mac 上完成白名单和隐私过滤，然后通过 WebSocket 将最终可公开的状态上报给 Chihiro。

## 隐私边界

- 只读取前台应用的 Bundle ID 和本地名称，用于内存中的白名单匹配
- 非白名单应用不会记录、落盘或上报
- 不读取窗口标题、文件名、网页 URL、输入内容或屏幕画面
- 系统 Now Playing 采集默认关闭，可分别控制是否发布媒体标题和创作者
- 可选发布播放器应用名称和 Bundle ID，不上传 PID
- Agent Token 存在 macOS Keychain，不写入配置文件

## Activity v1

Agent 连接：

```text
wss://example.com/realtime/activity/agent
Authorization: Bearer <ACTIVITY_AGENT_TOKEN>
```

设置页填写完整的 `ws://` 或 `wss://` WebSocket 地址。本地开发默认使用 `ws://127.0.0.1:3001/realtime/activity/agent`。

Token 由 Chihiro 服务端或管理后台生成。服务端保存 Token 后，将同一个值粘贴到 Agent：

```env
ACTIVITY_AGENT_TOKEN="服务端生成的 Token"
```

Agent 在连接时将 Token 保存到 macOS Keychain。只有两端 Token 一致，WebSocket 握手才能通过鉴权；Token 不得出现在博客公开前端。

握手：

```json
{
  "protocol": "activity.v1",
  "type": "agent:hello",
  "agentVersion": "0.1.0",
  "capabilities": ["foreground-application", "now-playing"]
}
```

每次变化或重连时发送完整公开快照：

```json
{
  "protocol": "activity.v1",
  "type": "agent:snapshot",
  "sequence": 42,
  "slots": [
    {
      "id": "foreground",
      "kind": "application",
      "appId": "com.microsoft.VSCode",
      "title": "Visual Studio Code",
      "subtitle": null,
      "source": null
    }
  ]
}
```

没有可公开状态时发送 `"slots": []`。每 30 秒发送 `agent:heartbeat`，连接失败时使用指数退避自动重连。

`appId` 使用 macOS Bundle Identifier，例如 `com.microsoft.VSCode`。应用名称 `title` 只用于展示；Agent 不上传本机应用图标，博客通过 `appId` 匹配自己的静态图标，未知 `appId` 按 `kind` 回退到通用图标。

## 运行

需要 macOS 14+ 和 Xcode 16+。

```bash
swift run ChihiroMonitor
```

构建本机 `.app`：

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Chihiro Monitor.app"
```

Chihiro 服务端需实现 `/realtime/activity/agent`、Token 鉴权、`server:ready` 握手、Redis TTL 和公开订阅广播。Mac Agent 仓库不包含博客接收与展示逻辑。
# Chihiro-activity-moniter
