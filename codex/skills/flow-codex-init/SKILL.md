---
name: flow-codex-init
description: 使用 Codex 兼容模板初始化根编排仓库或单个服务仓库的 Flow 元数据。用户要求初始化 Flow 或注册服务时使用。
---

# Codex Flow 初始化

需求命名、分支与提交遵循 `../flow-codex-core/references/git-conventions.md`；已有需求读取根 change.json；实际写入 Git 仓库前按该规则绑定并校验，提交使用公共脚本，中文描述贯穿业务、文档和测试。

读取 `../flow-codex-core/references/platform.md`。使用
`../flow-codex-core/assets/templates/`.

## 根模式

1. 探测候选服务仓库，只询问缺失的配置值。
2. 使用 Codex config 模板默认的 `agent_git: flow-v1`、完整 branch_pattern 与中文提交规范；不在项目配置写固定 task_id。渲染 `.flow/config.yaml`、`.flow/onboarding.md`、`.flow/services.md` 和知识库文档。
3. 将根项目角色标记为 `orchestrator`。在已有 AGENTS.md 中幂等合并 assets/templates/flow-delivery-entry.md.tmpl 的 Codex 交付约定；不覆盖用户规则。
4. 探测结果有歧义时，写入前展示待创建文件和候选服务。

## 服务模式

1. 要求提供根目录绝对路径、服务名、spec 工具、测试命令、分支规范、审核配置和知识库配置。
2. 渲染服务 `.flow/config.yaml` 和 `.flow/工作流程.md`，在已有 AGENTS.md 中幂等合并同一交付约定；反馈调查不进入该约定。
3. 将服务注册到根 `.flow/config.yaml` 和 `.flow/services.md` 前，先请求确认。

没有明确确认时，不要覆盖已有 Flow 元数据。
