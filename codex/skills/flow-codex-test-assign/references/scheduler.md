# Codex Flow 集成测试调度

## 状态机

```text
DESIGN_VERIFY_PASS -> IMPLEMENTING -> REVIEWING -> FIXING -> REVIEWING
                                             -> TESTING -> COMMITTED -> REPORTING -> DONE
```

与业务 spec 相同；失败时停止后续集成测试执行门禁。

## 并发规则

- 每个 change 通常 **一个** `st-api-<change>`，单 executor。
- system-test 仓与业务仓库并行写入允许，但同一测试仓内禁止并发写入 agent。
- 汇报更新根 `task.md`，必须串行执行（与业务 report 共用租约语义）。

## 完成标准

- manifest 当前 filter 冒烟通过（apply 阶段）
- 必需用例无永久 `@Disabled` / 无理由 skip
- 同一可恢复 revision 的 implementation verify PASS
- task.md 中 `st-api-<change>` 标记完成
