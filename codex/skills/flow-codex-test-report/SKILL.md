---
name: flow-codex-test-report
description: 在审核、冒烟和可恢复提交完成后记录 st-api 集成测试 spec，并经报告租约更新根 task。不得以 local-only 标记可发布完成。
---

# Codex Flow 集成测试汇报

进入本技能先按 `../flow-codex-core/references/test-observation.md` 记录阶段 `delivery`；阶段切换、暂停、恢复与交付由 Agent 调用计时入口，运行细分由 runner 生成。计时异常只警告，不阻断测试。


已接入 execution 且有 development 的后续开发，优先按 core/references/test-execution-cycle.md 的 revise / review-design / resume 推进；不套用下文旧 phase、派发租约或报告转换去阻断该路径。原授权范围、测试仓写入边界、代码审核和真实提交仍须满足；resume 不代表运行或结果 PASS。


正式测试先读取 `../flow-codex-core/references/test-execution-cycle.md`。已接入 execution 的需求使用 `flow-test.ps1 status`，按其 prepare/advance/resume 路径推进；以下旧 next/租约步骤仅用于尚未接入的需求。允许已审核的最小切片先正式运行，其余场景保持未验证；同一对话继续，不新增用户阶段。

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「测试与排障、文档与汇报」。沿用现有结果与授权机制，不增加阶段。

读取 core platform、checkpoints、`../flow-codex-core/references/test-controller.md`、task template 和 task-update-rules。

要求 REPORT_LEASE_GRANTED、root_path、change_name、spec_id、commit_hash、进度文件和静态实现校验摘要。只有 review PASS、
静态实现校验 PASS 且 commit 可恢复才可标记测试代码完成；local-only 必须有用户 waiver，记录为临时诊断，不能成为
implementation PASS 或发布依据。

先要求 controller `next=AWAIT_IMPLEMENTATION_RESULT` 并再次 `validate-lease`。提交形成 proposedTestRevision 后，生成绑定 implementationBaseRevision/proposed revision 的结构化 implementation report 和可信 scope guard report，调用 `accept-result`；controller 未从 canonical Git 接受实际 diff 并原子推进 test revision时，不得更新根 task 或返回 complete。

1. 仅在 authorization ceiling>=implementation 时，更新根 task 的 st-api 条目与 system-test 服务头部；更新 frontmatter
   与进度文件。不得写业务 c{n} progress/task。
2. 已提交写 `完成：{date} commit {hash}` 并勾选“集成测试代码完成”；不得勾选“集成测试执行 PASS”。
3. 返回 `[REPORT] complete`，供 implementation verify 检查。

不要回写开发文档、发版记录、Apifox 或业务代码。
