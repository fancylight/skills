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

### SQL 数据访问（仅相关 SQL）
- [PASS|REJECT] 数据访问契约: <根契约与 spec 传导；或不适用>
- [PASS|REJECT] JOIN/选行/索引: <与参考实现、等值键、基数和索引依据的比对>
- [PASS|REJECT] 风险形态与验证: <相关子查询、max/min、PageHelper count 与 Mapper/EXPLAIN 覆盖>


### 问题
1. <文件>:<行号> - <问题> - <必需修复>
```

全部检查通过时省略 `### 问题`。

## test 模式（st-api 集成测试）

当 `review_mode=test` 或 `spec_id` 以 `st-api-` 开头时：

- **设计对照**：`system-test/changes/<change>/test-design.md` + `test-plan.md` + `manifest.yaml`
- **不**读取 OpenSpec
- 检查项替换为：

```markdown
### 验收覆盖
- [PASS|REJECT] 每条 Y 验收均有 AC→场景→测试方法→核心断言；不得只写测试类

### manifest 一致性
- [PASS|REJECT] 端口/seeds/apiTestFilter 与 test-plan 一致

### skip 与禁用
- [PASS|REJECT] 必需用例无永久 skip/@Disabled

### fixtures
- [PASS|REJECT] 预留 ID 段与 IDS.md 一致；cleanup 不越界

### 非目标
- [PASS|REJECT] 未测试 test-plan Non-Goals 中声明不测的边界

### 副作用
- [PASS|REJECT] 声称写入/未写入的场景具备对应 DB、文件、MQ 或缓存观测
```
