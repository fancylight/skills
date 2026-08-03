---
name: flow-codex-test-apply
description: 在 system-test 仓按已验证的 test-design、test-plan 和 manifest 实现 st-api 集成测试代码。用于 test-receive 后，不修改业务源码。
---

# Codex Flow 集成测试编码

读取 core platform、checkpoints、`../flow-codex-core/references/test-controller.md`、test-design、test-plan 与 manifest。

先要求 controller `next=AWAIT_IMPLEMENTATION_RESULT`。每次写入、test-compile、静态发现或提交前同时执行 controller `validate-lease` 和 scope guard；lease 的 agent、capability、repository、path 或 implementationBaseRevision 任一不匹配即停止。agent 口述 PASS 不推进 state。

1. 要求 `change_name` 与 `spec_id=st-api-<change_name>`、design PASS 和 `testAuthorization.ceiling>=implementation`；
   编辑前检查期望分支和 scoped-clean 基线。
2. 每次编辑、静态校验、测试或提交前执行 `test-scope-guard.ps1`，AuthorizedRepo 必须是唯一 system-test 仓；
   静态校验必须显式传入 `-Action test -CommandKind static`，任何其他 CommandKind 在本阶段均应被拒绝。
   仅按已验证场景实现 JUnit、test-support、fixtures、stub 与系统测试配置；禁止修改、测试、提交业务仓或业务
   task/progress。任何 `[FLOW_GUARD] BLOCKED_SCOPE_VIOLATION` 立即停止。
3. runner 参数必须维护为 manifest `runner.command` token 数组；将实际测试类/方法、核心断言、manifest filter、
   静态实现校验和测试 revision 追加**测试仓进度文件**。
4. review PASS 前只允许 test-compile、语法解析和静态测试发现；禁止 SUT 启动、Docker、doctor、API/JUnit 集成
   执行、运行型 smoke 或 runner。不得以 Assumption skip 冒充通过。
5. 返回 REVIEW_REQUEST，design_path 指向 test-design + test-plan + manifest；REJECT 只修问题并重审。review PASS
   后仍不得运行型 smoke，直到 implementation verify PASS 且 ceiling>=execution。
6. 进入 flow-codex-test 前必须提交可恢复 revision。local-only 仅在用户明示 waiver 时允许临时诊断，且不得 release/archive/Goal complete。
7. REVIEW PASS、静态实现校验 PASS、提交后返回 REPORT_REQUEST；不得直接更新根 task。
8. 外部 evidence 缺失时仅输出 `[TEST_EXTERNAL_EVIDENCE] BLOCKED`（含 AC/scenario、owning repo、anchor、assertion）；
   不得创建业务任务、调用业务 apply、修改或运行业务单测、更改 SUT revision 或继续审核循环。
9. 为每个 API 场景实现稳定场景标识或等价关联字段；WireMock 必须精确匹配实际 method/path/query。fixture 的实际读写
   表/列、测试方法与 `failureObservability` 必须可追溯；失败证据使用 UTF-8，且不得记录密码、token 或完整连接串。
