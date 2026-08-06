# Codex 执行 Agent Checkpoints

> 宿主无关协议正文：`flow/docs/control-plane.md`（安装后随 core/docs 或仓库路径引用）。  
> 本文保留 Codex 触发名与生命周期表述；**词法冲突以 control-plane.md 为准**。

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

驳回时恢复同一个执行 agent。连续三轮驳回后停止并报告阻断项。测试 spec 的 identity 为
`<change_name>/<spec_id>/<design_fingerprint>`，计数由根状态维护；不得因更换 agent/reviewer、branch、baseline 或
SUT revision 清零。第三轮必须输出 `[REVIEW_LOOP] STOPPED` / `reason: MAX_REJECT_ROUNDS`；只有用户明确授权重新设计或
新实现周期才可创建新 fingerprint。

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

执行 agent 返回 `[REPORT] complete`，然后根 agent 释放租约。

## 集成测试执行 Agent 生命周期

system-test 执行 agent 遵循：

`flow-codex-test-receive -> flow-codex-test-apply -> flow-codex-test-report`

由 design verify PASS 且用户 ceiling>=implementation 后的 `flow-codex-test-assign` 派发。审核与报告租约语义与业务 spec 相同；`design_path`
在 test 模式下为 test-design + test-plan + manifest。REPORT complete 后必须先经 implementation verify PASS，且 design verify
已核验配置契约及最小只读探针，才可在用户 ceiling>=execution 时运行 runner；runner 后必须经 result verify PASS，才可完成集成测试 Flow。外部 evidence 缺失只能记录
`[TEST_EXTERNAL_EVIDENCE] BLOCKED`，不得自动写 owning repo。创建 agent 时记录 capability fingerprint
（sandboxMode/approvalPolicy/dockerAvailable/networkAvailable）；根环境变化时旧 agent 为 stale，必须 interrupt 而非恢复。

集成测试的 machine phase、revision、authorization 和下一动作以
[`test-controller.md`](test-controller.md) 为唯一运行协议。所有公开 test skills 先读取 controller `status`/`next`；实现 agent 的 receive/apply/report 每次写入前还必须验证同一活动 lease。Goal 只能执行 controller 返回的一个动作，不能按本文的叙述顺序自行跨阶段推进。
