# Codex Flow 调度器

## 状态机

```text
READY -> IMPLEMENTING -> REVIEWING -> FIXING -> REVIEWING
                                    -> TESTING -> COMMITTED -> REPORTING -> DONE
```

任何状态都可能进入 `FAILED`。失败后停止依赖当前 spec 的其他 specs。

## 并发规则

- 不同仓库中依赖就绪的 specs 可以并行执行。
- 同一仓库中的 specs 默认串行执行。
- 审核 agent 只读，可以并行运行。
- 汇报需要写入根 `task.md` 和 `发版记录.md`，必须串行执行。

## 根上下文预算

执行 agent 只返回 spec id、状态、变更文件、阻断问题、测试摘要、commit hash 和汇报完成状态。
根 agent 在派发过程中不读取业务代码或设计文档。
