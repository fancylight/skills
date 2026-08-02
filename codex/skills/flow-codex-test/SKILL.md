---
name: flow-codex-test
description: 在测试实现生命周期独立验证后编排 Flow 集成测试 runner，并仅在最终结果验证通过时更新完成状态。
---

# Codex Flow 集成测试编排

作为根编排 agent 执行。读取 core platform 与 `integration-test-result.md.tmpl`。

## 前置（硬门禁）

1. 根角色为 `orchestrator`，并提供 `change_name`。
2. `flow-codex-verify` 全量 §A+§B 无 ERROR。
3. 当前轮 `[TEST_VERIFY_RESULT] PASS` 且 `verify_mode: implementation`；测试仓 revision 未漂移。
4. manifest 的 `configurationSource`、`requiredEndpoints`、`connectivityProbe`、`ownership` 已在 design verify 中核验；
   最近一次最小只读探针成功，且其 configuration/revision fingerprint 与 implementation verify 一致。
5. `testAuthorization.ceiling` 为 `execution` 或 `result`，且为用户本轮明确授权；否则输出
   `next: STOP_AWAIT_USER_AUTHORIZATION`，不得委托 runner。
6. config 可解析 system-test 仓，且 manifest、test-design、test-plan、fixtures 存在。
7. 不接受 task 勾选、TEST_DESIGN READY、用户要求根代跑或 local-only 替代 implementation PASS。

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

4. runner FAIL 时仍须在 ceiling=`result` 下执行 result verify 的失败证据完整性分支；该分支不得输出 PASS。只有 confirmed 的
   `SUT_BUSINESS` 可形成独立业务 Flow 输入，其余类别只允许在归属仓形成新 revision；同一 revision 不得重跑。
5. runner 或 result verify FAIL/ERROR 时不得勾选 task、不得输出完成；保留 cleanup/阻断指引。

独立调试只能直接调用 system-test 的 `standalone`，其 PASS 不完成 Flow。
