# 集成测试 Controller 协议

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
| `VERIFY_ENVIRONMENT` | 以已认证 harness 对固定配置执行最小环境验证 | `flow-codex-test` |
| `RUN_ONCE` | 先 `start-run` 原子持久化，再执行 runner | `flow-codex-system-test` |
| `AWAIT_RUN_RESULT` | 只接受当前 active run 的结构化结果 | `flow-codex-system-test` |
| `VERIFY_RESULT` | 记录结构化 result verifier PASS | `flow-codex-test-verify result` |
| `COMPLETE` | 完成编排 | `flow-codex-test` |
| `BLOCKED` | 报告阻断并停止 | 所有入口 |

phase 与表中动作不一致时输出 `[FLOW_CONTROLLER] ERROR_TRANSITION` 并停止。`next=BLOCKED` 必须停止；`next=COMPLETE` 才能完成；不得自行选择后续 skill、提升 authorization 或跳过 implementation/environment/result verify。

## Lease 与结构化结果

- assign 通过 controller 签发 implementation lease；prompt 只传 controller 返回的 `leaseId`、agentId、repository、authorizedPaths、allowed/forbidden capabilities、implementationBaseRevision 和 expiresAt。
- receive/apply/report 每次写入、静态校验或提交前调用 `validate-lease`；无 lease、过期、agent/role/capability/path 不匹配立即停止。
- report 只把结构化 implementation report 和可信 scope guard report 交给 `accept-result`。controller 从 canonical Git 读取 base→proposed diff，成功后才推进 test revision。
- verifier 只提交结构化 PASS；controller 绑定 identity、mode、test/SUT/harness revision、configuration fingerprint 和 summaryHash。
- runner 只能在 `start-run` 成功后执行一次，再用 `record-run` 记录原始 evidence。agent 口述 PASS 不改变 state。

## Goal

持续 Goal 只允许：读取 `controller next` → 执行该动作一次 → 将结构化结果交回 controller。用户“尽量完成”不扩大授权。任何命令失败、revision/configuration/capability 漂移或重复 failure fingerprint 都停止，不自动恢复、切换配置、重跑或调用任意后续 skill。
