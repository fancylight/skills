# 集成测试仓初始化（scaffold）

供 `flow-codex-test-design` 在编写 change 产物**之前**执行。

## 模板源

安装后路径（优先）：

`../flow-codex-core/assets/templates/system-test/`

若本地开发未 install，可用 skills 仓库：

`{skills_repo}/flow/templates/system-test/`

模板含：根 `pom.xml`、`test-support/`、`backend-tests/`、`scripts/system-test.ps1`、`.env.example`、`.gitignore`、`changes/`、`config/services/`。

**不含**：中间件 compose、业务服务 yml、change 用例、CDC/UI 专用脚本。

## 解析测试服务

在编排根 `.flow/config.yaml` 的 `services` 中按以下优先级查找：

1. `type: system-test`（推荐）
2. `name` 为 `system-test` 或 `glm-system-test`（兼容）
3. `name` 以 `-system-test` 结尾

记为 `service_name` / `service_path`（相对编排根；可绝对路径）。

## 决策

| 条件 | 动作 |
|------|------|
| 找到条目且 `Join-Path orch_root service_path` 存在，且含 `scripts/system-test.ps1` | **跳过** scaffold，使用现有仓 |
| 找到条目但目录不存在 | 在该 path **scaffold** |
| 未找到条目 | 默认 `service_name=system-test`、`service_path=system-test`；向用户确认后 scaffold，并**追加**到 `config.services` |
| 目标目录已存在但不是测试仓（无 runner） | **BLOCKED**，勿覆盖 |

未确认且会新建目录或改 config 时，先展示将创建的 path 与 config 片段，取得确认后再写。

## Scaffold 步骤

1. 将模板目录**完整复制**到 `{orch_root}/{service_path}/`（保留相对结构）。
2. 若目标已有非空无关文件则停止。
3. 追加或更新根 `.flow/config.yaml`：

```yaml
  - name: "<service_name>"
    path: "<service_path>"
    type: "system-test"
    description: "Flow 集成测试框架仓"
    flow_initialized: false
    flow_initialized_at: ""
```

4. 可选：`git init`（仅当目标不是已有 git 仓且用户同意）。
5. 向进度/结果注明：`scaffold: created|reused` 与绝对路径。

## 之后

继续写 `changes/<change_name>/` 下的 manifest / test-plan 等（见 `manifest-checklist.md`）。  
task.md 服务章节标题与开发顺序括号内的服务名 = **config 中的 `service_name`**（勿写死 `glm-system-test`，除非 config 已是该名）。
