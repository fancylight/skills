# 集成测试独立 Verify 检查清单

仅供 `flow-codex-test-verify` 只读使用。结果必须为 `PASS`、`WARN` 或 `ERROR`，不得修改产物。

## design

- **TD.1 ERROR**：manifest、test-plan、test-design、IDS、seed、cleanup 均存在。
- **TD.2 ERROR**：每条概要设计验收均映射为集成 Y/N；N 有 Non-Goal 或后续阶段。
- **TD.3 ERROR**：每条 Y 映射到测试类、方法和核心断言。
- **TD.4 ERROR**：manifest filter 覆盖所有 required 类且与 plan 一致。
- **TD.5 ERROR**：test-design 覆盖 TDD.1–TDD.10，禁止不可独立执行的“复用约定”。
- **TD.6 ERROR**：fixtures 为预留 ID、seed 幂等、cleanup 不越界。
- **TD.7 ERROR**：数据访问风险含最终 SQL/count、参数、只读 EXPLAIN 与 evidence 路径。
- **TD.8 ERROR**：缺 happy path、方法与断言不一致，或缺少副作用观测。
- **TD.9 ERROR**：测试仓期望分支不符或有未知脏改动。
- **TD.10 ERROR**：test-design/test-plan 混入实际 PASS、执行时间或事后 evidence。
- **TD.11 ERROR**：SUT revision 未固定，或真实/替身边界无法判定。

## implementation

- **TI.1 ERROR**：进度有 receive、apply、review PASS、report request、lease 和 report complete。
- **TI.2 ERROR**：测试类/方法和核心断言落实 TD.3 映射。
- **TI.3 ERROR**：无永久 `@Disabled` 或 required 无理由 skip。
- **TI.4 ERROR**：冒烟记录存在且 filter 与 manifest 一致。
- **TI.5 ERROR**：未整体 mock SUT；外部 stub 与设计一致。
- **TI.6 ERROR**：测试代码、fixtures、manifest、stub、服务配置可从同一 revision 恢复。
- **TI.7 ERROR**：无错误分支、untracked 需求文件或未知脏改动。
- **TI.8 ERROR**：local-only 无用户 waiver；有 waiver 仅 WARN 且不得 release/archive。

## result

- **TR.1 ERROR**：当前 revision 已 implementation PASS 且未漂移。
- **TR.2 ERROR**：runner 原始报告与 summary 的 passed/failed/skipped 一致。
- **TR.3 ERROR**：required suite 全部完成，failed=0、skipped=0。
- **TR.4 ERROR**：evidence 有时间、命令、服务版本、测试/业务 revision。
- **TR.5 ERROR**：cleanup 与 success/failure policy 一致。
- **TR.6 ERROR**：SQL 风险 evidence 覆盖最终列表 SQL/count 和阈值。
- **TR.7 ERROR**：根 `集成测试.md` 与测试仓 evidence 一致。
- **TR.8 ERROR**：task 的执行 PASS 不早于 result PASS。
