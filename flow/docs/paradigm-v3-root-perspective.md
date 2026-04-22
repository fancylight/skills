# GLM Agent 开发范式 V3（根 Claude 视角）

> 统一根 Claude 编排层 + 子 Claude 执行层的完整开发范式。
> 基于：V2 子 Claude 范式（glm-attendance）、现有根目录工作流、用户多阶段自动化愿景。

---

## 一、核心问题：V2 只解决了一半

V2 范式从 glm-attendance 的视角出发，解决了**独立闭环服务**的 Agent 开发问题。但 GLM 的大部分需求是**跨服务**的：

| 需求类型 | 示例 | 根 Claude 介入度 | V2 覆盖 |
|---------|------|-----------------|---------|
| 独立服务内需求 | 精细化考勤 c1-c12 | 低（只做归档确认） | 已覆盖 |
| 跨服务需求 | LGB/GJG 登录统一 | 高（依赖排序、接口契约、进度协调） | 未覆盖 |
| 平台级需求 | 统一权限体系改造 | 极高（多服务联动、分阶段上线） | 未覆盖 |

根 Claude 的核心价值不在于管理单个服务的 change 状态，而在于**编排跨服务协作**。

---

## 二、两层架构：编排层 + 执行层

```
┌─────────────────────────────────────────────────┐
│                  编排层（根 Claude）                │
│                                                   │
│  需求分析 → 架构设计 → 任务分配 → 进度聚合 → 归档  │
│                                                   │
│  维护：proposal.md / tasks.md / next-tasks.md     │
│  协调：跨服务接口契约、依赖顺序、知识审核           │
│                                                   │
├─────────────────────────────────────────────────┤
│                  执行层（子 Claude）                │
│                                                   │
│  propose → apply → review → archive               │
│                                                   │
│  维护：子服务 change（proposal/design/tasks）       │
│  自主：编码、测试、design-blocks、知识沉淀          │
│                                                   │
└─────────────────────────────────────────────────┘
```

### 2.1 编排层职责（根 Claude 独有）

| 职责 | 输入 | 输出 | 时机 |
|------|------|------|------|
| 需求分析 | 用户需求描述 | proposal.md（What & Why） | 需求启动 |
| 架构设计 | proposal.md | 服务分工 + 依赖顺序 + 接口契约 | 需求启动 |
| 任务分配 | tasks.md + next-tasks.md | 子 Claude 指令包 | 开发启动 |
| 进度聚合 | 子 Claude 汇报 | tasks.md 勾选 + next-tasks.md 清理 | 持续 |
| 契约验证 | 子 Claude 的 api.md | 上下游一致性确认 | 服务完成时 |
| 归档确认 | 全部服务完成 | change 归档 + 知识审核 | 需求完成 |

### 2.2 执行层职责（子 Claude）

| 职责 | 自主度 | 说明 |
|------|--------|------|
| 服务内开发 | 完全自主 | propose → apply → archive |
| design-blocks | 完全自主 | 仅复杂需求需要，根 Claude 不关注 |
| 知识沉淀 | 完全自主 | 直接写入 `{knowledge_base_path}`，先向用户确认 |
| 接口文档 | 完全自主 | api.md + {上游服务}-api.md |
| 进度汇报 | 按需 | 有 GLW 任务号时汇报根 Claude，否则自行更新 |

---

## 三、服务复杂度分级

不同复杂度的需求，根 Claude 的介入方式不同：

### 3.1 Tier 1：独立服务需求

**特征**：单个服务内闭环，不涉及跨服务接口变更。
**示例**：精细化考勤 c1-c12、考勤 bug 修复。

```
用户 ──→ 子 Claude（直接指挥）
              │
              ├── propose → apply → archive
              ├── 自行维护 design-blocks（如需要）
              ├── 自行沉淀知识库
              └── 完成后可选通知根 Claude
```

**根 Claude 介入**：
- 需求启动时：不介入（用户直接与子 Claude 沟通）
- 开发过程中：不介入
- 完成后：可选归档确认

**子 Claude 扩展能力**（V2 已定义，根 Claude 认可）：
- design-blocks：按功能域拆分的模块化设计文档
- specs/knowledge/ 和 specs/standards/：需求级知识和规范
- review/：自我审核报告
- 这些结构由子 Claude 自行决定是否使用，根 Claude 不强制也不关注

### 3.2 Tier 2：跨服务需求

**特征**：涉及 2-5 个服务，有明确的接口依赖关系。
**示例**：LGB/GJG 登录统一、工人信息查询。

```
用户 ──→ 根 Claude（需求分析 + 架构设计）
              │
              ├── 输出 proposal.md + tasks.md + next-tasks.md
              │
              ├── 按依赖顺序指派子 Claude
              │     ├── 子 Claude A（被依赖方先行）
              │     │     └── propose → apply → 汇报 api.md
              │     │
              │     └── 子 Claude B（依赖方后行）
              │           └── propose → apply → 汇报
              │
              ├── 契约验证（A 的 api.md vs B 的期望）
              │
              └── 归档确认
```

**根 Claude 介入**：
- 需求启动时：创建 change（proposal + tasks + next-tasks）
- 开发过程中：协调依赖顺序、传递接口契约、聚合进度
- 完成后：验证契约一致性、归档、知识审核

### 3.3 Tier 3：平台级需求（未来）

**特征**：涉及 5+ 个服务，需要分阶段上线，可能有数据迁移。
**示例**：统一权限体系改造、全平台登录方式升级。

```
用户 ──→ 根 Claude（需求分析 + 架构设计 + 分阶段规划）
              │
              ├── 输出 proposal.md + tasks.md（按阶段分组）
              │
              ├── 阶段 1：基础服务改造
              │     ├── 子 Claude A
              │     └── 子 Claude B
              │
              ├── 阶段 1 验证通过 → 阶段 2
              │     ├── 子 Claude C
              │     └── 子 Claude D
              │
              └── 全部阶段完成 → 归档
```

**当前不展开设计**，等有实际需求时再细化。

---

## 四、状态管理模型（统一方案）

### 4.1 决策：保留现有 tasks.md 模型，不引入 index.md

**V2 提议**：在 `/glm/openspec/需求名/index.md` 中维护状态表。
**现有模型**：在 `changes/{change-name}/tasks.md` 中用 [x] 追踪。

**选择现有模型的原因**：
1. tasks.md 已经跑通了 LGB 登录统一的完整生命周期
2. index.md 会与 tasks.md 产生状态重复，增加同步负担
3. 根 Claude 的核心关注点是"哪些任务完成了、哪些阻塞了"，tasks.md 直接回答这个问题
4. 子 Claude 的 change 状态（active/archive）由子 Claude 自行管理，根 Claude 不需要追踪

**增强**：在 tasks.md 中增加需求级元数据头部：

```markdown
---
需求名称: LGB/GJG 登录权限统一
状态: 开发中
复杂度: Tier 2（跨服务）
分支: feature/lgb-auth-v2
涉及服务: worker-app-aggregator, worker-service, register-service, app-base-service, admin
创建日期: 2026-03-01
最后更新: 2026-04-21
---

## 开发顺序
...
```

### 4.2 根目录 change 结构（不变）

```
openspec/changes/{change-name}/
├── .openspec.yaml
├── proposal.md       ← What & Why（根 Claude 维护）
├── tasks.md          ← 进度追踪（根 Claude 维护，子 Claude 可直接更新）
├── next-tasks.md     ← 待开发任务详情（可选，根 Claude 维护）
└── {附加文档}.md     ← 按需（如上线方案.md）
```

### 4.3 子服务 change 结构（两种模式）

**标准模式**（大部分需求）：
```
openspec/changes/{change-name}/
├── .openspec.yaml
├── proposal.md
├── design.md
├── tasks.md
├── api.md            ← 如有 Controller 变动
└── {上游服务}-api.md  ← 如需上游实现接口
```

**扩展模式**（复杂长期需求，如精细化考勤）：
```
openspec/
├── index.md                    ← 服务级索引（子 Claude 自行维护）
├── {需求名}/
│   ├── changes/                ← 该需求的所有 change
│   │   ├── c1-xxx/
│   │   ├── c2-xxx/
│   │   └── ...
│   ├── review/                 ← 审核报告
│   ├── specs/
│   │   ├── design-blocks/      ← 模块化设计块
│   │   ├── knowledge/          ← 需求级知识
│   │   └── standards/          ← 需求级规范
│   └── archive/                ← 废弃文档
└── external-refs.md            ← 外部知识库引用
```

**根 Claude 不关注扩展模式的内部结构**。子 Claude 自行决定是否启用 design-blocks、review 等机制。根 Claude 只关注：
- 子 Claude 汇报的完成状态
- 子 Claude 产出的 api.md（跨服务契约）
- 子 Claude 沉淀的知识（事后审核）

---

## 五、多阶段开发流程（根 Claude 视角）

### 阶段 1：需求分析（根 Claude + 用户）

**输入**：用户需求描述（口头/文档/概要设计）
**输出**：
- `proposal.md`：需求背景、目标、涉及服务、依赖顺序、接口契约、非目标
- `tasks.md`：按服务分组的任务清单（初稿，允许不完整）

**根 Claude 动作**：
1. 分析需求，识别涉及哪些服务
2. 查阅 `{knowledge_base_path}/` 了解相关服务的现有架构和已知坑
3. 查阅 `.flow/services.md` 确认服务目录映射
4. 判断复杂度等级（Tier 1/2/3）
5. 输出 proposal.md + tasks.md

### 阶段 2：架构设计（根 Claude）

**输入**：proposal.md
**输出**：
- 更新 proposal.md 的接口契约章节
- 更新 tasks.md 的依赖顺序和服务分工
- 创建 next-tasks.md（可选，为子 Claude 提供详细任务说明）

**根 Claude 动作**：
1. 确定跨服务接口契约（请求/响应格式）
2. 确定开发顺序（被依赖方先行）
3. 为每个服务准备任务说明

### 阶段 3：编码实现（子 Claude）

**输入**：根 Claude 指令包 或 用户直接指挥
**输出**：代码 + change 归档 + api.md + 汇报

**两种启动方式**（不变）：

| 方式 | 触发 | 子 Claude 行为 |
|------|------|---------------|
| 根 Claude 指派 | 根 Claude 发送指令包 | 读 onboarding → 创建 TodoList → propose → apply → archive → 汇报 |
| 用户直接指挥 | 用户告知 change 名 | 读 next-tasks.md → 与用户讨论 → 开发 → 自行更新根 tasks.md |

### 阶段 4：代码审核（子 Claude 自主 / 根 Claude 可选介入）

**子 Claude 自主审核**：
- 执行完成检查清单（编译、测试、覆盖率）
- 复杂需求可输出 review 报告

**根 Claude 介入审核**（仅 Tier 2+ 需求）：
- 验证跨服务接口契约一致性
- 检查上下游 api.md 是否匹配

### 阶段 5：测试验证（子 Claude 自主）

- 单元测试 + .http 文件验证
- 子 Claude 自行判断是否通过

### 阶段 6：知识沉淀（子 Claude 主动 + 根 Claude 审核）

**子 Claude 主动沉淀**：
1. 任务完成后判断是否有值得沉淀的知识
2. 有则列变更确认表，向用户确认后写入 `{knowledge_base_path}/`
3. 在归档汇报中追加【知识库更新】小节

**根 Claude 审核**（需求完成后）：
1. 检查子 Claude 沉淀的知识是否准确
2. 补充跨服务级别的通用知识
3. 确认知识库结构合理

### 阶段 7：归档（根 Claude）

**根 Claude 动作**：
1. 确认所有服务的任务已完成（tasks.md 全部 [x]）
2. 确认接口契约一致
3. 将 change 移入 `changes/archive/`
4. 更新 `.flow/services.md`（如有新服务纳入）

---

## 六、任务传递接口（标准化）

### 6.1 根 → 子：指令包格式

```markdown
你好，我是 {服务名} 的子 Claude。

## 启动指引
请先阅读以下规范文件：
1. {root_path}/.flow/onboarding.md
2. {root_path}/.flow/changes/{change-name}/next-tasks.md（找到你的任务）

## 当前任务
根 Claude 指派任务：{任务简述}
任务号：GLW-{编号}（用于 commit message）
复杂度：Tier {1/2}
需求：{具体需求}

## 跨服务上下文（Tier 2 时提供）
- 依赖服务：{服务名} 的 {接口} 已就绪 / 待开发
- 接口契约：见 next-tasks.md 或 {服务名}-api.md
- 注意事项：{特殊约束}

## 工作要求
1. 创建 TodoList（使用 TaskCreate）
2. 执行 /opsx:propose 创建 change
3. 完成后告知用户："proposal 和 design 已完成，请审阅"
4. 提交代码时使用格式：GLW-{编号} <type>: <description>

注意：现在只做设计，不写代码。等用户审阅通过后再执行 /opsx:apply。
```

### 6.2 子 → 根：汇报格式

```markdown
【归档汇报】
服务：{服务名}
Change：{change-name}
功能：{一句话描述}
Commit：{commit-id}
根目录 tasks.md：已有条目（勾选）/ 新增条目（追加）

【接口变更】（如有）
- 新增：GET /xxx/yyy（见 api.md）
- 需要上游：{服务名} 提供 GET /zzz（见 {服务名}-api.md）

【知识库更新】（如有）
- 更新：{knowledge_base_path}/{path}\{file}.md — {说明}

【遗留问题】（如有）
- {问题描述}
```

### 6.3 手动模式（用户直接指挥子 Claude）

用户直接说："修一下 xxx bug" 或 "处理 change: yyy"

子 Claude 自行：
1. 读取相关 change 上下文
2. 开发、测试、提交
3. 自行更新根目录 tasks.md（找到进行中的大需求，勾选或追加）
4. 自行沉淀知识库（如有）
5. 向用户汇报

---

## 七、知识库协作模型

### 7.1 四级知识库（`{knowledge_base_path}/`）

**维护权限**：

| 角色 | 权限 | 约束 |
|------|------|------|
| 子 Claude | 读写 | 先列变更确认表向用户确认，确认后写入 |
| 根 Claude | 读写 + 审核 | 需求完成后审核子 Claude 的沉淀 |

**触发条件**（不变）：
- 新增业务规则、澄清历史决策、发现坑、接口变更 → 需要沉淀
- bug 修复、内部重构 → 不需要

### 7.2 子 Claude 的 openspec 内部知识（可选）

对于 Tier 1 复杂需求（如精细化考勤），子 Claude 可以在 openspec 内部维护：
- `specs/design-blocks/`：模块化设计块
- `specs/knowledge/`：需求级知识
- `specs/standards/`：需求级规范

**需求完成后**，子 Claude 判断哪些知识值得沉淀到 `{knowledge_base_path}/`：
- 服务级通用知识 → 写入 `{knowledge_base_path}/{服务名}\`
- 需求专属知识 → 保留在 openspec 内部作为历史归档

**根 Claude 不关注这些内部结构**，只在需求完成后做最终审核。

---

## 八、与现有体系的兼容

### 8.1 不变的部分

| 机制 | 说明 |
|------|------|
| 根目录 change 结构 | proposal.md + tasks.md + next-tasks.md，不变 |
| 子 Claude 标准流程 | propose → apply → archive，不变 |
| 指令包格式 | 基本不变，增加 Tier 和跨服务上下文 |
| tasks.md 维护规范 | 永久记录 [x]，next-tasks.md 完成即删，不变 |
| TodoList 强制要求 | 不变 |
| Git 提交规范 | GLW-编号格式，不变 |
| 知识库维护 | 子 Claude 直接维护，先确认后写入，不变 |

### 8.2 新增的部分

| 机制 | 说明 |
|------|------|
| 复杂度分级 | Tier 1/2/3，决定根 Claude 介入程度 |
| tasks.md 元数据头 | 增加需求级元数据（状态、复杂度、涉及服务） |
| 子 Claude 扩展模式 | 认可 design-blocks 等机制，但不强制 |
| 指令包增强 | Tier 2 时提供跨服务上下文 |

### 8.3 V2 提议的处理

| V2 提议 | 决策 | 原因 |
|---------|------|------|
| `/glm/openspec/需求名/index.md` 做状态管理 | 不采纳 | 与 tasks.md 重复，增加同步负担 |
| changes/ 不分 active/archive | 子 Claude 自行决定 | 根 Claude 不关注子服务内部结构 |
| 子 Claude 直接写入 `{knowledge_base_path}` | 已采纳（现有规范已支持） | 先确认后写入 |
| 三层上下文模型（L1/L2/L3） | 部分采纳 | L1 = onboarding.md，L2 = 子服务 index.md（可选），L3 = change |
| design-blocks 机制 | 认可但不强制 | 只有复杂长期需求才需要 |
| review 规范 | 认可但不强制 | 子 Claude 自行决定是否输出 review 报告 |
| 知识闭环检查 | 认可 | 好的实践，子 Claude 自行执行 |

---

## 九、走向全自动化的路径

### 9.1 当前状态（半自动）

```
用户 ──→ 根 Claude（手动对话）
              │
              ├── 手动分析需求
              ├── 手动创建 change
              ├── 手动复制指令包给子 Claude
              │
              └── 子 Claude（手动对话）
                    ├── 半自动：propose → apply → archive
                    └── 手动：向用户汇报，用户转达给根 Claude
```

**瓶颈**：根 Claude 和子 Claude 之间的信息传递依赖用户手动复制粘贴。

### 9.2 近期可改进（不需要新工具）

**改进 1：标准化汇报格式**
- 子 Claude 完成后输出结构化汇报（见 6.2）
- 用户直接复制给根 Claude，根 Claude 自动解析并更新 tasks.md

**改进 2：next-tasks.md 作为异步通信通道**
- 根 Claude 写入 next-tasks.md
- 子 Claude 读取 next-tasks.md
- 不需要用户转述需求

**改进 3：子 Claude 自行更新根 tasks.md**
- 用户直接指挥模式下，子 Claude 完成后直接写入根目录 tasks.md
- 减少根 Claude 的回填工作

### 9.3 中期目标（需要工具支持）

**编排 Agent**：一个能同时管理多个子 Claude 会话的编排层。

```
用户 ──→ 编排 Agent（根 Claude 升级版）
              │
              ├── 自动分析需求
              ├── 自动创建 change
              ├── 自动启动子 Claude 会话（按依赖顺序）
              ├── 自动接收子 Claude 汇报
              ├── 自动验证接口契约
              ├── 自动更新 tasks.md
              └── 自动归档
```

**需要的能力**：
- 根 Claude 能启动子 Claude 会话（当前不支持）
- 根 Claude 能读取子 Claude 的输出（当前通过用户中转）
- 根 Claude 能在子 Claude 完成后自动触发下一个（当前手动）

### 9.4 长期愿景（多阶段 AI 自动化）

对应用户的 Mermaid 流程图：

```
阶段1：需求分析 Agent（根 Claude）
    → PRD + 任务清单
    → 查询知识库获取历史方案

阶段2：架构设计 Agent（根 Claude）
    → 技术方案 + 模块划分
    → 查询知识库获取架构规范

阶段3：编码实现 Agent（子 Claude × N）
    → 业务代码
    → 查询知识库获取代码规范
    → 并行开发无依赖的服务

阶段4：代码审核 Agent（子 Claude 自审 + 根 Claude 交叉审核）
    → 审核通过？→ 不通过回到阶段3
    → 查询知识库获取审核规则

阶段5：测试验证 Agent（子 Claude）
    → 验证通过？→ 不通过回到阶段3

上线交付 → 知识沉淀 → 知识库闭环
```

**当前差距**：
1. 阶段 1-2 已基本实现（根 Claude + 用户协作）
2. 阶段 3 已半自动（子 Claude 的 propose → apply → archive）
3. 阶段 4 部分实现（子 Claude 自审，根 Claude 交叉审核待自动化）
4. 阶段 5 已实现（子 Claude 自主测试）
5. 知识闭环已实现（子 Claude 直接维护 + 根 Claude 审核）
6. **缺失**：阶段间的自动流转（当前依赖用户手动触发）

---

## 十、落地计划

### 第一步：确认本方案（当前）

- 用户审阅本文档
- 确认 Tier 分级、状态管理模型、V2 提议的处理决策
- 确认与现有体系的兼容性

### 第二步：更新根目录规范文件

如果方案通过，需要更新：
1. `.flow/spec.md` — 增加 Tier 分级说明
2. `.flow/config.yaml` — 增加复杂度分级的 context
3. `MEMORY.md` — 更新开发范式相关记忆
4. 子 Claude 的 `onboarding.md` — 增加 Tier 感知（Tier 2 时需要关注跨服务上下文）

### 第三步：在下一个需求中验证

- 选择一个 Tier 2 需求，按本范式执行
- 验证 tasks.md 元数据头、指令包增强、汇报格式是否顺畅
- 根据实际反馈迭代

### 第四步：子 Claude 范式对齐

- 将 V2 中根 Claude 认可的部分（design-blocks、知识闭环、review 规范）正式纳入子 Claude 的可选工具箱
- 不强制所有服务使用，由子 Claude 根据需求复杂度自行决定
```

