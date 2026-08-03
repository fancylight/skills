# WP7 Flow 自动化验证记录

> 历史验证证据；非运行时资源，不参与 skill 安装或加载。真实 change、服务和本机路径均以哈希定位，未写入本文或运行时资源。

## 结论

```text
[FLOW_AUTOMATION_RESULT] BLOCKED_FOR_CONTROLLED_ROLLOUT
```

WP5 executable harness 与 WP6 controller contract 的源码门禁已通过；WP7 仍不能启用真实需求自动化。阻断项是 PowerShell 7 不可用、三个真实 shadow 与旧流程动作不一致，以及真实 forward runner 候选不满足 canonical Git revision 与 harness certification 前置条件。源码修复后，以下 controlled harness PASS 只属于旧 revision，已明确标记为需重新验证，不能复用为当前 revision 的 rollout 结论。权威环境记录见 `evidence/flow-automation-wp7/environment-gates.json`。

## 隔离与证据约束

- 验证没有修改三个真实 Flow change、业务仓或外部配置；shadow 仅读取 task、Git HEAD 和不存在的 controller state 路径。
- 未创建产品 persistent Goal。Batch E 使用临时 Git 仓中的隔离持续调度循环，实际反复调用 controller 并注入故障。
- 所有执行日志、结构化结果和哈希位于 `docs/case-studies/evidence/flow-automation-wp7/`；该目录不被 skill、模板或安装脚本引用。
- controlled harness 使用正式 `system-test.ps1 run` 入口和受控 dependency adapter；它证明 runner/harness 行为，但不冒充真实 SUT forward test。

## Batch A：确定性执行

Windows PowerShell 下 12 组目标脚本均真实执行并返回 exit code 0。每项记录了脚本哈希、开始/结束时间、原始日志路径及日志哈希，汇总见 `evidence/flow-automation-wp7/deterministic/report.json`。

- domain validator、replay、Fact propagation、design truth gate：PASS。
- canonical test-cases、manifest/artifact、scope 与 distributable surface：PASS。
- controller deterministic lifecycle 与 skill/controller contract：PASS。
- executable harness self-test、certification 正反例与 failure evidence：PASS。
- 14 个 harness 场景的 runner 输出、结构化结果、evidence index、cleanup/retention 和 certification 位于 `evidence/flow-automation-wp7/harness/self-test/`。
- PowerShell 7：BLOCKED。`where.exe pwsh.exe` 返回 1；未用 Windows PowerShell 结果替代目标运行时。

## Batch B：事故回放

`codex/scripts/tests/fixtures/flow-automation-rollout/cases.json` 的 11 个回放项均绑定实际执行 artifact，而非只校验矩阵数量：

| 回放边界 | 实际执行证据 |
|---|---|
| 提前服务、提前 runner、第二测试根、重复失败 | `deterministic/controller.log` |
| 跨仓写入 | `deterministic/scope-guard.log` |
| 旧 agent、revision 漂移 | `goal-faults.json` |
| 工具输出污染 | `deterministic/test-artifacts.log` |
| required 场景删除 | `deterministic/canonical-test-cases.log` |
| harness 修改/绕过 | `deterministic/harness.log` 与 `harness/self-test/certification.json` |
| 人工配置不可用后停止 | `harness/self-test/artifacts/mysql-unavailable/runner-output.log` |

回放结果：首次非法动作均被 guard 拒绝，且没有业务仓写入或同 revision 重跑。

## Batch C：Forward test

controlled harness forward 已真实经过 runner 入口，14 个场景全部由进程 exit code、phase、classification、raw evidence 和 cleanup 状态判定，认证也验证了 evidence inventory/hash。该结果仅为 runner 平台 PASS。

真实 SUT forward runner：BLOCKED，未执行。只读环境检查发现候选目录和私有配置存在，但候选不是可验证的 canonical Git repository，同时缺少当前 harness certifier 与 certification。继续运行会绕过 revision/certification 门禁，因此在启动、seed 和 suite 之前停止。单服务、数据库异步、多服务 stub 与真实 SUT 业务失败四类真实 forward 不能声明 PASS。

## Batch D：三个真实 change 的 shadow

三个彼此不同、未归档的真实 Flow change 已完成只读观察。每个 artifact 保存 task 输入 revision、SUT HEAD、source locator hash、source mtime、初始 controller state、controller 原始输出哈希、规范化输出、旧流程准备动作和一致性结果：

- `evidence/flow-automation-wp7/shadow/shadow-1.json`
- `evidence/flow-automation-wp7/shadow/shadow-2.json`
- `evidence/flow-automation-wp7/shadow/shadow-3.json`

三者均不存在 `automation-state.yaml`，controller 实际返回 `ERROR_STATE_CORRUPT` 并归一为 `next=BLOCKED`；旧流程分别准备等待外部验证、派发实现和继续实现，故一致性均为 false。Shadow 执行本身完整，但 rollout gate 为 BLOCKED，不能把旧流程动作当成 controller transition。

## Batch E：隔离持续调度故障注入

`invoke-isolated-goal-faults.ps1` 在临时 Git repo 中建立真实 design → lease → implementation revision → environment verified 生命周期，再执行故障。原始结构化输出见 `evidence/flow-automation-wp7/goal-faults.json`。

- agent 以 exit code 73 异常退出：state 保持 `AWAIT_IMPLEMENTATION_RESULT`。
- 重复恢复：两次 `next` 不改变 state；重复签发 lease 被 `ERROR_TRANSITION` 拒绝。
- revision 漂移：`ERROR_REVISION_DRIFT`。
- stale lease：`ERROR_LEASE_INVALID`。
- 重复 runner：`ERROR_RUN_DUPLICATE`。
- runner FAIL：`next=BLOCKED`，随后 result verifier 被拒绝。
- evidence 缺失：`ERROR_INPUT`，state 不提升。

Batch E：PASS。这里的“持续”是隔离测试驱动循环，不是产品 persistent Goal；符合本轮不得创建 goal 的约束。

## 启用与回退

已满足：WP5/WP6 源码门禁、Windows PowerShell 确定性回归、可执行 harness certification、事故回放、三个真实 shadow 采样、隔离故障注入、原始 artifact 可追溯。

未满足：

1. PowerShell 7 目标运行时验证。
2. 三个真实 shadow 与 controller 动作一致。
3. 具备 canonical Git revision、当前 certification、可用 SUT/外部依赖的真实端到端 forward runner。

Rollback：保持 controller-driven 自动入口禁用；保留 state/evidence；继续由人工逐步调用公开 test skills。不得删除证据、提升授权、切换配置或对失败 revision 重跑。
