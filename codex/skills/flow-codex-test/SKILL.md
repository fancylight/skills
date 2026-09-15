---
name: flow-codex-test
description: 在测试实现生命周期独立验证后编排 Flow 集成测试 runner，并仅在最终结果验证通过时更新完成状态。
---

# Codex Flow 集成测试编排

初始化后，当前有效授权从 controller `authorization.maxPhase` 及 grants 读取；manifest.testAuthorization 仅为初始授权。用户追加授权按 core/references/test-controller.md 的 grant-authorization 入账，不从 next 推断、不要求重复授权、不改 manifest 来伪造授权。

作为根编排 agent 执行。读取 core platform、`../flow-codex-core/references/test-controller.md` 与 `integration-test-result.md.tmpl`。

执行已有用例先读取 ../flow-codex-core/references/test-execution.md；复用适用的项目执行路径，不重新设计测试或维护环境。

## 前置（硬门禁）

每轮只执行 controller `next` 返回的一个动作。`BLOCKED` 立即停止，`COMPLETE` 才输出完成；不得根据本文步骤、用户“尽量完成”或 skill 建议自行选择后续 skill。`VERIFY_ENVIRONMENT` 对 v2 resolved manifest 调用 core
`assets/scripts/validate-test-environment.ps1`；v1 继续消费认证 harness 的最小配置探针。只有结构化 PASS 才调用
`record-verifier -VerifyMode environment`；`RUN_ONCE` 才委托 system-test。

1. 根角色为 `orchestrator`，并提供 `change_name`。
2. `flow-codex-verify` 全量 §A+§B 无 ERROR。
3. 当前轮 `[TEST_VERIFY_RESULT] PASS` 且 `verify_mode: implementation`；测试仓 revision 未漂移。
4. manifest 的 `configurationSource`、`requiredEndpoints`、`connectivityProbe`、`ownership` 已在 design verify 中核验；
   最近一次最小只读探针成功，且其 configuration/revision fingerprint 与 implementation verify 一致。
5. `controller.authorization.maxPhase` 为 `execution` 或 `result`，且为用户已明确授权；否则输出
   `next: STOP_AWAIT_USER_AUTHORIZATION`，不得委托 runner。
6. config 可解析 system-test 仓，且 manifest、test-design、test-plan、fixtures 存在。
7. 不接受 task 勾选、TEST_DESIGN READY、用户要求根代跑或 local-only 替代 implementation PASS。

## VERIFY_ENVIRONMENT

当 `changes/<change>/resolved-manifest.json` 存在且 `sourceManifestSchemaVersion=2`：

1. 以 canonical state path、resolved manifest、独立 `VerifierId` 和结构化 report path 调用
   `validate-test-environment.ps1`；
2. verifier 只读检查输入 hash、test/provider/SUT revision、配置 target、环境引用、managed executable/start script/端口，
   并只执行 descriptor 中 `stage=preflight` 的 external TCP/HTTP probe；
3. verifier BLOCKED/ERROR 时停止，不调用 controller、不启动 config provider、SUT、Docker 或 runner；
4. verifier PASS 后，用 report 内完全一致的 test/SUT/harness revision 与 configuration fingerprint 调用 controller
   `record-verifier -VerifyMode environment`；
5. controller 推进到 `TEST_ENVIRONMENT_VERIFIED` 后本轮结束，下一轮才可执行 `RUN_ONCE`。

v1 manifest 没有 resolved manifest 时保持现有认证 harness 探针，不把 v2 verifier 结果伪造给旧配置契约。

v2 `RUN_ONCE` 由认证后的 `system-test.ps1` 按 schema 分派到 `run-resolved-environment.ps1`，并传入 controller state 中完全一致的
`ConfigurationFingerprint`。standalone PASS 仍不得提交为 canonical `record-run` 结果。

## 编排

1. 委托 `flow-codex-system-test`，明确 `execution_mode: orchestrated`，执行最小健康检查 → run；该 skill 写 evidence 与根
   `集成测试.md` 摘要，但不更新 task 完成状态。
2. runner 返回后，只有 ceiling=`result` 才运行 `flow-codex-test-verify result`，传入当前 manifest、业务/测试 revision
   和原始报告路径；仅为 `execution` 时保留 evidence 并输出 `next: STOP_AWAIT_USER_AUTHORIZATION`。
3. result PASS 才勾选 task 的“集成测试执行 PASS”，写入结果模板并输出：

```text
[INTEGRATION_TEST_RESULT] PASS
change_name: <name>
result_verify: PASS
```

4. runner FAIL 时，在 `record-run` 前完成失败 evidence index、原始报告和 failure report 的完整性检查；controller 随后进入
   `TEST_EXECUTED_FAIL`，`next=BLOCKED`，不得调用 result verifier。只有 confirmed 的 `SUT_BUSINESS` 可形成独立业务 Flow
   输入，其余类别只允许在归属仓形成新 revision；同一 revision 不得重跑。
5. runner 或 result verify FAIL/ERROR 时不得勾选 task、不得输出完成；保留 cleanup/阻断指引。

独立调试只能直接调用 system-test 的 `standalone`，其 PASS 不完成 Flow。
