---
name: flow-codex-test-verify
description: 只读验证 Flow 集成测试的设计、实现生命周期和最终运行证据。用于 test-design 后、test 前和 system-test 后的硬门禁；不编写测试、不启动服务、不修改 task。
---

# Codex Flow 集成测试验证

作为根编排 agent 或独立只读审核 agent 执行。读取
`../flow-codex-core/references/platform.md`、[检查清单](references/test-verify-checklist.md)
及其指向的共享模板。

## 输入与边界

要求提供 `change_name` 与 `verify_mode`（`design`、`implementation` 或 `result`）。只读检查；
不得编辑业务/测试产物、启动服务、运行 runner、修改 `task.md`，也不替代 `flow-codex-review` 的代码审核。

解析根 config 的 system-test 服务仓和 `changes/<change_name>/`。任何缺失、revision 漂移或无法追溯的
证据均为 ERROR，不以 task 勾选或执行者口述替代。

## 检查

1. `design`：读取根概要设计验收、操作链路/数据访问契约、已提交 SUT revision、`test-design.md`、
   `test-plan.md`、manifest 与 fixtures。按 TD.1–TD.11 验证三产物职责、AC 场景映射、拓扑、真实/桩边界、
   夹具、SQL 计划和 scoped-clean 基线。
2. `implementation`：读取设计 PASS、进度文件、review 结果、测试代码、冒烟记录与测试仓 Git 状态。
   按 TI.1–TI.8 验证场景/断言落实、无必需 skip、外部桩一致、同一可恢复 revision 和 local-only waiver。
3. `result`：读取 implementation PASS、runner 原始报告、evidence、根 `集成测试.md`、manifest 与业务/测试 revision。
   按 TR.1–TR.8 验证计数、必需 suite、cleanup、SQL evidence 与结果记录一致。

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
```
