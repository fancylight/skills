---
name: "Flow: Verify"
description: "Read-only Flow gates — format, domain, design, full, release (and optional legacy-api). Blocks assign/test/archive on ERROR."
category: Workflow
tags: [workflow, orchestration, multi-agent, verify]
version: "0.4.0"
---

对明确指定的 `change_name` 执行只读检查，输出结构化报告。清单 SoT：`~/.claude/commands/flow/templates/verify-checklist.md`。领域脚本：`~/.claude/commands/flow/scripts/validate-domain-artifact.ps1`。

- **ERROR**：阻断 `/flow:test`（full）、`/flow:archive`（release）或 `/flow:assign`（design）
- **WARN**：提示用户确认后可继续；design 模式存在 WARN 时报告末尾 **必须**附编排人确认清单
- **PASS**：该项满足

**输入**：`/flow:verify [change-name] [verify_mode=format|domain|design|full|release|legacy-api]`

---

**前置检查**

1. 确认 `.flow/config.yaml` 存在且 `role: orchestrator`
2. 确认有活跃 change；多个时 **AskUserQuestion** 选择
3. 未指定 `verify_mode` 时默认 `format`

---

## 调用模式

| 模式 | 参数 | 执行章节 | 时机 | ERROR 阻断 |
|------|------|----------|------|------------|
| **格式复验** | 默认 / `verify_mode=format` | §A | design 后可选 | 仅当调用方声明为门禁时 |
| **领域事实** | `verify_mode=domain` | §G | DOMAIN_DRAFT → 方案设计前强制 | 方案设计 |
| **设计合规** | `verify_mode=design` | §A + §C + §D + §E + §F.1–§F.3 + Fact ID 消费 | solution design 完成 → **assign 前强制** | assign |
| **全量 verify** | `verify_mode=full` | §A + §B | test 前 | test |
| **发布 verify** | `verify_mode=release` | §A + §B + §F | 集成测试后 → archive 前强制 | archive |
| **legacy-api** | `verify_mode=legacy-api` | 跨服务 api.md 交叉比对 | 过渡期可选 | 不作为 assign 主门禁 |

格式复验时 §B/§C/§D/§E/§F/§G 未完成属正常，不得因此报 ERROR。全量 verify **不**默认跑 §C–§G。domain 只跑 §G；design **不**跑 §B、§G 或运行时 F.4；release 不跑 §C/§D/§E/§G。

---

## 检查范围（与 Codex 同语义）

1. **§G 领域事实**（仅 domain）：运行  
   `powershell -File ~/.claude/commands/flow/scripts/validate-domain-artifact.ps1 -DomainModelPath <path>`  
   （参数以脚本实际 param 为准）。脚本 ERROR 原样输出并 `[DOMAIN_VERIFY_RESULT] ERROR`。脚本 PASS 后按 checklist DV.4/DV.5 独立抽查高风险代码/schema/契约；无 ERROR 时用文件哈希输出 `[DOMAIN_VERIFY_RESULT] PASS`、`phase: DOMAIN_VERIFIED`、`domain_model_sha256`。**只读**。
2. **§A 产物格式**：根四件套、Spec 矩阵、task 行型、开发文档、OpenSpec、发版记录
3. **§B 发布就绪**（full/release）：spec 完成度、分支、worktree、发版记录覆盖
4. **§C 设计过程合规**（design）：领域概念、歧义裁决、pass 决策表、集成范围、向下传导
5. **§D 链路合规**（design）：`操作链路.md` 结构与证据、步骤归属 spec、接口有调用方
6. **§E 设计文档一致性**（design）：Apifox、接口表范围、开发文档与 OpenSpec
7. **§F SQL 数据访问**（design F.1–F.3；release F.1–F.4）：契约传导与 EXPLAIN 证据（release）

输出格式：`[ERROR|WARN|PASS] <id>: …`

### design 模式 WARN 确认清单（mandatory）

```markdown
## 编排人 WARN 确认清单（assign 前）

| ID | 项 | 建议动作 |
|----|-----|----------|
| W1 | … | 确认 / 回 design 修 / waive（说明） |
```

### legacy-api（日落路径）

扫描各服务 `api.md` / `{provider}-api.md` 做路径/方法/字段交叉比对。**主路径不再依赖本模式**；CHANGELOG 标记日落。不得替代 design/release 门禁。

---

## 不在范围

- 业务运行时行为、HTTP 集成测试、单元测试覆盖
- 代码实现审核（归 `/flow:review`）
- 静默修复任何文件

不要编辑文件。按服务汇总阻断项。
