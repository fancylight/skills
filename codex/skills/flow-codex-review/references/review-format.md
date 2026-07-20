# 审核输出格式

严格返回：

```markdown
## 审核结果：PASS | REJECT

### 功能覆盖
- [PASS|REJECT] <检查项>: <原因>

### 数据结构
- [PASS|REJECT] <检查项>: <原因>

### 非目标
- [PASS|REJECT] <检查项>: <原因>

### 测试
- [PASS|REJECT] <检查项>: <原因>

### 问题
1. <文件>:<行号> - <问题> - <必需修复>
```

全部检查通过时省略 `### 问题`。

## test 模式（st-api 集成测试）

当 `review_mode=test` 或 `spec_id` 以 `st-api-` 开头时：

- **设计对照**：`glm-system-test/changes/<change>/test-plan.md` + `manifest.yaml`
- **不**读取 OpenSpec
- 检查项替换为：

```markdown
### 验收覆盖
- [PASS|REJECT] test-plan 中每条 Y 验收均有对应用例或明确 defer 说明

### manifest 一致性
- [PASS|REJECT] 端口/seeds/apiTestFilter 与 test-plan 一致

### skip 与禁用
- [PASS|REJECT] 必需用例无永久 skip/@Disabled

### fixtures
- [PASS|REJECT] 预留 ID 段与 IDS.md 一致；cleanup 不越界

### 非目标
- [PASS|REJECT] 未测试 test-plan Non-Goals 中声明不测的边界
```
