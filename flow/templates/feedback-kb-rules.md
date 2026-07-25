# Feedback → KB 规则

`flow-codex-kb feedback/{feedback-id}` / `/flow:kb feedback/{feedback-id}` 专用。主输入：`.flow/feedback/{id}/调查报告.md`。

**默认不写入 KB。** 仅当澄清了稳定业务规则或字段语义时才候选。

## 前置

- 根 `config.yaml` 中 `knowledge_base.enabled=true`
- 调查报告 `status=confirmed`（或即将 closed）
- 读取 KB `maintenance_guide` / `overview`（若配置）
- 先读调查日志「KB 沉淀」行；若为「否」→ 输出无需写入并仍可 closed

## 决策树（按序）

1. 是否澄清了**稳定业务规则**或**字段语义**？→ 候选 KB（功能域 / 数据设计 / 坑点）
2. 是否仅为**单次脏数据**且已 `data-fix`（或手工处理）？→ **跳过 KB**，feedback closed 即可
3. 是否为 **CDP / 运维手法**（鉴权、查库步骤、脚本）？→ 进 `{root}/.flow/cdp` playbook，**不进 KB**
4. 修 bug 且业务规则未变？→ **跳过 KB**

## 提取清单（给用户确认）

仅对决策树第 1 步为「是」的条目，列出路径与摘要。**用户确认后**再写入。不要默认「每条 feedback 一条已知问题」。

## 映射表（仅候选通过后）

| 调查报告情形 | KB 产物 |
|--------------|---------|
| bug + 新触发条件/根因模式（可复用） | 已知问题：根因、触发条件、影响范围 |
| by-design / 字段语义澄清 | FAQ / 业务规则 / 坑点 |
| data-issue **反复**且沉淀的是规则而非单次 SQL | 业务规则或字段说明（不是整段修正 SQL） |

## 跳过 KB

以下情况输出「无需写入 KB」并仍可 closed：

- 一次性脏数据已 data-fix / 手工处理
- 联调修正、GLW/commit、单次 MERGE 失效手法
- 纯 typo、无业务复用价值
- CDP playbook 级结论（应写 `.flow/cdp`）
- 用户明确拒绝
- Conclude「KB 沉淀：否」

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

`flow-codex-report` 仍跳过普通 bug 修复。feedback-kb 是独立入口，消费调查结论，不冲突；且比 change 入口更严（默认跳过）。
