---
name: flow-codex-test-verify
description: 只读验证 Flow 集成测试的 canonical test-cases、派生 sidecar、设计、实现生命周期和最终运行证据。用于 test-design 后、test 前和 system-test 后的硬门禁；不编写测试、不启动服务、不修改 task。
---

# Codex Flow 集成测试验证

作为根编排 agent 或独立只读审核 agent 执行。读取
`../flow-codex-core/references/platform.md`、[检查清单](references/test-verify-checklist.md)
、`../flow-codex-core/references/test-controller.md`
及其指向的共享模板。

## 输入与边界

首先读取 controller `status`/`next`。design、implementation、result 分别只接受 `VERIFY_DESIGN`、`VERIFY_IMPLEMENTATION`、`VERIFY_RESULT`；phase 不匹配立即 ERROR。验证 PASS 后只向 controller 提交绑定 identity、mode、test/SUT/harness revision、configuration fingerprint 与安全 summary 的结构化报告，由 `record-verifier` 决定是否提升 phase；本 skill 不直接改 state。

要求提供 `change_name` 与 `verify_mode`（`design`、`implementation` 或 `result`）；当前 `testAuthorization` 从
system-test change 的 manifest 读取。缺失、与用户授权不一致或由流程自行提升均为 ERROR。
只读检查；
不得编辑业务/测试产物、启动服务、运行 runner、修改 `task.md`，也不替代 `flow-codex-review` 的代码审核。

解析根 config 的 system-test 服务仓和 `changes/<change_name>/`。任何缺失、revision 漂移或无法追溯的
证据均为 ERROR，不以 task 勾选或执行者口述替代。

## 检查

1. `design`：先独立运行 `flow-codex-core/assets/scripts/validate-test-artifacts.ps1 -Mode design
   -CanonicalRevision <test revision>`，再运行
   `validate-test-cases.ps1 -Mode design -CanonicalRevision <test revision> -ManifestPath <manifest>
   -DerivedContractPath <test-cases.generated.json> -TestPlanPath <test-plan>`；guard ERROR 必须列为 ERROR，绝不自动修复。确认
   `test-cases.yaml` 是唯一可执行场景来源，test-plan 没有第二份计数/映射，稳定 ID 无重复/缺失，manifest 计数、
   integration Y/N、report class、filter、evidence、failureObservability 与 source revision/hash 一致；删除 required
   场景必须消费 controller state 绑定的结构化 design verifier PASS。integration-N 场景必须包含外部证据契约。
   读取根概要设计验收、操作链路/数据访问契约、已提交 SUT revision、`test-design.md`、
   `test-plan.md`、manifest 与 fixtures。按 TD.1–TD.11 验证三产物职责、AC 场景映射、拓扑、真实/桩边界、
   夹具、SQL 计划、scoped-clean 基线与配置契约；仅允许对用户确认的来源执行一次最小只读探针，失败即
   `[TEST_CONFIGURATION] BLOCKED` / `STOP_AWAIT_HUMAN_CONFIGURATION`。
2. `implementation`：读取设计 PASS、进度文件、review 结果、测试代码、静态实现校验记录与测试仓 Git 状态。
   按 TI.1–TI.8 验证场景/断言落实、无必需 skip、外部桩一致、同一可恢复 revision 和 local-only waiver；运行
   `validate-test-cases.ps1 -Mode implementation -CanonicalRevision <test revision> -ManifestPath <manifest>
   -DerivedContractPath <test-cases.generated.json> -TestPlanPath <test-plan> -JavaSourceRoot <java root> -EvidenceRoot <evidence root>`
   校验每个 Java 测试方法以稳定 ID 绑定且无未知、重复或类/方法漂移，
   并重新核验 sidecar/manifest/report/evidence 的 canonical revision 与 source hash；提供 EvidenceRoot 时普通与外部证据均须存在。
3. `result`：只在 controller `next=VERIFY_RESULT`（即已记录 runner PASS）时读取 implementation PASS、runner 原始报告、
   evidence、根 `集成测试.md`、manifest 与业务/测试 revision，按 TR.1–TR.8 验证计数、必需 suite、cleanup、SQL evidence
   与结果记录一致。runner FAIL 的 evidence index、failure report、原始报告与归因完整性必须在 `record-run` 前检查；记录后
   controller `next=BLOCKED`，不得调用本模式或输出 result PASS。缺任一关键证据须在记录运行前输出
   `[TEST_EVIDENCE_INCOMPLETE] ERROR`，结论只能是 `UNDETERMINED`，不得提升为业务缺陷。

`verify_mode: result` 还要求 `testAuthorization.ceiling=result`；若仅授权 execution，只保留 runner evidence 并输出
`next: STOP_AWAIT_USER_AUTHORIZATION`，不得给出 result PASS 或更新最终状态。

语义争议应列 WARN 并引用原文；缺少客观证据、required 场景或安全边界时列 ERROR。成功的 runner 只能证明
`SYSTEM_TEST_RESULT`，不能替代本 skill 的 result PASS。

## 输出

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
authorization_ceiling: design | implementation | execution | result
next_authorized: true | false
```

若当前生命周期下一步超过 authorization ceiling，输出 `next: STOP_AWAIT_USER_AUTHORIZATION` 和
`next_authorized: false`；verify 本身不得提升 ceiling、启动服务或修改产物。

implementation PASS 后，ceiling>=execution 时下一步为 `flow-codex-test`；否则必须停止等待用户授权。本 skill 不启动
服务或 runner，也不推断、修复或切换配置来源。
