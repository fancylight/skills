# 多阶段AI自动化开发流程（含Mermaid流程图）

本文档包含两个可直接渲染的Mermaid流程图，复制全部内容保存为\.md文件，可在Obsidian、GitBook、Notion等支持Mermaid的编辑器中打开，无需修改即可正常显示。

## 一、多阶段AI开发流程（含知识库闭环）

```mermaid
flowchart TD
        A["用户需求输入"] --> B["阶段1：需求分析 Agent"]
        B --> C["输出：PRD + 任务清单"]
        
        C --> D["阶段2：架构设计 Agent"]
        D --> E["输出：技术方案 + 模块划分"]
        
        E --> F["阶段3：编码实现 Agent"]
        F --> G["输出：业务代码"]
        
        G --> H["阶段4：代码审核 Agent"]
        H --> I{"审核通过？"}
        I -->|不通过| F[阶段3：编码实现 Agent]
        I -->|通过| J["阶段5：测试验证 Agent"]
        
        J --> K{"验证通过？"}
        K -->|不通过| F[阶段3：编码实现 Agent]
        K -->|通过| L["上线交付"]
        
        L --> M["运行日志 & 问题反馈"]
        M --> N["知识沉淀：规范/坑点/方案"]
        N --> O["团队知识库"]
        
        %% 知识库闭环（反向赋能各阶段）
        O --> B[阶段1：需求分析 Agent]
        O --> D[阶段2：架构设计 Agent]
        O --> F[阶段3：编码实现 Agent]
        O --> H[阶段4：代码审核 Agent]
    
```

## 二、人员 \+ Agent 协作时序图

```mermaid
sequenceDiagram
        actor 用户
        participant 需求Agent
        participant 架构Agent
        participant 编码Agent
        participant 审核Agent
        participant 知识库

        %% 需求阶段
        用户->>需求Agent: 提出原始需求
        需求Agent->>知识库: 查询历史方案、相似需求
        知识库-->>需求Agent: 返回参考内容（规范/模板）
        需求Agent-->>用户: 需求澄清与确认
        需求Agent->>架构Agent: 交付PRD + 任务清单

        %% 架构设计阶段
        架构Agent->>知识库: 查询架构规范、技术选型参考
        知识库-->>架构Agent: 返回架构模板、技术标准
        架构Agent->>编码Agent: 交付技术方案 + 模块划分

        %% 编码与审核迭代阶段
        loop 编码-审核循环（直至通过）
            编码Agent->>知识库: 查询代码规范、通用组件、示例代码
            知识库-->>编码Agent: 返回代码模板、规范要求
            编码Agent->>审核Agent: 提交完成代码
            审核Agent->>知识库: 查询审核规则、常见缺陷、校验标准
            知识库-->>审核Agent: 返回审核规范、缺陷案例
            审核Agent-->>编码Agent: 审核结果（通过/驳回+修改意见）
        end

        %% 后续流程与知识闭环
        编码Agent->>用户: 提交待验证代码版本
        用户->>知识库: 提交运行反馈、问题总结
        知识库-->>需求Agent: 更新需求处理规范
        知识库-->>架构Agent: 更新架构最佳实践
        知识库-->>编码Agent: 更新代码组件、避坑指南
        知识库-->>审核Agent: 更新审核规则、缺陷库
    
```

## 使用说明

- 复制本文档全部内容，保存为「多阶段AI开发流程\.md」文件

- 打开支持Mermaid的Markdown编辑器（如Obsidian、Notion、GitBook等），即可自动渲染流程图

- 流程图可直接修改、导出，无需额外配置

> （注：文档部分内容可能由 AI 生成）
