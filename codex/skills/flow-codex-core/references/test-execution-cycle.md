# 单对话测试执行与恢复

这是现有 controller / runner 的执行方式，不增加审核角色。`flow-test.ps1` 是薄入口，使用根 change 原来的 `automation-state.yaml`，不创建第二份当前状态。设计、编码和语义判断仍由当前 Agent 负责。以下规则用于已初始化 controller 的 v2 manifest；旧命令保留用于尚未接入的需求，接入后旧写命令返回新入口，不能绕过截止时间。

## 先证明链路，再展开覆盖

先审核业务输入、独立预期及关键反例，再确定真实/替身边界、必要服务和订阅者、触发动作、结果关联标识、完成条件、清理范围。测试夹具必须保持真实的数据关系。

从 canonical `test-cases.yaml` 选择覆盖主要风险的最小切片，先完成选中代码的审核、构件和环境核验，再正式运行。不要求其余场景已实现；未选中场景保持 PENDING。正式切片与全量使用同一 runner，不把 standalone 改标签作为正式证据。

普通场景一次必要投递，等待本次关联结果，集中断言。更正/重放只有业务用例明确要求时才有第二次动作，驱动不能隐式补发。独立数据可批量准备和投递；复用已核实版本和身份的服务，不等待共享队列清空或全局累计 ACK。订阅者缺失、夹具关系错误等公共链路故障先修一次，不让大矩阵重复失败。

首个切片完成后用实测耗时校准剩余成本。在原 test-plan 中明确等待条件和预计耗时，未证明拓扑可运行前不展开大规模测试实现。

## 四个入口

```powershell
$entry = '<core>/assets/scripts/flow-test.ps1'
& $entry prepare -StatePath <root-change>/automation-state.yaml -ScenarioIds <首组ID>
& $entry advance -StatePath <state> -ReviewPath <切片审核.json>
& $entry advance -StatePath <state> -ResultReviewPath <结果审核.json>
& $entry resume -StatePath <state> -RepairPath <修复影响审核.json> -ScenarioIds <下一组ID>
& $entry status -StatePath <state>
```

`prepare` 持久化开始时间，再检查 Git、canonical 场景源/过滤器和 harness certification，打印工具生成的 bindingKey。重复 prepare 不改变原预算、选择或结果。已有状态失败但没有 active run 时也可接入；旧运行保留。

`advance` 不自动生成审核 PASS。它接收当前 Agent 的真实审核结果，校验版本与场景绑定，先登记 active run，再启动 manifest runner，最后登记原始结果。选中 runner PASS 仍是 AWAITING_REVIEW；只有对应语义结果审核通过才成为场景 PASS，全部 canonical 场景均有效通过才进入 TEST_RESULT_VERIFIED。

环境预检同时核对实际构件：每个 SUT 的启动契约须提供经审核的只读 `-ValidateOnly`，验证构建回执、源码版本、JDK、产物路径和哈希，不能启动服务。未支持时给出具体阻断，不猜测该参数可用。预检失败记录为 `TEST_ENVIRONMENT_FAILED`，保留报告并经 `resume` 修复；不循环直接 `advance`。SUT 仅豁免未跟踪的 `logs/**/*.log` 运行日志，保留原文件；源码和其他未知文件仍须处理。

旧需求某服务使用已核实的历史分支时，`flow-git bind --change <change.json> --existing` 将例外限定到该需求和当前 Git 工作目录；不改根分支、不创建 worktree，不把 Flow 临时降级为无编号任务。

`resume` 统一处理测试代码、过滤器、夹具、配置、业务版本和已批准范围变化。变更必须是可恢复的提交；环境文件由原环境验证核验。提交和审核仍遵守 Git 规范与原用户授权。当前测试实施职责不能修改业务源码；需要业务修复时，在当前对话回业务步骤，完成代码审核和测试，再附 businessReviewPath 接回。原范围修复无需反复询问授权。

## 审核输入

审核 JSON 是现有审核的机器封套，prepare/advance/resume 自动生成带版本、场景和运行编号的审核输入，路径由 status 的 reviewInputPath、repairInputPath、pendingResultReviews 给出。初始结论一律 PENDING；Agent 只补业务判断、反例、耗时估计、失败分析和实际审核结论，不反复抄写指纹及映射。工具不覆盖已经填写的输入，只检查完整性和绑定，不能判断文字结论正确。

切片审核包含 `bindingKey`、`scenarioIds`、`review: self|independent`、`reviewer`、审核者决定的 `result`；`design/implementation/environment` 各含 `result/summary/evidencePaths`；并给出 `counterexample`、`waitCondition`、`estimatedSeconds`。design 依据遵循 design-challenge.md；implementation 检查选中方法的真实断言和夹具；environment 包含现有环境校验原始报告，不用说明文字替代运行校验。

结果审核包含 `runId/bindingKey/review/reviewer/result/summary/evidencePaths`，核对实际输入、关联结果、断言、版本、清理和未覆盖项。已知缺陷必须有同一断言的红/绿证据。字段齐全不能代替审核结论，REJECT 不得写成 PASS 以解锁。

修复影响审核包含审核者给出的 `result: PASS` 及 `reason/review/evidencePaths/impactAnalysis/approvedScope`；业务版本变化另附 `businessReviewPath`，其中记录 `result/sutRevision/review/evidencePaths`。测试或业务变更默认使旧检查和结果失效；配置或 harness 变化重验环境。只换入口、运行目录或改超时不算修复。改变 canonical 场景集合时用 `scopeGrant.grantedBy/requestRef/requestText` 追溯已批准的范围调整，不从局部运行推断用户放弃其他场景。

同版本环境修复须写 `rootCause/appliedRepair/repairReview: PASS` 及可核实修复证据，生成一次性重试许可。同一原因再次出现必须调查原因，不能用重启和超时掩盖。修复报告不得重放生成无限重试许可。

依赖复用是显式的保守例外：原切片审核已登记 `dependencies.<scenarioId>.completeReviewed: true`、`test` 和 `sut` 两组 Git 相对路径模式（包含公共夹具、启动配置和传递依赖）；影响审核的 `reuse` 条目给出 `scenarioId/runId/rationale`。脚本检查原结果已审核、场景/环境/harness 未变、两个仓库 diff 未触及依赖；无法证明依赖完整就不复用。依赖完整性的语义责任仍属于审核者。

## 中断、清理与预算

默认从首次 prepare 开始30分钟，最后120秒预留清理。构建、启动、诊断、修改和重跑共用原截止时间；Agent 每次这些动作前读取 status，不在预算耗尽后继续后台修复。runner 使用同一截止时间限制启动与命令等待。切换入口或新目录不能续期。

到期报告已验证范围、当前阻断、原始证据和残留资源，不能宣称需求通过。只有用户明确追加预算，才通过修复审核中的 `budgetGrant: {grantedBy: user, requestRef, requestText, minutes}` 登记；不虚构用户授权或复用旧请求。

中断后先 resume：有本次结果则只登记它，不再次投递；缺少结果时保留 active run，检查原始日志，恢复本次资源。确认 owned registry 已清理后，以 `interruptedRunDiagnosis/cleanupRestored: true` 和清理证据登记中断；不把中断登记为业务 PASS。普通清理失败也须先提供恢复证据。只清理本次身份关联的数据和进程，禁止清空共享环境。清理错误单独记录，不覆盖首个业务错误。

历史运行只追加，当前汇总从版本适用的记录计算。`resume -ImportEvidencePath <原记录>` 只收录 HISTORICAL_UNVERIFIED，不升级 standalone 为正式 PASS。默认向用户呈现业务场景进度、发现的问题、各环节耗时、当前阻断，原始日志按需展开。
