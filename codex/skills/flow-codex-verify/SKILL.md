---
name: flow-codex-verify
description: 只读检查 Flow 根产物格式与发布就绪；可选 design 模式校验设计过程合规（领域概念与 OpenSpec 传导）。不验证运行时行为与跨服务 api.md 契约。
---

# Codex Flow 验证

读取 `../flow-codex-core/references/platform.md` 与
`../flow-codex-core/assets/templates/verify-checklist.md`。

对明确指定的 `change_name` 执行只读检查，输出结构化报告：

- **ERROR**：阻断进入 `flow-codex-test` / `flow-codex-archive`（全量）或 `flow-codex-assign`（design 模式）
- **WARN**：提示用户确认后可继续
- **PASS**：该项满足

## 调用模式

| 模式 | 参数 | 执行章节 | 时机 | ERROR 阻断 |
|------|------|----------|------|------------|
| **格式复验** | 默认 / `verify_mode=format` | §A | design 后可选 | 仅当调用方声明为门禁时 |
| **设计合规** | `verify_mode=design` | §A + §C | design 完成 → **assign 前强制** | assign |
| **全量 verify** | `verify_mode=full` 或 test/archive 前置 | §A + §B | test / archive | test / archive |

格式复验时 §B / §C 未完成属正常，不得因此报 ERROR。全量 verify **不**默认跑 §C。design 模式 **不**跑 §B。

## 检查范围

1. **§A 产物格式**（见 checklist §A）：根四件套、概要设计 Spec 矩阵、task.md 行型与 Spec 粒度、开发文档格式、子 OpenSpec 结构、发版记录行型
2. **§B 发布就绪**（见 checklist §B，仅全量）：spec 完成度、分支、worktree、发版记录覆盖
3. **§C 设计过程合规**（见 checklist §C，仅 `verify_mode=design`）：领域概念、歧义裁决、pass 决策表、集成范围、向下传导

Spec 粒度（1 c = 1 repo）主门禁在 `flow-codex-design` 第 5 步；verify §A 做只读复验。

## §C 设计过程合规

- 读取根 `.flow/config.yaml` → `knowledge_base`（与 `flow-codex-kb` 一致）解析 C.1.3
- 标题匹配与检查项以 `verify-checklist.md` §C 为准（含 `## 审核 pass` / `## 集成` 别名）
- C.2.2 术语降级：按 checklist 内联模糊词示例；报 ERROR 须引用根概念行号与子 OpenSpec 位置
- 输出格式与 §A 相同：`[ERROR|WARN|PASS] C.x.x: …`
- **只读**：不写入 KB、不编辑产物、不审代码实现

## 不在范围

- 跨服务 api.md 契约比对（Claude Code 的 flow-verify 专责）
- §A / §B：不验证业务运行时行为、接口语义是否「最优」、验收是否通过
- §C：不验证代码实现（归 `flow-codex-review`）、不写入 KB（归 `flow-codex-kb`）
- HTTP 集成测试、单元测试覆盖

不要编辑或静默修复任何文件。按服务汇总阻断项。
