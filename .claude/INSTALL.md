# Flow Skill 安装说明

## 安装

```bash
# 用户级（推荐，所有项目可用）
./install.sh

# 仅当前项目
./install.sh --project

# 预览不写文件
./install.sh --dry-run
```

安装后重启 Claude Code（或执行 `/reload-plugins`），输入 `/flow:` 应能看到命令补全。

---

## 命令清单

| 命令 | 角色 | 说明 |
|------|------|------|
| `/flow:init` | 根/子 | 初始化必要文件 |
| `/flow:design` | 根/子 | 根：概要设计；子：spec 设计 + 自检 |
| `/flow:assign` | 根 | 生成子 agent 指令包 |
| `/flow:receive` | 子 | 接收任务，加载工作协议 |
| `/flow:report` | 子 | 提交汇报，更新根 task.md |
| `/flow:status` | 根 | 查看需求进度 |
| `/flow:verify` | 根 | 验证接口契约一致性 |
| `/flow:test` | 根 | 触发集成测试 |
| `/flow:change` | 根 | 处理需求变更 |
| `/flow:archive` | 根 | 归档已完成需求 |
| `/flow:hotfix` | 子 | 轻量级 bug 修复 |

---

## 快速开始

1. 在项目根目录执行 `/flow:init` 初始化根 agent
2. 执行 `/flow:design` 创建概要设计和 task.md
3. 执行 `/flow:assign <service-name>` 生成指令包
4. 在服务目录打开 Claude Code，粘贴指令包
5. 子 agent 执行 `/flow:receive` → `/flow:design` → 编码 → `/flow:report`

详细工作流程见 `flow-redesign.md`。