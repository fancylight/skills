---
name: flow-codex-test-report
description: 在审核、冒烟和可恢复提交完成后记录 st-api 集成测试 spec，并经报告租约更新根 task。不得以 local-only 标记可发布完成。
---

# Codex Flow 集成测试汇报

读取 core platform、checkpoints、task template 和 task-update-rules。

要求 REPORT_LEASE_GRANTED、root_path、change_name、spec_id、commit_hash、进度文件和冒烟摘要。只有 review PASS、
冒烟 PASS 且 commit 可恢复才可标记测试代码完成；local-only 必须有用户 waiver，记录为临时诊断，不能成为
implementation PASS 或发布依据。

1. 仅更新根 task 的 st-api 条目与 system-test 服务头部；更新 frontmatter 与进度文件。
2. 已提交写 `完成：{date} commit {hash}` 并勾选“集成测试代码完成”；不得勾选“集成测试执行 PASS”。
3. 返回 `[REPORT] complete`，供 implementation verify 检查。

不要回写开发文档、发版记录、Apifox 或业务代码。
