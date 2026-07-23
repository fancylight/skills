# Feedback → KB 规则

`/flow:kb feedback/{feedback-id}` 专用。主输入：`.flow/feedback/{id}/调查报告.md`。

## 前置

- 根 `config.yaml` 中 `knowledge_base.enabled=true`
- 调查报告 `status=confirmed`（或即将 closed）
- 读取 KB `maintenance_guide` / `overview`（若配置）

## 提取清单（给用户确认）

从调查报告提取可写入 KB 的条目，逐条列出路径与摘要。**用户确认后**再写入。

## 映射表

| 调查报告 type + resolution | KB 产物 |
|---------------------------|---------|
| bug + fix-now / fix-later | 已知问题：根因、触发条件、影响范围 |
| by-design | FAQ / 业务规则说明 |
| data-issue（反复出现） | 运维指引 / 清理 SQL 模式 |
| 字段语义误读 | 坑点 / 字段说明 |

## 跳过 KB

以下情况输出「无需写入 KB」并仍可 closed：

- 一次性脏数据已手工处理
- 纯 typo、无业务复用价值
- 用户明确拒绝

## 写入后

1. 回写调查报告 frontmatter `kb_ref`（KB 文档路径）
2. 更新 `_index.md` 对应行
3. 提示用户是否将 `status` 置为 `closed` 并填 `closed` 日期

## 段落模板

### 已知问题

```markdown
## 已知问题：{标题}

- **反馈 ID**：{feedback_id}
- **根因**：{一句话}
- **触发条件**：{条件}
- **影响范围**：{范围}
- **状态**：已修复（{fix_commit}）/ 暂未修复
- **关联接口/字段**：{路径} / {表}.{字段}
```

### 坑点

```markdown
## 坑点：{字段或场景}

- **现象**：{用户看到什么}
- **原因**：{为什么是设计或误读}
- **正确理解**：{应如何解读}
- **反馈 ID**：{feedback_id}
```

### FAQ

```markdown
## FAQ：{问题简述}

**问**：{用户疑问}

**答**：{设计说明或操作指引}

来源：feedback `{feedback_id}`
```

## 与 report KB 判断的关系

`/flow:report` 仍跳过普通 bug 修复。feedback-kb 是独立入口，消费调查结论，不冲突。
