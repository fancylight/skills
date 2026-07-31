---
name: flow-codex-test-receive
description: 将 st-api 集成测试 spec 加载到 glm-system-test 执行 agent。在 flow-codex-test-assign 后、编写测试代码前使用。
---

# Codex Flow 集成测试接收

读取 `../flow-codex-core/references/platform.md`。

## 输入

要求提供 `root_path`、`change_name` 和 `spec_id`（`st-api-<change_name>`）。优先使用编排 agent
传入的值。

## 流程

1. 读取根 `.flow/config.yaml`、根 `task.md`、`.flow/changes/<change_name>/概要设计.md` 验收表。
2. 从根 config 解析 system-test 服务 path；读取 `changes/<change_name>/manifest.yaml`、`test-plan.md`、`test-design.md`。
3. 读取 `release-sql/` 路径（根镜像与测试仓 `fixtures/release/`）。
4. 确认 spec_id 为 `st-api-<change_name>`，且仅负责该集成测试 spec。
5. 检查测试仓工作区期望分支与干净基线（该仓通常无 `.flow/config.yaml`，以根 config 中
   `type: system-test` 条目为准）。
6. **不**调用 OpenSpec；测试设计权威 = test-design + test-plan + manifest。
7. 向进度文件追加 `[TEST_RECEIVE] complete`，概述覆盖范围与 apiTestFilter。

产物缺失、分支不匹配或 spec 歧义时停止。
