---
name: flow-codex-init
description: 使用 Codex 兼容模板初始化根编排仓库或单个服务仓库的 Flow 元数据。用户要求初始化 Flow 或注册服务时使用。
---

# Codex Flow 初始化

读取 `../flow-codex-core/references/platform.md`。使用
`../flow-codex-core/assets/templates/`.

## 根模式

1. 探测候选服务仓库，只询问缺失的配置值。
2. 渲染 `.flow/config.yaml`、`.flow/onboarding.md`、`.flow/services.md` 和知识库文档。
3. 将根项目角色标记为 `orchestrator`。
4. 探测结果有歧义时，写入前展示待创建文件和候选服务。

## 服务模式

1. 要求提供根目录绝对路径、服务名、spec 工具、测试命令、分支规范、审核配置和知识库配置。
2. 渲染服务 `.flow/config.yaml` 和 `.flow/工作流程.md`。
3. 将服务注册到根 `.flow/config.yaml` 和 `.flow/services.md` 前，先请求确认。

没有明确确认时，不要覆盖已有 Flow 元数据。
