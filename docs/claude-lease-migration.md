# Claude Flow：legacy → lease-v1 迁移清单

> 给**业务项目**根 Agent / 维护者。skills 仓库协议正文见 [flow/docs/control-plane.md](../flow/docs/control-plane.md)。

## 何时需要迁移

| 场景 | 建议 |
|------|------|
| 进行中 change，子 agent 已在 apply | **不要**中途 bump；保持 legacy 直到 archive |
| 刚开的 change，尚未 assign | 可直接 `protocol_version: lease-v1` |
| 下一需求 | init/design 默认 lease-v1（Phase 1 落地后） |

缺省（未声明）= **legacy**：内联审核 + 直接 `/flow:report` 仍可用，但会收到警告。

## 一页升级步骤（单个 change）

1. **暂停**所有未完成 apply 的执行会话；不要在 REVIEW 中途切换。
2. 确认根 `.flow/config.yaml` 或该 change 的 `task.md` frontmatter：
   ```yaml
   protocol_version: lease-v1
   # 或
   flow:
     protocol_version: lease-v1
   ```
3. 已完成（`[x]`）的 spec **不要改**勾选与 commit 记录。
4. 未完成 spec：用**新** child prompt（lease 生命周期章节）重新 assign；旧内联 review 会话作废。
5. 根侧准备好：收到 `REVIEW_REQUEST` → `/flow:review` → 回传 `REVIEW_RESULT`；收到 `REPORT_REQUEST` → 串行 `REPORT_LEASE_GRANTED` → 子 agent `/flow:report`。
6. 冒烟：任一 spec 无 grant 时 report 应被拒绝。

## 旧 `/flow:test` 映射（Phase 3 后）

| 旧用法 | 新链 |
|--------|------|
| `/flow:test <service>` 跑 test_command | 单元测试仍在 apply；服务级集成走 test-design 链 |
| `/flow:test <change>` 手写 E2E | `test-design` → `test-verify design` → … → `system-test` → `test-verify result` |

## 回滚

把 `protocol_version` 改回 `legacy` 或删除字段；仅影响**之后**启动的执行会话。已按 lease 发出的 REQUEST 由根按 lease 规则收尾或人工中止。

## 共享脚本

门禁与 controller 安装在：

- Claude：`~/.claude/commands/flow/scripts/*.ps1`
- 仓库源：`flow/scripts/`

无 PowerShell 时相关门禁应 **BLOCKED**，禁止静默跳过。
