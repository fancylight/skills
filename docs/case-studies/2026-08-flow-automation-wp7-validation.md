# WP7 Flow 自动化验证记录

> 历史验证证据；非运行时资源，不参与 skill 安装或加载。任务、服务与仓库上下文均已匿名化。

## 范围与隔离

- 验证基线：WP0–WP6 及 WP7 回放期间产生的责任包修复提交。
- 未修改任何业务仓、真实 Flow change、外部配置或运行环境。
- Forward test 使用五个全新、只读 agent 上下文；只提供匿名任务原文和 skill 路径，不提供预期答案、事故结论或本目录内容。
- `docs/case-studies/` 未被任何 skill、模板、agent prompt 或安装脚本引用。

## Batch A：确定性验证

结论：Windows PowerShell 回归 PASS。

- controller 状态、授权、revision、lease、scope、runner uniqueness、原子恢复：PASS。
- domain validator、领域 replay contract 与 Fact 传导：PASS。
- canonical test-cases、派生 sidecar、Java 绑定和 evidence 漂移：PASS。
- harness self-test、revision certification、失效与配置 ownership 路由：PASS。
- public skills 的 controller/lease/Goal 契约：PASS。
- `codex/validate.ps1`、`codex/install.ps1 -WhatIf`、`git diff --check`：PASS。
- PowerShell 7 目标运行时：BLOCKED；当前机器不存在 `pwsh.exe`，未以 Windows PowerShell 冒充目标运行时验证。

## Batch B：通用事故回放

匿名化矩阵见 `codex/scripts/tests/fixtures/flow-automation-rollout/cases.json`。11 个事故动作均映射到首次非法动作 guard：提前启动、提前 runner、跨仓写入、旧 agent、第二测试根、SUT 漂移、工具输出污染、重复失败、删除 required 场景、harness 修改和配置来源切换。

回放过程中发现并退回责任包修复三项：

1. fixture 失败分类遗漏 `FIXTURE_ASSERTION`；已由 WP5 fix 修复并回归。
2. cleanup 二次失败仍被摘要标记为已清理；已由 WP5 fix 修复，保留 retained state 与恢复命令。
3. runner FAIL 文案要求进入 result verifier，但 controller 权威状态为 `TEST_EXECUTED_FAIL → BLOCKED`；已由 WP6 fix 统一。

修复后确定性回放：PASS。

## Batch C：Forward test

| 匿名任务 | 独立结论 | 结果 |
|---|---|---|
| 单服务同步 API | canonical 场景、lease、environment、单次 runner、result verifier 后 COMPLETE | PASS |
| 数据库加异步任务 | MySQL/PostgreSQL/Redis 关联证据与最终一致性观测；人工配置失败 BLOCKED | PASS |
| 多服务加外部 stub | integration-N 外部证据、WireMock 证据分层、仅 confirmed SUT 失败可形成独立输入 | PASS |
| runner 平台故障 | Surefire/cleanup 失败路由 TEST_HARNESS，原始报告缺失保持 UNDETERMINED，不重跑、不写业务仓 | PASS |
| 真实 SUT 业务失败 | 固定 revision 单次 FAIL 后 BLOCKED；不得删除场景、放宽断言或自动改代码 | PASS |

这些 forward test 验证了新上下文 agent 的规则选择与停止行为；它们是只读推演，不等同于在真实 SUT/外部环境完成的端到端 runner 认证。

## Batch D：Shadow mode

三个匿名状态快照与人工判断一致：

- `TEST_DESIGN_VERIFIED` 请求 runner：拒绝，唯一下一步为 implementation lease。
- `TEST_IMPLEMENTATION_VERIFIED` 请求 runner：拒绝，唯一下一步为 environment verify。
- `TEST_EXECUTED_PASS` 请求 complete：拒绝，唯一下一步为 result verify。

合成 shadow 对照：PASS。尚未只读观察三个真实、进行中的 Flow change。

## Batch E：Goal 故障注入

配置、WireMock、fixture、runner report、SUT、evidence 与越界写入七类故障已完成确定性路由矩阵；controller/skill 契约证明 `BLOCKED` 不自动恢复、相同 revision 不重跑、范围不扩张、result verifier 前不完成。

持续 Goal 的真实隔离运行未执行；本轮未创建 goal，也未用脚本模拟结果冒充持续 Goal 验证。

## 启用门禁

```text
[FLOW_AUTOMATION_RESULT] BLOCKED_FOR_CONTROLLED_ROLLOUT
```

已满足：非法转换/越界写入确定性阻断、单 revision 单 runner、事故首次动作停止、五类新上下文 forward trace、合成 shadow 一致、明确 rollback。

未满足：

1. PowerShell 7 目标运行时全量验证。
2. 三个真实进行中 Flow change 的只读 shadow 观察。
3. 隔离环境中的持续 Goal 七类故障注入。
4. 真实 SUT/外部依赖环境的端到端 forward runner。

Rollback：禁用 controller-driven Goal 入口，保留 controller state/evidence，只恢复到人工逐步调用公开 test skills；不回滚业务仓、不删除证据、不提升授权。
