# 改动方案：集成测试设计协议重构、独立 Verify 与生命周期硬门禁

> **状态**：待实施  
> **实施者**：按本文 §9 修改 `self/skills` 仓库；不得顺带修改业务项目测试代码。  
> **检视者**：独立 agent 按本文 §11 对实施提交做只读 PASS/REJECT。  
> **前置**：现有 Codex 链路 `test-design → test-assign → test-receive → test-apply → test-review → test-report → test → system-test`。  
> **背景与决策摘要**：见 §0。

---

## 0. 背景

### 0.1 问题从哪来

`overseas-roster-template-optimization` 的本地集成测试最终得到 7 passed、0 failed、0 skipped，并留下
SQL EXPLAIN 证据；但 Flow 过程仍被错误判定为完整完成：

- `test-design` 产物存在，但缺少独立 readiness 复验，设计内容与验收映射不完整。
- `test-assign`、review、report 的结构化 checkpoint 没有形成完整、可追踪的闭环。
- 根 agent 直接调用 runner，并以 runner PASS + 手工勾选 `task.md` 推导 Goal 完成。
- system-test 测试代码和 change 产物仍可处于 `local-only`、错误分支或未提交状态，但现有门禁仍允许标记完成。

这说明三个问题同时存在：

| 类型 | 问题 |
|------|------|
| 测试设计协议不足 | `test-design.md`、`test-plan.md` 的最低内容契约过弱，无法独立指导测试实现并证明验收 |
| 执行偏离 | agent 没有遵守已写明的顺序，把“测试运行通过”等同于“测试 Flow 完成” |
| 机制缺口 | 设计、实现和结果阶段都依赖执行者自报或 task 勾选，缺少独立只读验证 |

### 0.2 现有测试 Skills 为何不够

| 现有位置 | 当前行为 | 可绕过点 |
|----------|----------|----------|
| `flow-codex-test-design` | 生成 manifest、test-plan、test-design 并输出 READY | 既缺完整测试设计协议，又由产出者自证 |
| `manifest-checklist.md` | test-design 仅要求鉴权、WireMock、VM、故障归因四类信息 | 不要求 SUT revision、拓扑、数据模型、观测点和覆盖策略 |
| `test-plan.md` | 可用“验收主题 → 测试类”表达覆盖 | 没有场景、准备数据、请求、断言和副作用，无法指导实现或独立审核 |
| `flow-codex-test-assign` | 接受最近 READY，或 `task.md` 已就绪 | 手工勾选可替代真实校验 |
| `flow-codex-review` test 模式 | 对照 test-plan + manifest 审实现 | 不验证 test-design 完整性和整个生命周期证据 |
| `flow-codex-test-report` | 允许 `local-only` 并勾选“代码完成” | 未提交、错误分支、未知脏改动仍可能被视为可交付 |
| `flow-codex-test` | 检查 manifest/test-plan 存在和 st-api 完成 | 不验证验收映射质量、review/report 记录、测试仓可复现性 |
| `flow-codex-system-test` | 运行 runner 并生成 evidence | 可被直接调用；PASS 只证明本次运行，不证明前序流程完成 |

因此本方案不是“给现有流程补一个 verify”这么简单，而是先提升测试设计协议，再用独立 verify 和调用方
硬门禁保证协议被执行。

### 0.3 测试设计、执行配置和证据边界

| 产物 | 权威职责 | 禁止承载 |
|------|----------|----------|
| `test-design.md` | 为什么这样测：SUT revision、本地拓扑、真实/桩边界、数据模型、观测方式、覆盖策略、失败归因 | 实际 PASS/FAIL、测试代码实现细节 |
| `test-plan.md` | 测什么：验收 ID → 场景 ID → 准备数据 → 请求/步骤 → 核心断言 → DB/文件/副作用断言 → 测试方法 | 事后执行结果、模糊的“某测试类覆盖” |
| `manifest.yaml` | 怎么跑：服务、命令、端口、依赖、环境变量、seed/cleanup、suite/filter | 替代测试目标、覆盖论证或场景设计 |
| 测试代码 | 按 test-plan 自动执行场景 | 自己发明未设计的验收口径 |
| `evidence/`、`集成测试.md` | 实际执行命令、revision、原始报告、结果、SQL 计划和 cleanup | 回写并污染设计基线 |

### 0.4 核心决策

| ID | 决策 |
|----|------|
| D1 | 重构 `flow-codex-test-design`：它与业务 `flow-codex-design` 在质量保障层面对等，负责设计“如何证明 as-built 正确” |
| D2 | test-design 必须在业务代码实现、审核和提交后执行，并绑定被测业务 revision |
| D3 | 强制分离 test-design、test-plan、manifest 和 evidence 的职责 |
| D4 | 新增独立只读 skill：`flow-codex-test-verify` |
| D5 | 不扩充 `flow-codex-verify`；后者继续负责业务设计、发布就绪和 SQL 发布证据 |
| D6 | test verify 提供 `design`、`implementation`、`result` 三种模式 |
| D7 | assign/test/Goal 完成分别强依赖三个模式的当前验证结果，不接受 task 勾选作为替代证据 |
| D8 | `flow-codex-system-test` 允许独立用于复现，但独立执行结果标记为 `standalone`，不得完成 Flow |
| D9 | test verify 只读；不修文件、不启动服务、不修改 task、不替代 test review |
| D10 | 测试仓默认必须处于需求期望分支且 scoped clean；`local-only` 只能显式 waiver，不能默认完成 |

---

## 1. 目标与非目标

### 1.1 目标

- 将 `flow-codex-test-design` 提升为真正的需求级测试设计阶段，而不是 runner 配置或测试清单生成器。
- 以概要设计验收标准、已提交 as-built 和本地可用环境为输入，设计“如何证明开发正确”。
- 让一个未参与设计的 test-apply agent 能仅凭 test-design/test-plan 实现测试。
- 让一个未参与实现的 review/verify agent 能仅凭设计、测试代码和 evidence 判断覆盖是否成立。
- 防止 test-design 自证 READY。
- 防止 `task.md` 手工勾选绕过 assign/test 门禁。
- 验证每条概要设计验收标准都有明确测试映射、断言和阶段。
- 验证 test apply 已经过独立 review、冒烟和 report。
- 验证最终 evidence 与实际测试报告、manifest、源代码版本一致。
- 明确区分：
  - `SYSTEM_TEST_RESULT PASS`：一次 runner 运行成功；
  - `TEST_VERIFY_RESULT PASS`：某阶段产物合规；
  - `INTEGRATION_TEST_RESULT PASS`：完整测试 Flow 完成。

### 1.2 非目标

- 不要求 test-design 重复业务 OpenSpec 的实现设计；它只描述验证策略和可执行场景。
- 不在 verify 中生成测试设计或 JUnit。
- 不替代 `flow-codex-review` 对测试代码正确性的审核。
- 不重新执行 runner；运行仍归 `flow-codex-system-test`。
- 不把测试代码质量检查塞入业务 `flow-codex-verify`。
- 不要求所有需求必须测试生产外部依赖；允许按设计使用 WireMock，但必须登记 mock 边界。
- 本计划不修改任何业务仓代码或当前 GLM 集成测试用例。

---

## 2. 实施后生命周期

```text
业务 spec 完成 + flow-codex-verify full PASS
  → 固定各业务仓被测 revision
  → flow-codex-test-design
      读取概要设计验收 + as-built + 本地环境能力
      产出 test-design + test-plan + manifest + fixtures 契约
  → flow-codex-test-verify verify_mode=design
      ERROR：回 test-design 修复
      PASS：允许 test-assign
  → flow-codex-test-assign
  → test-receive → test-apply
  → flow-codex-review review_mode=test
  → test-report
  → flow-codex-test-verify verify_mode=implementation
      ERROR：回 apply/review/report 修复
      PASS：允许 flow-codex-test
  → flow-codex-test
  → flow-codex-system-test（doctor → run）
  → flow-codex-test-verify verify_mode=result
      ERROR：不得勾选最终 PASS，不得完成 Goal
      PASS：输出 INTEGRATION_TEST_RESULT PASS
  → flow-codex-verify release → archive
```

`flow-codex-system-test` 被用户单独调用时：

```text
[SYSTEM_TEST_RESULT] PASS
execution_mode: standalone
flow_completed: false
next: flow-codex-test-verify result（仅当此前 implementation PASS）
```

---

## 3. 重构 `flow-codex-test-design`

### 3.1 定位和时机

`flow-codex-test-design` 的定位：

> 在业务代码完成、独立审核、单元测试和提交后，基于概要设计验收标准、确定的 as-built revision 与
> 本地中间件/数据能力，设计一套足以证明开发正确的本地集成测试。

硬前置：

1. 所有纳入范围的业务 spec 已完成 review、测试和提交。
2. `flow-codex-verify full` 对业务 spec 范围 PASS。
3. 每个被测业务仓有明确 commit；未提交业务代码不得作为 SUT 基线。
4. 本地可用服务、中间件、数据库和外部依赖替身已盘点；缺关键观测能力时 BLOCKED。
5. 本阶段不得读取“已经写好的本需求集成测试代码”反推设计；历史测试仅可作为复用实现参考，并须标注。

### 3.2 输入

| 输入 | 用途 |
|------|------|
| 根 `概要设计.md` 验收标准 | 唯一验收义务来源 |
| 根 `操作链路.md`、数据访问契约 | 确定跨服务路径、状态变化和 SQL 计划义务 |
| 各业务 OpenSpec + 已提交代码 revision | 确定真实接口、字段、异步行为和实现边界 |
| 单元测试结果 | 识别已在单元层证明和仍需集成证明的内容，不替代集成测试 |
| 本地环境/playbook | 确定 MySQL/PG/Redis/MQ/WireMock、端口、启动和鉴权能力 |
| system-test 仓现有公共支撑 | 判断可复用 runner、fixture、客户端和 stub 能力 |

### 3.3 `test-design.md` 必备章节

| ID | 章节 | 必须回答 |
|----|------|----------|
| TDD.1 | 测试目标与风险 | 本次要证明什么；最高风险路径、边界和明确不测项 |
| TDD.2 | SUT 与 revision | 服务、仓库、commit、启动模块、端口、配置文件 |
| TDD.3 | 本地测试拓扑 | 被测服务、真实中间件、真实数据库、WireMock/假依赖及调用方向 |
| TDD.4 | 真实与替身边界 | 哪些依赖必须真实、哪些允许 stub、stub 请求匹配与响应/失败契约 |
| TDD.5 | 鉴权与上下文 | header、JWT/Redis key、tenant/project/org/user 约定 |
| TDD.6 | 数据模型与夹具 | 关键实体关系、预留 ID、seed 顺序、幂等和 cleanup 范围 |
| TDD.7 | 可观测点 | HTTP、异步结果、Excel/文件、DB、MQ、缓存和“无副作用”如何验证 |
| TDD.8 | 验收覆盖策略 | 每条验收需要 happy path、边界、失败和回归中的哪些组合 |
| TDD.9 | SQL 计划策略 | 最终 SQL/count、代表性数据量、只读数据源、阈值和 evidence |
| TDD.10 | 失败归因 | doctor → health → fixture/schema → stub/Feign → 鉴权 → 业务断言 |

可用 Mermaid 或表格表达拓扑；简单单服务需求可用表格，但不得只写“复用现有环境”。

### 3.4 `test-plan.md` 场景协议

每条概要设计验收标准必须有稳定 ID，如 `AC-1`。每个测试场景必须有稳定 ID，如 `AC-3-S2`。

场景表至少包含：

| 字段 | 要求 |
|------|------|
| 验收 ID / 原文 | 可回溯到概要设计，不得重新改写验收语义 |
| 场景 ID / 名称 | 区分 happy、boundary、failure、regression |
| 必需性 | required / optional；required 不得 skip |
| 测试类 / 方法 | 设计阶段可指定计划名称；apply 后必须精确一致 |
| 前置与准备数据 | fixture ID、初始 DB/缓存/MQ 状态 |
| 请求或操作步骤 | API、参数、文件输入和异步轮询方式 |
| 响应断言 | HTTP、错误信息、返回字段 |
| 文件/Excel 断言 | sheet、表头、下拉、隐藏元数据、单元格值等 |
| 数据与副作用断言 | DB/MQ/缓存写入，或明确验证未写入 |
| 清理 | 自动清理对象和保留现场条件 |
| 阶段 / suite | S1…Sn、api/e2e/cdc 等 |

规则：

- 只写测试类、不写方法和断言，BLOCKED。
- 方法名声称“未写入”但无 DB/副作用断言，BLOCKED。
- “现网行为不变”必须指定观测字段；否则明确分配给单元回归并标为集成 N，不得虚报集成覆盖。
- 一条验收可拆多个场景；不得用一个宽泛场景名覆盖互不相同的验证义务。
- 正向行为没有 happy path、只测错误分支时，默认 BLOCKED。

### 3.5 `manifest.yaml` 边界

manifest 只能由测试设计推导执行配置：

- SUT revision/工作目录、启动命令、配置和 health。
- suite/filter。
- dependencies、compose profile、required env。
- seed/cleanup 顺序与预留 ID。
- success/failure cleanup policy。

manifest 不得作为验收覆盖证明。`services[].note` 不能替代 test-design 的拓扑和依赖契约。

### 3.6 设计与 evidence 隔离

- test-design/test-plan 只能写计划、阈值和目标 evidence 路径。
- 实际 `PASS`、耗时、执行日期、真实 EXPLAIN 和测试计数只写入 `evidence/` 与根 `集成测试.md`。
- 执行后发现设计遗漏，应回到 test-design 修改并重新 design verify；禁止只在 evidence 中补口径。

### 3.7 READY 语义

`[TEST_DESIGN_RESULT] READY` 仅表示产物者认为设计完成，输出必须包含：

- 业务 SUT revisions；
- AC 数量、required 场景数量；
- 本地拓扑摘要；
- BLOCKED/WARN；
- 下一步 `flow-codex-test-verify design`。

它不是 assign 凭据，独立 design verify PASS 才是。

---

## 4. 新增 `flow-codex-test-verify`

### 4.1 Skill

新增：

```text
codex/skills/flow-codex-test-verify/
├── SKILL.md
├── agents/openai.yaml
└── references/
    └── test-verify-checklist.md
```

建议 frontmatter：

```yaml
---
name: flow-codex-test-verify
description: 只读验证 Flow 集成测试设计、测试实现生命周期或最终运行证据。用于 test-design 后、test 前以及 system-test 后的硬门禁；不编写测试、不启动服务、不修改 task。
---
```

严格输出：

```text
[TEST_VERIFY_RESULT] PASS | WARN | ERROR
change_name: <name>
verify_mode: design | implementation | result
checked_revision: <system-test commit or local tree fingerprint>
errors:
  - <item or none>
warnings:
  - <item or none>
next: <next skill or blocked>
```

### 4.2 `design` 模式

时机：`flow-codex-test-design` 后、`flow-codex-test-assign` 前。

检查：

| ID | 级别 | 检查项 |
|----|------|--------|
| TD.1 | ERROR | manifest、test-plan、test-design、IDS、seed、cleanup 存在 |
| TD.2 | ERROR | 概要设计每条验收 ID 均映射为 Y/N；N 必须给出 Non-Goal 或后续阶段 |
| TD.3 | ERROR | 每条 Y 映射到具体测试类 + 方法 + 核心断言，不接受只写类名 |
| TD.4 | ERROR | manifest `apiTestFilter` 覆盖所有必需类，且与 plan 一致 |
| TD.5 | ERROR | test-design 完整覆盖 TDD.1–TDD.10，不接受“复用现有约定”等不可独立执行表述 |
| TD.6 | ERROR | fixture 使用预留 ID、seed 幂等、cleanup 仅清理预留范围 |
| TD.7 | ERROR | 数据访问契约风险均有最终 SQL/count、代表性参数、只读 EXPLAIN 与 evidence 路径 |
| TD.8 | WARN/ERROR | 场景矩阵不足以证明验收；正向能力无 happy path、方法名与断言不一致或缺少副作用观测时 ERROR |
| TD.9 | ERROR | 测试仓分支不符合预期，或存在无法归属的历史脏改动 |
| TD.10 | ERROR | test-plan/test-design 混入实际 PASS、执行日期或事后 evidence |
| TD.11 | ERROR | SUT revision 未固定，或本地真实/替身边界无法判定 |

### 4.3 `implementation` 模式

时机：test-report 后、`flow-codex-test` 前。

检查：

| ID | 级别 | 检查项 |
|----|------|--------|
| TI.1 | ERROR | 进度文件存在 TEST_RECEIVE、TEST_APPLY、REVIEW_RESULT PASS、REPORT_REQUEST、REPORT_LEASE_GRANTED、REPORT complete |
| TI.2 | ERROR | 实际测试类/方法覆盖 TD.3 映射；不能用方法名冒充断言 |
| TI.3 | ERROR | 无永久 `@Disabled`、必需用例无无理由 skip |
| TI.4 | ERROR | apply 冒烟结果存在，filter 与 manifest 一致 |
| TI.5 | ERROR | 测试没有整体 mock 被测服务；外部 stub 与 test-design 声明一致 |
| TI.6 | ERROR | 测试代码、fixtures、manifest、stub、服务配置均可从同一 git revision 恢复 |
| TI.7 | ERROR | 测试仓错误分支、untracked 需求文件或未知脏改动 |
| TI.8 | WARN/ERROR | `local-only`：默认 ERROR；仅用户明确 waiver 且记录原因时 WARN，但不得用于 release/archive |

### 4.4 `result` 模式

时机：`flow-codex-system-test` 后、勾选最终 PASS 或 Goal 完成前。

检查：

| ID | 级别 | 检查项 |
|----|------|--------|
| TR.1 | ERROR | 当前 revision 已通过 implementation 模式；revision/fingerprint 未漂移 |
| TR.2 | ERROR | runner 报告、Surefire/Playwright 等原始报告与 summary 的 passed/failed/skipped 一致 |
| TR.3 | ERROR | 必需 suite 全部完成，failed=0、skipped=0 |
| TR.4 | ERROR | evidence 有执行时间、命令、服务版本、测试仓 revision、业务仓 revision |
| TR.5 | ERROR | success cleanup 成功；failure retained state/cleanup command 一致 |
| TR.6 | ERROR | SQL 风险证据覆盖最终列表 SQL及分页 count；验收阈值满足 |
| TR.7 | ERROR | 根 `集成测试.md` 与测试仓 evidence 内容一致 |
| TR.8 | ERROR | task 的“集成测试执行 PASS”不能早于 result PASS |

---

## 5. 现有 Skills 修改

### 5.1 `flow-codex-test-design`

- 按 §3 重构输入、产物协议和 READY 语义。
- 它是测试设计入口，不是 scaffold/manifest 辅助工具；scaffold 降为步骤 0 的基础设施准备。
- 继续负责产出，不再将自己的 READY 视为 assign 的充分条件。
- 结果 `next` 改为 `flow-codex-test-verify design`。
- test-plan 强制使用 AC/场景协议，至少包含准备、步骤、响应、文件/数据/副作用断言。
- 禁止用“现网行为不受影响”作为空泛测试项；必须指出观测字段和断言。
- 禁止在 test-plan 写实际 PASS 和执行 evidence。

### 5.2 `flow-codex-test-assign`

```diff
- 最近一次 TEST_DESIGN_RESULT READY（或 task.md 已就绪）
+ 当前轮 TEST_VERIFY_RESULT PASS，verify_mode=design
```

- 删除 task checkbox 兜底。
- 保留分支/worktree 检查，但以 test verify 结果为硬门禁。

### 5.3 `flow-codex-review` test 模式

- 继续审查测试实现正确性，不承担流程完整性验证。
- design path 增加 `test-design.md`，避免只看 plan + manifest。
- 审核报告必须列出未覆盖验收 ID；有缺失则 REJECT。

### 5.4 `flow-codex-test-apply` / `test-report`

- apply 将冒烟命令、filter、结果和测试 revision 追加到进度文件。
- report 仅在 review PASS + 冒烟 PASS 后运行。
- 将“提交可选/local-only”改为：
  - 开发中可 local-only；
  - 进入 `flow-codex-test`、release 或 Goal complete 前必须形成可恢复 revision；
  - 用户显式 waiver 仅允许临时本地验证，不得标记发布就绪。

### 5.5 `flow-codex-test`

硬门禁改为：

1. `flow-codex-verify full` PASS。
2. `flow-codex-test-verify implementation` PASS。
3. 测试仓 revision 与 implementation 检查时一致。
4. 委托 system-test 后运行 `flow-codex-test-verify result`。
5. 只有 result PASS 才勾选 task 并输出 `[INTEGRATION_TEST_RESULT] PASS`。

删除“用户明示跳过 test-assign、由根代跑”作为完成 Flow 的通道；若保留临时调试能力，必须输出
`standalone`，不能更新完成状态。

### 5.6 `flow-codex-system-test`

- 输入增加 `execution_mode: orchestrated | standalone`。
- evidence 增加测试仓 revision、业务仓 revision、manifest hash。
- 不论 PASS/FAIL，都不推导 Flow 完成。
- 原始报告不存在或 summary 与原始报告不一致时返回 FAIL。

### 5.7 Goal / status / archive

- `flow-codex-status` 区分“设计通过、代码完成、runner 通过、完整测试 Flow 通过”。
- `flow-codex-archive` 前要求最近一次 `test verify result PASS`。
- 通用 Goal 只能在 task 完成且 test result verify PASS 后标记完成。

---

## 6. 协议与模板

| 文件 | 动作 |
|------|------|
| `flow/templates/test-design.md.tmpl` | 新增测试设计模板，固定 TDD.1–TDD.10 |
| `flow/templates/test-plan.md.tmpl` | 新增 AC/场景模板，固定准备、步骤、响应、文件/数据/副作用断言 |
| `codex/skills/flow-codex-test-design/references/manifest-checklist.md` | 从 manifest 清单升级为三产物协议；不再以四条 test-design 要求为完成标准 |
| `flow/templates/test-verify-checklist.md` | 新增共享检查清单，作为安装后的权威规则 |
| `flow/templates/integration-test-result.md.tmpl` | 增加 execution_mode、test revision、business revisions、manifest hash、result verify |
| `flow/templates/task-md-maintenance.md` | READY/代码完成/执行 PASS 三种状态不得互相替代 |
| `flow/docs/schema.md` | 登记集成测试阶段和 result 字段 |
| `codex/skills/flow-codex-core/references/checkpoints.md` | 增加三个 test verify checkpoint |
| `codex/validate.ps1` | 注册新 skill，并校验调用链和模板存在 |
| `codex/install.ps1` | 依赖现有“复制全部顶层模板”，确认新 checklist 被安装 |
| `AGENTS.md` / `codex/PLAN.md` | 更新生命周期和公开 skill 清单 |
| `CHANGELOG.md` | Unreleased 记录 |

Claude 当前仍使用旧 `/flow:test` 模式。P0 先保证 Codex 链路闭环；P1 再决定是新增 Claude test verify，
还是明确记录“Codex-only，Claude follow-up”，不得假装双平台已经同步。

---

## 7. 结果语义

| 结果 | 证明什么 | 不证明什么 |
|------|----------|------------|
| `TEST_DESIGN_RESULT READY` | 产出者按新协议完成测试设计 | 不证明独立校验通过 |
| `TEST_VERIFY_RESULT design PASS` | 测试设计符合门禁 | 不证明测试代码已实现 |
| `REVIEW_RESULT PASS` | 测试代码符合设计 | 不证明 runner 已执行 |
| `SYSTEM_TEST_RESULT PASS` | 指定 revision 的一次运行通过 | 不证明完整 Flow 或可发布 |
| `TEST_VERIFY_RESULT result PASS` | 运行证据完整且与 revision/验收一致 | 不替代业务发布 verify |
| `INTEGRATION_TEST_RESULT PASS` | 完整集成测试 Flow 完成 | 不自动归档 |

---

## 8. 兼容与迁移

- 已完成的历史 change 不自动改写。
- 历史 change 再次执行 test/archive 时，必须补齐三个 verify 阶段；缺 progress marker 可通过重新 review/report
  或形成一次有依据的迁移记录解决，禁止直接补写假 marker。
- 现有 `local-only` 测试仓：
  - 可用于诊断和补测试；
  - 必须提交到正确测试分支后才能进入 implementation PASS；
  - 不删除已有 evidence，但重跑后 evidence 必须记录新 revision。

---

## 9. 涉及文件与实施顺序

1. 新增 `PLAN-test-verify-lifecycle-gate.md`（本文）。
2. 先新增 `test-design.md.tmpl`、`test-plan.md.tmpl`，重写三产物协议和 manifest checklist。
3. 重构 `flow-codex-test-design`，确保先形成可独立实施/审核的设计。
4. 新增 `flow/templates/test-verify-checklist.md`。
5. 新增 `codex/skills/flow-codex-test-verify/`，用 skill-creator 脚本生成骨架和 `agents/openai.yaml`。
6. 修改 test-assign / test-apply / test-report / test / system-test / review。
7. 修改 checkpoints、integration-test-result、task 维护规则和 schema。
8. 修改 status/archive 的调用门禁。
9. 更新 validate、AGENTS、codex/PLAN、CHANGELOG。
10. 运行 `codex/validate.ps1`。
11. 运行 `codex/install.ps1` 安装到 `~/.agents/skills`。
12. 用一个原始 artifact 快照做三阶段 dry-run，再用新会话 forward-test。

---

## 10. 验收与 dry-run

### 10.1 静态验证

- [ ] `codex/validate.ps1` PASS。
- [ ] test-design 模板完整覆盖 TDD.1–TDD.10。
- [ ] test-plan 模板能从 AC 追踪到场景、方法、准备、步骤和所有关键断言。
- [ ] manifest、设计和 evidence 职责无交叉污染。
- [ ] 新 skill frontmatter、目录名和 `agents/openai.yaml` 合规。
- [ ] test-design / assign / test / archive 对三个 verify 阶段表述一致。
- [ ] 默认 `flow-codex-verify` 行为不变。
- [ ] Claude 未同步时有明确 follow-up 标记。

### 10.2 负例

以下情况必须被阻断：

- [ ] 只有 manifest/test-plan，缺 test-design。
- [ ] test-design 只有鉴权、桩、runner、SQL 四条摘要。
- [ ] 缺 SUT revision、本地拓扑、数据模型或可观测点。
- [ ] test-plan 只映射到类名，没有测试方法和核心断言。
- [ ] 方法名写“未写入”，但没有 DB/副作用断言。
- [ ] 正向需求只有负例，没有 happy path。
- [ ] test-plan 混入实际 PASS、执行时间或 EXPLAIN 结果。
- [ ] 手工勾选 `集成测试设计 READY`，但 design verify 未执行。
- [ ] 测试代码在错误分支或为 untracked/local-only。
- [ ] 缺 REVIEW_RESULT PASS 或 REPORT complete。
- [ ] runner 7 passed，但有一个验收 ID 未覆盖。
- [ ] summary 写 7 passed，Surefire 原始报告不一致。
- [ ] 业务代码 revision 在测试后发生变化。
- [ ] 直接调用 system-test PASS 后尝试完成 Goal。

### 10.3 正例

- [ ] 未参与业务开发的 agent 可仅凭 test-design/test-plan 实现测试，无需猜测验收义务。
- [ ] 未参与测试实现的 agent 可从 AC → 场景 → 方法 → 断言判断覆盖是否完整。
- [ ] design verify PASS 后可以 assign。
- [ ] review/report 完整且测试仓 revision 可恢复时 implementation PASS。
- [ ] runner 原始报告、summary、SQL evidence、cleanup 和 revision 一致时 result PASS。
- [ ] 只有 result PASS 后，`flow-codex-test` 才勾选最终检查项。

### 10.4 Forward-test

使用不含预期答案的新 agent，分别给出：

1. 完整合规测试 change；
2. 7 passed 但验收映射缺失的 change；
3. 测试通过但代码为 untracked/local-only 的 change；
4. 直接运行 runner、无 review/report 的 change。

预期：仅场景 1 可得到完整 `INTEGRATION_TEST_RESULT PASS`。

---

## 11. 检视要求（一票否决）

| ID | 条件 |
|----|------|
| V1 | `flow-codex-test-design` 仍只是 manifest/scaffold 辅助，没有完整测试设计协议 |
| V2 | test-plan 仍允许只写测试类而不写场景、方法、准备和断言 |
| V3 | 设计文档仍承载实际 PASS/evidence，或 manifest 被用作覆盖证明 |
| V4 | 新 verify skill 会编辑业务或测试产物 |
| V5 | `flow-codex-verify` 原 format/design/full/release 行为被破坏 |
| V6 | assign/test 仍允许 task checkbox 代替 test verify PASS |
| V7 | system-test standalone PASS 仍可勾选 Flow 完成 |
| V8 | result verify 不核对原始报告、revision 或 manifest |
| V9 | `local-only` 默认可进入 release/Goal complete |
| V10 | test verify 与 test review 职责重复，或 verify 开始审核业务代码实现 |
| V11 | `codex/validate.ps1` 失败、P0 文件遗漏或调用链表述不一致 |

检视输出：

```markdown
## [PLAN_REVIEW] PASS | REJECT

**范围**：<commit/PR>
**validate.ps1**：PASS | FAIL

### P0
- [PASS|REJECT] test-design/test-plan/manifest 三产物协议：…
- [PASS|REJECT] 新 flow-codex-test-verify：…
- [PASS|REJECT] design / implementation / result 三模式：…
- [PASS|REJECT] assign / test / system-test 硬门禁：…
- [PASS|REJECT] revision 与原始 evidence：…

### 一票否决
- V1–V11：无 | 触发 Vx：…

### 问题（REJECT 时必填）
1. <文件>:<行或节> — <违反本文哪条> — <修复方式>
```

---

## 12. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 测试设计文档过重 | 复杂度分级；字段 mandatory，但简单需求可用紧凑表格，不重复业务 OpenSpec |
| test-plan 与 Java 代码重复 | 计划描述验证义务和关键断言，不复制完整 payload/实现代码；公共输入引用 fixture |
| 三次 verify 增加流程成本 | 每次只读且按阶段扫描；不启动服务；输出固定结构 |
| 历史 local-only change 无法通过 | 仅在再次 test/release 时补正，不批量改历史记录 |
| 验收映射判断过于主观 | design 模式要求“方法 + 核心断言”的客观映射；语义争议降 WARN 并列原文 |
| 测试仓天然含多个 change 的共享改动 | 要求 scoped clean，而非整个仓绝对 clean；未知改动才阻断 |
| 原始报告会被后续运行覆盖 | evidence 保存 revision、时间和报告摘要/hash；需要时复制到 change evidence |
| 双平台漂移 | P0 明确 Codex 边界；Claude 侧单独评估，不做虚假同步 |

---

## 修订记录

| 日期 | 说明 |
|------|------|
| 2026-07-31 | 初稿：基于海外模板测试 Flow 偏离，增加三阶段独立 test verify 与硬门禁 |
| 2026-07-31 | 重构：将根因提升为整体测试设计协议不足；增加 test-design/test-plan/manifest 边界、SUT revision、拓扑、场景和断言契约 |
