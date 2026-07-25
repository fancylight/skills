# Feedback 调查工作流

## 状态机

```text
investigating → confirmed → closed
```

| 字段 | 枚举 | 说明 |
|------|------|------|
| status | investigating / confirmed / closed | frontmatter 权威 |
| type | bug / data-issue / by-design / unknown | 问题性质；unknown 仅 investigating |
| resolution | fix-now / fix-later / data-fix / kb-only / close / pending | 收尾路径；与 type 正交 |
| remediation | pending / data-fix / code-fix / none | 修复形态；与 resolution 对齐见下表 |

## resolution ↔ remediation

| resolution | remediation | 说明 |
|------------|-------------|------|
| data-fix | data-fix | 用户/工单执行 SQL；skill 不自动 UPDATE |
| fix-now | code-fix | 服务仓直接改代码 |
| fix-later | code-fix | 待改代码 |
| kb-only | none | 仅沉淀知识 |
| close | none | 无需修复 |
| pending | pending | 调查中 |

## closed 条件

满足其一即可 `status=closed`：

- `resolution=data-fix`：数据修复说明已交付，且用户确认已执行（或明确不执行）
- `fix_commit` 已填（fix-now 路径）
- `kb_ref` 已填（kb-only 或选定沉淀路径）
- `resolution=close` 且判定摘要已说明理由

**不强制**：data-fix / 一次性脏数据路径必须写 KB。

## _index.md 维护

Intake：追加 `| {id} | investigating | unknown | pending | {标题} | {date} |`

Conclude：更新 type、resolution、status=confirmed

Close：更新 status=closed、resolution、updated、closed 日期

## Discover 产物（写入调查日志）

- `相关 feedback：…` 或 `无历史重复`
- `已读 KB：[相对路径…]` 或 `KB：未启用或不可访问`
- `CDP：选用 {file}` / `CDP 缺口：…` / `CDP：无目录`

## 模板路径

安装后位于 `flow-codex-core/assets/templates/`：

- `feedback-index.md.tmpl`
- `feedback-record.md.tmpl`
- `feedback-report.md.tmpl`
- `cdp-playbook.md.tmpl`（渲染到 `{root}/.flow/cdp/{slug}-ops.md`）

占位符：`{{feedback_id}}`、`{{title}}`、`{{received_date}}`、`{{created_date}}`、`{{updated_date}}`、`{{scenario}}`、`{{platform_url}}`、`{{script_name}}`、`{{slug}}` 等；未提供字段留空或 `unknown`。

## slug 生成

从用户标题生成 kebab-case slug，去掉非法字符，最长 40 字符。
