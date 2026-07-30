# Flow Codex 适配层

## 目标

保持 Claude Code 实现不变，新增原生 Codex 适配层。复用 `.flow` 协议、OpenSpec 目录、任务元数据和
公共模板。

## 平台边界

Codex 执行 agent 不负责调度审核 agent。保留原始生命周期，将审核调用扁平化：

```text
根 agent：flow-codex-assign
  -> 执行 agent：flow-codex-receive -> flow-codex-apply
  -> 执行 agent 返回 REVIEW_REQUEST 并暂停
  -> 根 agent 启动同级 flow-codex-review
  -> 根 agent 使用 PASS 或 REJECT 恢复执行 agent
  -> 执行 agent 测试、提交并返回 REPORT_REQUEST
  -> 根 agent 发放一个串行报告租约
  -> 执行 agent：flow-codex-report
```

## 规则

- **1 spec = 1 单仓库 OpenSpec change = 1 git 仓库**：根 task 每个 c{n} 恰好一个 repo；跨仓 c 递增；禁止一行多仓 bundle。详见 `flow-codex-core/references/platform.md`。
- 保持 `1 spec = 1 executor = 1 commit`（executor 处理上述单仓 change）。
- 仅允许不同仓库之间并行写入。
- 汇报会更新根 `.flow` 追踪文件，必须串行执行。
- 分支不匹配或 worktree 存在历史改动时停止，不要静默切换分支。
- 每个 OpenSpec change 均可 apply 后，才能声明设计完成。
- `flow-codex-assign` 前须 `flow-codex-verify`（`verify_mode=design`，§A+§C+§D+§E+§F.1–§F.3）无 ERROR；test 前全量 verify 为 §A+§B；archive 前 `verify_mode=release` 为 §A+§B+§F（SQL 风险 EXPLAIN 证据），不默认跑 §C/§D/§E。

## 公开 Skills

- `flow-codex-init`
- `flow-codex-design`
- `flow-codex-assign`
- `flow-codex-receive`
- `flow-codex-apply`
- `flow-codex-report`
- `flow-codex-status`
- `flow-codex-verify`（`format` / `design` / `full`；design 模式校验领域概念、操作链路与设计文档一致性）
- `flow-codex-test-design`
- `flow-codex-test-assign`
- `flow-codex-test-receive`
- `flow-codex-test-apply`
- `flow-codex-test-report`
- `flow-codex-test`
- `flow-codex-system-test`
- `flow-codex-change`
- `flow-codex-archive`
- `flow-codex-feedback`
- `flow-codex-kb`（change 或 `feedback/{id}` 入口）
- `flow-codex-hotfix`

## 内部 Skills

- `flow-codex-core`
- `flow-codex-review`

## 工具

- `install.ps1`
- `validate.ps1`
