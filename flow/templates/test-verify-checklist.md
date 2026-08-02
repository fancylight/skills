# 集成测试独立 Verify 检查清单

仅供 `flow-codex-test-verify` 只读使用；不得修改产物。

## design

- **TD.1 ERROR**：manifest、test-design、test-plan、IDS、seed、cleanup 缺失。
- **TD.2 ERROR**：验收未映射为 integration Y/N、Non-Goal 或后续阶段。
- **TD.3 ERROR**：integration-Y 缺测试方法、核心断言或副作用观测。
- **TD.4 ERROR**：fixture 不幂等、cleanup 越界，或 SQL fixture 不安全。
- **TD.5 ERROR**：SUT revision、真实/替身边界或 system-test path 不可追溯。
- **TD.6 ERROR**：`configurationSource`、`requiredEndpoints`、`connectivityProbe`、`ownership` 缺失；probe 未获用户确认、非最小只读或失败后未停止。
- **TD.7 ERROR**：设计产物含工具输出、实际执行结果、耗时或事后 evidence。
- **TD.8 ERROR**：缺少场景/方法关联、原始报告与日志/桩/数据库证据路径，或缺少 `UNDETERMINED` 边界。

## implementation

- **TI.1 ERROR**：缺 design PASS、review PASS、可恢复 revision 或静态实现校验。
- **TI.2 ERROR**：测试代码、fixture、stub 或配置超出已验证设计，或 required 场景缺实现。
- **TI.3 ERROR**：implementation PASS 前启动 Docker、服务、API/JUnit 集成执行或 runner。
- **TI.4 ERROR**：写入、测试或提交业务仓/业务 progress，或 external evidence 缺失后自动修业务。
- **TI.5 ERROR**：review identity 被变更重置，第三次 REJECT 后未停止，或 stale agent 被恢复。
- **TI.6 ERROR**：场景 ID、测试方法、manifest filter、WireMock 契约与失败可观测性映射不一致，或记录敏感配置。

## result

- **TR.1 ERROR**：runner 前置的 implementation PASS、execution 授权、配置探针或 revision 一致性缺失。
- **TR.2 ERROR**：原始报告、计数、required suite、cleanup、SQL evidence 或 revision 不一致。
- **TR.3 ERROR**：ceiling 不足时运行 runner 或 result verify，或将 runner PASS 视为完整 Flow 完成。
- **TR.4 ERROR**：runner FAIL 缺 `evidence/current/index.md`、`failure-report.md`、原始报告状态或 failure/error 全量映射；
  证据不足时必须输出 `[TEST_EVIDENCE_INCOMPLETE] ERROR` 与 `UNDETERMINED`，不得判定业务缺陷。
