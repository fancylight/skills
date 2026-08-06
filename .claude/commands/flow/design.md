---
name: "Flow: Design"
description: "Root domain discovery then solution design (domain-model → DOMAIN_VERIFIED → overview/OpenSpec/journey/SQL). Child mode advanced only."
category: Workflow
tags: [workflow, orchestration, multi-agent, design]
version: "0.4.0"
---

设计阶段。根模式：**先领域模型，经独立 domain verify 后**才生成方案产物。清单/模板：`~/.claude/commands/flow/templates/`；脚本：`~/.claude/commands/flow/scripts/`。

---

## 前置检查

读取 `.flow/config.yaml`，确认存在。不存在则提示 `/flow:init`。

---

## 根模式（role: orchestrator）

1. **确定 change 目录**

   扫描 `.flow/changes/`（排除 archive/）。无则 AskUserQuestion 收集需求名，目录 `{需求名}-{YYYYMMDD}`。多个则选择。

   **新建 change** 在 task.md frontmatter 或 change 约定处写入 `protocol_version: lease-v1`（不改进行中 change 的 version）。

2. **领域发现（DOMAIN_DRAFT）— 首次根调用只做这一步**

   - 读取 `domain-model.md.tmpl`，写入 `.flow/changes/<change>/domain-model.md`（Decision/Fact ID、生效/不生效条件、E1/E2 证据、冲突与未决）。
   - **不得**把概要设计、实现设想或 agent 推断当领域证据。
   - 返回 `[FLOW_DOMAIN_RESULT] DOMAIN_DRAFT`，提示执行 `/flow:verify verify_mode=domain`。
   - **立即停止**：同一动作内不得生成概要设计、开发文档、task、发版记录、操作链路或 OpenSpec，不得自称 DOMAIN_VERIFIED。

3. **domain 门禁**

   若已有 `domain-model.md` 但无完整 `[DOMAIN_VERIFY_RESULT] PASS` + `phase: DOMAIN_VERIFIED` + 同一 `domain_model_sha256`，保持 DOMAIN_DRAFT 并停止。领域模型变更后旧指纹失效，必须重跑 domain verify。

以下步骤**仅在** DOMAIN_VERIFIED 且指纹匹配后执行。

4. **查询 Apifox**（MCP 可用时）：`getStructureInfo` + `readEntityDetails`；禁止仅用 listOpenApiEndpoints 关键词搜。不可用则 §3.2.4 标「待录入」。

5. **现状链路 as-built** → `操作链路.md`（读 `操作链路.md.tmpl`）。每步 MUST 有 `文件:行` 或 `文件#符号`。禁止仅凭需求文档推导 as-built。

6. **方案产物**

   创建/修复：`概要设计.md`、`开发文档.md`、`task.md`、`发版记录.md`、`操作链路.md`（补 new/changed + owning spec）。

   概要设计强制节（在「服务拆分」前）：`## 领域概念`、`## 歧义裁决`、`## 审核 pass / 写库决策表`、`## 集成 / 联调范围`、`## 数据访问契约`（条件 mandatory；无此类查询写「无」）。

   「领域事实引用」列出已验证 Fact ID 与方案消费位置。业务规则/SQL/验收必须引用 Fact ID。

   Spec 拆分铁律（读 `task-md-maintenance.md` §2.2/§3.1）：矩阵每行恰好一个服务/一个 repo；`1 c = 1 repo`。

   开发文档骨架：读 `dev-doc-maintenance.md` + `开发文档模板.md.tmpl`（§3.2.4 只列本次新增/修改接口；禁止 JSON）。

7. **每矩阵行 = 一个 OpenSpec change**：用 `spec_tool` 生成 proposal/design/delta/tasks。design.md 必须含实现方案、单元测试计划、非目标、数据访问契约（适用时）。子 OpenSpec MUST 引用根领域概念与 Fact ID。

8. **不得**自声明 design 完成或可 assign。提示用户执行 `/flow:verify verify_mode=design`。返回 Spec 矩阵、依赖图、artifact 清单（不含 VERIFY 结论）。

### design 不做

- 不替代 `/flow:verify`
- 不替编排人确认 WARN
- 不写入 KB

---

## 子模式（role: executor）【远期】

当前主线由根完成 spec 设计。若启用：只修已分配服务 spec；需要独立设计审核时向根返回 checkpoint，不嵌套审核 agent。子 spec **不得**改根领域概念或根 `操作链路.md`。

---

**约束**

- domain → domain verify → solution design 顺序硬门禁
- 新建 change 默认 lease-v1
- 验收标准、数据访问契约、操作链路按模板强制
