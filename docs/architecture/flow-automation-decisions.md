# Flow 可验证自动化 ADR

## ADR-001：machine state 的位置与格式

**状态：Accepted**

machine state 存放在编排根目录的
`.flow/changes/<change>/automation-state.yaml`，采用带 `schemaVersion` 的 YAML 文档。
它由 controller 原子写入并作为流程状态的唯一权威；state 不保存密码、token 或完整连接串。
system-test manifest、设计文档和 verifier 输出只提供经校验的输入或结果，不能直接修改
phase、授权或 `allowedNext`。

这样使状态与一个 change 的编排边界一致，避免在业务仓、system-test 仓和多个 Markdown
产物中分别维护可变状态。

## ADR-002：controller 的首版实现语言

**状态：Accepted（路径修订：Phase 0）**

controller 首版使用 PowerShell 实现；**源代码单一事实源为 `flow/scripts/`**（原 `codex/scripts/`
已迁出，Codex 树内仅保留过渡 shim）。安装时复制到各宿主运行时资产目录（Codex：
`flow-codex-core/assets/scripts/`；Claude：`commands/flow/scripts/`）。其输入输出、state schema
和错误码必须是平台无关的；Node/跨平台重写是后续兼容工作，不作为控制器语义前置条件。

这复用当前仓库的 PowerShell 校验与测试基础，同时避免在控制器语义尚未稳定时维护两套
行为实现。

## ADR-003：测试场景的权威来源

**状态：Accepted**

每个 system-test change 的 `changes/<change>/test-cases.yaml` 是测试场景、稳定 ID、覆盖映射
和证据需求的唯一权威结构化来源。test-plan、manifest、测试方法映射、runner filter 和
evidence 清单必须由它生成或接受严格一致性校验；Markdown 只保留人读说明。

这消除多个手工场景清单之间的漂移，并让删除或变更场景成为可验证的设计阶段动作。

## ADR-004：harness 认证绑定对象

**状态：Accepted**

harness certification 绑定可复现的 harness revision（内容指纹或不可变 revision），而不是
仅绑定可变的版本号。可选的语义版本仅作人读元数据，不能单独用于授权业务 suite 运行。

因此任一 runner、测试支持代码或执行依赖的实际变更都会使旧认证失效，并要求重新执行
self-test 与认证。

## ADR-005：Codex 与 Claude 的上线顺序

**状态：Accepted（Claude 对齐进行中）**

可验证自动化的 controller、状态协议和 skill 接入**先在 Codex 上验证**。共享 schema、模板与
`flow/scripts/` 必须保持平台无关。Claude 运行时接入按独立工作包推进，且须具备**同等**
controller / 租约约束后才算完成对等（见仓库计划 Phase 0–5 与 `flow/docs/control-plane.md`）。

在 Claude 完成 lease-v1 与 test 全链之前，不得声称双宿主行为一致；缺省 `protocol_version: legacy`
保护进行中业务 change。

## ADR-006：旧 `testAuthorization.ceiling` 的迁移

**状态：Accepted**

controller 初始化时读取现有 `testAuthorization.ceiling`，将其规范化为 machine state 的
`authorization.maxPhase`。迁移后只有用户明确授权和 controller 的受控状态写入可以提升该
上限；legacy manifest 字段仅作为兼容输入或派生镜像，不再是授权权威。

现有 `design`、`implementation`、`execution`、`result` 阶段语义保持不变。任何旧 agent、
`next` 建议、revision 变化或重启都不能提升上限或重置授权。

## 后续实现约束

- WP1/WP2 必须消费 ADR-001 与 ADR-005，不能在 domain artifact 中引入第二份流程状态。
- WP3 必须实现 ADR-001、ADR-002 和 ADR-006；其测试要验证 state 原子性、无 secret 与授权单调性。
- WP4/WP5 必须分别实现 ADR-003 与 ADR-004；未经认证的 harness revision 不得执行业务 suite。
- WP6 的公开 skills 只能通过 controller lease 调度动作，不得重新解释这些 ADR。
