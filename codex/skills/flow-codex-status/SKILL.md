---
name: flow-codex-status
description: 只读展示一个根需求的 Flow 进度。用户询问需求、服务、spec、审核、测试或汇报状态时使用。
---

# Codex Flow 状态

读取根 `.flow/config.yaml`、明确指定需求的 `task.md` 和对应进度文件。不要编辑文件，也不要读取
服务业务代码。集成测试须分别汇总设计 verify、代码/report、implementation verify、runner、result verify 和完整
Flow 通过状态；不得将 runner PASS 显示为完整完成。
