# 集成测试 Controller 协议

Codex 单对话执行方式见 first-delivery.md；保持本协议所有状态、授权、租约与版本约束。

集成测试自动化的唯一 machine state 位于编排根
`.flow/changes/<change>/automation-state.yaml`。只用安装后的
`assets/scripts/flow-test-controller.ps1` 读取或写入；manifest、task、agent 口述和 Goal 建议都不能直接改变 phase、授权或 revision。

## 入口规则

每个测试 skill 的第一步都执行 `status` 和 `next`，并核对 canonical state path、当前 phase、authorization ceiling、test/SUT/harness revision 与 configuration fingerprint。state 不存在时，只有 `flow-codex-test-design` 可在产物形成可提交 design revision 后执行一次 `initialize`；其他入口一律 BLOCKED。

| `next` | 唯一允许动作 | Skill |
|---|---|---|
| `VERIFY_DESIGN` | 记录结构化 design verifier PASS | `flow-codex-test-verify design` |
| `ISSUE_IMPLEMENTATION_LEASE` | 签发一个 test-implementer lease | `flow-codex-test-assign` |
| `AWAIT_IMPLEMENTATION_RESULT` | 仅持租约 agent receive/apply/report | `flow-codex-test-receive/apply/report` |
| `VERIFY_IMPLEMENTATION` | 记录结构化 implementation verifier PASS | `flow-codex-test-verify implementation` |
| `VERIFY_ENVIRONMENT` | v2 调用只读 `validate-test-environment.ps1`；v1 保留认证 harness 最小探针 | `flow-codex-test` |
| `RUN_ONCE` | 先 `start-run` 原子持久化，再执行 runner；v2 传入 active run fingerprint | `flow-codex-system-test` |
| `AWAIT_RUN_RESULT` | 只接受当前 active run 的结构化结果 | `flow-codex-system-test` |
| `VERIFY_RESULT` | 记录结构化 result verifier PASS | `flow-codex-test-verify result` |
| `COMPLETE` | 完成编排 | `flow-codex-test` |
| `BLOCKED` | 报告阻断并停止 | 所有入口 |

phase 与表中动作不一致时输出 `[FLOW_CONTROLLER] ERROR_TRANSITION` 并停止。`next=BLOCKED` 必须停止；`next=COMPLETE` 才能完成；不得自行选择后续 skill、提升 authorization 或跳过 implementation/environment/result verify。
runner FAIL 在 `record-run` 前完成失败证据收集与完整性检查，记录后进入 `TEST_EXECUTED_FAIL` / `next=BLOCKED`；不得把失败运行送入只接受 PASS 的 result verifier。

若失败被结构化证据明确归类为 `TEST_HARNESS`，且 cleanup 成功，可执行一次受限的 `retry-harness-failure` 修复迁移。该命令要求业务 revision 与配置指纹保持不变、新测试 revision 只修改 `scripts/**` 和 `self-test/**`、新 harness 完成认证，并保留原失败运行；迁移后回到 `TEST_IMPLEMENTED` 重新执行 implementation verify、environment verify 和唯一一次新 revision runner。业务失败、配置失败、未清理现场或同 revision 均不得使用该迁移。

## Lease 与结构化结果

- assign 通过 controller 签发 implementation lease；prompt 只传 controller 返回的 `leaseId`、agentId、repository、authorizedPaths、allowed/forbidden capabilities、implementationBaseRevision 和 expiresAt。
- receive/apply/report 每次写入、静态校验或提交前调用 `validate-lease`；无 lease、过期、agent/role/capability/path 不匹配立即停止。
- report 只把结构化 implementation report 和可信 scope guard report 交给 `accept-result`。controller 从 canonical Git 读取 base→proposed diff，成功后才推进 test revision。
- verifier 只提交结构化 PASS；controller 绑定 identity、mode、test/SUT/harness revision、configuration fingerprint 和 summaryHash。
- v2 environment verifier 只消费 `resolved-manifest.json` 和 controller state；它复核输入 hash、provider/SUT/test revision、
  environment file 的引用可用性、managed 启动构件与端口、external preflight probe。它不记录配置值、不启动 managed
  资源，BLOCKED 报告不能提交为 controller PASS。
- runner 只能在 `start-run` 成功后执行一次，再用 `record-run` 记录原始 evidence。agent 口述 PASS 不改变 state。

## Goal

v2 standalone smoke 不写 controller。场景选择的 `fullSuite=false` 证据及 `execution_mode: standalone` 证据不能交给 `record-run` 登记全量 PASS；证据保存在独立 `evidence/runs/<run-id>/`，不覆盖已记录的全量失败。

持续 Goal 只允许：读取 `controller next` → 执行该动作一次 → 将结构化结果交回 controller。用户“尽量完成”不扩大授权。任何命令失败、revision/configuration/capability 漂移或重复 failure fingerprint 都停止，不自动恢复、切换配置、重跑或调用任意后续 skill。
