# Flow 自动化旧规则迁移矩阵

## 范围与使用方式

本文是可验证自动化改造的唯一迁移索引。它覆盖实施入口 WP0 要求的全部现存
`PLAN-test-*.md` 与 `PLAN-design-*.md`，以及当前 Codex 适配层规则。每个旧 PLAN
仅出现一次；后续 Work Package 必须以本表的“新归属”为准，而不是并行扩写旧计划。

“当前实现位置”描述 WP0 开始时的事实基线，不表示该位置继续拥有最终权威性。
`keep` 表示保留用户可见语义并迁移其执行权威；`replace` 表示由控制器或单一事实源
取代其规则承载方式；`remove` 表示不再保留为独立门禁或独立权威。

| 旧 PLAN/规则 | 当前实现位置 | 新归属 | keep/replace/remove | 生效 WP |
|---|---|---|---|---|
| `PLAN-test-verify-lifecycle-gate.md` | `flow-codex-test-verify`、`flow/docs/schema.md` §11 | controller machine state 的阶段转换；verifier 只提交结构化结论 | replace | WP3、WP6 |
| `PLAN-test-flow-simplification-and-config-stop.md` | 测试 manifest 配置契约、`flow-codex-test-design`、`flow-codex-system-test` | controller 的 environment ownership route 与经认证 harness 的环境检查 | replace | WP3、WP5、WP6 |
| `PLAN-test-flow-authorization-and-scope-guards.md` | manifest `testAuthorization`、范围守卫脚本、test skills | controller lease、授权状态与 canonical repository/path 校验 | replace | WP3、WP6 |
| `PLAN-test-failure-reporting-and-triage.md` | `collect-failure-evidence.ps1`、`flow-codex-test-verify`、evidence 目录 | failure fingerprint、责任路由与新 revision 的受控输入 | keep | WP3、WP5、WP6 |
| `PLAN-test-executable-readiness-gate.md` | design/implementation verify 规则、runner 调用链 | 对应阶段的确定性 transition guard；不保留独立 readiness 凭据 | remove | WP3、WP4、WP5 |
| `PLAN-design-verify-journey.md` | `verify_mode=design` 的链路检查与 `verify-checklist.md` | `domain-model.md` 事实消费和 solution verify 的可追溯检查 | replace | WP1、WP2 |
| `PLAN-design-verify-domain-concepts.md` | design verify 概念检查、设计模板与检查清单 | `domain-model.md` 的 Fact ID / Decision ID 协议及 domain verify | replace | WP1、WP2 |
| `PLAN-design-verify-assign-gate.md` | design/verify/assign skills、`verify-checklist.md` | solution verification 结果进入 controller state 后签发 assignment lease | replace | WP2、WP3、WP6 |
| `codex/PLAN.md`（当前 Codex 生命周期规则） | `codex/PLAN.md`、`AGENTS.md`、`flow-codex-core` 平台引用 | 保持公开入口与生命周期术语；执行授权和完成状态由 controller state 统一裁决 | keep | WP3、WP6 |

## 迁移约束

- 旧文档可作为历史设计依据，但不得被实现或安装后的 skill 当作并行运行时权威。
- 在对应 WP 落地前，现有规则继续作为兼容边界；不得借迁移矩阵绕过现有授权、范围、revision 或失败停止规则。
- 迁移完成后，派生产物中的重复计数、场景清单和阶段声明必须由对应的单一事实源生成或校验。
