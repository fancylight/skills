# Feedback 调查工作流

## 状态机

```text
investigating → confirmed → closed
```

| 字段 | 枚举 | 说明 |
|------|------|------|
| status | investigating / confirmed / closed | frontmatter 权威 |
| type | bug / data-issue / by-design / unknown | unknown 仅 investigating |
| resolution | fix-now / fix-later / kb-only / close / pending | 与 type 正交 |

## closed 条件

满足其一：

- `kb_ref` 已填
- `fix_commit` 已填（fix-now 路径）
- `resolution=close` 且判定摘要已说明理由

## _index.md 维护

Intake：追加 `| {id} | investigating | unknown | pending | {标题} | {date} |`

Conclude：更新 type、resolution、status=confirmed

Close：更新 status=closed、resolution、updated、closed 日期

## 模板路径

安装后位于 `flow-codex-core/assets/templates/`：

- `feedback-index.md.tmpl`
- `feedback-record.md.tmpl`
- `feedback-report.md.tmpl`

占位符：`{{feedback_id}}`、`{{title}}`、`{{received_date}}`、`{{created_date}}`、`{{updated_date}}` 等；未提供字段留空或 `unknown`。

## slug 生成

从用户标题生成 kebab-case slug，去掉非法字符，最长 40 字符。
