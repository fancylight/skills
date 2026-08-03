# Flow 执行遥测与关键节点耗时分析方案

> **实施入口**：本文是本改造的唯一入口。执行 agent 必须按 Work Package 顺序实施，
> 一次只处理一个 WP，并在每个 WP 验证、提交和人工审核完成后再进入下一包。
> 本方案是通用 Flow 基础设施，不得引入任何具体业务需求、服务名、接口名或测试数据。

## 1. 背景

Flow 已能记录部分 revision、审核结论和集成测试 runner 状态，但无法可靠回答一次任务的时间究竟消耗在哪里。设计、派发、子 agent 接收、实现、编译、测试、审核、返修、等待、提交和汇报主要存在于对话文本中；事后只能凭消息顺序估算。

这会隐藏以下问题：

- 简单实现被多轮编译、错误测试夹具或重复审核放大；
- 根 agent 长时间等待子 agent，却无法区分正常工具执行和无效轮询；
- 相同 revision、相同命令或相同失败在没有新输入时被重复执行；
- 多 agent 并行时把各 agent 用时简单相加，错误地当成总墙钟时间；
- 模型和 token 消耗缺少平台证据时被主观猜测；
- 最终只报告 PASS/FAIL，无法量化有效工作、工具等待、返工和流程成本。

本方案不通过增加人工填写 Markdown 解决问题，而是在现有可验证自动化控制器和 skills 生命周期上增加确定性、追加式执行遥测。

## 2. 目标与非目标

### 2.1 目标

1. 自动记录 Flow 各关键阶段的开始、结束、结果、尝试次数、revision 和失败原因。
2. 同时度量总墙钟时间、agent 执行时间、工具时间、根等待时间、审核与返工时间，避免并行重复计数。
3. 对相同 revision 的重复命令、重复审核和重复 runner 给出可机器判断的重试链路。
4. 在 change 结束或阻断时生成可审计、可横向比较的执行耗时报告。
5. 将记录缺口、未闭合 span、时钟异常和敏感信息泄露作为可验证问题。
6. 保持记录开销足够低，不把遥测本身变成新的流程负担。

### 2.2 非目标

- 不记录或输出密码、token、Authorization、完整连接串、完整环境变量或未脱敏请求正文。
- 不推断平台没有提供的 token 数；不得用字符数或墙钟时间估算 token。
- 不把“耗时较长”自动判定为低质量；分类必须有失败、重试、等待或审核证据。
- 不记录每一次代码搜索、文件读取或 30 秒轮询；只记录能够解释流程成本的关键 span。
- 不用遥测替代 Flow 状态控制、业务审核或测试结果验证。
- 不为了补齐统计而自动重跑已经结束的命令、测试或 runner。

## 3. 设计原则

1. **确定性写入**：事件由共享脚本或 controller 写入，禁止多个 skill 各自拼接 Markdown。
2. **追加而非覆盖**：原始事件只追加；更正通过新事件引用旧事件，不改写历史。
3. **span 成对**：长动作使用 `start/end`；瞬时动作使用 `event`。崩溃后保留未闭合 span。
4. **revision 绑定**：编译、测试、审核和 runner 必须绑定输入 revision；重试必须引用前次 attempt 和失败指纹。
5. **墙钟与累计分开**：报告同时输出 elapsed wall time 和各 agent/span 累计值，禁止直接相加冒充总耗时。
6. **平台事实优先**：模型、token、缓存命中仅在平台返回权威字段时记录；否则为 `unknown/null`。
7. **最小敏感面**：命令记录使用命令类别、可执行文件名、脱敏参数摘要和哈希，不保存原始 secret-bearing command line。
8. **控制器自动记录优先**：已有 controller transition、lease、runner 由 controller 自动发事件；只有无法由控制器观察的动作才由 skill 显式调用 recorder。
9. **遥测失败可见**：自动化模式下遥测写入失败必须停止自动跨阶段并报告 `FLOW_TELEMETRY_BLOCKED`；人工可以明确选择继续，但报告必须标记不完整。

## 4. 权威产物与目录

每个 change 在编排根目录使用：

```text
.flow/changes/<change>/execution/
  events.jsonl              # 追加式原始事件，机器权威
  summary.json              # 由 events 派生，可重复生成
  执行耗时报告.md            # 面向人，禁止作为状态权威
```

约束：

- `events.jsonl` 只能由 recorder/controller 写入，agent 不得手工编辑。
- `summary.json` 和报告必须能从同一份 events 完整重建。
- 原始事件属于根 change 审计产物，不进入业务服务 spec 的 scoped commit。
- 并发 agent 通过文件锁或原子临时文件合并写入，禁止直接并发 `Add-Content`。
- 中断或恢复会话必须复用同一 `traceId`；不得因新对话创建第二份时间线。

## 5. 事件协议

### 5.1 公共字段

```json
{
  "schemaVersion": 1,
  "eventId": "uuid",
  "traceId": "uuid",
  "spanId": "uuid-or-null",
  "parentSpanId": "uuid-or-null",
  "eventType": "span.start|span.end|event",
  "occurredAtUtc": "2026-01-01T00:00:00.0000000Z",
  "changeName": "example-change",
  "specId": "c1-example-or-null",
  "stage": "design|design_verify|assign|receive|implementation|unit_test|review|rework|commit|report|test_design|test_implementation|environment|runner|result_verify|archive",
  "activity": "agent|tool|wait|gate|user_wait",
  "actor": {
    "agentId": "root-or-child-id",
    "role": "orchestrator|executor|reviewer|verifier|runner",
    "model": null,
    "modelSource": "platform|explicit|inherited|unknown"
  },
  "attempt": 1,
  "revision": {
    "repository": "canonical-id-or-null",
    "before": "sha-or-null",
    "after": "sha-or-null"
  },
  "outcome": "running|pass|fail|blocked|cancelled|timeout",
  "failure": null,
  "tokenUsage": null,
  "metadata": {}
}
```

### 5.2 结束事件

`span.end` 必须引用相同 `spanId`，并包含：

- `durationMs`：由 recorder 根据权威开始事件计算；调用方不得自行传入；
- `outcome`；
- `failure.classification`：`requirements|domain|design|implementation|unit_test|review|configuration|infrastructure|test_harness|fixture|assertion|business_behavior|tool_timeout|user_wait|unknown`；
- `failure.fingerprint`：脱敏、稳定哈希；无失败时为 `null`；
- `retryOfSpanId`：仅重试时存在；
- `findingIds`：审核返修时引用稳定 finding；
- `evidenceRefs`：相对于 change 的证据路径，不写本机绝对路径。

### 5.3 工具动作元数据

工具 span 只允许保存：

```json
{
  "commandKind": "compile|unit-test|integration-test|service-start|health-check|git|other",
  "executable": "mvn",
  "argumentSummary": "-Dtest=<class> test",
  "commandFingerprint": "sha256:...",
  "exitCode": 0,
  "timedOut": false
}
```

不得保存 `.env` 内容、JDBC 密码、HTTP Authorization header 或未经脱敏的完整命令。

### 5.4 Token 与模型

- 平台返回精确模型 ID 时写 `actor.model`；只知道“继承”时 `model=null, modelSource=inherited`。
- 平台返回 token usage 时记录 `inputTokens/outputTokens/cachedTokens` 与 `source=platform`。
- 平台未返回时全部为 `null`；报告写“平台未提供”，禁止估算。

## 6. Recorder 与分析器

新增共享源：

```text
codex/scripts/flow-telemetry.ps1
codex/scripts/flow-telemetry-report.ps1
codex/scripts/tests/test-flow-telemetry.ps1
codex/scripts/tests/test-flow-telemetry-report.ps1
codex/skills/flow-codex-core/references/execution-telemetry.md
```

安装时复制到 `flow-codex-core/assets/scripts/` 与 `references/`。如 Claude 平台同步实现，使用同一 schema 和事件语义，不另创字段。

### 6.1 `flow-telemetry.ps1`

建议命令：

```text
initialize-trace
start-span
end-span
record-event
validate
status
```

必须具备：

- 规范化并验证 change/spec/stage/actor/revision；
- 独占文件锁、追加写与 flush；
- 自动生成 event/span/trace ID；
- 自动计算 duration；
- 拒绝重复结束、未知 span、负时长和跨 trace parent；
- 自动脱敏并拒绝疑似 secret；
- 同一 stage/revision/command fingerprint 的重试必须提供 `retryOfSpanId`；
- 发现同 revision、同失败指纹且无新 revision/输入证据时输出 `ERROR_REPEAT_WITHOUT_CHANGE`；
- 支持读取中断后未闭合 span，但不得伪造结束时间。

### 6.2 `flow-telemetry-report.ps1`

从 `events.jsonl` 生成：

- 总 elapsed wall time；
- 各阶段 wall time；
- 各 actor 的累计 span 时间；
- tool、wait、review、rework、user wait 分类时间；
- 并行 overlap，明确累计值不可与 elapsed 相加；
- 命令次数、超时、失败、重试与 failure fingerprint；
- REVIEW REJECT 次数与每轮 finding；
- 未闭合、孤儿、重复或时钟异常 span；
- token/model coverage，缺失时明确 unknown；
- 最长 10 个关键 span 和建议调查点。

报告不得自动断言“浪费”。只有出现重复无变化、超时、返工、无效等待或错误环境证据时，才归入“可避免成本”；其余列为“未归因耗时”。

## 7. Skills 接入点

### 7.1 业务开发链路

| Skill | 自动事件 |
|---|---|
| `flow-codex-design/change` | domain/design start/end、用户阻断、设计 revision |
| `flow-codex-verify` | verifier start/end、PASS/ERROR/WARN、finding IDs |
| `flow-codex-assign` | assign event、child wait span、agent/model provenance |
| `flow-codex-receive` | receive start/end、branch/worktree gate |
| `flow-codex-apply` | implementation、每次 compile/unit-test、REVIEW_REQUEST、rework span |
| `flow-codex-review` | review round start/end、PASS/REJECT、finding IDs |
| `flow-codex-report` | scoped commit、report lease、根回写 start/end |

根 agent 启动子 agent 前开启一个 child lifecycle span；收到最终 `REVIEW_REQUEST/REPORT_REQUEST/FINAL` 时结束。根等待必须是一个连续 wait span，不得按每次 `wait_agent` 调用产生事件。

### 7.2 集成测试链路

`flow-test-controller.ps1` 自动记录：

- initialize、phase transition、lease issue/accept/expire；
- design/implementation/environment/result verifier；
- runner `start-run/record-run`；
- BLOCKED、重复执行拒绝和 revision/configuration drift。

测试 skills 只补 controller 看不到的动作：测试代码编译、静态验证、服务健康检查、外部工具执行和用户等待。不得让 skill 与 controller 为同一 transition 重复记两次。

### 7.3 Status 与 Report

- `flow-codex-status` 增加可选的 timing 摘要，但保持只读。
- `flow-codex-report/test-report/archive` 在阶段或 change 结束时调用 report 生成器。
- `flow-codex-verify` 检查 required span 完整性；缺失时只影响“遥测完整性”，不得伪造业务失败。
- 自动化/Goal 模式若 required span 缺失，不允许自动进入下一阶段；人工模式可明确继续并保留 `telemetryCompleteness=partial`。

## 8. 必记节点与采样边界

### 8.1 必记

- 每个 Flow stage 的 start/end；
- 子 agent spawn/receive/final；
- 根 agent 对单个子 agent 的整体等待；
- 每次编译、单元测试、runner 和服务启动；
- 每轮审核及返修；
- timeout、cancel、interrupt、blocked；
- revision 变化、commit 和 failure fingerprint；
- 用户输入导致的真实暂停。

### 8.2 不记

- 普通 `rg/read/status` 等低成本只读动作；
- 每次 10–30 秒轮询；
- 无法从平台取得的内部思考时间和 token；
- 未脱敏的原始日志正文。

## 9. Work Packages

### WP0：协议、迁移矩阵与事故回放夹具

**允许修改**：

- `PLAN-flow-execution-telemetry-and-timing.md`
- `flow/docs/schema.md`
- 新增 `codex/scripts/tests/fixtures/flow-telemetry/**`

**工作**：

- 固化事件 schema、stage/activity/failure 枚举和目录；
- 建立“现有生命周期节点 → 遥测事件”矩阵；
- 抽象至少四类通用回放：工具超时、测试夹具错误、审核返工、并行 agent；
- 明确旧 change 没有 events 时为 `not-instrumented`，不得伪造历史。

**验证**：schema 可解析；fixtures 不含业务专名、绝对路径或 secret；人工审核协议后提交。

### WP1：Recorder 与基础单元测试

**依赖**：WP0。

**允许修改**：

- `codex/scripts/flow-telemetry.ps1`
- `codex/scripts/tests/test-flow-telemetry.ps1`
- recorder 专用 fixtures

**验证**：

- start/end 配对与 duration；
- 20 个并发 writer 不产生损坏 JSON 行；
- 重复 end、未知 span、跨 trace parent、负时长被拒绝；
- secret 红线正反例；
- 同 revision/同失败无变化重试被拒绝；新 revision 或新输入允许重试；
- 中断后未闭合 span 可识别且不会自动闭合。

### WP2：Controller 自动遥测

**依赖**：WP1 和现有最小 controller 测试 PASS。

**允许修改**：

- `codex/scripts/flow-test-controller.ps1`
- `codex/scripts/tests/test-flow-test-controller.ps1`
- `codex/skills/flow-codex-core/references/test-controller.md`

**工作**：controller 在状态转换成功后原子追加事件；转换失败记录拒绝事件，但不得先推进 state。现有 `startedAt` 迁移为统一 runner span，保持 state 向后兼容。

**验证**：每个合法 transition 恰好一组事件；非法/重复 transition 不产生成功事件；runner FAIL/PASS 均闭合；模拟 state 写失败时 telemetry 不宣称 transition 成功。

### WP3：业务 Flow 与子 agent 生命周期接入

**依赖**：WP1。

**允许修改**：

- `codex/skills/flow-codex-{design,change,verify,assign,receive,apply,review,report,status}/**`
- `codex/skills/flow-codex-core/references/execution-telemetry.md`
- `flow/templates/codex/child-agent-prompt.md`
- 对应 contract tests

**工作**：加入统一 recorder 调用协议；root 负责 child lifecycle/wait，executor 负责 implementation/tool/rework，reviewer 负责 review round。禁止不同角色重复记录同一 span。

**验证**：静态 contract test 确认所有入口消费统一 reference；模拟 assign→review reject→rework→review pass→commit/report，事件完整且无重复。

### WP4：测试 Skills 接入

**依赖**：WP2。

**允许修改**：

- `codex/skills/flow-codex-test*/**`
- `codex/skills/flow-codex-system-test/**`
- test skill/controller contract tests

**工作**：controller 负责 transition，skills 仅记录 controller 不可见的 compile、probe、health、service 和 runner tool span；同 revision 重跑规则引用 controller revision 与 failure fingerprint。

**验证**：一次 PASS 和一次 FAIL 回放；environment BLOCKED 不产生 runner span；同 revision runner 重跑仍由 controller 拒绝；skill/controller 不重复计数。

### WP5：汇总报告与完整性门禁

**依赖**：WP1、WP3、WP4。

**允许修改**：

- `codex/scripts/flow-telemetry-report.ps1`
- `codex/scripts/tests/test-flow-telemetry-report.ps1`
- `flow/templates/execution-timing-report.md.tmpl`
- `flow/templates/verify-checklist.md`
- `flow/templates/test-verify-checklist.md`
- report/status/archive skills 的相关引用

**验证**：

- 串行和并行时间线的 elapsed/累计/overlap 计算正确；
- tool timeout、review rework、user wait 分类正确；
- 不完整 span 明确显示，不被当成 0 秒；
- token/model 未提供时显示 unknown；
- 报告不含 secret、绝对路径或完整命令；
- report 重生成字节稳定或仅允许明确的 generatedAt 差异。

### WP6：安装、回放与启用门禁

**依赖**：WP0–WP5。

**允许修改**：

- `codex/install.ps1`
- `codex/validate.ps1`
- `AGENTS.md`、`README.md`、`CHANGELOG.md`
- 必要的 Claude 同步文件
- 仅用于隔离验证的 fixtures

**验证**：

1. PowerShell parser 和全部新增单测 PASS；
2. 现有 `codex/validate.ps1` 全量 PASS；
3. 安装到临时目录后脚本、reference 和模板齐全；
4. 通用事故回放全部生成预期时间线和报告；
5. 两个 fresh-agent forward tests：一个业务 spec、一个集成测试失败闭环；
6. shadow 模式用于一个隔离 change，记录行为但不阻断；
7. shadow 结果与人工事件清单一致后，才启用完整性门禁。

## 10. 统一 WP 输出与提交规则

每个 WP 完成后必须输出：

```text
[FLOW_TELEMETRY_WP_RESULT] PASS | BLOCKED
work_package: WP<n>
commit: <sha or none>
changed_files:
  - <path>
validation:
  - <command>: PASS | FAIL
telemetry_overhead:
  events: <count>
  elapsed_ms: <number>
remaining:
  - <item or none>
next: WP<n+1> | STOP_FOR_REVIEW
```

约束：

- 一个 WP 一个 scoped commit，便于审核和回滚；
- 当前仓库已有未提交修改时必须保留，不得 reset、clean、暂存或提交；
- 不得多个 agent 并发修改同一 controller、skill 或模板；
- 每个 WP 由独立 reviewer 审核，REJECT 只修 findings；
- 不修改 `~/.agents/skills` 安装副本，安装验证只使用临时目录或 `codex/install.ps1`；
- WP6 前不得宣称已可用于真实任务的自动时间分析。

## 11. 验证矩阵

| 场景 | 期望 |
|---|---|
| 单 agent 一次通过 | elapsed、stage、tool 与 commit 时间完整，无 rework |
| Maven 首次 timeout，修复后 PASS | 两个 attempt；第二次引用第一次；timeout 单独计入可避免成本 |
| 测试夹具错误后修复 | failure=`fixture`，不得归为业务实现 |
| Review REJECT 两轮后 PASS | 每轮 finding 可追踪，rework 时间独立统计 |
| 两 agent 并行 | elapsed 小于 actor 累计；报告展示 overlap，不重复计入总时长 |
| root 连续轮询等待 | 只生成一个 child wait span，不生成 N 个轮询事件 |
| 配置 probe BLOCKED | environment span 闭合为 blocked，后续 runner 不存在 |
| 同 revision 同失败重跑 | recorder/controller 拒绝并记录拒绝原因 |
| revision 改变后重跑 | 允许新 attempt，关联旧 failure fingerprint |
| 会话重启后继续 | traceId 不变，未闭合 span显式存在，不伪造历史 |
| 平台不返回 token/model | 字段为 null/unknown，不估算 |
| command 含 secret | 写入被拒绝或只保留脱敏摘要 |

## 12. 性能与可靠性验收

- 单事件写入 P95 小于 100 ms（本地 SSD、无竞争基线）；
- 1000 个事件的 validate + report P95 小于 2 秒；
- 20 writer 并发测试无丢行、重复 eventId 或破损 JSON；
- recorder 故障不修改 controller phase、revision 或业务产物；
- 所有报告数值可追溯到 eventId/spanId；
- 完整流程 required span 覆盖率 100%；
- 同 revision、同失败、无新输入的重复执行拦截率 100%；
- secret fixture 泄露率 0；
- 与未安装遥测的现有 change 向后兼容，显示 `not-instrumented` 而非失败。

## 13. 启用策略

1. `off`：默认关闭，仅用于开发脚本；
2. `shadow`：记录和报告，但不阻断现有 Flow；
3. `enforced`：自动化/Goal 流程缺 required span 或发生重复无变化时停止；
4. 人工交互流程可显式接受 `partial`，但最终报告必须突出缺口。

从 `shadow` 升级到 `enforced` 必须满足：

- WP0–WP6 全部 PASS；
- 至少一个业务开发和一个集成测试隔离回放完整；
- fresh-agent forward tests 没有遗漏关键 span；
- 遥测平均额外墙钟开销低于流程总时长的 1%；
- 人工审核确认报告能解释超时、返工和等待，而不是只输出事件流水。

## 14. 最终验收

本方案完成后，任意已启用遥测的 Flow change 必须能够回答：

1. 总墙钟时间是多少；
2. 每个阶段何时开始、结束、由谁执行；
3. 子 agent 实际工作与 root 等待分别多久；
4. 编译、测试、服务和 runner 各执行几次、每次为什么重试；
5. 审核返工来自哪些 findings；
6. 哪些耗时有客观证据可判定为 timeout、重复、返工或等待；
7. 当前模型与 token 数据是平台事实还是 unknown；
8. 时间线是否完整，哪些节点因中断或旧版本不可恢复。

只有上述问题都能由结构化事件和报告直接回答，且验证矩阵全部通过，才能声明：

```text
[FLOW_TELEMETRY_RESULT] VERIFIED_FOR_SHADOW_ROLLOUT
```

在 `shadow` 实际验证和启用门禁完成前，不得宣称该能力已经解决真实任务的时间与 token 分析问题。
