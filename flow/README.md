# Flow — Multi-Agent Orchestration Skill for Claude Code

多 Agent 编排工作流 Skill，用于管理根 Agent（编排者）和子 Agent（执行者）之间的协作。

完整文档见 [`CLAUDE.md`](./CLAUDE.md)。

---

## 快速开始

```bash
# 1. 安装 Skill（符号链接推荐）
ln -s /path/to/skills/flow/commands ~/.claude/commands/flow

# 2. 在项目根目录初始化
/flow:init

# 3. 创建需求
/flow:init 统一登录系统改造

# 4. 分配任务给子 Agent
/flow:assign user-service

# 5. 子 Agent 接收任务
/flow:receive

# 6. 子 Agent 完成后汇报
/flow:report

# 7. 查看进度
/flow:status

# 8. 验证接口契约
/flow:verify

# 9. 归档
/flow:archive
```

---

## 核心概念

### 两级 Agent 模型

- **根 Agent（Orchestrator）**：在项目根目录工作，负责需求拆解、任务分配、进度追踪、契约验证
- **子 Agent（Executor）**：在单个服务目录工作，负责设计、编码、测试、知识沉淀

### 复杂度分级（Tier）

| Tier | 场景 | 根 Agent 介入度 |
|------|------|----------------|
| 1 | 单服务内需求 | 低（可选归档确认） |
| 2 | 跨 2-5 个服务 | 中（依赖排序、契约验证） |
| 3 | 平台级（5+ 服务） | 高（分阶段规划） |

### 插件式执行层

子 Agent 可以使用任何 spec 工具（OpenSpec、自定义等），根 Agent 不关心内部实现，只要求子 Agent 遵守：领任务 -> 设计 -> 编码 -> 验证 -> 汇报。
