---
name: flow-codex-test-apply
description: 在 system-test 仓按已验证的 test-design、test-plan 和 manifest 实现 st-api 集成测试代码。用于 test-receive 后，不修改业务源码。
---

# Codex Flow 集成测试编码

进入本技能先按 `../flow-codex-core/references/test-observation.md` 记录阶段 `implementation`；阶段切换、暂停、恢复与交付由 Agent 调用计时入口，运行细分由 runner 生成。计时异常只警告，不阻断测试。


旧执行预算耗尽后，用户新授权的设计/开发按 core/references/test-execution-cycle.md 的 revise / review-design 推进，读取 developmentNext；不得把旧 budget-exhausted 当成整个需求永久停止。原轮修复重跑仍受旧预算约束，设计/编码授权不隐含新运行预算。


正式测试先读取 `../flow-codex-core/references/test-execution-cycle.md`。已接入 execution 的需求使用 `flow-test.ps1 status`，按其 prepare/advance/resume 路径推进；以下旧 next/租约步骤仅用于尚未接入的需求。允许已审核的最小切片先正式运行，其余场景保持未验证；同一对话继续，不新增用户阶段。

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

初始化后，当前有效授权从 controller `authorization.maxPhase` 及 grants 读取；manifest.testAuthorization 仅为初始授权。用户追加授权按 core/references/test-controller.md 的 grant-authorization 入账，不从 next 推断、不要求重复授权、不改 manifest 来伪造授权。

质量要求：读取 ../flow-codex-core/assets/templates/engineering-quality.md 的「实现与审核、测试与排障」。沿用现有结果与授权机制，不增加阶段。

读取 core platform、checkpoints、`../flow-codex-core/references/test-controller.md`、test-design、test-plan 与 manifest。

先要求 controller `next=AWAIT_IMPLEMENTATION_RESULT`。进入写入范围、执行命令或提交时校验范围；同一范围内连续编辑不逐文件重复租约检查。绑定变化时核实并更新既有授权，不把可纠正的参数错误当成任务停止。agent 口述 PASS 不推进 state。

1. 要求 `change_name` 与 `spec_id=st-api-<change_name>`、design PASS 和 `controller.authorization.maxPhase>=implementation`；
   编辑前检查期望分支和 scoped-clean 基线。
   实施中用户明确修订范围时，按test-controller.md的record-scope-review记录当前提交绑定的范围自查；不因原required用例经批准退出就要求重置流程。该检查点提交不代表代码review/report完成。
2. 进入新的写入范围、执行命令或提交前执行 `test-scope-guard.ps1`，AuthorizedRepo 必须是唯一 system-test 仓；
   静态校验必须显式传入 `-Action test -CommandKind static`，任何其他 CommandKind 在本阶段均应被拒绝。
   仅按已验证场景实现 JUnit、test-support、fixtures、stub 与系统测试配置；禁止修改、测试、提交业务仓或业务
   task/progress。`[FLOW_GUARD] BLOCKED_SCOPE_VIOLATION` 范围拒绝只阻止对应动作：纠正参数后继续；真实越界不得执行，独立的已授权工作继续。
3. runner 参数必须维护为 manifest `runner.command` token 数组；将实际测试类/方法、核心断言、manifest filter、
   静态实现校验和测试 revision 追加**测试仓进度文件**。
4. review PASS 前只允许 test-compile、语法解析和静态测试发现；禁止 SUT 启动、Docker、doctor、API/JUnit 集成
   执行、运行型 smoke 或 runner。不得以 Assumption skip 冒充通过。
5. 返回 REVIEW_REQUEST，design_path 指向 test-design + test-plan + manifest；REJECT 只修问题并重审。review PASS
   后仍不得运行型 smoke，直到 implementation verify PASS 且 ceiling>=execution。
6. 进入 flow-codex-test 前必须提交可恢复 revision。local-only 仅在用户明示 waiver 时允许临时诊断，且不得 release/archive/Goal complete。
7. REVIEW PASS、静态实现校验 PASS、提交后返回 REPORT_REQUEST；不得直接更新根 task。
8. 外部 evidence 缺失时仅输出 `[TEST_EXTERNAL_EVIDENCE] BLOCKED`（含 AC/scenario、owning repo、anchor、assertion）；
   不得擅自修改业务仓或冒称该场景通过；当前对话按既有授权处理缺失证据，其他独立场景可以继续实现与审核。
9. 为每个 API 场景实现稳定场景标识或等价关联字段；WireMock 必须精确匹配实际 method/path/query。fixture 的实际读写
   表/列、测试方法与 `failureObservability` 必须可追溯；失败证据使用 UTF-8，且不得记录密码、token 或完整连接串。
