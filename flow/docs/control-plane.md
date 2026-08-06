# Flow 控制面协议（宿主无关）

> **单一事实源**：业务 / 集成测试的审核中继、报告租约与 test controller 握手词法。  
> Codex 与 Claude 宿主包只适配**如何拉起 agent**与**命令名**，不得另写第二套语义。  
> Codex 历史表述见 `codex/skills/flow-codex-core/references/checkpoints.md`（应与本文一致；冲突以本文为准）。  
> 集成测试 machine state 细节见同目录安装后的 `test-controller` 协议（Codex：`flow-codex-core/references/test-controller.md`）。

---

## 0. `protocol_version`

| 值 | 含义 |
|----|------|
| `legacy` | 执行侧可内联审核并直接 report（Claude 旧路径）。**缺省**：change / 根 config 未声明时按 legacy。 |
| `lease-v1` | 根调度 peer review；执行侧 `REVIEW_REQUEST` / `REPORT_REQUEST`；无 `REPORT_LEASE_GRANTED` 不得 report。 |

声明位置（任一处明确即可；change 级覆盖根 config）：

- 根 `.flow/config.yaml` → `flow.protocol_version`
- change 元数据（`task.md` frontmatter 或 change 目录约定文件）→ `protocol_version`

**禁止**在 apply 中途自动改写进行中 change 的 version。新建 change 由 init/design 默认写入 `lease-v1`（Phase 1+）；存量保持缺省 legacy 直至人工 bump。

---

## 1. 业务执行生命周期（lease-v1）

```text
receive → apply
  → [REVIEW_REQUEST]  （实现完成后暂停）
  → 根：peer review → [REVIEW_RESULT] PASS | REJECT
  → （REJECT：恢复同一执行 agent，最多 3 轮）
  → 测试 + 提交
  → [REPORT_REQUEST]
  → 根：串行 [REPORT_LEASE_GRANTED]
  → report → [REPORT] complete
  → 根：释放租约
```

### 1.1 `REVIEW_REQUEST`

执行 agent 在实现完成后返回（不得自行启动 review agent）：

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

根 agent：

1. 启动**同级** peer review（Codex：`flow-codex-review`；Claude：`/flow:review` / Agent tool）。
2. 将结果中继回**同一**执行上下文：

```text
[REVIEW_RESULT] PASS
```

或：

```text
[REVIEW_RESULT] REJECT
<actionable findings>
```

### 1.2 驳回计数

- 连续三轮 REJECT 后停止，输出 `[REVIEW_LOOP] STOPPED` / `reason: MAX_REJECT_ROUNDS`。
- 测试 spec 的 identity 为 `<change_name>/<spec_id>/<design_fingerprint>`；计数由根状态维护。
- 不得因更换 agent/reviewer、branch、baseline 或 SUT revision 清零。
- 仅用户明确授权重新设计或新实现周期才可创建新 fingerprint。

### 1.3 `REPORT_REQUEST` / `REPORT_LEASE_GRANTED`

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

根 agent **每次只向一个**执行 agent 发放：

```text
[REPORT_LEASE_GRANTED]
```

执行 agent 跑 report 后返回 `[REPORT] complete`，根再释放租约。  
`lease-v1` 下无 grant 的 report **必须拒绝**。

---

## 2. Claude 宿主编排要点（与 Codex 的差异只在机制）

Codex 可将执行 agent 暂停并由根恢复 sibling。Claude Code 常见模型是根持有/续跑执行子会话：

1. 执行子 agent 在消息中输出 `REVIEW_REQUEST` 并**停止继续编码**。
2. 根运行 peer review（`/flow:review` 或 Agent tool）。
3. 根把 `REVIEW_RESULT` 作为 **follow-up** 注入**同一**执行子 agent，令其继续测试/提交或按 REJECT 返工。
4. `REPORT_REQUEST` 同理：根串行发放 `REPORT_LEASE_GRANTED` 后再让该子 agent 执行 report。

词法与轮次规则与 §1 完全相同；禁止 Claude 包另造标记名。

---

## 3. legacy 兼容

当 `protocol_version` 缺省或为 `legacy`：

- 允许执行侧内联启动 review（Claude 旧 `/flow:apply`）。
- 允许无 `REPORT_LEASE_GRANTED` 直接 report（应警告）。
- 根不必实现租约循环。

legacy 有日落计划；新 change 不得新开 legacy（init 默认 lease-v1 后）。

---

## 4. 集成测试执行生命周期

```text
test-receive → test-apply → test-report
```

由 design verify PASS 且用户 authorization ceiling ≥ `implementation` 后的 test-assign 派发。

- 审核与报告租约语义与业务 spec 相同；test 模式下 `design_path` 为 test-design + test-plan + manifest。
- REPORT complete 后须 implementation verify PASS，且 design verify 已核验配置契约及最小只读探针，才可在 ceiling ≥ `execution` 时运行 runner。
- runner 后须 result verify PASS，才可完成集成测试 Flow。
- 外部 evidence 缺失只能 `[TEST_EXTERNAL_EVIDENCE] BLOCKED`，不得自动写 owning repo。
- 创建 agent 时记录 capability fingerprint；根环境变化时旧 agent 为 stale，须 interrupt 而非恢复。

### 4.1 Controller 权威

集成测试的 machine phase、revision、authorization 与下一动作以 **test-controller 协议** + `flow/scripts/flow-test-controller.ps1`（安装后 `assets/scripts/` 或 Claude `commands/flow/scripts/`）为唯一运行权威。

公开 test 入口先读 controller `status` / `next`；实现 agent 的 receive/apply/report 每次写入前验证同一活动 lease。Goal 只能执行 controller 返回的**一个**动作，不得按叙述顺序自行跨阶段推进。

| `next`（摘要） | 唯一允许动作 |
|----------------|--------------|
| `VERIFY_DESIGN` | design verifier 结构化 PASS |
| `ISSUE_IMPLEMENTATION_LEASE` | 签发 test-implementer lease |
| `AWAIT_IMPLEMENTATION_RESULT` | 仅持租约 agent receive/apply/report |
| `VERIFY_IMPLEMENTATION` | implementation verifier PASS |
| `VERIFY_ENVIRONMENT` | 已认证 harness 最小环境验证 |
| `RUN_ONCE` / `AWAIT_RUN_RESULT` | start-run → runner → record-run |
| `VERIFY_RESULT` | result verifier PASS |
| `COMPLETE` / `BLOCKED` | 完成或停止 |

详情与字段以 controller 协议文档及 `flow/docs/schema.md` §11 为准。

---

## 5. 共享脚本位置

| 脚本 | 仓库路径 | 安装后（Codex） | 安装后（Claude） |
|------|----------|-----------------|------------------|
| domain / test validators、scope guard、controller | `flow/scripts/*.ps1` | `flow-codex-core/assets/scripts/` | `commands/flow/scripts/` |

`codex/scripts/*.ps1` 仅为过渡 shim，调用方与 install 应直接使用 `flow/scripts/`。

---

## 6. 宿主适配边界

| 可适配 | 不可分叉 |
|--------|----------|
| 触发名：`/flow:*` vs `flow-codex-*` | lease / REVIEW / REPORT 词法 |
| Agent 拉起方式（Agent tool vs 读 skill） | 3 轮 REJECT、串行 report |
| 模板/脚本安装路径 | controller `next` 状态机 |
| 用户确认 UI（AskUserQuestion 等） | schema 字段含义 |
