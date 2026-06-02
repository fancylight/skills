# Codex 执行 Agent Checkpoints

Codex 子 agent 不能假设嵌套子 agent 工具可调用。根编排 agent 负责审核调度和串行汇报。

## 执行 Agent 生命周期

执行 agent 始终遵循：

`flow-codex-receive -> flow-codex-apply -> flow-codex-report`

`flow-codex-apply` 可能暂停两次：

1. 实现完成后返回 `REVIEW_REQUEST`。
2. 审核、测试和提交完成后返回 `REPORT_REQUEST`。

## 审核中继

执行 agent 返回：

```text
[REVIEW_REQUEST]
change_name: <change>
spec_id: <spec>
service_path: <absolute path>
design_path: <absolute path>
changed_files:
  - <path>
round: <1..3>
```

根 agent 启动同级 `flow-codex-review` agent，并中继以下结果之一：

```text
[REVIEW_RESULT] PASS
```

or:

```text
[REVIEW_RESULT] REJECT
<actionable findings>
```

驳回时恢复同一个执行 agent。连续三轮驳回后停止并报告阻断项。

## 报告租约

审核通过、测试成功并完成服务提交后，执行 agent 返回：

```text
[REPORT_REQUEST]
change_name: <change>
spec_id: <spec>
service_path: <absolute path>
commit_hash: <hash>
progress_file: <absolute path>
tests: <summary>
```

根 agent 每次只向一个执行 agent 发放：

```text
[REPORT_LEASE_GRANTED]
```

执行 agent 运行 `flow-codex-report`，返回 `[REPORT] complete`，然后根 agent 释放租约。
