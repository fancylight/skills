# Feedback · KB Discover 选篇

Discover 步骤 2.2：从用户给出的接口路径 / 服务名 / 表名，在 `knowledge_base.path` 下选篇阅读。

## 前置

- 读根 `config.yaml` → `knowledge_base`；`enabled≠true` 或 path 不可用 → 调查日志 `KB：未启用或不可访问`，跳过选篇
- **深度上限**：每跳最多 **3** 篇；全程最多 **8** 篇；调查日志只记相对路径列表，不粘贴正文

## 3 跳算法

```text
1. API 路径 / 服务名
   → 服务架构/各服务/{service}.md（或等价服务索引）

2. 文内 relates-to / 功能域链接
   → 功能域/*.md（业务规则、读写语义）

3. 表名 / 字段名（若已知）
   → 数据设计/{table}.md（或等价表文档）
```

匹配不到时：用路径片段 / 中文模块名在 KB 内 grep，仍计入篇数上限。

## 调查日志

```text
已读 KB：[相对路径1, 相对路径2, …]
```

## Conclude 一行

```text
KB 沉淀：否（默认）/ 是（理由：澄清了 xxx 业务规则或字段语义）
```

- 默认 **否**；仅当澄清了稳定业务规则或字段语义时标「是」
- 实际写入仍只经 `flow-codex-kb feedback/{id}` + 用户确认
- 遵循维护指南：修 bug 且规则不变 → 不更新 KB
