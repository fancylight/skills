# Flow 可验证自动化实施入口

## 0. 给执行 Agent 的唯一入口

本文件是本轮 skills 改进的唯一实施入口。不要同时把三份架构文档全部加载后自行拆任务。

阅读顺序：

1. 先完整读取本文件；
2. 确认当前只处理一个 Work Package；
3. 只读取该 Work Package 指定的参考设计章节；
4. 检查 `git status --short`，保留并避开现有未提交改动；
5. 按“允许修改文件”实施；
6. 执行该包自己的验证；
7. 输出结构化 checkpoint，停止等待下一包派发。

三份参考设计：

| 文档 | 何时读取 | 用途 |
|---|---|---|
| [`PLAN-flow-verifiable-automation-architecture.md`](./PLAN-flow-verifiable-automation-architecture.md) | WP0、架构争议时 | 总体原则、状态和迁移边界 |
| [`PLAN-domain-discovery-and-design-truth-gate.md`](./PLAN-domain-discovery-and-design-truth-gate.md) | WP1–WP2 | 领域事实产物和 domain verify |
| [`PLAN-system-test-controller-and-validation.md`](./PLAN-system-test-controller-and-validation.md) | WP3–WP7 | 控制器、场景源、harness、goal 和验证 |

## 1. 实施约束

### 1.1 仓库规则

- 只修改当前 skills 仓库根目录及当前 Work Package 明确列出的相对路径；
- 不编辑 `~/.agents/skills` 安装副本；
- 共享模板只改 `flow/templates/`；
- Codex 平台实现改 `codex/skills/`、`codex/scripts/` 和 `codex/install.ps1`；
- 协议字段改动同步 `flow/docs/schema.md`；
- Claude 侧只在对应 Work Package 明确要求时同步；
- 不清理、reset、覆盖或提交与当前 Work Package 无关的已有修改。

### 1.2 工作粒度

- 一次只实施一个 Work Package；
- 一个 Work Package 可以拆多个小提交，但不得跨包提交；
- 不允许多个 agent 并发修改同一文件；
- 发现前置包未满足验收时，停止并报告，不在后续包中顺手补救；
- 设计存在歧义时回到本入口记录决策，不由实现 agent临时发明协议。

### 1.3 每包统一输出

```text
[FLOW_AUTOMATION_WP_RESULT] PASS | BLOCKED
work_package: WP<n>
changed_files:
  - <path>
validation:
  - <command>: PASS | FAIL
remaining:
  - <item or none>
next: WP<n+1> | STOP_FOR_REVIEW
```

## 2. 依赖图

```text
WP0 基线与迁移矩阵
 |
 +--> WP1 领域产物协议
 |      |
 |      +--> WP2 Domain verify 与设计传导
 |
 +--> WP3 最小状态控制器
        |
        +--> WP4 测试场景单一事实源
        |
        +--> WP5 Harness 认证与环境路由
                    |
                    +--> WP6 Skills 接入与 Goal 调度
                                   |
                                   +--> WP7 回放、Forward test 与启用门禁
```

WP1 和 WP3 在 WP0 后可以由不同 agent 并行，但当前仓库存在大量重叠未提交修改时，默认串行。

## 3. WP0：基线、旧计划迁移矩阵与 ADR

### 目标

建立新架构的事实基线，明确哪些旧 PLAN 被吸收、保留或废弃，避免实现时出现多个权威规则。

### 必读

- `PLAN-flow-verifiable-automation-architecture.md`；
- 根目录所有 `PLAN-test-*.md`、`PLAN-design-*.md`；
- `MAINTENANCE.md`；
- `flow/docs/schema.md`；
- `codex/PLAN.md`。

### 允许修改文件

- 新增 `docs/architecture/flow-automation-migration-matrix.md`；
- 新增 `docs/architecture/flow-automation-decisions.md`；
- 本入口文档仅允许修正路径和依赖，不扩写架构。

### 必须产出

迁移矩阵至少包含：

```markdown
| 旧 PLAN/规则 | 当前实现位置 | 新归属 | keep/replace/remove | 生效 WP |
```

ADR 至少裁决：

- machine state 的存储位置和格式；
- controller 使用 PowerShell 还是跨平台实现；
- `test-cases.yaml` 是否作为权威源；
- harness 认证按 version 还是 revision；
- Claude 与 Codex 是同步上线还是 Codex 先行；
- 旧 `testAuthorization.ceiling` 如何迁移。

### 验证

- 每份现存相关 PLAN 在迁移矩阵中恰好出现一次；
- 每项 ADR 只有一个 accepted 结论；
- 不修改任何 skill 或模板。

### 停止条件

任一核心 ADR 未裁决时不得进入 WP1/WP3。

## 4. WP1：领域事实产物协议

### 目标

新增 `domain-model.md` 模板、Fact ID 和 Decision ID 协议，但暂不修改 verify 行为。

### 必读

- `PLAN-domain-discovery-and-design-truth-gate.md` §1–§5；
- WP0 ADR；
- `flow/templates/overview-design.md.tmpl`；
- `flow/docs/schema.md`；
- `codex/skills/flow-codex-design/SKILL.md`。

### 允许修改文件

- 新增 `flow/templates/domain-model.md.tmpl`；
- 修改 `flow/docs/schema.md`；
- 修改 `codex/skills/flow-codex-design/SKILL.md`；
- 必要时修改 `codex/skills/flow-codex-design/agents/openai.yaml`；
- 修改 `codex/install.ps1`，确保模板安装到 core assets；
- Claude 对应 design command/skill（按 WP0 ADR）。

### 实现要求

- `flow-codex-design` 必须先生成 DOMAIN_DRAFT；
- 领域事实包含 Fact ID、生效条件、不生效条件、证据和影响 Decision ID；
- 方案设计前输出明确 checkpoint，不得同一动作内直接生成概要设计；
- 不要求扫描整个系统，只覆盖本 change 的实现决策点；
- 不允许概要设计作为领域事实证据。

### 验证

1. `domain-model.md.tmpl` 可生成完整 Markdown；
2. 缺 Fact ID、条件、反例或证据的示例能被基础校验拒绝；
3. `codex/install.ps1` dry-run/安装检查能找到新模板；
4. `codex/validate.ps1` 无新增 ERROR；
5. Claude 同步范围符合 WP0 ADR。

### 完成定义

Skill 能稳定停在 DOMAIN_DRAFT 并提示执行 `flow-codex-verify verify_mode=domain`，但 domain verifier 尚可在 WP2 才实现。

## 5. WP2：Domain verify 与方案传导

### 目标

实现领域真实性审核，并阻止未经验证的 Fact ID 进入概要设计和 OpenSpec。

### 必读

- `PLAN-domain-discovery-and-design-truth-gate.md` §6–§11；
- WP1 产物协议；
- `flow/templates/verify-checklist.md`；
- `codex/skills/flow-codex-verify/SKILL.md`；
- `codex/skills/flow-codex-review/SKILL.md`。

### 允许修改文件

- `flow/templates/verify-checklist.md`；
- `flow/templates/overview-design.md.tmpl`；
- `codex/skills/flow-codex-verify/SKILL.md`；
- `codex/skills/flow-codex-design/SKILL.md`；
- `codex/skills/flow-codex-review/SKILL.md`；
- `codex/scripts/` 下新增或修改领域 artifact validator；
- `codex/validate.ps1`；
- 对应 schema、安装和 Claude 同步文件。

### 实现要求

- 增加 `verify_mode=domain`；
- verifier 独立抽查高风险领域事实，不能只检查表格存在；
- DOMAIN_VERIFIED 之前 design skill 不生成 solution artifacts；
- 概要设计、OpenSpec 和 review 使用 Fact ID；
- design verify 检查事实消费和反例传导，不重复假装验证事实本身。

### 必备测试夹具

- 条件字段只在某类型生效；
- `null` 不是合法聚合键；
- 同名覆盖与不同名独立；
- 导出/导入状态范围不一致；
- 文档一致但领域事实与代码证据冲突；
- KB 与当前代码冲突且未裁决。

### 验证

- validator 正反例测试；
- domain verify 对上述错误全部 ERROR；
- 已通过 domain 的 Fact ID 能传导到概要设计和 OpenSpec；
- 现有不涉及新 domain 阶段的兼容策略符合 WP0 ADR；
- `codex/validate.ps1` 和 Claude 校验无新增 ERROR。

## 6. WP3：最小可执行状态控制器

### 目标

先实现最小控制器，不接入 goal，不实现完整 harness。优先证明状态、revision 和 scope 能由程序拒绝。

### 必读

- `PLAN-system-test-controller-and-validation.md` §1–§5、§9；
- WP0 ADR；
- `codex/scripts/test-scope-guard.ps1`；
- `codex/scripts/validate-test-artifacts.ps1`；
- `flow/docs/schema.md`。

### 允许修改文件

- 新增 `codex/scripts/flow-test-controller.ps1`；
- 新增 `codex/scripts/tests/test-flow-test-controller.ps1`；
- 修改 `flow/docs/schema.md`；
- 修改 `codex/install.ps1`；
- 必要时新增 `flow/templates/system-test/changes/.flow-state.example.yaml`；
- 此包不修改任何 test skill 行为。

### 最小命令

```text
status
next
initialize
issue-lease
validate-lease
accept-result
record-verifier
record-run
block
```

### 首版必须保护

- 合法和非法 phase transition；
- SUT/test revision lock；
- canonical repository/path；
- lease role、capability 和 allowed paths；
- verifier revision 一致性；
- 同 revision runner 唯一性；
- failure fingerprint 去重；
- state 原子写入和损坏恢复。

### 验证

- 每条合法转换有单元测试；
- 每条非法跨级转换被拒绝；
- 超路径 diff、过期租约、SUT 漂移和重复 runner 被拒绝；
- state 不包含 secret；
- 中途写入失败不会留下半个状态文件；
- `codex/validate.ps1` 无新增 ERROR。

## 7. WP4：测试场景单一事实源

### 目标

引入 `test-cases.yaml` 和派生校验，消除 test-plan、manifest、Java 和 evidence 的场景漂移。

### 必读

- `PLAN-system-test-controller-and-validation.md` §6；
- `flow/templates/test-design.md.tmpl`；
- `flow/templates/test-plan.md.tmpl`；
- `flow/templates/test-verify-checklist.md`；
- `codex/skills/flow-codex-test-design/references/manifest-checklist.md`。

### 允许修改文件

- 新增 `flow/templates/test-cases.yaml.tmpl`；
- 新增 `codex/scripts/validate-test-cases.ps1`；
- 新增对应测试脚本；
- 修改测试设计、计划和 verify 模板；
- 修改 `flow/docs/schema.md`；
- 修改相关 test-design/test-verify skills；
- 修改安装和双平台同步文件。

### 实现要求

- `test-cases.yaml` 是场景映射的唯一权威；
- Markdown 保留人读说明，不维护第二份可执行计数；
- Java 测试方法通过稳定 ID 绑定场景；
- manifest count、report class、filter 和 evidence 映射由生成器生成或严格校验；
- 删除 required 场景必须回到 test design verify，不能在测试修复阶段完成。

### 验证

- ID 重复、缺失、Java 未绑定、report class 漂移、evidence 陈旧全部失败；
- integration-N 缺外部证据失败；
- 从同一场景源重复生成结果完全一致；
- 生成器不覆盖人工说明区；
- 旧 manifest 迁移策略符合 WP0 ADR。

## 8. WP5：Harness 认证与环境责任路由

### 目标

将 runner 平台能力与具体业务 change 解耦，建立 self-test、认证结果和配置所有权路由。

### 必读

- `PLAN-system-test-controller-and-validation.md` §7–§10；
- `flow/templates/system-test/scripts/system-test.ps1`；
- `flow/templates/system-test/scripts/collect-failure-evidence.ps1`；
- `codex/skills/flow-codex-system-test/references/runtime-contract.md`；
- 现有 runner 相关测试。

### 允许修改文件

- `flow/templates/system-test/scripts/`；
- `flow/templates/system-test/test-support/`；
- 新增 `flow/templates/system-test/self-test/`；
- `codex/scripts/tests/`；
- system-test skill 及 runtime references；
- schema、安装和双平台同步文件。

### 实现要求

- harness certification 绑定 revision/version；
- 未认证 harness 不能运行业务 suite；
- 配置来源和 ownership 固定；
- 人工所有配置失败只返回 BLOCKED；
- 平台所有配置进入独立 harness 修复；
- API 业务 suite 不再被无关 SQL/evidence 平台规则提前阻断；
- PASS 和 FAIL 都可靠 cleanup 并输出原始报告索引。

### Self-test 场景

- 正常运行；
- SUT 启动失败；
- MySQL/PG/Redis 不通；
- WireMock unmatched；
- Maven `-D` 和含空格参数；
- Surefire 报告缺失；
- seed/cleanup 失败；
- 中文日志和编码；
- 中途终止；
- evidence 文件缺失。

### 验证

- 所有 self-test 生成结构化结果；
- 失败类别和 evidence 可复现；
- 未认证 revision 被 controller 拒绝；
- 修改 harness 后旧 certification 自动失效；
- 业务 change 不需要修改 runner 才能运行标准 API suite。

## 9. WP6：Skills 接入控制器与 Goal 调度

### 目标

让现有公开 skills 使用 controller state 和 lease；goal 只请求 `next`，不能自由选择后续 skill。

### 必读

- `PLAN-system-test-controller-and-validation.md` §11–§12；
- WP3–WP5 的实现与测试；
- 所有 `flow-codex-test-*` SKILL；
- `codex/skills/flow-codex-core/references/checkpoints.md`；
- `AGENTS.md` 生命周期说明。

### 允许修改文件

- `codex/skills/flow-codex-test-*`；
- `codex/skills/flow-codex-system-test/`；
- `codex/skills/flow-codex-core/`；
- `flow/templates/codex/test-child-agent-prompt.md`；
- `AGENTS.md`、`README.md`、`CHANGELOG.md`；
- schema、安装和 Claude 对应文件。

### 接入顺序

1. test-design；
2. test-verify design；
3. test-assign/receive/apply；
4. test-verify implementation；
5. system-test；
6. test-verify result；
7. flow-codex-test 总编排。

每接入一个 skill 就运行 controller contract tests，不要全部修改后一次验证。

### Goal 协议

- Goal 读取 `controller next`；
- `next=BLOCKED` 时必须停止并报告；
- `next=COMPLETE` 时才能完成；
- 其他情况下只执行返回租约中的一个动作；
- Skill 自己推导出的建议不得提升 state 或 authorization；
- 不允许以用户“尽量完成”替代 machine transition。

### 验证

- 每个 skill 在错误 phase 被拒绝；
- 旧 agent 或无 lease agent 无法写入；
- agent 口述 PASS 不改变 state；
- goal 不能跳过 implementation/result verify；
- 公开入口兼容策略符合 WP0 ADR；
- `codex/validate.ps1`、安装冒烟和 Claude 校验通过。

## 10. WP7：事故回放、Forward test、Shadow 与启用

### 目标

证明新流程确实阻止已知事故，并能完成不同类型的真实测试任务。此包不再开发新功能，发现缺陷必须回到责任 Work Package。

### 必读

- 三份参考设计的验证章节；
- `docs/case-studies/`；
- WP0 的通用事故夹具和 ADR；
- WP1–WP6 的全部验证结果。

### 允许修改文件

- `docs/case-studies/`；
- `codex/scripts/tests/fixtures/`；
- 新增验证报告；
- 不修改业务仓或真实业务 change。

### 验证批次

#### Batch A：确定性测试

- controller 单元测试；
- schema/生成器测试；
- scope/revision/fingerprint 测试；
- harness self-test；
- Codex/Claude 安装与仓库校验。

#### Batch B：事故回放

逐项回放并验证首次阻断位置：

- 提前启动服务；
- 提前 runner；
- 跨仓业务修改；
- 旧 agent 恢复；
- 多测试目录；
- SUT 漂移；
- 工具输出污染；
- 相同失败重复执行；
- 删除场景或放宽断言；
- 修改 harness 绕过业务失败；
- 配置失败后切换来源。

#### Batch C：Forward test

- 单服务同步 API；
- 数据库加异步任务；
- 多服务加外部 stub；
- 平台故障；
- 真实 SUT 业务失败。

使用全新上下文，不向 agent 泄露预期答案。

#### Batch D：Shadow mode

至少观察三个现有 Flow change，只输出合法 `next` 和拒绝原因，不执行写入。与人工判断逐项比对。

#### Batch E：Goal 故障注入

在隔离仓运行持续 goal，注入配置、fixture、runner、evidence、SUT 和越界写入故障。

### 启用门禁

只有同时满足以下条件才可在真实需求启用：

- 所有非法转换与非授权写入均被阻断；
- 相同 failure fingerprint 重复执行为 0；
- 事故回放全部在首次非法动作处停止；
- Forward test 能完成 happy path 并正确路由失败；
- Shadow mode 与人工判断一致；
- Goal 故障注入无范围扩张、无循环、无错误完成；
- 有明确 rollback 到旧流程的方法。

## 11. 推荐派发方式

不要派发“实现完整 Flow 自动化”。应按以下方式逐包派发：

```text
请实现 WP<n>。只读取实施入口及 WP<n> 指定文档；只修改允许文件；
不得进入下一 WP。完成后运行本包验证并输出 FLOW_AUTOMATION_WP_RESULT。
```

推荐 ownership：

| Work Package | 适合角色 | 是否可与其他包并行 |
|---|---|---|
| WP0 | 架构/维护 agent | 否 |
| WP1 | design skill agent | WP3 可并行，前提是文件不重叠 |
| WP2 | design verify agent | 依赖 WP1 |
| WP3 | controller agent | WP1 可并行 |
| WP4 | test design agent | 依赖 WP3 |
| WP5 | harness agent | 依赖 WP3，可与 WP4 部分并行 |
| WP6 | integration agent | 依赖 WP2、WP4、WP5 |
| WP7 | 独立验证 agent | 依赖全部 |

## 12. 完成定义

完成某个 Work Package 不代表总体方案完成。只有 WP7 启用门禁全部通过后，才允许声明：

```text
[FLOW_AUTOMATION_RESULT] VERIFIED_FOR_CONTROLLED_ROLLOUT
```

在此之前只能报告当前完成的 WP 和验证结果，不能宣称 Flow 已适合 goal 全自动运行。
