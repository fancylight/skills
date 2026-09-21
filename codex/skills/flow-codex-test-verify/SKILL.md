---
name: flow-codex-test-verify
description: 只读验证 Flow 集成测试的 canonical test-cases、派生 sidecar、设计、实现生命周期和最终运行证据。用于 test-design 后、test 前和 system-test 后的硬门禁；不编写测试、不启动服务、不修改 task。
---

# Codex Flow 集成测试验证

进入本技能先按 `../flow-codex-core/references/test-observation.md` 记录阶段 `review`；阶段切换、暂停、恢复与交付由 Agent 调用计时入口，运行细分由 runner 生成。计时异常只警告，不阻断测试。


正式测试先读取 `../flow-codex-core/references/test-execution-cycle.md`。已接入 execution 的需求使用 `flow-test.ps1 status`，按其 prepare/advance/resume 路径推进；以下旧 next/租约步骤仅用于尚未接入的需求。允许已审核的最小切片先正式运行，其余场景保持未验证；同一对话继续，不新增用户阶段。

审核业务判断时先读取 `../flow-codex-core/references/design-challenge.md`，在现有审核中核对原始依据和可证伪输入；结构检查不得自动产生语义 PASS。

单对话按 core/references/test-controller.md 以真实当前身份完成分阶段自查。result 阶段若项目已有 local-delivery.json，应向 validate-test-artifacts.ps1 传 LocalDeliveryPlan、LocalDeliveryEvidence、PythonExecutable，合并只读核验结果；该检查不执行测试，也不替代正式门禁。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「测试与排障」。沿用现有结果与授权机制，不增加阶段。

作为根编排 agent 或独立只读审核 agent 执行。读取
`../flow-codex-core/references/platform.md`、[检查清单](references/test-verify-checklist.md)
、`../flow-codex-core/references/test-controller.md`
及其指向的共享模板。

## 输入与边界

首先读取状态。已接入 execution 且有 development 的 design 审核走 test-execution-cycle.md 的 review-design：核对当前 designBinding，审核业务设计及静态产物，不受旧执行预算或旧运行 revision 锁阻断，不使用下面的旧 phase 门禁；完整设计缺项仍不能 PASS。implementation 的版本接纳走 resume，result 沿用执行结果审核。尚未接入 execution 的旧流程才读取 controller `status`/`next`，design、implementation、result 分别只接受 `VERIFY_DESIGN`、`VERIFY_IMPLEMENTATION`、`VERIFY_RESULT`；phase 不匹配立即 ERROR。验证 PASS 后只向 controller 提交绑定 identity、mode、test/SUT/harness revision、configuration fingerprint 与安全 summary 的结构化报告，由 `record-verifier` 决定是否提升 phase；本 skill 不直接改 state。

要求提供 `change_name` 与 `verify_mode`（`design`、`implementation` 或 `result`）；初始 `testAuthorization` 从 manifest 读取；初始化后的当前上限读取 controller `authorization.maxPhase` 和 grants（协议中的追加授权记录）。旧state可无grants，继续沿用原锁定上限；任何新增授权必须入账。授权缺失、与用户授权不一致或由流程自行提升均为 ERROR。
只读检查；
不得编辑业务/测试产物、启动服务、运行 runner、修改 `task.md`，也不替代 `flow-codex-review` 的代码审核。

解析根 config 的 system-test 服务仓和 `changes/<change_name>/`。任何缺失、revision 漂移或无法追溯的
证据均为 ERROR，不以 task 勾选或执行者口述替代。

## 检查

1. `design`：先核对生成计划中的业务输入、规则分支、独立预期及推导、关键反例、Y/N和真实最终落点，再检查技术设计能否实际证明这些预期。不得用方法数、字段齐全或静态脚本PASS替代业务覆盖审核；语义无法确定时保留缺口。存量旧PASS不是新规则的通过证据，先按协议重开复核。
   从 controller `revisions.testBaseline` 读取稳定的 `<test baseline revision>`；当前设计提交由
   `revisions.designRevision`/`revisions.test` 单独锁定，不能拿它替换 sidecar 基线。先独立运行
   `flow-codex-core/assets/scripts/validate-test-artifacts.ps1 -Mode design
   -CanonicalRevision <test baseline revision>`，再运行
   `validate-test-cases.ps1 -RequireBusiness -Mode design -CanonicalRevision <test baseline revision> -ManifestPath <manifest>
   -DerivedContractPath <test-cases.generated.json> -TestPlanPath <test-plan>`；guard ERROR 必须列为 ERROR，绝不自动修复。确认
   `test-cases.yaml` 是唯一可执行场景来源，test-plan 没有第二份计数/映射，稳定 ID 无重复/缺失，manifest 计数、
   integration Y/N、report class、filter、evidence、failureObservability 与 source revision/hash 一致；删除 required
   场景必须消费 controller state 绑定的结构化 design verifier PASS。integration-N 场景必须包含外部证据契约。
   读取根概要设计验收、操作链路/数据访问契约、已提交 SUT revision、`test-design.md`、
   `test-plan.md`、manifest 与 fixtures。按 TD.1–TD.11 验证三产物职责、AC 场景映射、拓扑、真实/桩边界、
   夹具、SQL 计划、scoped-clean 基线与配置契约；仅允许对用户确认的来源执行一次最小只读探针，失败即
   具体配置诊断及证据；已有授权内可修复的问题返回修复步骤，只有缺失用户信息或权限才暂停对应动作。
2. `implementation`：读取设计 PASS、进度文件、review 结果、测试代码、静态实现校验记录与测试仓 Git 状态。若用户在实施中修订范围，按test-controller.md复核当前提交绑定的scopeDesignReviews及删除证据；它仅补充范围设计审核，不代替代码review和本模式门禁。
   按 TI.1–TI.8 验证场景/断言落实、无必需 skip、外部桩一致、同一可恢复 revision 和 local-only waiver；运行
   `validate-test-cases.ps1 -Mode implementation -CanonicalRevision <test baseline revision from controller> -ManifestPath <manifest>
   -DerivedContractPath <test-cases.generated.json> -TestPlanPath <test-plan> -JavaSourceRoot <java root> -EvidenceRoot <evidence root>`
   校验每个 Java 测试方法以稳定 ID 绑定且无未知、重复或类/方法漂移，
   并重新核验 sidecar 的稳定 baseline revision、source hash、manifest/report/evidence 与 controller 当前实现 revision；
   baseline 不随设计或实现提交变化，当前 revision 仍必须通过 controller 独立一致性校验。提供 EvidenceRoot 时普通与外部证据均须存在。
3. `result`：只在 controller `next=VERIFY_RESULT`（即已记录 runner PASS）时读取 implementation PASS、runner 原始报告、
   evidence、根 `集成测试.md`、manifest 与业务/测试 revision，按 TR.1–TR.8 验证计数、必需 suite、cleanup、SQL evidence
   与结果记录一致。runner FAIL 的 evidence index、failure report、原始报告与归因完整性必须在 `record-run` 前检查；记录后
   controller `next=BLOCKED`，不得调用本模式或输出 result PASS。缺任一关键证据须在记录运行前输出
   `[TEST_EVIDENCE_INCOMPLETE] ERROR`，结论只能是 `UNDETERMINED`，不得提升为业务缺陷。

`verify_mode: result` 还要求 `controller.authorization.maxPhase=result`；若仅授权 execution，只保留 runner evidence 并输出
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
