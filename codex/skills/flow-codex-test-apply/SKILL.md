---
name: flow-codex-test-apply
description: 在 glm-system-test 实现 st-api 集成测试代码（JUnit、test-support、fixtures、yml）。在 flow-codex-test-receive 后使用。
---

# Codex Flow 集成测试编码

读取 `../flow-codex-core/references/platform.md` 和
`../flow-codex-core/references/checkpoints.md`。

## 实现

1. 要求明确提供 `change_name` 和 `spec_id`（`st-api-<change_name>`）。
2. 编辑前重新检查 glm-system-test 期望分支和干净基线。
3. 按 `test-plan.md` 与 `manifest.yaml` 实现：
   - `backend-tests/` JUnit API 测试
   - `test-support/` 共享支撑（鉴权、HTTP 客户端等）
   - `fixtures/` 落地与 `config/services/*/application-system-test.yml` 必要修改
4. **禁止**修改业务服务源码。
5. 本地冒烟：`mvn -f glm-system-test/pom.xml -pl backend-tests -am test`，使用 manifest 的
   `apiTestFilter`（或 test-plan 指定子集）。
6. 实现完成后返回 `REVIEW_REQUEST`（design_path 指向 test-plan + manifest）。

## 审核后恢复

- 收到 `REVIEW_RESULT REJECT` 时，只修复审核问题，再次返回 `REVIEW_REQUEST`。
- 收到 `REVIEW_RESULT PASS` 时，重跑冒烟；失败时修复并重跑，最多三轮。
- **提交可选**：广火类需求可本地-only；若提交则使用根 `conventions.commit_format`，scope 含
  `st-api-<change>`。
- 返回 `REPORT_REQUEST`；`commit_hash` 可为实际 hash 或 `local-only`。

不要直接更新根 `task.md`。
