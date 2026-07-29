---
name: flow-codex-design
description: 为 Codex 编排设计或修复 Flow 需求。创建根需求产物、拆分服务 spec、生成 OpenSpec change 或修复无法 apply 的设计时使用。
---

# Codex Flow 设计

读取 `../flow-codex-core/references/platform.md` 和 `references/openspec-readiness.md`。使用 core
模板生成概要设计、开发文档和发版记录。

## 根模式

1. 要求明确提供 `change_name`。
2. 读取根 Flow 配置和已有需求产物。
3. **查询 Apifox 已有接口**：如 Apifox MCP 可用，对涉及的接口（新增/修改）**必须**使用 `getStructureInfo`（`entityType=endpoint`，`projectId`）定位候选，再 `readEntityDetails` 读取定义——修改的查当前定义对比差异，新增的查命名冲突。**禁止**仅用 `listOpenApiEndpoints` 关键词搜代替上述步骤。Apifox 链接格式：`https://app.apifox.com/link/project/{projectId}/apis/api-{entityId}`。MCP 不可用时降级跳过并在 §3.2.4 Apifox 列标「待录入」。
3.5 **现状链路提取**（产出 `操作链路.md` 的 `as-built` 部分）。
   - 先读 `../flow-codex-core/assets/templates/操作链路.md.tmpl`。
   - 从需求涉及的**入口端**（小程序/H5/PC 页面、定时任务、上游 MQ）出发，用代码检索逐跳还原调用链：入口调了哪个接口 → 该接口由哪个可部署服务承载 → 它又调了谁。
   - 每个 `as-built` 步骤 **MUST** 记录 `文件:行` 或 `文件#符号` 级依据。
   - 前端/上游仓库不在根 `.flow/config.yaml` 时，向用户索取路径；拿不到则该行写 `未校验（原因）`。
   - **禁止**仅凭需求文档、概要设计或既有认知推导 `as-built` 行——这会使后续 §D 退化为设计自证。
   - 纯新建服务且无既有链路时，可无 `as-built` 行，但须在「未覆盖说明」写明。
4. 创建或修复 `.flow/changes/<change_name>/概要设计.md`、`开发文档.md`、`task.md`、`发版记录.md` 和 **`操作链路.md`**。
   - 生成 `开发文档.md` 前读取 `../flow-codex-core/assets/templates/dev-doc-maintenance.md` 与 `开发文档模板.md.tmpl`。
   - 生成 `概要设计.md` 前读取 `../flow-codex-core/assets/templates/overview-design.md.tmpl`。
   - 生成 `操作链路.md` 前读取 `../flow-codex-core/assets/templates/操作链路.md.tmpl`；在步骤 3.5 的 `as-built` 基础上补 `new` / `changed` 步骤，每步填 `owning spec`（与 Spec 矩阵一致）。
   - **概要设计强制节**（在「服务拆分」之前，顺序固定）：
     - `## 领域概念`、`## 歧义裁决`、`## 审核 pass / 写库决策表`（条件 mandatory）、`## 集成 / 联调范围`
     - 领域概念：先查 KB 功能域；有则 `来源: kb` + KB 引用，无则 `来源: change` + `kb_action: 待沉淀|无需`
     - 涉及合同、审核节点、预警类型、身份/权限码等必须先查 KB；不得用实现别名代替未定义词条
     - 子 OpenSpec 生成时 **MUST** 引用根领域概念词条名，禁止单独发明更模糊的同义表述
   - **§1–§2**：从需求/用户输入填写；§2「相关规则」写业务可验证规则。
   - **§3.2.1–§3.2.3**：仅写摘要或占位（业务规则要点、存储语义草稿、流转草图）；**禁止**从 `概要设计.md` 复制消费点表、Java/文件清单、JSON。
   - **§3.2.4**：**只列本次新增/修改接口**（不得写无变更/不变/现网行）；路径 + **恰好一个可部署服务**（非 git 仓库名）+ 变更类型 + 一行说明；BFF 对外 HTTP 行填 BFF 服务，不得填后端 provider；Apifox 列从步骤 3 填入链接或「待录入」；**禁止 JSON**。
   - **§4.1**：按**可部署/运行单元**填服务-分支（多模块仓拆多行，`git 仓库` 列可重复；禁止一行只写仓名）；**§4.2** 留空或「无」（report 写 SQL 全文）；**§4.3** 写业务验收要点（非测试类名/本机环境）。
   - §3.2.4 每条「新增/修改」接口都必须能在 `操作链路.md` 中找到调用方；找不到时**先回头质疑该接口是否真的需要**，不要为通过检查而编造调用方。
5. **Spec 拆分铁律（最终阻断由 verify ERROR 判定；design 不得自声明可 assign）**——写 `task.md` 前**必须**读取 `../flow-codex-core/assets/templates/task-md-maintenance.md` §2.2 与 §3.1。
   - 在 `概要设计.md` 产出 **「Spec | 服务 | 职责 | 依赖」矩阵**（每行恰好一个服务；跨仓同能力须多行、c 递增）。
   - `task.md` 开发顺序必须符合 §2.2 格式：`{序号}. {spec-id}（{单一 service}，依赖 cX 或 —）`。
   - 写 task / 矩阵时若发现以下情况须**当场修正**（assign 门禁仍以 verify 为准）：
     - 某 c 的开发顺序行或矩阵行出现 `+`、顿号、多个服务名
     - 某 c 对应多个 OpenSpec change 目录或多个 git repo
     - 概要设计「开发顺序」仍按服务枚举而非 spec 矩阵驱动
6. 对每个服务 spec（每行矩阵 = 一个 OpenSpec change）使用已安装的 OpenSpec 流程生成 proposal、design、delta specs 和 tasks。
7. 对每个 spec 执行 OpenSpec readiness 检查，持续补齐设计，直到没有阻断项。
8. 提示用户或根 agent 执行 `flow-codex-verify`（`verify_mode=design`，覆盖 §A+§C+§D+§E）。**不得**自声明 design 完成或可 assign；**不得**输出 verify PASS 结论。
9. 返回 Spec 矩阵、spec 依赖图、apply-readiness 与已产出 artifact 清单（不含 verify 结论）。

## design 不做的事

- **不**替代 `flow-codex-verify`（§C/§D/§E 门禁由 verify 判定）
- **不**替编排人确认 WARN（assign 前由编排人对 verify 输出的确认清单逐项确认）
- **不**写入 KB（归 `flow-codex-kb` / archive 后沉淀）

## 服务模式

只创建或修复一个已分配的服务 spec。以内联执行 agent 运行且需要独立设计审核时，向根 agent
返回审核 checkpoint，不要尝试启动嵌套审核 agent。

生成的 OpenSpec 须与根 `概要设计.md` 领域概念一致；不一致时修复 OpenSpec 而非改根概念（根概念变更走 `flow-codex-change`）。子 spec 不得擅自改根领域概念。子 spec **不得**修改根 `操作链路.md`；发现链路与实际不符时向根 agent 报告，由 `flow-codex-change` 统一更新。
