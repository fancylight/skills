---
name: flow-codex-test-receive
description: 将 st-api 集成测试 spec 加载到 config 中 type=system-test 的执行 agent。在 flow-codex-test-assign 后、编写测试代码前使用。
---

# Codex Flow 集成测试接收

读取 `../flow-codex-core/references/platform.md` 和 `../flow-codex-core/references/test-controller.md`。

## 输入

先要求 controller `next=AWAIT_IMPLEMENTATION_RESULT`，并用 `validate-lease` 核验 leaseId、agentId、role、canonical repository、目标路径与 `read` capability。无活动租约、过期或不匹配时停止，不能只凭 assign prompt 继续。

要求提供 `root_path`、`change_name`、`spec_id`（`st-api-<change_name>`）、authorization ceiling、唯一
system-test repo/path allowlist 和 capability fingerprint。优先使用编排 agent 传入的值；缺一项或 ceiling<implementation
时停止，不得自行补全或扩大授权。

## 流程

1. 读取根 `.flow/config.yaml`、根 `task.md`、`.flow/changes/<change_name>/概要设计.md` 验收表。
2. 从根 config 解析 system-test 服务 path；读取 `changes/<change_name>/manifest.yaml`、`test-plan.md`、`test-design.md`。
3. 读取 `release-sql/` 路径（根镜像与测试仓 `fixtures/release/`）。
4. 确认 spec_id 为 `st-api-<change_name>`，且仅负责该集成测试 spec。
5. 检查测试仓工作区期望分支与干净基线（该仓通常无 `.flow/config.yaml`，以根 config 中
   `type: system-test` 条目为准）。
6. **不**调用 OpenSpec；测试设计权威 = test-design + test-plan + manifest。
7. 检查 capability fingerprint 仍与根环境一致；不一致标记 stale 并停止，不得恢复旧 agent。
8. 向进度文件追加 `[TEST_RECEIVE] complete`，概述覆盖范围与 apiTestFilter。

产物缺失、分支不匹配或 spec 歧义时停止。
