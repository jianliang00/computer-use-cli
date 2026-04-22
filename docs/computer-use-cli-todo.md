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

## 任务清单

- [ ] T01 初始化工程骨架
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

- [ ] T02 定义 machine metadata 模型与本地存储
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

- [ ] T03 实现 `ContainerBridge`
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
  - 上层 CLI 不直接调用散落的 `ContainerKit` / `ContainerClient`

- [ ] T04 实现 machine 命令
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

- [ ] T05 定义 agent HTTP 协议
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

- [ ] T06 实现 `ComputerUseAgent.app` 外壳
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

- [ ] T07 实现权限检测
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

- [ ] T08 实现 `/apps`
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

- [ ] T09 实现 bootstrap agent
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

- [ ] T10 完成镜像安装层
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
  - `container build --platform darwin/arm64 -f images/macos/Dockerfile ...` 成功
  - 产物镜像可启动
  - 启动后 `admin` 能自动登录
  - `ComputerUseAgent.app` 会自动启动

- [ ] T11 产出 authorized image
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
  4. 执行 `container commit`

  完成标准：
  - `authorized image` 可重复用于创建新 guest
  - 新建 guest 后不需要再次人工授权

- [ ] T12 实现 `agent ping` 与 `agent doctor`
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

- [ ] T13 实现 `/state`
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

- [ ] T14 实现 snapshot cache
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

- [ ] T15 实现基础输入动作
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

- [ ] T16 实现剩余动作
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
