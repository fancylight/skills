# Codex 平台规则

## 资源位置

所有 Codex 模板均位于已安装的同级 skill 下：

`../flow-codex-core/assets/templates/`

相对于当前执行中的 `flow-codex-*` skill 目录解析路径。不要使用 Claude 命令目录、Codex 用户主目录
命令目录或硬编码的用户 profile 路径。

## 提示词和 Skill 调用

- 流程需要另一个 skill 时，将该 skill 附带给子 agent，或要求 agent 读取已安装的 `SKILL.md`。
- 不要使用 Claude 专属内联调用语法。
- 需要用户选择时，在对话中提出一个简短问题。
- 工作包含多个步骤时使用任务计划，不要依赖 Claude 专属任务列表工具。

## Spec 粒度（铁律）

根 `task.md` 里的每个 `c{n}` **不是**「逻辑能力名」下的多仓 bundle，而是 **单仓库 OpenSpec change** 的唯一标识。必须同时满足：

| 维度 | 规则 |
|------|------|
| Git 仓库 | 恰好 1 个 |
| OpenSpec | 恰好 1 个 change 目录（`<repo>/openspec/changes/<spec-id>/`） |
| 派发 | 1 executor 处理上述一个 change → 理想 1 commit |
| task 开发顺序 | 每行括号内 **恰好 1 个服务名** |

**禁止**：`c4（service-a + service-b）`、一个根 c 下多个仓库各 commit、概要设计里一行 spec 绑多个 repo。

**跨仓必须 c 递增拆分**——同一业务能力涉及 register + aggregator + worker 时，应是 c3 @ register、c4 @ aggregator、c5 @ worker，而不是 c4 = register + aggregator。

格式权威：`../flow-codex-core/assets/templates/task-md-maintenance.md` §2.2。概要设计须产出 Spec | 服务 | 职责矩阵，每行恰好一个服务。

## 仓库安全

- 编辑前读取期望分支。分支不匹配时停止，不要静默 checkout。
- 编辑前读取 `git status --short`。存在未知历史改动时停止，除非用户已确认基线或选择隔离 worktree。
- 没有隔离 worktree 时，不要在同一仓库并发运行两个写入 agent。
- 不要并发更新根追踪文件。

## OpenSpec 就绪检查

实现前执行：

```powershell
openspec instructions apply --change <spec-id> --json
```

OpenSpec 报告 blocked 状态时停止。proposal、design、delta specs 和 tasks 齐备，并且 apply 指令
可用后，设计才算完成。
