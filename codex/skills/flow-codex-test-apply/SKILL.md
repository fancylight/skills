---
name: flow-codex-test-apply
description: 在 system-test 仓按已验证的 test-design、test-plan 和 manifest 实现 st-api 集成测试代码。用于 test-receive 后，不修改业务源码。
---

# Codex Flow 集成测试编码

读取 core platform、checkpoints、test-design、test-plan 与 manifest。

1. 要求 `change_name` 与 `spec_id=st-api-<change_name>`；编辑前检查期望分支和 scoped-clean 基线。
2. 仅按已验证场景实现 JUnit、test-support、fixtures、stub 与系统测试配置；禁止自己发明验收口径或修改业务源码。
3. 将实际测试类/方法、核心断言、manifest filter、冒烟命令、结果和测试 revision 追加进度文件。
4. 冒烟使用 manifest filter；无 worker-service 等运行前置时不得以 Assumption skip 冒充通过。
5. 返回 REVIEW_REQUEST，design_path 指向 test-design + test-plan + manifest；REJECT 只修问题并重审，PASS 后重跑冒烟。
6. 进入 flow-codex-test 前必须提交可恢复 revision。local-only 仅在用户明示 waiver 时允许临时诊断，且不得 release/archive/Goal complete。
7. REVIEW PASS、冒烟 PASS、提交后返回 REPORT_REQUEST；不得直接更新根 task。
