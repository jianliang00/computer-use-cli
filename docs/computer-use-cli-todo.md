# Computer Use CLI TODO

本文档使用 checkbox 管理实施任务。每完成一个任务，直接勾选对应条目。

## 完成标准

当以下结果全部达成时，本清单完成：

- 能从 `authorized image` 创建 guest
- 能通过 CLI 启动 guest，并在 host 侧连通 guest agent
- 能列出 guest 中运行中的应用
- 能获取 screenshot、AX tree 和 `snapshot_id`
- 能执行 `click`、`type`、`key`、`drag`、`scroll`、`set-value`、`action`
- 权限缺失时能返回明确错误

## 当前验证状态

已通过 `swift test` 验证：

- SwiftPM 工程、库目标、可执行目标和测试目标可编译
- machine metadata 可创建、读取、更新、删除，并能检测 host port 冲突
- `ContainerBridge` 可构造 `container` 生命周期命令、解析 inspect JSON、读取 logs
- `machine create/start/inspect/stop/list/logs/rm` 已接入 metadata 与 bridge
- agent HTTP 协议模型可稳定 encode/decode
- host 侧已具备 Agent HTTP client 与 CLI 转发命令：
  - `agent ping`
  - `agent doctor`
  - `permissions get`
  - `apps list`
  - `state get`
  - `action click/type/key/drag/scroll/set-value/action`
- guest 侧已具备 `computer-use-agent` 可执行入口和 HTTP server/router
- `GET /health`、`GET /permissions`、`GET /apps` 已通过本机 smoke 验证
- `/permissions` 使用 macOS Accessibility 与 Screen Recording API 检测真实授权状态
- `/apps` 使用 `NSWorkspace` 枚举运行中 GUI app，并标记 frontmost app
- `POST /state` 已可通过 ScreenCaptureKit 返回 PNG screenshot，并通过 AX API 返回基础 AX tree
- snapshot cache 已实现最近 8 个 snapshot、60 秒 TTL 和 element_id 绑定
- `click`、`type`、`key`、`drag`、`scroll` 已接入 CoreGraphics 事件执行器
- `set-value` 与 `action` 已通过 snapshot cache 接入 AX 元素执行
- `bootstrap-agent` 可刷新并持久化 bootstrap status JSON
- 已提供 bootstrap LaunchDaemon 与 session LaunchAgent plist 模板
- 已提供 `ComputerUseAgent.app` 打包脚本，并验证 bundle id 为 `io.github.jianliang00.computer-use.agent`
- `scripts/smoke-local-agent-e2e.sh` 已通过本机端到端 smoke：
  - TextEdit：element click、type、Return、set-value、AXRaise action、AX tree 读回 marker
  - Finder：坐标 click、scroll、drag
- 已提供 `scripts/prepare-computer-use-image-context.sh`，可生成 macOS image build context
- 已在克隆 macOS guest 中完成 live install 验证：
  - `ComputerUseAgent.app`、`bootstrap-agent` 与 launchd plists 已安装为 `root:wheel`
  - LaunchDaemon `io.github.jianliang00.computer-use.bootstrap` 已加载，`last exit code = 0`
  - LaunchAgent `io.github.jianliang00.computer-use.agent` 已进入 `gui/501`，`state = running`
  - `GET /health` 返回 `200`
  - `GET /permissions` 返回未授权状态
  - `GET /apps` 能列出 Terminal、Finder、Dock 等运行中 app
  - `/state` 在未授权时返回 `403 permission_denied`
  - `/var/run/computer-use/bootstrap-status.json` 已刷新为 `bootstrapped: true`
- 已基于验证后的临时镜像创建稳定本地基础镜像目录，并已将其打包加载为 `local/macos-base:latest`
- 已构建 `local/computer-use:product`：
  - 通过项目 runtime wrapper inspect 后显示 `darwin/arm64`
  - product OCI 镜像可通过项目 runtime wrapper 启动
  - guest 内安装文件、LaunchDaemon、LaunchAgent 均存在
  - bootstrap LaunchDaemon 已加载，`last exit code = 0`
  - `autoLoginUser` 已配置为 `admin`
  - 因 `/etc/kcpassword` 尚未 seed，启动后没有 `gui/501` 登录会话，session LaunchAgent 未启动
- 已适配当前 macOS runtime 对 `--publish` 的限制：
  - darwin image 创建遇到 `--publish is not supported for --os darwin` 时会自动重试无 publish 创建
  - 无 published port 的 darwin sandbox 会记录 `agentTransport: "container_exec"`
  - host 侧 agent 请求会通过 `container exec <sandbox> curl 127.0.0.1:7777` 转发
- 已通过真实 CLI 验证 `computer-use machine create/start` 可启动 `local/computer-use:product` 并写入 `agentTransport: "container_exec"`

尚未完成：

- 用最新 session agent 重新打包并重新加载本地 `authorized image`，再重跑
  fresh-guest smoke

## 任务清单

- [x] T01 初始化工程骨架
  目标：
  建立 Swift Package、目录结构和测试目标。

  产出：
  - `Package.swift`
  - `Sources/ComputerUseCLI/`
  - `Sources/ContainerBridge/`
  - `Sources/AgentProtocol/`
  - `Sources/BootstrapAgent/`
  - `Sources/ComputerUseAgentApp/`
  - `Sources/ComputerUseAgentCore/`
  - `Tests/...`

  完成标准：
  - `swift build` 成功
  - `swift test` 成功

- [x] T02 定义 machine metadata 模型与本地存储
  目标：
  固定 host 侧 machine 状态的唯一来源。

  产出：
  - `~/.computer-use-cli/machines/<machine-name>/machine.json` 的读写实现
  - metadata model
  - host port 分配与持久化逻辑

  `machine.json` 至少包含：
  - machine name
  - image reference
  - sandbox id
  - allocated host port
  - current status

  完成标准：
  - 可以创建、读取、更新、删除 machine metadata
  - 对同一台 machine 重复执行读取时结果稳定
  - host port 冲突可检测并返回明确错误

- [x] T03 实现 `ContainerBridge`
  目标：
  把所有 `container` 交互收口到一个模块中。

  产出：
  - create sandbox
  - start sandbox
  - inspect sandbox
  - stop sandbox
  - remove sandbox
  - query logs
  - resolve published host port

  完成标准：
  - 有单元测试或最小集成测试覆盖 machine 生命周期主路径
  - 上层 CLI 不直接调用散落的 `container` SDK CLI/API

- [x] T04 实现 machine 命令
  目标：
  打通 guest 生命周期闭环。

  产出：
  - `computer-use machine create --name <name> --image <image>`
  - `computer-use machine start --machine <name>`
  - `computer-use machine inspect --machine <name>`
  - `computer-use machine stop --machine <name>`
  - `computer-use machine rm --machine <name>`
  - `computer-use machine logs --machine <name>`

  完成标准：
  - `machine create` 会创建 metadata 并固定 host port
  - `machine start` 会使用 metadata 中记录的 host port 建立 publish
  - `machine inspect` 能返回 sandbox id、image、host port、status
  - `machine logs` 能返回 container 侧日志位置或内容

- [x] T05 定义 agent HTTP 协议
  目标：
  固定 host 和 guest 之间的通信契约。

  产出：
  - 请求/响应模型
  - 错误码模型
  - JSON 编解码实现

  必须包含的接口模型：
  - `GET /health`
  - `GET /permissions`
  - `GET /apps`
  - `POST /state`
  - `POST /actions/click`
  - `POST /actions/type`
  - `POST /actions/key`
  - `POST /actions/drag`
  - `POST /actions/scroll`
  - `POST /actions/set-value`
  - `POST /actions/action`

  完成标准：
  - 所有模型可稳定 encode/decode
  - CLI 与 agent 共用同一份协议定义

- [x] T06 实现 `ComputerUseAgent.app` 外壳
  目标：
  让 session agent 以固定身份的 app bundle 运行。

  产出：
  - `/Applications/ComputerUseAgent.app`
  - app 启动入口
  - HTTP server
  - 基础日志能力

  固定要求：
  - bundle id 为 `io.github.jianliang00.computer-use.agent`
  - guest 内监听 `127.0.0.1:7777`

  完成标准：
  - app 可在登录用户会话中启动
  - `GET /health` 返回 `200`
  - 日志写入 `/Users/admin/Library/Logs/ComputerUseAgent.log`

- [x] T07 实现权限检测
  目标：
  明确 Accessibility 与 Screen Recording 的可用状态。

  产出：
  - Accessibility 权限检测
  - Screen Recording 权限检测
  - `/permissions` 接口

  完成标准：
  - 能准确返回权限状态
  - 权限缺失时不继续执行动作
  - 错误返回统一使用协议中定义的错误码

- [x] T08 实现 `/apps`
  目标：
  枚举用户会话中的可见应用。

  产出：
  - 运行中应用枚举逻辑
  - `/apps` 接口

  每个应用至少包含：
  - `bundle_id`
  - `name`
  - `pid`
  - `is_frontmost`

  完成标准：
  - `computer-use apps list --machine <name>` 可返回稳定结果
  - frontmost app 能正确标记

- [x] T09 实现 bootstrap agent
  目标：
  为 guest 启动后的状态诊断提供稳定数据源。

  产出：
  - `/usr/local/libexec/computer-use/bootstrap-agent`
  - `/Library/LaunchDaemons/io.github.jianliang00.computer-use.bootstrap.plist`
  - `/var/run/computer-use/bootstrap-status.json`

  bootstrap agent 只做以下事情：
  - 检查用户会话是否就绪
  - 检查 `ComputerUseAgent.app` 是否已启动
  - 写状态文件
  - 写日志

  完成标准：
  - guest 启动后能写出 `bootstrap-status.json`
  - 状态文件至少包含：
    - `bootstrapped`
    - `user`
    - `session_ready`
    - `agent_installed`
    - `agent_running`
    - `agent_port`

- [x] T10 完成镜像安装层
  目标：
  让 product image 启动后具备完整运行条件。

  产出：
  - `images/macos/Dockerfile`
  - session LaunchAgent plist
  - bootstrap LaunchDaemon plist
  - auto-login 配置脚本

  镜像内必须安装：
  - `ComputerUseAgent.app`
  - bootstrap agent
  - launchd plist
  - auto-login 配置

  完成标准：
  - `swift run computer-use runtime container -- build --platform darwin/arm64 -f images/macos/Dockerfile ...` 成功
  - 产物镜像可启动
  - 启动后 `admin` 能自动登录
  - `ComputerUseAgent.app` 会自动启动

  当前状态：
  - 已有 Dockerfile、installer、LaunchDaemon、LaunchAgent 和 image context 准备脚本
  - 已在克隆 guest 中验证 live install、LaunchDaemon、LaunchAgent、HTTP health 和 bootstrap status
  - 已创建稳定本地基础镜像目录，验证 guest agent 可连通，并加载为 `local/macos-base:latest`
  - 已通过项目 runtime wrapper 生成 `local/computer-use:product`
  - `local/computer-use:product` 可通过项目 runtime wrapper 启动
  - product guest 内 bootstrap LaunchDaemon 已加载，安装文件存在
  - 当前 runtime 对 darwin 镜像不支持 `--publish`；host-side 访问路径已改为 `container_exec`
  - 已通过真实 CLI 验证 product machine 可启动，metadata 会记录 `agentTransport: "container_exec"`
  - Dockerfile 现在通过 `configure-autologin.sh admin admin` seed `/etc/kcpassword`
  - `configure-autologin.sh` 现在同时禁用 guest sleep、display sleep 和
    screensaver password prompt，避免切回 VM 后进入锁屏
  - 已验证 product guest 启动后 `admin` 自动登录，`gui/501` 存在，session LaunchAgent 自动启动

- [x] T11 产出 authorized image
  目标：
  把权限状态固化为最终运行镜像。

  产出：
  - `local/computer-use:product`
  - `local/computer-use:authorized`
  - 授权操作说明

  固定流程：
  1. 启动 `product image`
  2. 在 guest 中手工授予：
     - Accessibility
     - Screen Recording
  3. 验证 agent 可用
  4. 执行 `swift run computer-use runtime container -- macos package` 并通过
     `swift run computer-use runtime container -- image load` 加载

  完成标准：
  - `authorized image` 可重复用于创建新 guest
  - 新建 guest 后不需要再次人工授权

  当前状态：
  - 已产出并加载 `local/computer-use:authorized`
  - 当前平台 manifest digest:
    `sha256:b2a31026a9bd29565b9b5b2e19a92fbdb93db982f81d24f198cadcf72bcf13aa`
  - 从 regenerated authorized image 新建 `cu-authorized-verify-20260426` guest 后验证通过：
    `autoLoginUser=admin`、`/dev/console=admin 501`、LaunchAgent 运行、
    `/health` 正常、`/permissions` 为 Accessibility 和 Screen Recording
    双 true、`/state` 返回 PNG screenshot 和 AX tree
  - fresh authorized guest 的锁屏策略已验证：`pmset -g` 显示 `sleep 0`、
    `displaysleep 0`、`disksleep 0`，admin ByHost screensaver plist 包含
    `askForPassword=0`、`askForPasswordDelay=0`、`idleTime=0`
  - 替换为最新 `ComputerUseAgent.app` 后，在 live authorized guest 中再次验证：
    `/apps` 可发现 `com.apple.TextEdit`，`/state --bundle-id
    com.apple.TextEdit` 可返回 TextEdit screenshot 和 AX tree，
    `/actions/type` 可写入 `Hello from codex`
  - 为支持替换 app 后重新授权，新增 `POST /permissions/request` 和
    `computer-use permissions request --machine <name>`
  - 已重新从 IPSW 干净源 guest 生成并重新加载本地 `authorized image`
  - 已定位 fresh host-side smoke 的根因：`authorized image` 内固化的
    `/usr/local/bin/container-macos-guest-agent` 是旧 hash `c6e6d2...`。
    guest 日志显示 sidecar 发 `process.start` 后 agent 在
    `SpawnedProcessSession.flushOutputAndSendExit` 中因
    `NSFileHandleOperationException` 崩溃并重启
  - 同一份 stopped clone 仅替换为当前 active container SDK build 内的新 guest-agent
    `fee5e8...` 后，`container start` 在 13s 内成功，
    `__guest-agent-log__` 和 workload 都在第 1 次 `process.start` 成功
  - 设计修正：项目必须像独立应用一样管理自己的 container app root 与
    install root，直接使用线上发布的 container SDK，不依赖用户已有的
    `/usr/local/bin/container`，也不复用 OpenBox runtime bundle
  - 已从安装项目独立 container SDK guest-agent 的干净 authorized guest
    重新打包 `local/computer-use:authorized`

- [x] T12 实现 `agent ping` 与 `agent doctor`
  目标：
  建立稳定的诊断链路。

  产出：
  - `computer-use agent ping --machine <name>`
  - `computer-use agent doctor --machine <name>`

  `agent doctor` 至少展示：
  - sandbox 是否运行
  - published host port
  - bootstrap 是否就绪
  - session agent 是否就绪
  - Accessibility 状态
  - Screen Recording 状态

  完成标准：
  - 出问题时可以仅通过 `agent doctor` 判断故障位于 host、container、bootstrap、session agent 还是权限

  当前状态：
  - 已通过 `authorized-smoke` 真实 CLI 验证 `agent ping`
  - `agent doctor` 能报告 sandbox 运行状态、`container_exec` transport、
    session agent readiness、Accessibility 和 Screen Recording 状态
  - darwin 镜像无 published port 时会使用 `container_exec` transport
  - 已修复大 `/state` 响应下 `container exec` stdout 读取不及时导致的
    runtime attachment buffer 问题

- [x] T13 实现 `/state`
  目标：
  建立完整的观测闭环。

  产出：
  - screenshot 采集
  - AX tree 构建
  - frontmost app / target app 解析
  - `/state` 接口

  响应必须包含：
  - `snapshot_id`
  - app 信息
  - window 信息
  - screenshot
  - ax tree

  完成标准：
  - `computer-use state get --machine <name>` 可返回完整结果
  - screenshot 与 AX tree 对应同一时刻

- [x] T14 实现 snapshot cache
  目标：
  保证元素操作基于稳定快照执行。

  产出：
  - `snapshot_id` 生成逻辑
  - `element_id` 与 snapshot 的绑定逻辑
  - snapshot TTL 管理

  固定规则：
  - 每次 `/state` 生成一个新的 `snapshot_id`
  - `element_id` 只在对应 `snapshot_id` 下有效
  - 保留最近 8 个 snapshot
  - TTL 为 60 秒

  完成标准：
  - 过期 snapshot 返回 `snapshot_expired`
  - 使用错误 `snapshot_id` 时不会误操作其他元素

- [x] T15 实现基础输入动作
  目标：
  实现最常用的动作集。

  产出：
  - `POST /actions/click`
  - `POST /actions/type`
  - `POST /actions/key`
  - CLI 对应命令

  完成标准：
  - 能稳定驱动 TextEdit 输入文本
  - 坐标点击和元素点击都可用
  - Return、Tab、方向键等基础键可用

- [x] T16 实现剩余动作
  目标：
  补齐全部动作能力。

  产出：
  - `POST /actions/drag`
  - `POST /actions/scroll`
  - `POST /actions/set-value`
  - `POST /actions/action`
  - CLI 对应命令

  完成标准：
  - drag 可用于窗口内拖动
  - scroll 可作用于可滚动控件
  - `set-value` 可作用于文本类控件
  - `action` 可执行如 `AXPress`

- [ ] T17 端到端验证
  目标：
  用真实应用证明系统可交付。

  产出：
  - 冒烟验证脚本或操作手册
  - 至少一组端到端录屏或日志

  必须覆盖的场景：
  1. 创建并启动 machine
  2. `agent ping`
  3. `apps list`
  4. `state get`
  5. 打开 TextEdit 并输入文本
  6. 在 Finder 或 Safari 中完成一次点击与滚动

  完成标准：
  - 从 `machine create` 到动作执行的完整链路可重复成功
  - 失败时能通过日志和 `agent doctor` 快速定位

## 执行顺序

按以下顺序实施：

1. `T01` 到 `T04`
2. `T05` 到 `T08`
3. `T09` 到 `T12`
4. `T13` 到 `T16`
5. `T17`
